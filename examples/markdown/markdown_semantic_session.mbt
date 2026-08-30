///|
priv struct CachedMarkdownPublication {
  root : ReactiveMarkdownDocumentRoot
  document : MarkdownIR
  top_level_revision_keys : Array[Int]
  diagnostics_clean : Bool
}

///|
/// One semantic Markdown publication and the revision keys of its top-level
/// rendered blocks.
///
/// A key remains stable only while the corresponding block can be rendered
/// from the previous publication without changing its visible semantics.
pub struct MarkdownSemanticPublication {
  priv document : MarkdownIR
  priv top_level_revision_keys : Array[Int]
}

///|
pub fn MarkdownSemanticPublication::document(
  self : MarkdownSemanticPublication,
) -> MarkdownIR {
  self.document
}

///|
pub fn MarkdownSemanticPublication::top_level_revision_keys(
  self : MarkdownSemanticPublication,
) -> ArrayView[Int] {
  self.top_level_revision_keys[:]
}

///|
/// Imperative owner of one parser-bound, one-generation Markdown semantic
/// publication cache.
pub struct MarkdownSemanticSession {
  priv parser : @loom.SyntaxParser
  priv extensions : MarkdownExtensions
  priv mut previous : CachedMarkdownPublication?
  priv mut next_revision_key : Int
}

///|
pub fn MarkdownSemanticSession::MarkdownSemanticSession(
  parser : @loom.SyntaxParser,
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
  first_revision_key? : Int = 0,
) -> MarkdownSemanticSession {
  { parser, extensions, previous: None, next_revision_key: first_revision_key }
}

///|
/// The first revision key that a future publication may allocate.
pub fn MarkdownSemanticSession::next_revision_key(
  self : MarkdownSemanticSession,
) -> Int {
  self.next_revision_key
}

///|
fn MarkdownSemanticSession::fresh_revision_key(
  self : MarkdownSemanticSession,
) -> Int {
  let key = self.next_revision_key
  self.next_revision_key += 1
  key
}

///|
fn MarkdownSemanticSession::fresh_revision_keys(
  self : MarkdownSemanticSession,
  count : Int,
) -> Array[Int] {
  Array::makei(count, _ => self.fresh_revision_key())
}

///|
fn MarkdownSemanticSession::direct_publication(
  self : MarkdownSemanticSession,
  snapshot : @loom.SyntaxSnapshot,
) -> (MarkdownSemanticPublication, CachedMarkdownPublication) {
  let root = reactive_markdown_document_root(snapshot.syntax)
  let document = experimental_markdown_ir_from_syntax_snapshot(
    snapshot,
    extensions=self.extensions,
  )
  let keys = self.fresh_revision_keys(document.children().length())
  (
    { document, top_level_revision_keys: keys },
    {
      root,
      document,
      top_level_revision_keys: keys,
      diagnostics_clean: snapshot.diagnostics.is_empty(),
    },
  )
}

///|
fn publication_node_can_shift(ir : MarkdownIR) -> Bool {
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
fn publication_can_shift(ir : MarkdownIR) -> Bool {
  let pending = [ir]
  while !pending.is_empty() {
    let current = pending.pop().unwrap()
    if !publication_node_can_shift(current) {
      return false
    }
    for child in current.children() {
      pending.push(child)
    }
  }
  true
}

///|
fn first_direct_cst_child(cst : @seam.CstNode) -> @seam.CstNode? {
  for element in cst.children() {
    match element {
      @seam.CstElement::Node(node) => return Some(node)
      @seam.CstElement::Token(_) => ()
    }
  }
  None
}

///|
fn last_direct_cst_child(cst : @seam.CstNode) -> @seam.CstNode? {
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
fn has_boundary_physical_continuity(
  previous : ReactiveMarkdownDocumentRoot,
  current : ReactiveMarkdownDocumentRoot,
) -> Bool {
  match
    (first_direct_cst_child(previous.cst), first_direct_cst_child(current.cst)) {
    (Some(before), Some(after)) if physical_equal(before, after) => return true
    _ => ()
  }
  match
    (last_direct_cst_child(previous.cst), last_direct_cst_child(current.cst)) {
    (Some(before), Some(after)) => physical_equal(before, after)
    _ => false
  }
}

///|
fn MarkdownSemanticSession::update(
  self : MarkdownSemanticSession,
  snapshot : @loom.SyntaxSnapshot,
  previous : CachedMarkdownPublication,
) -> (MarkdownSemanticPublication, CachedMarkdownPublication) {
  let current_root = reactive_markdown_document_root(snapshot.syntax)
  if previous.diagnostics_clean &&
    snapshot.diagnostics.is_empty() &&
    previous.root.start == current_root.start &&
    physical_equal(previous.root.cst, current_root.cst) {
    return (
      {
        document: previous.document,
        top_level_revision_keys: previous.top_level_revision_keys,
      },
      previous,
    )
  }
  if !has_boundary_physical_continuity(previous.root, current_root) ||
    !previous.diagnostics_clean ||
    !snapshot.diagnostics.is_empty() {
    return self.direct_publication(snapshot)
  }
  let current_syntax = reactive_markdown_syntax_root(current_root)
  let current_layout = reactive_markdown_document_layout(current_root)
  let definitions = collect_link_reference_definitions(current_syntax)
  let previous_definitions = collect_link_reference_definitions(
    reactive_markdown_syntax_root(previous.root),
  )
  if definitions != previous_definitions {
    return self.direct_publication(snapshot)
  }
  let previous_layout = reactive_markdown_document_layout(previous.root)
  let previous_children = previous.document.children()
  guard previous_children.length() == previous.top_level_revision_keys.length() else {
    abort("Markdown semantic publication key count mismatch")
  }
  guard previous_children.length() == previous_layout.blocks.length() else {
    abort("Markdown semantic publication layout mismatch")
  }
  let block_count = current_layout.blocks.length()
  if previous_layout.blocks.length() != block_count {
    return self.direct_publication(snapshot)
  }
  fn reusable(index : Int) -> Bool {
    let before = previous_layout.blocks[index]
    let after = current_layout.blocks[index]
    physical_equal(before.cst, after.cst) &&
    (
      before.start == after.start ||
      publication_can_shift(previous_children[index])
    )
  }
  let mut hit_count = 0
  for index in 0..<block_count {
    if reusable(index) {
      hit_count += 1
    }
  }
  if block_count - hit_count != 1 {
    return self.direct_publication(snapshot)
  }
  let current_children = current_syntax.children()
  let children : Array[MarkdownIR] = []
  let keys : Array[Int] = []
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
      keys.push(previous.top_level_revision_keys[index])
    } else {
      let current = current_children[slot.document_child_index]
      guard current.cst_node() == slot.cst else {
        abort("Markdown semantic publication CST mismatch")
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
      keys.push(self.fresh_revision_key())
    }
  }
  let document = MarkdownIR::document(children, current_layout.origin)
  (
    { document, top_level_revision_keys: keys },
    {
      root: current_root,
      document,
      top_level_revision_keys: keys,
      diagnostics_clean: true,
    },
  )
}

///|
/// Publish semantics for the parser's current snapshot.
///
/// The next publication is completed before replacing the sole retained
/// previous generation. A conservative miss publishes canonical direct
/// lowering and immediately uses that result as the next revision's seed.
pub fn MarkdownSemanticSession::publish(
  self : MarkdownSemanticSession,
) -> MarkdownSemanticPublication {
  let snapshot = self.parser.snapshot().read_or_abort()
  let (publication, next) = match self.previous {
    Some(previous) => self.update(snapshot, previous)
    None => self.direct_publication(snapshot)
  }
  self.previous = Some(next)
  publication
}
