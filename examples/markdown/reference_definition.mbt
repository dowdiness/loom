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
  let open = match char_at(input, start) {
    Some('\"') => '\"'
    Some('\'') => '\''
    Some('(') => '('
    _ => return None
  }
  let close = if open == '(' { ')' } else { open }
  let mut cursor = start + 1
  while cursor < input.length() {
    match char_at(input, cursor) {
      Some(ch) if ch == close => return Some(cursor + 1)
      Some('(') if open == '(' => return None
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
/// A forward-only view over reference-definition source pieces. Parser
/// lookahead supplies zero-copy token views and ends the sequence at a blank
/// line; String classification supplies one whole-source view. Every supplied
/// piece is inspected at most once. `inspected` is retained as a deterministic
/// work measure for the private adversarial test.
priv struct ReferenceDefinitionCursor {
  piece_at : (Int) -> StringView?
  mut piece_index : Int
  mut piece : StringView
  mut piece_offset : Int
  mut offset : Int
  mut inspected : Int
  mut exhausted : Bool
}

///|
fn new_reference_definition_cursor(
  piece_at : (Int) -> StringView?,
) -> ReferenceDefinitionCursor {
  {
    piece_at,
    piece_index: 0,
    piece: StringView::default(),
    piece_offset: 0,
    offset: 0,
    inspected: 0,
    exhausted: false,
  }
}

///|
fn ReferenceDefinitionCursor::ensure_piece(
  self : ReferenceDefinitionCursor,
) -> Bool {
  while self.piece_offset >= self.piece.length() && !self.exhausted {
    match (self.piece_at)(self.piece_index) {
      Some(piece) => {
        self.piece_index = self.piece_index + 1
        self.piece = piece
        self.piece_offset = 0
        self.inspected = self.inspected + piece.length()
      }
      None => self.exhausted = true
    }
  }
  !self.exhausted
}

///|
fn ReferenceDefinitionCursor::peek(self : ReferenceDefinitionCursor) -> Char? {
  if self.ensure_piece() {
    self.piece.get_char(self.piece_offset)
  } else {
    None
  }
}

///|
fn ReferenceDefinitionCursor::advance(
  self : ReferenceDefinitionCursor,
) -> Char? {
  match self.peek() {
    Some(ch) => {
      let width = if ch.to_int() > 0xFFFF { 2 } else { 1 }
      self.piece_offset = self.piece_offset + width
      self.offset = self.offset + width
      Some(ch)
    }
    None => None
  }
}

///|
fn ReferenceDefinitionCursor::skip_spaces(
  self : ReferenceDefinitionCursor,
) -> Unit {
  while self.peek() is Some(' ' | '\t') {
    ignore(self.advance())
  }
}

///|
fn ReferenceDefinitionCursor::consume_line_ending(
  self : ReferenceDefinitionCursor,
) -> Bool {
  match self.peek() {
    Some('\r') => {
      ignore(self.advance())
      if self.peek() is Some('\n') {
        ignore(self.advance())
      }
      true
    }
    Some('\n') => {
      ignore(self.advance())
      true
    }
    _ => false
  }
}

///|
fn ReferenceDefinitionCursor::consume_backslash_escape(
  self : ReferenceDefinitionCursor,
) -> Int {
  guard self.peek() is Some('\\') else { return 0 }
  ignore(self.advance())
  match self.peek() {
    Some(ch) if ch.is_ascii_punctuation() => {
      ignore(self.advance())
      2
    }
    _ => 1
  }
}

///|
fn ReferenceDefinitionCursor::consume_label(
  self : ReferenceDefinitionCursor,
) -> (Int, Int, Bool)? {
  guard self.peek() is Some('[') else { return None }
  ignore(self.advance())
  let label_start = self.offset
  let mut content_chars = 0
  let mut has_non_whitespace = false
  while content_chars <= 999 {
    match self.peek() {
      Some(']') if content_chars > 0 => {
        let label_end = self.offset
        ignore(self.advance())
        return Some((label_start, label_end, has_non_whitespace))
      }
      Some('[') | None => return None
      Some('\r') | Some('\n') => {
        guard self.consume_line_ending() else { return None }
        content_chars = content_chars + 1
        while self.peek() is Some(' ' | '\t') {
          ignore(self.advance())
          content_chars = content_chars + 1
        }
        guard !(self.peek() is Some('\r' | '\n')) else { return None }
      }
      Some('\\') => {
        content_chars = content_chars + self.consume_backslash_escape()
        has_non_whitespace = true
      }
      Some(ch) => {
        ignore(self.advance())
        content_chars = content_chars + 1
        match ch {
          ' ' | '\t' => ()
          _ => has_non_whitespace = true
        }
      }
    }
  }
  None
}

///|
fn ReferenceDefinitionCursor::consume_destination(
  self : ReferenceDefinitionCursor,
) -> (Int, Int, Bool)? {
  let start = self.offset
  guard self.peek() is Some(_) else { return None }
  if self.peek() is Some('<') {
    ignore(self.advance())
    let value_start = self.offset
    while true {
      match self.peek() {
        Some('>') => {
          let value_end = self.offset
          ignore(self.advance())
          return Some((value_start, value_end, true))
        }
        Some('<') | Some('\r') | Some('\n') | None => return None
        Some('\\') => ignore(self.consume_backslash_escape())
        Some(_) => ignore(self.advance())
      }
    }
  }
  let mut depth = 0
  while true {
    match self.peek() {
      Some('\\') => ignore(self.consume_backslash_escape())
      Some('(') => {
        guard depth < 32 else { return None }
        depth = depth + 1
        ignore(self.advance())
      }
      Some(')') if depth > 0 => {
        depth = depth - 1
        ignore(self.advance())
      }
      Some(')') => return None
      Some(' ') | Some('\t') | Some('\r') | Some('\n') | None => break
      Some(ch) if ch.to_int() < 0x20 || ch.to_int() == 0x7F => return None
      Some(_) => ignore(self.advance())
    }
  }
  if self.offset > start && depth == 0 {
    Some((start, self.offset, false))
  } else {
    None
  }
}

///|
fn ReferenceDefinitionCursor::consume_title(
  self : ReferenceDefinitionCursor,
) -> (Int, Int)? {
  let open = match self.peek() {
    Some('\"') => '\"'
    Some('\'') => '\''
    Some('(') => '('
    _ => return None
  }
  ignore(self.advance())
  let value_start = self.offset
  let close = if open == '(' { ')' } else { open }
  while true {
    match self.peek() {
      Some(ch) if ch == close => {
        let value_end = self.offset
        ignore(self.advance())
        return Some((value_start, value_end))
      }
      Some('(') if open == '(' => return None
      Some('\r') | Some('\n') => {
        guard self.consume_line_ending() else { return None }
        self.skip_spaces()
        guard !(self.peek() is Some('\r' | '\n')) else { return None }
      }
      None => return None
      Some('\\') => ignore(self.consume_backslash_escape())
      Some(_) => ignore(self.advance())
    }
  } nobreak {
    None
  }
}

///|
fn ReferenceDefinitionCursor::finish_line(
  self : ReferenceDefinitionCursor,
) -> Int? {
  self.skip_spaces()
  if self.consume_line_ending() || self.peek() is None {
    Some(self.offset)
  } else {
    None
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
priv enum ReferenceDefinitionScanOutcome {
  ReferenceDefinitionFound(LinkReferenceDefinitionMatch)
  InvalidAngleDestinationLiteral
  NoReferenceDefinition
}

///|
fn scan_reference_definition_cursor(
  cursor : ReferenceDefinitionCursor,
) -> ReferenceDefinitionScanOutcome {
  // Keep this recognizer monotonic: optional multiline labels and titles move
  // the same cursor forward instead of rebuilding and rescanning a suffix.
  let mut initial_spaces = 0
  while cursor.peek() is Some(' ') {
    ignore(cursor.advance())
    initial_spaces = initial_spaces + 1
  }
  guard initial_spaces <= 3 else { return NoReferenceDefinition }
  guard cursor.consume_label()
    is Some((label_start, label_end, label_has_content)) else {
    return NoReferenceDefinition
  }
  guard cursor.peek() is Some(':') else { return NoReferenceDefinition }
  ignore(cursor.advance())
  cursor.skip_spaces()
  let destination_on_next_line = cursor.consume_line_ending()
  if destination_on_next_line {
    cursor.skip_spaces()
  }
  guard cursor.consume_destination()
    is Some((destination_start, destination_end, angle_destination)) else {
    return NoReferenceDefinition
  }
  let after_destination = cursor.offset
  if angle_destination && !destination_on_next_line {
    match cursor.peek() {
      Some(' ' | '\t' | '\r' | '\n') | None => ()
      Some(_) => return InvalidAngleDestinationLiteral
    }
  }
  guard label_has_content else { return NoReferenceDefinition }
  cursor.skip_spaces()
  let after_destination_space = cursor.offset
  if after_destination_space > after_destination {
    match cursor.peek() {
      Some('\"' | '\'' | '(') =>
        match cursor.consume_title() {
          Some((title_start, title_end)) =>
            match cursor.finish_line() {
              Some(end) =>
                return ReferenceDefinitionFound(
                  reference_definition_match(
                    end,
                    label_start,
                    label_end,
                    destination_start,
                    destination_end,
                    Some(title_start),
                    Some(title_end),
                  ),
                )
              None => return NoReferenceDefinition
            }
          None => return NoReferenceDefinition
        }
      _ => ()
    }
  }
  if cursor.consume_line_ending() {
    let definition_end = cursor.offset
    cursor.skip_spaces()
    match cursor.peek() {
      Some('\"' | '\'' | '(') =>
        match cursor.consume_title() {
          Some((title_start, title_end)) =>
            match cursor.finish_line() {
              Some(end) =>
                ReferenceDefinitionFound(
                  reference_definition_match(
                    end,
                    label_start,
                    label_end,
                    destination_start,
                    destination_end,
                    Some(title_start),
                    Some(title_end),
                  ),
                )
              None =>
                ReferenceDefinitionFound(
                  reference_definition_match(
                    definition_end,
                    label_start,
                    label_end,
                    destination_start,
                    destination_end,
                    None,
                    None,
                  ),
                )
            }
          None =>
            ReferenceDefinitionFound(
              reference_definition_match(
                definition_end,
                label_start,
                label_end,
                destination_start,
                destination_end,
                None,
                None,
              ),
            )
        }
      _ =>
        ReferenceDefinitionFound(
          reference_definition_match(
            definition_end,
            label_start,
            label_end,
            destination_start,
            destination_end,
            None,
            None,
          ),
        )
    }
  } else if cursor.peek() is None {
    ReferenceDefinitionFound(
      reference_definition_match(
        cursor.offset,
        label_start,
        label_end,
        destination_start,
        destination_end,
        None,
        None,
      ),
    )
  } else {
    NoReferenceDefinition
  }
}

///|
fn scan_link_reference_definition(
  input : String,
) -> ReferenceDefinitionScanOutcome {
  let source = input.view()
  scan_reference_definition_cursor(
    new_reference_definition_cursor(index => {
      if index == 0 {
        Some(source)
      } else {
        None
      }
    }),
  )
}

///|
fn classify_link_reference_definition(
  input : String,
) -> LinkReferenceDefinitionMatch? {
  match scan_link_reference_definition(input) {
    ReferenceDefinitionFound(definition) => Some(definition)
    _ => None
  }
}

///|
fn normalize_link_reference_label(label : String) -> String {
  let builder = StringBuilder::StringBuilder()
  let mut has_content = false
  let mut pending_space = false
  for ch in label {
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
fn current_reference_definition_scan(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ReferenceDefinitionScanOutcome {
  let start = ctx.cursor_position()
  let cursor = new_reference_definition_cursor(offset => {
    match ctx.peek_index(offset) {
      EOF | BlankLine => None
      _ => Some(ctx.token_text_at(start + offset))
    }
  })
  scan_reference_definition_cursor(cursor)
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
  match current_reference_definition_scan(ctx) {
    ReferenceDefinitionFound(definition) => Some(definition)
    _ => None
  }
}

///|
fn current_line_is_link_reference_definition(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  current_link_reference_definition(ctx) is Some(_)
}

///|
fn current_line_has_invalid_reference_definition_angle_destination(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Bool {
  let possible_opener = match ctx.peek() {
    LeftBracket => true
    Indentation(_) =>
      current_token_leading_indent(ctx) <= 3 && ctx.peek_nth(1) is LeftBracket
    _ => false
  }
  possible_opener &&
  current_reference_definition_scan(ctx) is InvalidAngleDestinationLiteral
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

///|
/// A malformed angle destination remains an ordinary paragraph, but block
/// ownership emits its tokens literally so inline recovery cannot reinterpret
/// the candidate.
fn parse_invalid_reference_definition_angle_destination_paragraph(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> Unit {
  ctx.node(ParagraphNode, fn() {
    while !(ctx.peek() is Newline) &&
          !(ctx.peek() is BlankLine) &&
          ctx.peek() != EOF {
      ctx.emit_token(TextToken)
    }
    let handler : ContinuationHandler[BlockContinuationAction] = {
      decide: () => decide_root_paragraph_continuation(ctx),
      consume: action => consume_block_continuation(ctx, action),
    }
    parse_indexed_inline_container(ctx, InlineParsePolicy::paragraph(), handler)
    if ctx.peek() is Newline {
      ctx.emit_token(NewlineToken)
    }
  })
}
