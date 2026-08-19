///|
priv struct DecodedEntityReference {
  replacement : String
  end : Int
}

///|
fn is_ascii_digit_code_unit(code_unit : Int) -> Bool {
  code_unit >= 0x30 && code_unit <= 0x39
}

///|
fn is_ascii_hex_digit_code_unit(code_unit : Int) -> Bool {
  is_ascii_digit_code_unit(code_unit) ||
  (code_unit >= 0x41 && code_unit <= 0x46) ||
  (code_unit >= 0x61 && code_unit <= 0x66)
}

///|
fn is_ascii_alphanumeric_code_unit(code_unit : Int) -> Bool {
  is_ascii_digit_code_unit(code_unit) ||
  (code_unit >= 0x41 && code_unit <= 0x5A) ||
  (code_unit >= 0x61 && code_unit <= 0x7A)
}

///|
fn is_ascii_punctuation_code_unit(code_unit : Int) -> Bool {
  (code_unit >= 0x21 && code_unit <= 0x2F) ||
  (code_unit >= 0x3A && code_unit <= 0x40) ||
  (code_unit >= 0x5B && code_unit <= 0x60) ||
  (code_unit >= 0x7B && code_unit <= 0x7E)
}

///|
fn numeric_digit_value(code_unit : Int) -> Int {
  if code_unit >= 0x30 && code_unit <= 0x39 {
    code_unit - 0x30
  } else if code_unit >= 0x41 && code_unit <= 0x46 {
    code_unit - 0x41 + 10
  } else {
    code_unit - 0x61 + 10
  }
}

///|
fn commonmark_numeric_reference_replacement(codepoint : Int) -> String {
  if codepoint == 0 ||
    codepoint > 0x10FFFF ||
    (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
    "\u{FFFD}"
  } else {
    codepoint.unsafe_to_char().to_string()
  }
}

///|
fn decode_commonmark_numeric_reference(
  text : String,
  start : Int,
) -> DecodedEntityReference? {
  guard start + 2 < text.length() &&
    text.code_unit_at(start).to_int() == 0x26 &&
    text.code_unit_at(start + 1).to_int() == 0x23 else {
    return None
  }
  let marker = text.code_unit_at(start + 2).to_int()
  let (radix, max_digits, digit_start) = if marker == 0x78 || marker == 0x58 {
    (16, 6, start + 3)
  } else {
    (10, 7, start + 2)
  }
  let mut cursor = digit_start
  let mut digits = 0
  let mut codepoint = 0
  while cursor < text.length() && digits < max_digits {
    let code_unit = text.code_unit_at(cursor).to_int()
    let valid = if radix == 16 {
      is_ascii_hex_digit_code_unit(code_unit)
    } else {
      is_ascii_digit_code_unit(code_unit)
    }
    if !valid {
      break
    }
    codepoint = codepoint * radix + numeric_digit_value(code_unit)
    cursor = cursor + 1
    digits = digits + 1
  }
  guard digits > 0 &&
    cursor < text.length() &&
    text.code_unit_at(cursor).to_int() == 0x3B else {
    return None
  }
  Some({
    replacement: commonmark_numeric_reference_replacement(codepoint),
    end: cursor + 1,
  })
}

///|
fn decode_commonmark_named_reference(
  text : String,
  start : Int,
) -> DecodedEntityReference? {
  guard start + 1 < text.length() && text.code_unit_at(start).to_int() == 0x26 else {
    return None
  }
  let name_start = start + 1
  let mut cursor = name_start
  while cursor < text.length() && cursor - name_start < 32 {
    if !is_ascii_alphanumeric_code_unit(text.code_unit_at(cursor).to_int()) {
      break
    }
    cursor = cursor + 1
  }
  guard cursor > name_start &&
    cursor < text.length() &&
    text.code_unit_at(cursor).to_int() == 0x3B else {
    return None
  }
  match commonmark_named_entity(text[name_start:cursor].to_owned()) {
    Some(replacement) => Some({ replacement, end: cursor + 1 })
    None => None
  }
}

///|
fn decode_commonmark_reference(
  text : String,
  start : Int,
) -> DecodedEntityReference? {
  match decode_commonmark_numeric_reference(text, start) {
    Some(reference) => Some(reference)
    None => decode_commonmark_named_reference(text, start)
  }
}

///|
fn write_inline_source_slice(
  buf : StringBuilder,
  text : String,
  start : Int,
  end : Int,
) -> Unit {
  if start < end {
    buf.write_string(text[start:end].to_owned())
  }
}

///|
fn decode_markdown_text_references(text : String) -> String {
  if !text.contains("&") {
    return strip_backslash_escapes(text)
  }
  let buf = StringBuilder::StringBuilder()
  let mut literal_start = 0
  let mut cursor = 0
  while cursor < text.length() {
    let code_unit = text.code_unit_at(cursor).to_int()
    if code_unit == 0x5C && cursor + 1 < text.length() {
      let escaped = text.code_unit_at(cursor + 1).to_int()
      if is_ascii_punctuation_code_unit(escaped) {
        write_inline_source_slice(buf, text, literal_start, cursor)
        buf.write_char(escaped.unsafe_to_char())
        literal_start = cursor + 2
        cursor = cursor + 2
        continue
      }
    }
    if code_unit == 0x26 {
      match decode_commonmark_reference(text, cursor) {
        Some(reference) => {
          write_inline_source_slice(buf, text, literal_start, cursor)
          buf.write_string(reference.replacement)
          cursor = reference.end
          literal_start = cursor
          continue
        }
        None => ()
      }
    }
    cursor = cursor + 1
  }
  write_inline_source_slice(buf, text, literal_start, text.length())
  buf.to_string()
}

///|
/// Decode CommonMark references while applying backslash escapes in the same
/// source pass. An escaped ampersand must remain literal rather than becoming
/// eligible for entity decoding after escape removal.
fn decode_markdown_inline_text(text : String) -> String {
  decode_markdown_text_references(text)
}

///|
/// Decode entities and ASCII-punctuation backslash escapes in a fenced-code
/// info string. Escaped ampersands stay literal and are not entity-decoded.
fn decode_markdown_info_string_entities(text : String) -> String {
  decode_markdown_text_references(text)
}

///|
fn decode_markdown_ir_entity_children(
  children : Array[MarkdownIR],
  source : String,
) -> Unit {
  for index, child in children {
    children[index] = decode_markdown_ir_text_entities(child, source)
  }
}

///|
/// Apply entity decoding only after source-sensitive whitespace and delimiter
/// normalization has fixed each Text origin. Re-reading the owned source slice
/// preserves the distinction between `&copy;` and `\&copy;` without letting a
/// decoded whitespace code point masquerade as source indentation or a hard
/// break marker.
fn decode_markdown_ir_text_entities(
  ir : MarkdownIR,
  source : String,
) -> MarkdownIR {
  match ir.node {
    Document(children)
    | Heading(_, children, _)
    | Paragraph(children, _)
    | BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _)
    | ListItem(children, _, _, _)
    | OrderedListItem(children, _, _, _)
    | Bold(children, _)
    | Italic(children, _)
    | Link(children, _, _, _)
    | Image(children, _, _, _) => {
      decode_markdown_ir_entity_children(children, source)
      ir
    }
    Text(value) => {
      let origin = ir.origin()
      let raw = source[origin.start():origin.end()].to_owned()
      // Some pre-existing lowering paths intentionally normalize source text
      // (for example CRLF to LF). Preserve those values unless the origin is
      // an exact backslash-unescape witness for this Text node.
      guard strip_backslash_escapes(raw) == value else { return ir }
      MarkdownIR::text(decode_markdown_inline_text(raw), origin)
    }
    CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | Autolink(_, _, _, _, _)
    | InlineHtml(_, _)
    | ThematicBreak
    | InlineCode(_, _)
    | SoftBreak(_)
    | HardBreak(_, _)
    | Unsupported(_)
    | Raw(_, _)
    | Recovered(_, _) => ir
  }
}
