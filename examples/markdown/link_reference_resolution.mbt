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
fn parse_inline_link_target(input : String) -> InlineLinkTarget? {
  let destination_start = skip_reference_spaces(input, 0)
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
  let after_destination_space = skip_reference_spaces(input, after_destination)
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
  guard skip_reference_spaces(input, after_title) == input.length() else {
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
    Recovered(message, _) =>
      message == "[" && source_slice(source, child.origin()) == "["
    _ => false
  }
}

///|
fn is_shortcut_reference_close(child : MarkdownIR, source : String) -> Bool {
  match child.node {
    Raw(value, _) => value == "]" && source_slice(source, child.origin()) == "]"
    _ => false
  }
}

///|
fn shortcut_reference_close_index(
  children : Array[MarkdownIR],
  start : Int,
  source : String,
) -> Int? {
  let mut depth = 1
  for index = start + 1; index < children.length(); index = index + 1 {
    if is_shortcut_reference_open(children[index], source) {
      depth = depth + 1
    } else if is_shortcut_reference_close(children[index], source) {
      depth = depth - 1
      if depth == 0 {
        return Some(index)
      }
    }
  }
  None
}

///|
fn shortcut_reference_label_children(
  children : Array[MarkdownIR],
  start : Int,
  end : Int,
) -> Array[MarkdownIR] {
  let label : Array[MarkdownIR] = []
  for index = start + 1; index < end; index = index + 1 {
    label.push(children[index])
  }
  label
}

///|
fn shortcut_reference_has_inline_destination_suffix(
  children : Array[MarkdownIR],
  close_index : Int,
  source : String,
) -> Bool {
  let next_index = close_index + 1
  guard next_index < children.length() else { return false }
  let close_origin = children[close_index].origin()
  let next_origin = children[next_index].origin()
  close_origin.end() == next_origin.start() &&
  char_at(source, next_origin.start()) is Some('(')
}

///|
fn unmatched_reference_open_has_later_close(
  children : Array[MarkdownIR],
  index : Int,
  source : String,
) -> Bool {
  guard children.last() is Some(last) else { return false }
  let start = children[index].origin().end()
  let end = last.origin().end()
  start <= end && source[start:end].to_owned().contains("]")
}

///|
fn resolve_shortcut_references(
  children : Array[MarkdownIR],
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  let resolved : Array[MarkdownIR] = []
  let mut index = 0
  while index < children.length() {
    if is_shortcut_reference_open(children[index], context.source) {
      match shortcut_reference_close_index(children, index, context.source) {
        Some(close_index) if shortcut_reference_has_inline_destination_suffix(
            children,
            close_index,
            context.source,
          ) => {
          resolved.push(children[index])
          index = index + 1
        }
        Some(close_index) => {
          let open_origin = children[index].origin()
          let close_origin = children[close_index].origin()
          let label_origin = MarkdownIROrigin(
            start=open_origin.end(),
            end=close_origin.start(),
          )
          let definition = context.reference_definitions.lookup(
            normalize_link_reference_label(
              source_slice(context.source, label_origin),
            ),
          )
          match definition {
            Some(definition) =>
              resolved.push(
                MarkdownIR::link_with_metadata(
                  shortcut_reference_label_children(
                    children, index, close_index,
                  ),
                  definition.destination_value,
                  definition.title_value,
                  ShortcutReferenceLinkForm,
                  MarkdownIROrigin(
                    start=open_origin.start(),
                    end=close_origin.end(),
                  ),
                  Some(label_origin),
                  None,
                  Some(definition.destination_value_origin),
                  definition.title_value_origin,
                ),
              )
            None => {
              resolved.push(MarkdownIR::text("[", open_origin))
              for child_index = index + 1
                  child_index < close_index
                  child_index = child_index + 1 {
                resolved.push(children[child_index])
              }
              resolved.push(MarkdownIR::text("]", close_origin))
            }
          }
          index = close_index + 1
        }
        None => {
          if unmatched_reference_open_has_later_close(
              children,
              index,
              context.source,
            ) {
            let origin = children[index].origin()
            resolved.push(MarkdownIR::text("[", origin))
          } else {
            resolved.push(children[index])
          }
          index = index + 1
        }
      }
    } else {
      resolved.push(children[index])
      index = index + 1
    }
  }
  resolved
}

///|
fn inline_image_bang_start(
  previous : MarkdownIR,
  link : MarkdownIR,
  source : String,
) -> Int? {
  guard previous.origin().end() == link.origin().start() else { return None }
  guard previous.node is Text(value) && value.has_suffix("!") else {
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
            guard previous.node is Text(value) else {
              abort("inline image bang owner must be text")
            }
            let remaining = value[0:value.length() - 1].to_owned()
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
