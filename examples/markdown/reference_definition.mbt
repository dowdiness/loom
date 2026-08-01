///|
priv struct LinkReferenceDefinitionMatch {
  end : Int
  label_start : Int
  label_end : Int
  destination_start : Int
  destination_end : Int
  title_start : Int?
  title_end : Int?
}

///|
#warnings("-unused_field")
priv struct LinkReferenceDefinition {
  normalized_label : String
  destination_value : String
  title_value : String?
  definition_origin : MarkdownIROrigin
  label_value_origin : MarkdownIROrigin
  destination_value_origin : MarkdownIROrigin
  title_value_origin : MarkdownIROrigin?
}

///|
priv struct LinkReferenceDefinitionTable {
  entries : @hashmap.HashMap[String, LinkReferenceDefinition]
}

///|
fn LinkReferenceDefinitionTable::empty() -> LinkReferenceDefinitionTable {
  { entries: @hashmap.HashMap::new() }
}

///|
fn LinkReferenceDefinitionTable::lookup(
  self : LinkReferenceDefinitionTable,
  normalized_label : String,
) -> LinkReferenceDefinition? {
  self.entries.get(normalized_label)
}

///|
#warnings("-unused_value")
fn LinkReferenceDefinitionTable::length(
  self : LinkReferenceDefinitionTable,
) -> Int {
  self.entries.length()
}

///|
fn LinkReferenceDefinitionTable::insert_first(
  self : LinkReferenceDefinitionTable,
  definition : LinkReferenceDefinition,
) -> LinkReferenceDefinitionTable {
  if self.lookup(definition.normalized_label) is Some(_) {
    self
  } else {
    { entries: self.entries.add(definition.normalized_label, definition) }
  }
}

///|
fn skip_reference_spaces(input : String, start : Int) -> Int {
  let mut cursor = start
  while cursor < input.length() {
    match char_at(input, cursor) {
      Some(' ') | Some('\t') => cursor = cursor + 1
      _ => break
    }
  }
  cursor
}

///|
fn skip_reference_initial_spaces(input : String) -> Int {
  let mut cursor = 0
  while cursor < input.length() && char_at(input, cursor) is Some(' ') {
    cursor = cursor + 1
  }
  cursor
}

///|
fn reference_backslash_escape_end(input : String, start : Int) -> Int? {
  guard char_at(input, start) is Some('\\') && start + 1 < input.length() else {
    return None
  }
  match char_at(input, start + 1) {
    Some(ch) if ch.is_ascii_punctuation() =>
      Some(@core.next_char_offset(input, start + 1))
    _ => None
  }
}

///|
fn consume_reference_label(input : String, start : Int) -> Int? {
  guard char_at(input, start) is Some('[') else { return None }
  let mut cursor = start + 1
  let mut content_chars = 0
  while cursor < input.length() && content_chars <= 999 {
    match char_at(input, cursor) {
      Some(']') if content_chars > 0 => return Some(cursor + 1)
      Some('[') | None => return None
      Some('\r') | Some('\n') => {
        guard reference_line_ending_end(input, cursor) is Some(after_newline) else {
          return None
        }
        let next_content = skip_reference_spaces(input, after_newline)
        guard reference_line_ending_end(input, next_content) is None else {
          return None
        }
        content_chars = content_chars + 1
        cursor = after_newline
      }
      Some('\\') =>
        match reference_backslash_escape_end(input, cursor) {
          Some(after_escape) => {
            cursor = after_escape
            content_chars = content_chars + 2
          }
          None => {
            cursor = cursor + 1
            content_chars = content_chars + 1
          }
        }
      Some(_) => {
        let next = @core.next_char_offset(input, cursor)
        content_chars = content_chars + 1
        cursor = next
      }
    }
  }
  None
}

///|
fn consume_reference_destination(input : String, start : Int) -> Int? {
  guard start < input.length() else { return None }
  if char_at(input, start) is Some('<') {
    let mut cursor = start + 1
    while cursor < input.length() {
      match char_at(input, cursor) {
        Some('>') => return Some(cursor + 1)
        Some('<') | Some('\r') | Some('\n') | None => return None
        Some('\\') =>
          match reference_backslash_escape_end(input, cursor) {
            Some(after_escape) => cursor = after_escape
            None => cursor = cursor + 1
          }
        Some(_) => cursor = @core.next_char_offset(input, cursor)
      }
    }
    return None
  }
  let mut cursor = start
  let mut depth = 0
  while cursor < input.length() {
    match char_at(input, cursor) {
      Some('\\') =>
        match reference_backslash_escape_end(input, cursor) {
          Some(after_escape) => cursor = after_escape
          None => cursor = cursor + 1
        }
      Some('(') => {
        guard depth < 32 else { return None }
        depth = depth + 1
        cursor = cursor + 1
      }
      Some(')') if depth > 0 => {
        depth = depth - 1
        cursor = cursor + 1
      }
      Some(')') => return None
      Some(' ') | Some('\t') | Some('\r') | Some('\n') | None => break
      Some(ch) if ch.to_int() < 0x20 || ch.to_int() == 0x7F => return None
      Some(_) => cursor = @core.next_char_offset(input, cursor)
    }
  }
  if cursor > start && depth == 0 {
    Some(cursor)
  } else {
    None
  }
}

///|
fn consume_reference_title(input : String, start : Int) -> Int? {
  let close = match char_at(input, start) {
    Some('\"') => '\"'
    Some('\'') => '\''
    Some('(') => ')'
    _ => return None
  }
  let mut cursor = start + 1
  while cursor < input.length() {
    match char_at(input, cursor) {
      Some(ch) if ch == close => return Some(cursor + 1)
      Some('\r') | Some('\n') => {
        guard reference_line_ending_end(input, cursor) is Some(after_newline) else {
          return None
        }
        let next_content = skip_reference_spaces(input, after_newline)
        guard reference_line_ending_end(input, next_content) is None else {
          return None
        }
        cursor = after_newline
      }
      None => return None
      Some('\\') =>
        match reference_backslash_escape_end(input, cursor) {
          Some(after_escape) => cursor = after_escape
          None => cursor = cursor + 1
        }
      Some(_) => cursor = @core.next_char_offset(input, cursor)
    }
  }
  None
}

///|
fn reference_line_ending_end(input : String, start : Int) -> Int? {
  match input.view(start_offset=start) {
    ['\r', '\n', ..] => Some(start + 2)
    ['\r', ..] | ['\n', ..] => Some(start + 1)
    _ => None
  }
}

///|
fn finish_reference_definition_line(input : String, start : Int) -> Int? {
  let line_end = skip_reference_spaces(input, start)
  match reference_line_ending_end(input, line_end) {
    Some(end) => Some(end)
    None if line_end == input.length() => Some(line_end)
    None => None
  }
}

///|
fn reference_definition_match(
  end : Int,
  label_start : Int,
  label_end : Int,
  destination_start : Int,
  destination_end : Int,
  title_start : Int?,
  title_end : Int?,
) -> LinkReferenceDefinitionMatch {
  {
    end,
    label_start,
    label_end,
    destination_start,
    destination_end,
    title_start,
    title_end,
  }
}

///|
fn classify_link_reference_definition(
  input : String,
) -> LinkReferenceDefinitionMatch? {
  let label_start = skip_reference_initial_spaces(input)
  guard label_start <= 3 else { return None }
  guard consume_reference_label(input, label_start) is Some(after_label) else {
    return None
  }
  guard normalize_link_reference_label(
      input[label_start + 1:after_label - 1].to_owned(),
    ) !=
    "" else {
    return None
  }
  guard char_at(input, after_label) is Some(':') else { return None }
  let after_colon_space = skip_reference_spaces(input, after_label + 1)
  let destination_start = match
    reference_line_ending_end(input, after_colon_space) {
    Some(after_newline) => skip_reference_spaces(input, after_newline)
    None => after_colon_space
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
  if after_destination_space > after_destination {
    match consume_reference_title(input, after_destination_space) {
      Some(title_end) => {
        guard finish_reference_definition_line(input, title_end) is Some(end) else {
          return None
        }
        return Some(
          reference_definition_match(
            end,
            label_start + 1,
            after_label - 1,
            destination_value_start,
            destination_value_end,
            Some(after_destination_space + 1),
            Some(title_end - 1),
          ),
        )
      }
      None => ()
    }
  }
  match reference_line_ending_end(input, after_destination_space) {
    Some(definition_end) => {
      let next_title_start = skip_reference_spaces(input, definition_end)
      match consume_reference_title(input, next_title_start) {
        Some(title_end) =>
          match finish_reference_definition_line(input, title_end) {
            Some(end) =>
              Some(
                reference_definition_match(
                  end,
                  label_start + 1,
                  after_label - 1,
                  destination_value_start,
                  destination_value_end,
                  Some(next_title_start + 1),
                  Some(title_end - 1),
                ),
              )
            None =>
              Some(
                reference_definition_match(
                  definition_end,
                  label_start + 1,
                  after_label - 1,
                  destination_value_start,
                  destination_value_end,
                  None,
                  None,
                ),
              )
          }
        None =>
          Some(
            reference_definition_match(
              definition_end,
              label_start + 1,
              after_label - 1,
              destination_value_start,
              destination_value_end,
              None,
              None,
            ),
          )
      }
    }
    None if after_destination_space == input.length() =>
      Some(
        reference_definition_match(
          after_destination_space,
          label_start + 1,
          after_label - 1,
          destination_value_start,
          destination_value_end,
          None,
          None,
        ),
      )
    None => None
  }
}

///|
fn normalize_link_reference_label(label : String) -> String {
  let decoded = decode_markdown_inline_text(label)
  let builder = StringBuilder::StringBuilder()
  let mut has_content = false
  let mut pending_space = false
  for ch in decoded {
    match ch {
      ' ' | '\t' | '\r' | '\n' => if has_content { pending_space = true }
      _ => {
        if pending_space {
          builder.write_char(' ')
        }
        builder.write_char(ch)
        has_content = true
        pending_space = false
      }
    }
  }
  @casefold.casefold(builder.to_string())
}

///|
fn link_reference_definition_from_node(
  node : @seam.SyntaxNode,
) -> LinkReferenceDefinition? {
  let source = node.text()
  guard classify_link_reference_definition(source) is Some(definition) else {
    return None
  }
  let base = node.start()
  let title_value = match (definition.title_start, definition.title_end) {
    (Some(start), Some(end)) =>
      Some(decode_markdown_inline_text(source[start:end].to_owned()))
    _ => None
  }
  let title_value_origin = match
    (definition.title_start, definition.title_end) {
    (Some(start), Some(end)) =>
      Some(MarkdownIROrigin(start=base + start, end=base + end))
    _ => None
  }
  Some({
    normalized_label: normalize_link_reference_label(
      source[definition.label_start:definition.label_end].to_owned(),
    ),
    destination_value: decode_markdown_inline_text(
      source[definition.destination_start:definition.destination_end].to_owned(),
    ),
    title_value,
    definition_origin: MarkdownIROrigin(start=base, end=base + definition.end),
    label_value_origin: MarkdownIROrigin(
      start=base + definition.label_start,
      end=base + definition.label_end,
    ),
    destination_value_origin: MarkdownIROrigin(
      start=base + definition.destination_start,
      end=base + definition.destination_end,
    ),
    title_value_origin,
  })
}

///|
fn collect_link_reference_definitions_walk(
  node : @seam.SyntaxNode,
  table : LinkReferenceDefinitionTable,
) -> LinkReferenceDefinitionTable {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  if kind is LinkReferenceDefinitionNode {
    match link_reference_definition_from_node(node) {
      Some(definition) => table.insert_first(definition)
      None => table
    }
  } else {
    let mut next = table
    for child in node.children() {
      next = collect_link_reference_definitions_walk(child, next)
    }
    next
  }
}

///|
fn collect_link_reference_definitions(
  root : @seam.SyntaxNode,
) -> LinkReferenceDefinitionTable {
  collect_link_reference_definitions_walk(
    root,
    LinkReferenceDefinitionTable::empty(),
  )
}

///|
fn current_reference_definition_source(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> String {
  let builder = StringBuilder::StringBuilder()
  let start = ctx.cursor_position()
  for offset = 0 {
    match ctx.peek_index(offset) {
      EOF | BlankLine => break
      Newline => {
        builder.write_string(ctx.token_text_at(start + offset).to_owned())
        continue offset + 1
      }
      _ => {
        builder.write_string(ctx.token_text_at(start + offset).to_owned())
        continue offset + 1
      }
    }
  }
  builder.to_string()
}

///|
fn current_link_reference_definition(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> LinkReferenceDefinitionMatch? {
  let possible_opener = match ctx.peek() {
    LeftBracket => true
    Indentation(_) =>
      current_token_leading_indent(ctx) <= 3 && ctx.peek_nth(1) is LeftBracket
    _ => false
  }
  guard possible_opener else { return None }
  let source = current_reference_definition_source(ctx)
  classify_link_reference_definition(source)
}

///|
fn current_line_is_link_reference_definition(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  current_link_reference_definition(ctx) is Some(_)
}

///|
fn parse_link_reference_definition(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  guard current_link_reference_definition(ctx) is Some(definition) else {
    abort("reference-definition parser requires a complete definition")
  }
  ctx.node(LinkReferenceDefinitionNode, fn() {
    let mut consumed = 0
    while consumed < definition.end {
      let token_length = ctx.current_token_text().length()
      guard token_length > 0 else {
        abort("reference-definition parser stopped before its classified end")
      }
      guard consumed + token_length <= definition.end else {
        abort("reference-definition classifier ended inside a token")
      }
      emit_current_token_with_actual_kind(ctx)
      consumed = consumed + token_length
    }
    guard consumed == definition.end else {
      abort("reference-definition parser did not reach its classified end")
    }
  })
}
