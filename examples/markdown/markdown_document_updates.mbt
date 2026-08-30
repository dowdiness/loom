///|
priv struct CachedMarkdownDocument {
  root : ReactiveMarkdownDocumentRoot
  document : MarkdownIR
  diagnostics_clean : Bool
}

///|
/// Parser-bound producer of canonical Markdown document updates.
///
/// The producer retains exactly one semantic baseline. It reports only safe
/// position-independent matches to its direct previous result and never
/// allocates renderer keys. The caller owns and mutates the `SyntaxParser`.
pub struct MarkdownDocumentUpdates {
  priv parser : @loom.SyntaxParser
  priv extensions : MarkdownExtensions
  priv mut previous : CachedMarkdownDocument?
  priv domain : Ref[Unit]
  priv mut next_sequence : Int
  priv mut previous_sequence : Int?
}

///|
/// Attach document-update production to a caller-owned syntax parser.
///
/// Extensions are fixed for the producer lifetime. A replacement producer has
/// a distinct update domain even when it observes the same parser and source.
pub fn MarkdownDocumentUpdates::MarkdownDocumentUpdates(
  parser : @loom.SyntaxParser,
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> MarkdownDocumentUpdates {
  {
    parser,
    extensions,
    previous: None,
    domain: Ref::Ref(()),
    next_sequence: 0,
    previous_sequence: None,
  }
}

///|
fn MarkdownDocumentUpdates::direct_document(
  self : MarkdownDocumentUpdates,
  snapshot : @loom.SyntaxSnapshot,
) -> (MarkdownIR, Array[Int?], CachedMarkdownDocument) {
  let root = reactive_markdown_document_root(snapshot.syntax)
  let document = experimental_markdown_ir_from_syntax_snapshot(
    snapshot,
    extensions=self.extensions,
  )
  (
    document,
    Array::make(document.children().length(), None),
    { root, document, diagnostics_clean: snapshot.diagnostics.is_empty() },
  )
}

///|
fn document_update_node_can_shift(ir : MarkdownIR) -> Bool {
  // Keep this match exhaustive: every new semantic variant must make an
  // explicit origin-shift decision before it can enter the reuse path.
  match ir.view() {
    Link(surface~, ..) | Image(surface~, ..) =>
      surface.form is MarkdownIRLinkReferenceForm::InlineLinkForm
    Raw(..) | Recovered(..) => false
    Document
    | Heading(..)
    | Paragraph
    | BlockQuote
    | UnorderedList(..)
    | OrderedList(..)
    | ListItem(..)
    | OrderedListItem(..)
    | CodeBlock(..)
    | HtmlBlock(..)
    | ThematicBreak
    | Text(..)
    | Bold
    | Italic
    | InlineCode(..)
    | Autolink(..)
    | InlineHtml(..)
    | SoftBreak
    | HardBreak(..)
    | Unsupported(..) => true
  }
}

///|
fn document_update_can_shift(ir : MarkdownIR) -> Bool {
  let pending = [ir]
  while !pending.is_empty() {
    let current = pending.pop().unwrap()
    if !document_update_node_can_shift(current) {
      return false
    }
    for child in current.children() {
      pending.push(child)
    }
  }
  true
}

///|
fn document_update_first_cst_child(cst : @seam.CstNode) -> @seam.CstNode? {
  for element in cst.children() {
    match element {
      @seam.CstElement::Node(node) => return Some(node)
      @seam.CstElement::Token(_) => ()
    }
  }
  None
}

///|
fn document_update_last_cst_child(cst : @seam.CstNode) -> @seam.CstNode? {
  let children = cst.children()
  for offset in 0..<children.length() {
    match children[children.length() - offset - 1] {
      @seam.CstElement::Node(node) => return Some(node)
      @seam.CstElement::Token(_) => ()
    }
  }
  None
}

///|
fn document_update_has_boundary_continuity(
  previous : ReactiveMarkdownDocumentRoot,
  current : ReactiveMarkdownDocumentRoot,
) -> Bool {
  match
    (
      document_update_first_cst_child(previous.cst),
      document_update_first_cst_child(current.cst),
    ) {
    (Some(before), Some(after)) if physical_equal(before, after) => return true
    _ => ()
  }
  match
    (
      document_update_last_cst_child(previous.cst),
      document_update_last_cst_child(current.cst),
    ) {
    (Some(before), Some(after)) => physical_equal(before, after)
    _ => false
  }
}

///|
fn MarkdownDocumentUpdates::next_document(
  self : MarkdownDocumentUpdates,
  snapshot : @loom.SyntaxSnapshot,
  previous : CachedMarkdownDocument,
) -> (MarkdownIR, Array[Int?], CachedMarkdownDocument) {
  let current_root = reactive_markdown_document_root(snapshot.syntax)
  if previous.diagnostics_clean &&
    snapshot.diagnostics.is_empty() &&
    previous.root.start == current_root.start &&
    physical_equal(previous.root.cst, current_root.cst) {
    return (
      previous.document,
      Array::makei(previous.document.children().length(), index => Some(index)),
      previous,
    )
  }
  if !document_update_has_boundary_continuity(previous.root, current_root) ||
    !previous.diagnostics_clean ||
    !snapshot.diagnostics.is_empty() {
    return self.direct_document(snapshot)
  }
  let current_syntax = reactive_markdown_syntax_root(current_root)
  let current_layout = reactive_markdown_document_layout(current_root)
  let definitions = collect_link_reference_definitions(current_syntax)
  let previous_definitions = collect_link_reference_definitions(
    reactive_markdown_syntax_root(previous.root),
  )
  if definitions != previous_definitions {
    return self.direct_document(snapshot)
  }
  let previous_layout = reactive_markdown_document_layout(previous.root)
  let previous_children = previous.document.children()
  guard previous_children.length() == previous_layout.blocks.length() else {
    abort("Markdown document update layout mismatch")
  }
  let block_count = current_layout.blocks.length()
  if previous_layout.blocks.length() != block_count {
    return self.direct_document(snapshot)
  }
  fn reusable(index : Int) -> Bool {
    let before = previous_layout.blocks[index]
    let after = current_layout.blocks[index]
    physical_equal(before.cst, after.cst) &&
    (
      before.start == after.start ||
      document_update_can_shift(previous_children[index])
    )
  }
  let mut hit_count = 0
  for index in 0..<block_count {
    if reusable(index) {
      hit_count += 1
    }
  }
  if block_count - hit_count != 1 {
    return self.direct_document(snapshot)
  }
  let current_children = current_syntax.children()
  let children : Array[MarkdownIR] = []
  let matches : Array[Int?] = []
  for index, slot in current_layout.blocks {
    if reusable(index) {
      let before = previous_layout.blocks[index]
      let cached = previous_children[index]
      children.push(
        if before.start == slot.start {
          cached
        } else {
          place_local_markdown_ir(cached, slot.start - before.start)
        },
      )
      matches.push(Some(index))
    } else {
      let current = current_children[slot.document_child_index]
      guard current.cst_node() == slot.cst else {
        abort("Markdown document update CST mismatch")
      }
      children.push(
        lower_contextual_resolved_block(
          self.parser.source_id(),
          current,
          snapshot.source,
          label => definitions.lookup(label),
          origin => {
            diagnostics_in_origin(
              self.parser.source_id(),
              snapshot.diagnostics,
              origin,
            )
          },
          extensions=self.extensions,
        ).ir,
      )
      matches.push(None)
    }
  }
  let document = MarkdownIR::document(children, current_layout.origin)
  (document, matches, { root: current_root, document, diagnostics_clean: true })
}

///|
/// Validate the partial injective match relation before it reaches a consumer.
///
/// The local boolean array is temporary validation state. It avoids exposing or
/// retaining a general-purpose identity map in the update boundary.
fn validated_document_update_matches(
  matches : Array[Int?],
  previous_block_count : Int?,
) -> Array[Int?] {
  guard previous_block_count is Some(count) else {
    return Array::make(matches.length(), None)
  }
  let seen = Array::make(count, false)
  for match_index in matches {
    guard match_index is Some(index) else { continue }
    if index < 0 || index >= count || seen[index] {
      return Array::make(matches.length(), None)
    }
    seen[index] = true
  }
  matches
}

///|
/// Produce the canonical document and safe matches for the parser's current
/// snapshot.
///
/// The completed update is built before the sole retained baseline and update
/// sequence advance. Repeated calls therefore create distinct direct-previous
/// positions even when the parser source has not changed.
pub fn MarkdownDocumentUpdates::document_update(
  self : MarkdownDocumentUpdates,
) -> MarkdownDocumentUpdate {
  let snapshot = self.parser.snapshot().read_or_abort()
  let previous_block_count = self.previous.map(previous => {
    previous.document.children().length()
  })
  let (ir, raw_matches, next) = match self.previous {
    Some(previous) => self.next_document(snapshot, previous)
    None => self.direct_document(snapshot)
  }
  let matches = validated_document_update_matches(
    raw_matches, previous_block_count,
  )
  let document = markdown_document_from_syntax_snapshot(
    self.parser.source_id(),
    snapshot,
    ir,
  )
  let nodes = document.root().children()
  guard nodes.length() == matches.length() else {
    abort("Markdown document update block count mismatch")
  }
  let blocks = nodes.mapi((index, node) => {
    node,
    matched_previous_block_index: matches[index],
  })
  let sequence = self.next_sequence
  let update : MarkdownDocumentUpdate = {
    document,
    blocks,
    domain: self.domain,
    sequence,
    previous_sequence: self.previous_sequence,
  }
  self.previous = Some(next)
  self.next_sequence += 1
  self.previous_sequence = Some(sequence)
  update
}
