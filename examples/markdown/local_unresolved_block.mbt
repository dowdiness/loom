///|
#warnings("-unused_value")
priv struct LocalReferenceCandidate {
  placeholder : String
  normalized_label : String?
  display : Array[MarkdownIR]
  literal : Array[MarkdownIR]
  form : LinkReferenceForm
  origin : MarkdownIROrigin
  label_origin : MarkdownIROrigin?
  reference_label_origin : MarkdownIROrigin?
} derive(Eq)

///|
fn register_local_reference_candidate(
  candidates : Array[LocalReferenceCandidate],
  normalized_label : String?,
  display : Array[MarkdownIR],
  literal : Array[MarkdownIR],
  form : LinkReferenceForm,
  origin : MarkdownIROrigin,
  label_origin : MarkdownIROrigin?,
  reference_label_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  let placeholder = "private local reference candidate " +
    candidates.length().to_string()
  candidates.push({
    placeholder,
    normalized_label,
    display,
    literal,
    form,
    origin,
    label_origin,
    reference_label_origin,
  })
  MarkdownIR::unsupported(placeholder, origin)
}

///|
fn find_local_reference_candidate(
  candidates : Array[LocalReferenceCandidate],
  candidate_indices : @hashmap.HashMap[String, Int],
  placeholder : String,
) -> LocalReferenceCandidate? {
  candidate_indices.get(placeholder).map(index => candidates[index])
}

///|
const LOCAL_NESTED_LINK_OPENER = "private local nested-link opener"

///|
const LOCAL_DEFERRED_INLINE_FINALIZE = "private local inline finalize"

///|
fn mark_local_deferred_inline_finalize(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let start = match children {
    [first, ..] => first.origin().start()
    [] => 0
  }
  let marked = [
    MarkdownIR::unsupported(
      LOCAL_DEFERRED_INLINE_FINALIZE,
      MarkdownIROrigin(start~, end=start),
    ),
  ]
  for child in children {
    marked.push(child)
  }
  marked
}

///|
fn take_local_deferred_inline_finalize(
  children : Array[MarkdownIR],
) -> (Bool, Array[MarkdownIR]) {
  match children {
    [first, ..] if first.node is Unsupported(LOCAL_DEFERRED_INLINE_FINALIZE) => {
      let unmarked : Array[MarkdownIR] = []
      for index = 1; index < children.length(); index = index + 1 {
        unmarked.push(children[index])
      }
      (true, unmarked)
    }
    _ => (false, children)
  }
}

///|
fn finish_local_inline_resolution(
  children : Array[MarkdownIR],
  should_finalize : Bool,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  if should_finalize {
    restore_local_nested_link_openers(
      resolve_normalized_inline_reference_children(
        protect_local_nested_link_openers(children, context.source),
        context,
      ),
    )
  } else {
    children
  }
}

///|
fn protect_local_nested_link_openers(
  children : Array[MarkdownIR],
  source : String,
) -> Array[MarkdownIR] {
  let guarded = children.copy()
  let open_indices : Array[Int] = []
  for index, child in children {
    if is_shortcut_reference_open(child, source) {
      open_indices.push(index)
    } else if is_shortcut_reference_close(child, source) {
      match open_indices.pop() {
        Some(open_index) => {
          let opener = children[open_index]
          let start = opener.origin().start()
          let is_image = start > 0 &&
            char_at(source, start - 1) is Some('!') &&
            !preceded_by_odd_backslashes(source, start - 1)
          let mut contains_link = false
          for inner = open_index + 1; inner < index; inner = inner + 1 {
            if markdown_ir_contains_link(children[inner]) {
              contains_link = true
              break
            }
          }
          if contains_link && !is_image {
            guarded[open_index] = MarkdownIR::unsupported(
              LOCAL_NESTED_LINK_OPENER,
              opener.origin(),
            )
          }
        }
        None => ()
      }
    }
  }
  guarded
}

///|
fn restore_local_nested_link_openers(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let restored : Array[MarkdownIR] = []
  let mut index = 0
  while index < children.length() {
    let child = children[index]
    if child.node is Unsupported(LOCAL_NESTED_LINK_OPENER) {
      if index + 1 < children.length() {
        let next = children[index + 1]
        match next.node {
          Text(value) if child.origin().end() == next.origin().start() => {
            restored.push(
              MarkdownIR::text(
                "[" + value,
                MarkdownIROrigin(
                  start=child.origin().start(),
                  end=next.origin().end(),
                ),
              ),
            )
            index = index + 2
            continue
          }
          _ => ()
        }
      }
      restored.push(MarkdownIR::text("[", child.origin()))
    } else {
      restored.push(child)
    }
    index = index + 1
  }
  restored
}

///|
#warnings("-unused_value")
priv enum LocalBlockPlacement {
  RelativeLocalBlock
  ContextualAbsoluteBlock
} derive(Eq)

///|
#warnings("-unused_value")
priv struct LocalBlockPlan {
  source_id : @core.SourceId
  source : String
  unresolved : MarkdownIR
  reference_candidates : Array[LocalReferenceCandidate]
} derive(Eq)

///|
#warnings("-unused_value")
priv struct ResolvedLocalBlock {
  ir : MarkdownIR
  placement : LocalBlockPlacement
} derive(Eq)

///|
fn resolve_local_markdown_ir(
  ir : MarkdownIR,
  reference_candidates : Array[LocalReferenceCandidate],
  reference_candidate_indices : @hashmap.HashMap[String, Int],
  context : MarkdownIRLoweringContext,
) -> MarkdownIR {
  fn resolve_sequence(children : Array[MarkdownIR]) -> Array[MarkdownIR] {
    let resolved : Array[MarkdownIR] = []
    for child in children {
      let candidate = match child.node {
        Unsupported(placeholder) =>
          find_local_reference_candidate(
            reference_candidates, reference_candidate_indices, placeholder,
          )
        _ => None
      }
      match candidate {
        Some(candidate) => {
          let definition = match candidate.normalized_label {
            Some(label) => (context.reference_definition_lookup)(label)
            None => None
          }
          match definition {
            Some(definition) => {
              let (should_finalize, display_children) = take_local_deferred_inline_finalize(
                candidate.display,
              )
              let display = finish_local_inline_resolution(
                resolve_sequence(display_children),
                should_finalize,
                context,
              )
              let link = MarkdownIR::link_with_metadata(
                display,
                definition.destination_value,
                definition.title_value,
                candidate.form,
                candidate.origin,
                candidate.label_origin,
                candidate.reference_label_origin,
                Some(definition.destination_value_origin),
                definition.title_value_origin,
              )
              let contains_nested_link = display.any(markdown_ir_contains_link)
              let becomes_image = match resolved.last() {
                Some(previous) =>
                  inline_image_bang_start(previous, link, context.source)
                  is Some(_)
                None => false
              }
              if contains_nested_link && !becomes_image {
                for
                  literal in hide_nested_link_opener(
                    resolve_sequence(candidate.literal),
                  ) {
                  resolved.push(literal)
                }
              } else {
                resolved.push(link)
              }
            }
            None =>
              for literal in resolve_sequence(candidate.literal) {
                resolved.push(literal)
              }
          }
        }
        None =>
          resolved.push(
            resolve_local_markdown_ir(
              child, reference_candidates, reference_candidate_indices, context,
            ),
          )
      }
    }
    resolved
  }
  fn resolve_inline(children : Array[MarkdownIR]) -> Array[MarkdownIR] {
    let (should_finalize, inline_children) = take_local_deferred_inline_finalize(
      children,
    )
    finish_local_inline_resolution(
      resolve_sequence(inline_children),
      should_finalize,
      context,
    )
  }
  let node : MarkdownIRNode = match ir.node {
    Document(children) =>
      Document(
        children.map(child => {
          resolve_local_markdown_ir(
            child, reference_candidates, reference_candidate_indices, context,
          )
        }),
      )
    Heading(depth, children, content_origin) =>
      Heading(depth, resolve_inline(children), content_origin)
    Paragraph(children, content_origin) =>
      Paragraph(resolve_inline(children), content_origin)
    BlockQuote(children) =>
      BlockQuote(
        children.map(child => {
          resolve_local_markdown_ir(
            child, reference_candidates, reference_candidate_indices, context,
          )
        }),
      )
    UnorderedList(children, spread, marker) =>
      UnorderedList(
        children.map(child => {
          resolve_local_markdown_ir(
            child, reference_candidates, reference_candidate_indices, context,
          )
        }),
        spread,
        marker,
      )
    OrderedList(children, spread, marker) =>
      OrderedList(
        children.map(child => {
          resolve_local_markdown_ir(
            child, reference_candidates, reference_candidate_indices, context,
          )
        }),
        spread,
        marker,
      )
    ListItem(children, spread, content_origin, marker, task) =>
      ListItem(
        children.map(child => {
          resolve_local_markdown_ir(
            child, reference_candidates, reference_candidate_indices, context,
          )
        }),
        spread,
        content_origin,
        marker,
        task,
      )
    OrderedListItem(children, spread, content_origin, marker, task) =>
      OrderedListItem(
        children.map(child => {
          resolve_local_markdown_ir(
            child, reference_candidates, reference_candidate_indices, context,
          )
        }),
        spread,
        content_origin,
        marker,
        task,
      )
    CodeBlock(info, value, content_origin) =>
      CodeBlock(info, value, content_origin)
    HtmlBlock(value, content_origin) => HtmlBlock(value, content_origin)
    ThematicBreak => ThematicBreak
    Text(value) => Text(value)
    ReferenceLinkOpener => ReferenceLinkOpener
    Bold(children, content_origin) =>
      Bold(resolve_inline(children), content_origin)
    Italic(children, content_origin) =>
      Italic(resolve_inline(children), content_origin)
    InlineCode(value, content_origin) => InlineCode(value, content_origin)
    Link(children, destination, title, surface) =>
      Link(resolve_inline(children), destination, title, surface)
    Image(children, destination, title, surface) =>
      Image(resolve_inline(children), destination, title, surface)
    Autolink(kind, display, destination, display_origin, destination_origin) =>
      Autolink(kind, display, destination, display_origin, destination_origin)
    InlineHtml(value, content_origin) => InlineHtml(value, content_origin)
    SoftBreak(content_origin) => SoftBreak(content_origin)
    HardBreak(surface, content_origin) => HardBreak(surface, content_origin)
    Unsupported(message) => Unsupported(message)
    Raw(value, diagnostics) => Raw(value, diagnostics)
    Recovered(message, diagnostics) => Recovered(message, diagnostics)
  }
  { node, origin: ir.origin }
}

///|
#warnings("-unused_value")
fn lower_local_unresolved_block(
  source_id : @core.SourceId,
  cst : @seam.CstNode,
) -> LocalBlockPlan {
  let root = @seam.SyntaxNode::from_cst(cst)
  let source = root.text()
  let reference_candidates : Array[LocalReferenceCandidate] = []
  let context : MarkdownIRLoweringContext = {
    source_id,
    source,
    reference_definition_lookup: _ => None,
    diagnostics_in_origin: _ => [],
    deferred_reference_candidates: Some(reference_candidates),
    extensions: MarkdownExtensions::none(),
  }
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node_with_diags(node, lower, context)
  }
  { source_id, source, unresolved: lower(root), reference_candidates }
}

///|
#warnings("-unused_value")
fn resolved_local_block_requires_context(block : ResolvedLocalBlock) -> Bool {
  guard block.placement is RelativeLocalBlock else { return false }
  let pending = [block.ir]
  while pending.length() > 0 {
    let current = pending.pop().unwrap()
    if current.node is Raw(_, _) || current.node is Recovered(_, _) {
      return true
    }
    for child in current.children() {
      pending.push(child)
    }
  }
  false
}

///|
#warnings("-unused_value")
fn lower_contextual_resolved_block(
  source_id : @core.SourceId,
  block : @seam.SyntaxNode,
  source : String,
  lookup : (String) -> LinkReferenceDefinition?,
  diagnostics_in_block : (MarkdownIROrigin) -> Array[@core.Diagnostic],
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> ResolvedLocalBlock {
  let context : MarkdownIRLoweringContext = {
    source_id,
    source,
    reference_definition_lookup: lookup,
    diagnostics_in_origin: diagnostics_in_block,
    deferred_reference_candidates: None,
    extensions,
  }
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node_with_diags(node, lower, context)
  }
  {
    ir: finalize_reference_link_openers(
      decode_markdown_ir_text_entities(lower(block), source),
    ),
    placement: ContextualAbsoluteBlock,
  }
}

///|
#warnings("-unused_value")
fn resolve_local_block(
  plan : LocalBlockPlan,
  lookup : (String) -> LinkReferenceDefinition?,
) -> ResolvedLocalBlock {
  let mut reference_candidate_indices : @hashmap.HashMap[String, Int] = @hashmap.HashMap::new()
  for index, candidate in plan.reference_candidates {
    reference_candidate_indices = reference_candidate_indices.add(
      candidate.placeholder,
      index,
    )
  }
  let context : MarkdownIRLoweringContext = {
    source_id: plan.source_id,
    source: plan.source,
    reference_definition_lookup: lookup,
    diagnostics_in_origin: _ => [],
    deferred_reference_candidates: None,
    extensions: MarkdownExtensions::none(),
  }
  {
    ir: finalize_reference_link_openers(
      decode_markdown_ir_text_entities(
        resolve_local_markdown_ir(
          plan.unresolved,
          plan.reference_candidates,
          reference_candidate_indices,
          context,
        ),
        plan.source,
      ),
    ),
    placement: RelativeLocalBlock,
  }
}

///|
fn shift_local_origin(
  origin : MarkdownIROrigin,
  base : Int,
) -> MarkdownIROrigin {
  MarkdownIROrigin(start=origin.start() + base, end=origin.end() + base)
}

///|
fn shift_optional_local_origin(
  origin : MarkdownIROrigin?,
  base : Int,
) -> MarkdownIROrigin? {
  origin.map(value => shift_local_origin(value, base))
}

///|
fn place_local_task(task : MarkdownIRTask?, base : Int) -> MarkdownIRTask? {
  task.map(task => {
    MarkdownIRTask(
      checked=task.checked(),
      marker_origin=shift_local_origin(task.marker_origin(), base),
    )
  })
}

///|
fn place_local_link_surface(surface : LinkSurface, base : Int) -> LinkSurface {
  let destination_is_block_owned = surface.form
    is LinkReferenceForm::InlineLinkForm
  {
    form: surface.form,
    label_origin: shift_optional_local_origin(surface.label_origin, base),
    reference_label_origin: shift_optional_local_origin(
      surface.reference_label_origin,
      base,
    ),
    destination_origin: if destination_is_block_owned {
      shift_optional_local_origin(surface.destination_origin, base)
    } else {
      surface.destination_origin
    },
    title_origin: if destination_is_block_owned {
      shift_optional_local_origin(surface.title_origin, base)
    } else {
      surface.title_origin
    },
    target_origin: if destination_is_block_owned {
      shift_optional_local_origin(surface.target_origin, base)
    } else {
      surface.target_origin
    },
  }
}

///|
fn place_local_markdown_ir(ir : MarkdownIR, base : Int) -> MarkdownIR {
  let node : MarkdownIRNode = match ir.node {
    Document(children) =>
      Document(children.map(child => place_local_markdown_ir(child, base)))
    Heading(depth, children, content_origin) =>
      Heading(
        depth,
        children.map(child => place_local_markdown_ir(child, base)),
        shift_optional_local_origin(content_origin, base),
      )
    Paragraph(children, content_origin) =>
      Paragraph(
        children.map(child => place_local_markdown_ir(child, base)),
        shift_optional_local_origin(content_origin, base),
      )
    BlockQuote(children) =>
      BlockQuote(children.map(child => place_local_markdown_ir(child, base)))
    UnorderedList(children, spread, marker) =>
      UnorderedList(
        children.map(child => place_local_markdown_ir(child, base)),
        spread,
        marker,
      )
    OrderedList(children, spread, marker) =>
      OrderedList(
        children.map(child => place_local_markdown_ir(child, base)),
        spread,
        marker,
      )
    ListItem(children, spread, content_origin, marker, task) =>
      ListItem(
        children.map(child => place_local_markdown_ir(child, base)),
        spread,
        shift_optional_local_origin(content_origin, base),
        marker,
        place_local_task(task, base),
      )
    OrderedListItem(children, spread, content_origin, marker, task) =>
      OrderedListItem(
        children.map(child => place_local_markdown_ir(child, base)),
        spread,
        shift_optional_local_origin(content_origin, base),
        marker,
        place_local_task(task, base),
      )
    CodeBlock(info, value, content_origin) =>
      CodeBlock(info, value, shift_optional_local_origin(content_origin, base))
    HtmlBlock(value, content_origin) =>
      HtmlBlock(value, shift_optional_local_origin(content_origin, base))
    ThematicBreak => ThematicBreak
    Text(value) => Text(value)
    ReferenceLinkOpener => ReferenceLinkOpener
    Bold(children, content_origin) =>
      Bold(
        children.map(child => place_local_markdown_ir(child, base)),
        shift_optional_local_origin(content_origin, base),
      )
    Italic(children, content_origin) =>
      Italic(
        children.map(child => place_local_markdown_ir(child, base)),
        shift_optional_local_origin(content_origin, base),
      )
    InlineCode(value, content_origin) =>
      InlineCode(value, shift_optional_local_origin(content_origin, base))
    Link(children, destination, title, surface) =>
      Link(
        children.map(child => place_local_markdown_ir(child, base)),
        destination,
        title,
        place_local_link_surface(surface, base),
      )
    Image(children, destination, title, surface) =>
      Image(
        children.map(child => place_local_markdown_ir(child, base)),
        destination,
        title,
        place_local_link_surface(surface, base),
      )
    Autolink(kind, display, destination, display_origin, destination_origin) =>
      Autolink(
        kind,
        display,
        destination,
        shift_optional_local_origin(display_origin, base),
        shift_optional_local_origin(destination_origin, base),
      )
    InlineHtml(value, content_origin) =>
      InlineHtml(value, shift_optional_local_origin(content_origin, base))
    SoftBreak(content_origin) =>
      SoftBreak(shift_optional_local_origin(content_origin, base))
    HardBreak(surface, content_origin) =>
      HardBreak(surface, shift_optional_local_origin(content_origin, base))
    Unsupported(message) => Unsupported(message)
    Raw(value, diagnostics) => Raw(value, diagnostics)
    Recovered(message, diagnostics) => Recovered(message, diagnostics)
  }
  { node, origin: shift_local_origin(ir.origin, base) }
}

///|
#warnings("-unused_value")
fn place_resolved_local_block(
  block : ResolvedLocalBlock,
  base : Int,
) -> MarkdownIR {
  match block.placement {
    RelativeLocalBlock => {
      guard !resolved_local_block_requires_context(block) else {
        abort(
          "resolved local block requires contextual lowering for recovery atoms",
        )
      }
      place_local_markdown_ir(block.ir, base)
    }
    // Contextual blocks already own absolute origins, so base is ignored.
    ContextualAbsoluteBlock => block.ir
  }
}
