///|
priv struct InlineLinkTarget {
  destination : String
  title : String?
  destination_start : Int
  destination_end : Int
  title_start : Int?
  title_end : Int?
}

///|
fn inline_link_target(
  destination : String,
  title : String?,
  destination_start : Int,
  destination_end : Int,
  title_start : Int?,
  title_end : Int?,
) -> InlineLinkTarget {
  {
    destination,
    title,
    destination_start,
    destination_end,
    title_start,
    title_end,
  }
}

///|
fn skip_inline_link_target_spaces(input : String, start : Int) -> Int {
  let mut cursor = start
  while cursor < input.length() {
    match char_at(input, cursor) {
      Some(' ') | Some('\t') | Some('\r') | Some('\n') => cursor = cursor + 1
      _ => break
    }
  }
  cursor
}

///|
fn parse_inline_link_target(input : String) -> InlineLinkTarget? {
  let destination_start = skip_inline_link_target_spaces(input, 0)
  if destination_start == input.length() {
    return Some(
      inline_link_target(
        "",
        None,
        destination_start,
        destination_start,
        None,
        None,
      ),
    )
  }
  guard consume_reference_destination(input, destination_start)
    is Some(after_destination) else {
    return None
  }
  let destination_value_start = if char_at(input, destination_start)
    is Some('<') {
    destination_start + 1
  } else {
    destination_start
  }
  let destination_value_end = if char_at(input, destination_start) is Some('<') {
    after_destination - 1
  } else {
    after_destination
  }
  let after_destination_space = skip_inline_link_target_spaces(
    input, after_destination,
  )
  if after_destination_space == input.length() {
    return Some(
      inline_link_target(
        decode_markdown_inline_text(
          input[destination_value_start:destination_value_end].to_owned(),
        ),
        None,
        destination_value_start,
        destination_value_end,
        None,
        None,
      ),
    )
  }
  guard after_destination_space > after_destination &&
    consume_reference_title(input, after_destination_space) is Some(after_title) else {
    return None
  }
  guard skip_inline_link_target_spaces(input, after_title) == input.length() else {
    return None
  }
  Some(
    inline_link_target(
      decode_markdown_inline_text(
        input[destination_value_start:destination_value_end].to_owned(),
      ),
      Some(
        decode_markdown_inline_text(
          input[after_destination_space + 1:after_title - 1].to_owned(),
        ),
      ),
      destination_value_start,
      destination_value_end,
      Some(after_destination_space + 1),
      Some(after_title - 1),
    ),
  )
}

///|
fn is_shortcut_reference_open(child : MarkdownIR, source : String) -> Bool {
  match child.node {
    ReferenceLinkOpener => true
    Text("[") => source_slice(source, child.origin()) == "["
    _ => false
  }
}

///|
fn literal_reference_link_opener(node : MarkdownIR) -> MarkdownIR {
  match node.node {
    ReferenceLinkOpener => MarkdownIR::text("[", node.origin())
    _ => node
  }
}

///|
fn is_shortcut_reference_close(child : MarkdownIR, source : String) -> Bool {
  match child.node {
    Raw(value, _) | Recovered(value, _) => value == "]"
    Text("]") => source_slice(source, child.origin()) == "]"
    _ => false
  }
}

///|
priv struct ShortcutReferenceFrame {
  opener : MarkdownIR
  children : Array[ShortcutReferenceChunk]
  mut contains_balanced_brackets : Bool
}

///|
priv enum ShortcutReferenceChunk {
  ShortcutReferenceAtom(MarkdownIR)
  LiteralShortcutBracket(MarkdownIR, Array[ShortcutReferenceChunk], MarkdownIR)
}

///|
fn push_shortcut_reference_chunk(
  output : Array[ShortcutReferenceChunk],
  frames : Array[ShortcutReferenceFrame],
  chunk : ShortcutReferenceChunk,
) -> Unit {
  match frames.last() {
    Some(frame) => frame.children.push(chunk)
    None => output.push(chunk)
  }
}

///|
fn push_shortcut_reference_atom(
  output : Array[ShortcutReferenceChunk],
  frames : Array[ShortcutReferenceFrame],
  atom : MarkdownIR,
) -> Unit {
  push_shortcut_reference_chunk(output, frames, ShortcutReferenceAtom(atom))
}

///|
fn flatten_shortcut_reference_chunks(
  chunks : Array[ShortcutReferenceChunk],
) -> Array[MarkdownIR] {
  let flattened : Array[MarkdownIR] = []
  let pending : Array[ShortcutReferenceChunk] = []
  for index = chunks.length() - 1; index >= 0; index = index - 1 {
    pending.push(chunks[index])
  }
  while pending.length() > 0 {
    match pending.pop().unwrap() {
      ShortcutReferenceAtom(atom) => flattened.push(atom)
      LiteralShortcutBracket(opener, children, closer) => {
        pending.push(ShortcutReferenceAtom(closer))
        for index = children.length() - 1; index >= 0; index = index - 1 {
          pending.push(children[index])
        }
        pending.push(ShortcutReferenceAtom(opener))
      }
    }
  }
  flattened
}

///|
priv struct LiteralShortcutSuffixFrame {
  reference : ShortcutReferenceFrame
  closer : MarkdownIR
  atoms : Array[MarkdownIR]
  mut depth : Int
}

///|
priv struct OrphanLiteralShortcutSuffixFrame {
  closer : MarkdownIR
  atoms : Array[MarkdownIR]
  mut depth : Int
}

///|
priv struct FullReferenceSuffixFrame {
  label : ShortcutReferenceFrame
  label_closer : MarkdownIR
  reference_opener : MarkdownIR
  reference_children : Array[MarkdownIR]
}

///|
fn emit_literal_shortcut_frame(
  output : Array[ShortcutReferenceChunk],
  frames : Array[ShortcutReferenceFrame],
  frame : ShortcutReferenceFrame,
  closer : MarkdownIR,
) -> Unit {
  push_shortcut_reference_chunk(
    output,
    frames,
    LiteralShortcutBracket(
      MarkdownIR::text("[", frame.opener.origin()),
      frame.children,
      MarkdownIR::text("]", closer.origin()),
    ),
  )
}

///|
const COMMONMARK_LINK_LABEL_MAX_CHARACTERS = 999

///|
/// CommonMark counts Unicode characters rather than UTF-8 bytes. Stop after
/// the first over-limit character so every lookup performs bounded work.
fn link_reference_label_is_within_limit(
  source : String,
  origin : MarkdownIROrigin,
) -> Bool {
  let mut cursor = origin.start()
  let mut character_count = 0
  while cursor < origin.end() {
    if character_count == COMMONMARK_LINK_LABEL_MAX_CHARACTERS {
      return false
    }
    cursor = match reference_line_ending_end(source, cursor) {
      Some(after_line_ending) if after_line_ending <= origin.end() =>
        after_line_ending
      _ => @core.next_char_offset(source, cursor)
    }
    character_count = character_count + 1
  }
  true
}

///|
fn lookup_bounded_link_reference_definition(
  context : MarkdownIRLoweringContext,
  label_origin : MarkdownIROrigin,
) -> LinkReferenceDefinition? {
  match bounded_link_reference_label(context, label_origin) {
    Some(label) => (context.reference_definition_lookup)(label)
    None => None
  }
}

///|
fn bounded_link_reference_label(
  context : MarkdownIRLoweringContext,
  label_origin : MarkdownIROrigin,
) -> String? {
  guard link_reference_label_is_within_limit(context.source, label_origin) else {
    return None
  }
  Some(
    normalize_link_reference_label(source_slice(context.source, label_origin)),
  )
}

///|
fn emit_resolved_shortcut_reference(
  output : Array[ShortcutReferenceChunk],
  frames : Array[ShortcutReferenceFrame],
  frame : ShortcutReferenceFrame,
  closer : MarkdownIR,
  context : MarkdownIRLoweringContext,
) -> Unit {
  let opener_origin = frame.opener.origin()
  let closer_origin = closer.origin()
  let label_origin = MarkdownIROrigin(
    start=opener_origin.end(),
    end=closer_origin.start(),
  )
  match lookup_bounded_link_reference_definition(context, label_origin) {
    Some(definition) =>
      push_shortcut_reference_atom(
        output,
        frames,
        MarkdownIR::link_with_metadata(
          flatten_shortcut_reference_chunks(frame.children),
          definition.destination_value,
          definition.title_value,
          LinkReferenceForm::ShortcutReferenceLinkForm,
          MarkdownIROrigin(start=opener_origin.start(), end=closer_origin.end()),
          Some(label_origin),
          None,
          Some(definition.destination_value_origin),
          definition.title_value_origin,
        ),
      )
    None => emit_literal_shortcut_frame(output, frames, frame, closer)
  }
}

///|
fn literal_shortcut_suffix_atom(atom : MarkdownIR) -> MarkdownIR {
  match atom.node {
    Raw(value, _) | Recovered(value, _) =>
      MarkdownIR::text(value, atom.origin())
    ReferenceLinkOpener => literal_reference_link_opener(atom)
    _ => atom
  }
}

///|
fn resolve_shortcut_references(
  children : Array[MarkdownIR],
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  let output : Array[ShortcutReferenceChunk] = []
  let frames : Array[ShortcutReferenceFrame] = []
  let mut pending : (ShortcutReferenceFrame, MarkdownIR)? = None
  let mut orphan_close : MarkdownIR? = None
  let mut literal_suffix : LiteralShortcutSuffixFrame? = None
  let mut orphan_literal_suffix : OrphanLiteralShortcutSuffixFrame? = None
  let mut full_reference_suffix : FullReferenceSuffixFrame? = None
  // Each structural bracket atom is consumed exactly once.  The parser has
  // already classified LinkNode candidates, so this pass never reparses a
  // suffix or searches ahead for a closer.
  for child in children {
    match full_reference_suffix {
      Some(suffix) =>
        if is_shortcut_reference_close(child, context.source) {
          let reference_origin = MarkdownIROrigin(
            start=suffix.reference_opener.origin().end(),
            end=child.origin().start(),
          )
          match
            lookup_bounded_link_reference_definition(context, reference_origin) {
            Some(definition) =>
              push_shortcut_reference_atom(
                output,
                frames,
                MarkdownIR::link_with_metadata(
                  flatten_shortcut_reference_chunks(suffix.label.children),
                  definition.destination_value,
                  definition.title_value,
                  LinkReferenceForm::FullReferenceLinkForm,
                  MarkdownIROrigin(
                    start=suffix.label.opener.origin().start(),
                    end=child.origin().end(),
                  ),
                  Some(
                    MarkdownIROrigin(
                      start=suffix.label.opener.origin().end(),
                      end=suffix.label_closer.origin().start(),
                    ),
                  ),
                  Some(reference_origin),
                  Some(definition.destination_value_origin),
                  definition.title_value_origin,
                ),
              )
            None => {
              emit_literal_shortcut_frame(
                output,
                frames,
                suffix.label,
                suffix.label_closer,
              )
              let literal_reference_children : Array[ShortcutReferenceChunk] = []
              for atom in suffix.reference_children {
                if is_shortcut_reference_open(atom, context.source) {
                  literal_reference_children.push(ShortcutReferenceAtom(atom))
                } else {
                  literal_reference_children.push(ShortcutReferenceAtom(atom))
                }
              }
              pending = Some(
                (
                  {
                    opener: suffix.reference_opener,
                    children: literal_reference_children,
                    contains_balanced_brackets: false,
                  },
                  child,
                ),
              )
            }
          }
          full_reference_suffix = None
        } else {
          suffix.reference_children.push(child)
        }
      None =>
        match orphan_literal_suffix {
          Some(suffix) => {
            suffix.atoms.push(child)
            match child.node {
              Raw("(", _) | Recovered("(", _) => suffix.depth = suffix.depth + 1
              Raw(")", _) | Recovered(")", _) => suffix.depth = suffix.depth - 1
              _ => ()
            }
            if suffix.depth == 0 {
              push_shortcut_reference_atom(
                output,
                frames,
                MarkdownIR::text("]", suffix.closer.origin()),
              )
              for atom in suffix.atoms {
                push_shortcut_reference_atom(
                  output,
                  frames,
                  literal_shortcut_suffix_atom(atom),
                )
              }
              orphan_literal_suffix = None
            }
          }
          None =>
            match literal_suffix {
              Some(suffix) => {
                suffix.atoms.push(child)
                match child.node {
                  Raw("(", _) | Recovered("(", _) =>
                    suffix.depth = suffix.depth + 1
                  Raw(")", _) | Recovered(")", _) =>
                    suffix.depth = suffix.depth - 1
                  _ => ()
                }
                if suffix.depth == 0 {
                  push_shortcut_reference_atom(
                    output,
                    frames,
                    MarkdownIR::text("[", suffix.reference.opener.origin()),
                  )
                  for
                    atom in flatten_shortcut_reference_chunks(
                      suffix.reference.children,
                    ) {
                    push_shortcut_reference_atom(
                      output,
                      frames,
                      literal_shortcut_suffix_atom(atom),
                    )
                  }
                  push_shortcut_reference_atom(
                    output,
                    frames,
                    MarkdownIR::text("]", suffix.closer.origin()),
                  )
                  for atom in suffix.atoms {
                    push_shortcut_reference_atom(
                      output,
                      frames,
                      literal_shortcut_suffix_atom(atom),
                    )
                  }
                  literal_suffix = None
                }
              }
              None =>
                match orphan_close {
                  Some(closer) if (
                      child.node is Raw("(", _) ||
                      child.node is Recovered("(", _)
                    ) &&
                    closer.origin().end() == child.origin().start() => {
                    orphan_literal_suffix = Some({
                      closer,
                      atoms: [child],
                      depth: 1,
                    })
                    orphan_close = None
                  }
                  Some(closer) => {
                    push_shortcut_reference_atom(output, frames, closer)
                    orphan_close = None
                    if is_shortcut_reference_open(child, context.source) {
                      frames.push({
                        opener: child,
                        children: [],
                        contains_balanced_brackets: false,
                      })
                    } else {
                      push_shortcut_reference_atom(output, frames, child)
                    }
                  }
                  None =>
                    match pending {
                      Some((frame, closer)) if is_shortcut_reference_open(
                          child,
                          context.source,
                        ) => {
                        full_reference_suffix = Some({
                          label: frame,
                          label_closer: closer,
                          reference_opener: child,
                          reference_children: [],
                        })
                        pending = None
                      }
                      Some((frame, closer)) if (
                          child.node is Raw("(", _) ||
                          child.node is Recovered("(", _)
                        ) &&
                        closer.origin().end() == child.origin().start() => {
                        literal_suffix = Some({
                          reference: frame,
                          closer,
                          atoms: [child],
                          depth: 1,
                        })
                        pending = None
                      }
                      Some((frame, closer)) => {
                        emit_resolved_shortcut_reference(
                          output, frames, frame, closer, context,
                        )
                        pending = None
                        if is_shortcut_reference_open(child, context.source) {
                          frames.push({
                            opener: child,
                            children: [],
                            contains_balanced_brackets: false,
                          })
                        } else if is_shortcut_reference_close(
                            child,
                            context.source,
                          ) {
                          match frames.pop() {
                            Some(frame) => {
                              match frames.last() {
                                Some(parent) =>
                                  parent.contains_balanced_brackets = true
                                None => ()
                              }
                              pending = Some((frame, child))
                            }
                            None => orphan_close = Some(child)
                          }
                        } else {
                          push_shortcut_reference_atom(output, frames, child)
                        }
                      }
                      None =>
                        if is_shortcut_reference_open(child, context.source) {
                          frames.push({
                            opener: child,
                            children: [],
                            contains_balanced_brackets: false,
                          })
                        } else if is_shortcut_reference_close(
                            child,
                            context.source,
                          ) {
                          match frames.pop() {
                            Some(frame) => {
                              match frames.last() {
                                Some(parent) =>
                                  parent.contains_balanced_brackets = true
                                None => ()
                              }
                              pending = Some((frame, child))
                            }
                            None => orphan_close = Some(child)
                          }
                        } else {
                          push_shortcut_reference_atom(output, frames, child)
                        }
                    }
                }
            }
        }
    }
  }
  match full_reference_suffix {
    Some(suffix) => {
      emit_literal_shortcut_frame(
        output,
        frames,
        suffix.label,
        suffix.label_closer,
      )
      push_shortcut_reference_atom(
        output,
        frames,
        literal_reference_link_opener(suffix.reference_opener),
      )
      for atom in suffix.reference_children {
        push_shortcut_reference_atom(output, frames, atom)
      }
    }
    None => ()
  }
  match literal_suffix {
    Some(suffix) => {
      push_shortcut_reference_atom(
        output,
        frames,
        literal_reference_link_opener(suffix.reference.opener),
      )
      for atom in flatten_shortcut_reference_chunks(suffix.reference.children) {
        push_shortcut_reference_atom(output, frames, atom)
      }
      push_shortcut_reference_atom(output, frames, suffix.closer)
      for atom in suffix.atoms {
        push_shortcut_reference_atom(output, frames, atom)
      }
    }
    None => ()
  }
  match orphan_literal_suffix {
    Some(suffix) => {
      push_shortcut_reference_atom(output, frames, suffix.closer)
      for atom in suffix.atoms {
        push_shortcut_reference_atom(output, frames, atom)
      }
    }
    None => ()
  }
  match pending {
    Some((frame, closer)) =>
      emit_resolved_shortcut_reference(output, frames, frame, closer, context)
    None => ()
  }
  match orphan_close {
    Some(closer) => push_shortcut_reference_atom(output, frames, closer)
    None => ()
  }
  // Preserve candidate provenance across nested inline containers so a parent
  // emphasis/reference pass can still resolve it. Public views expose the
  // private candidate as ordinary Text when no parent consumes it.
  for frame in frames {
    let opener = if frame.contains_balanced_brackets {
      literal_reference_link_opener(frame.opener)
    } else {
      frame.opener
    }
    output.push(ShortcutReferenceAtom(opener))
    for chunk in frame.children {
      output.push(chunk)
    }
  }
  flatten_shortcut_reference_chunks(output)
}

///|
/// Error-token parentheses are ordinary literal text when structurally
/// balanced.  Keep unmatched recovery atoms untouched.
fn literalize_balanced_raw_parentheses(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let matched = Array::make(children.length(), false)
  let open_indices : Array[Int] = []
  for index, child in children {
    match child.node {
      Raw("(", _) => open_indices.push(index)
      Raw(")", _) =>
        match open_indices.pop() {
          Some(open_index) => {
            matched[open_index] = true
            matched[index] = true
          }
          None => ()
        }
      _ => ()
    }
  }
  let output : Array[MarkdownIR] = []
  for index, child in children {
    if matched[index] {
      match child.node {
        Raw("(", _) => output.push(MarkdownIR::text("(", child.origin()))
        Raw(")", _) => output.push(MarkdownIR::text(")", child.origin()))
        _ => output.push(child)
      }
    } else {
      output.push(child)
    }
  }
  output
}

///|
fn emphasis_with_literal_reference_open(node : MarkdownIR) -> MarkdownIR? {
  let replace = fn(children : Array[MarkdownIR]) {
    let rewritten : Array[MarkdownIR] = []
    let mut found = false
    for child in children {
      match child.node {
        ReferenceLinkOpener => {
          rewritten.push(literal_reference_link_opener(child))
          found = true
        }
        _ => rewritten.push(child)
      }
    }
    (found, rewritten)
  }
  match node.node {
    Italic(children, content_origin) => {
      let (found, rewritten) = replace(children)
      if found {
        Some(MarkdownIR::italic(rewritten, node.origin(), content_origin))
      } else {
        None
      }
    }
    Bold(children, content_origin) => {
      let (found, rewritten) = replace(children)
      if found {
        Some(MarkdownIR::bold(rewritten, node.origin(), content_origin))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn emphasis_reference_open_start(node : MarkdownIR) -> Int? {
  let inner = match node.node {
    Italic(children, _) | Bold(children, _) => Some(children)
    _ => None
  }
  match inner {
    Some(children) => {
      for atom in children {
        if atom.node is ReferenceLinkOpener {
          return Some(atom.origin().start())
        }
      }
      None
    }
    None => None
  }
}

///|
/// Resolve only the parser-owned reference opener embedded in one emphasis
/// container and closed by a later sibling Raw `]`. This is a single
/// parent-level pass; it neither searches source nor recurses.
fn resolve_emphasis_boundary_shortcuts(
  children : Array[MarkdownIR],
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  let output : Array[MarkdownIR] = []
  let mut pending : (MarkdownIR, MarkdownIR, Array[MarkdownIR])? = None
  for child in children {
    match pending {
      Some((original, rewritten, between)) =>
        match child.node {
          Raw("]", _) if original.origin().end() <= child.origin().start() => {
            let opener_start = emphasis_reference_open_start(original)
            match opener_start {
              Some(start) if between.is_empty() => {
                let label_start = start + 1
                let label_end = original.origin().end()
                match
                  lookup_bounded_link_reference_definition(
                    context,
                    MarkdownIROrigin(start=label_start, end=label_end),
                  ) {
                  Some(definition) => {
                    let prefix = MarkdownIR::text(
                      context.source[original.origin().start():start].to_owned(),
                      MarkdownIROrigin(
                        start=original.origin().start(),
                        end=start,
                      ),
                    )
                    output.push(prefix)
                    let label : Array[MarkdownIR] = []
                    let mut label_cursor = label_start
                    match rewritten.node {
                      Italic(inner, _) | Bold(inner, _) =>
                        for atom in inner {
                          if atom.origin().start() >= label_start {
                            label_cursor = atom.origin().end()
                            label.push(atom)
                          }
                        }
                      _ => ()
                    }
                    if label_cursor < label_end {
                      label.push(
                        MarkdownIR::text(
                          context.source[label_cursor:label_end].to_owned(),
                          MarkdownIROrigin(start=label_cursor, end=label_end),
                        ),
                      )
                    }
                    output.push(
                      MarkdownIR::link_with_metadata(
                        label,
                        definition.destination_value,
                        definition.title_value,
                        LinkReferenceForm::ShortcutReferenceLinkForm,
                        MarkdownIROrigin(start~, end=child.origin().end()),
                        Some(MarkdownIROrigin(start=label_start, end=label_end)),
                        None,
                        Some(definition.destination_value_origin),
                        definition.title_value_origin,
                      ),
                    )
                  }
                  None => {
                    output.push(rewritten)
                    output.push(MarkdownIR::text("]", child.origin()))
                  }
                }
              }
              _ => {
                output.push(rewritten)
                for atom in between {
                  output.push(atom)
                }
                output.push(MarkdownIR::text("]", child.origin()))
              }
            }
            pending = None
          }
          _ => between.push(child)
        }
      None =>
        match emphasis_with_literal_reference_open(child) {
          Some(rewritten) => pending = Some((child, rewritten, []))
          None => output.push(child)
        }
    }
  }
  match pending {
    Some((original, _, between)) => {
      output.push(original)
      for atom in between {
        output.push(atom)
      }
    }
    None => ()
  }
  output
}

///|
fn inline_image_bang_start(
  previous : MarkdownIR,
  link : MarkdownIR,
  source : String,
) -> Int? {
  guard previous.origin().end() == link.origin().start() else { return None }
  guard (previous.node is Text(value) && value.has_suffix("!")) ||
    previous.node is Raw("!", _) else {
    return None
  }
  let bang_start = previous.origin().end() - 1
  guard char_at(source, bang_start) is Some('!') &&
    !preceded_by_odd_backslashes(source, bang_start) else {
    return None
  }
  Some(bang_start)
}

///|
fn resolve_inline_images(
  children : Array[MarkdownIR],
  source : String,
) -> Array[MarkdownIR] {
  let resolved : Array[MarkdownIR] = []
  for child in children {
    match (resolved.last(), child.node) {
      (Some(previous), Link(_, _, _, _)) =>
        match inline_image_bang_start(previous, child, source) {
          Some(bang_start) => {
            let previous = resolved.pop().unwrap()
            let remaining = match previous.node {
              Text(value) => value[0:value.length() - 1].to_owned()
              Raw("!", _) => ""
              _ => abort("inline image bang owner must be text or raw bang")
            }
            if !remaining.is_empty() {
              resolved.push(
                MarkdownIR::text(
                  remaining,
                  MarkdownIROrigin(
                    start=previous.origin().start(),
                    end=bang_start,
                  ),
                ),
              )
            }
            resolved.push(
              MarkdownIR::image_from_link(
                child,
                MarkdownIROrigin(start=bang_start, end=child.origin().end()),
              ),
            )
          }
          None => resolved.push(child)
        }
      _ => resolved.push(child)
    }
  }
  resolved
}
