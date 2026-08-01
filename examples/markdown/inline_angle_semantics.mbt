///|
priv enum InlineAngleKind {
  UriAutolink
  EmailAutolink
  InlineHtmlAngle
}

///|
priv struct InlineAngleMatch {
  kind : InlineAngleKind
  end : Int
}

///|
fn is_ascii_letter_code_unit(code_unit : Int) -> Bool {
  (code_unit >= 0x41 && code_unit <= 0x5A) ||
  (code_unit >= 0x61 && code_unit <= 0x7A)
}

///|
fn is_ascii_digit_code_unit_local(code_unit : Int) -> Bool {
  code_unit >= 0x30 && code_unit <= 0x39
}

///|
fn is_uri_scheme_code_unit(code_unit : Int) -> Bool {
  is_ascii_letter_code_unit(code_unit) ||
  is_ascii_digit_code_unit_local(code_unit) ||
  code_unit == 0x2B ||
  code_unit == 0x2E ||
  code_unit == 0x2D
}

///|
fn is_autolink_uri_body_code_unit(code_unit : Int) -> Bool {
  code_unit > 0x20 && code_unit != 0x3C && code_unit != 0x3E
}

///|
fn is_email_local_code_unit(code_unit : Int) -> Bool {
  is_ascii_letter_code_unit(code_unit) ||
  is_ascii_digit_code_unit_local(code_unit) ||
  (match code_unit {
    0x21
    | 0x23
    | 0x24
    | 0x25
    | 0x26
    | 0x27
    | 0x2A
    | 0x2B
    | 0x2D
    | 0x2E
    | 0x2F
    | 0x3D
    | 0x3F
    | 0x5E
    | 0x5F
    | 0x60
    | 0x7B
    | 0x7C
    | 0x7D
    | 0x7E => true
    _ => false
  })
}

///|
fn is_email_domain_code_unit(code_unit : Int) -> Bool {
  is_ascii_letter_code_unit(code_unit) ||
  is_ascii_digit_code_unit_local(code_unit) ||
  code_unit == 0x2D
}

///|
fn consume_email_domain_label(input : String, start : Int) -> Int? {
  guard start < input.length() &&
    (
      is_ascii_letter_code_unit(input.code_unit_at(start).to_int()) ||
      is_ascii_digit_code_unit_local(input.code_unit_at(start).to_int())
    ) else {
    return None
  }
  let mut cursor = start + 1
  while cursor < input.length() &&
        cursor - start < 63 &&
        is_email_domain_code_unit(input.code_unit_at(cursor).to_int()) {
    cursor = cursor + 1
  }
  guard input.code_unit_at(cursor - 1).to_int() != 0x2D else { return None }
  Some(cursor)
}

///|
fn classify_email_autolink_at(input : String, start : Int) -> InlineAngleMatch? {
  guard start + 5 <= input.length() &&
    input.code_unit_at(start).to_int() == 0x3C else {
    return None
  }
  let local_start = start + 1
  let mut cursor = local_start
  while cursor < input.length() &&
        is_email_local_code_unit(input.code_unit_at(cursor).to_int()) {
    cursor = cursor + 1
  }
  guard cursor > local_start &&
    cursor < input.length() &&
    input.code_unit_at(cursor).to_int() == 0x40 else {
    return None
  }
  cursor = cursor + 1
  let mut labels = 0
  while true {
    match consume_email_domain_label(input, cursor) {
      Some(label_end) => {
        labels = labels + 1
        cursor = label_end
      }
      None => return None
    }
    if cursor < input.length() && input.code_unit_at(cursor).to_int() == 0x2E {
      cursor = cursor + 1
      continue
    }
    break
  }
  if labels > 0 &&
    cursor < input.length() &&
    input.code_unit_at(cursor).to_int() == 0x3E {
    Some({ kind: EmailAutolink, end: cursor + 1 })
  } else {
    None
  }
}

///|
fn is_html_whitespace_code_unit(code_unit : Int) -> Bool {
  code_unit == 0x09 ||
  code_unit == 0x0A ||
  code_unit == 0x0C ||
  code_unit == 0x0D ||
  code_unit == 0x20
}

///|
fn is_html_attribute_name_start(code_unit : Int) -> Bool {
  is_ascii_letter_code_unit(code_unit) || code_unit == 0x5F || code_unit == 0x3A
}

///|
fn is_html_attribute_name_code_unit(code_unit : Int) -> Bool {
  is_html_attribute_name_start(code_unit) ||
  is_ascii_digit_code_unit_local(code_unit) ||
  code_unit == 0x2E ||
  code_unit == 0x2D
}

///|
fn skip_html_whitespace(input : String, start : Int) -> Int {
  let mut cursor = start
  while cursor < input.length() &&
        is_html_whitespace_code_unit(input.code_unit_at(cursor).to_int()) {
    cursor = cursor + 1
  }
  cursor
}

///|
fn consume_html_tag_name(input : String, start : Int) -> Int? {
  guard start < input.length() &&
    is_ascii_letter_code_unit(input.code_unit_at(start).to_int()) else {
    return None
  }
  let mut cursor = start + 1
  while cursor < input.length() {
    let code_unit = input.code_unit_at(cursor).to_int()
    if is_ascii_letter_code_unit(code_unit) ||
      is_ascii_digit_code_unit_local(code_unit) ||
      code_unit == 0x2D {
      cursor = cursor + 1
    } else {
      break
    }
  }
  Some(cursor)
}

///|
fn consume_html_attribute_value(input : String, start : Int) -> Int? {
  guard start < input.length() else { return None }
  let quote = input.code_unit_at(start).to_int()
  if quote == 0x22 || quote == 0x27 {
    let mut cursor = start + 1
    while cursor < input.length() &&
          input.code_unit_at(cursor).to_int() != quote {
      cursor = cursor + 1
    }
    if cursor < input.length() {
      Some(cursor + 1)
    } else {
      None
    }
  } else {
    let mut cursor = start
    while cursor < input.length() {
      let code_unit = input.code_unit_at(cursor).to_int()
      if is_html_whitespace_code_unit(code_unit) ||
        code_unit == 0x22 ||
        code_unit == 0x27 ||
        code_unit == 0x3D ||
        code_unit == 0x3C ||
        code_unit == 0x3E ||
        code_unit == 0x60 {
        break
      }
      cursor = cursor + 1
    }
    if cursor > start {
      Some(cursor)
    } else {
      None
    }
  }
}

///|
fn classify_inline_open_tag_at(input : String, start : Int) -> Int? {
  guard consume_html_tag_name(input, start + 1) is Some(initial_end) else {
    return None
  }
  let mut cursor = initial_end
  while true {
    let after_space = skip_html_whitespace(input, cursor)
    let had_space = after_space > cursor
    cursor = after_space
    guard cursor < input.length() else { return None }
    if input.code_unit_at(cursor).to_int() == 0x3E {
      return Some(cursor + 1)
    }
    if input.code_unit_at(cursor).to_int() == 0x2F &&
      cursor + 1 < input.length() &&
      input.code_unit_at(cursor + 1).to_int() == 0x3E {
      return Some(cursor + 2)
    }
    guard had_space &&
      is_html_attribute_name_start(input.code_unit_at(cursor).to_int()) else {
      return None
    }
    cursor = cursor + 1
    while cursor < input.length() &&
          is_html_attribute_name_code_unit(input.code_unit_at(cursor).to_int()) {
      cursor = cursor + 1
    }
    let after_name_space = skip_html_whitespace(input, cursor)
    if after_name_space < input.length() &&
      input.code_unit_at(after_name_space).to_int() == 0x3D {
      let value_start = skip_html_whitespace(input, after_name_space + 1)
      match consume_html_attribute_value(input, value_start) {
        Some(value_end) => cursor = value_end
        None => return None
      }
    } else {
      // Leave separator whitespace for the next loop iteration. Consuming it
      // here would make a following boolean attribute look adjacent.
      ()
    }
  }
  None
}

///|
fn classify_inline_close_tag_at(input : String, start : Int) -> Int? {
  guard start + 3 < input.length() &&
    input.code_unit_at(start + 1).to_int() == 0x2F &&
    consume_html_tag_name(input, start + 2) is Some(name_end) else {
    return None
  }
  let cursor = skip_html_whitespace(input, name_end)
  if cursor < input.length() && input.code_unit_at(cursor).to_int() == 0x3E {
    Some(cursor + 1)
  } else {
    None
  }
}

///|
fn find_ascii_delimiter(
  input : String,
  start : Int,
  delimiter : String,
) -> Int? {
  let mut cursor = start
  while cursor + delimiter.length() <= input.length() {
    if input[cursor:cursor + delimiter.length()].to_owned() == delimiter {
      return Some(cursor + delimiter.length())
    }
    cursor = cursor + 1
  }
  None
}

///|
fn classify_inline_comment_at(input : String, start : Int) -> Int? {
  guard start + 4 <= input.length() &&
    input[start:start + 4].to_owned() == "<!--" else {
    return None
  }
  if start + 5 <= input.length() && input[start:start + 5].to_owned() == "<!-->" {
    return Some(start + 5)
  }
  if start + 6 <= input.length() &&
    input[start:start + 6].to_owned() == "<!--->" {
    return Some(start + 6)
  }
  let content_start = start + 4
  guard content_start < input.length() &&
    input.code_unit_at(content_start).to_int() != 0x3E &&
    !(input.code_unit_at(content_start).to_int() == 0x2D &&
    content_start + 1 < input.length() &&
    input.code_unit_at(content_start + 1).to_int() == 0x3E) else {
    return None
  }
  match find_ascii_delimiter(input, content_start, "-->") {
    Some(end) if end - 3 == content_start ||
      input.code_unit_at(end - 4).to_int() != 0x2D => Some(end)
    _ => None
  }
}

///|
fn classify_inline_declaration_at(input : String, start : Int) -> Int? {
  guard start + 4 < input.length() &&
    input.code_unit_at(start + 1).to_int() == 0x21 else {
    return None
  }
  let mut cursor = start + 2
  let name_start = cursor
  while cursor < input.length() {
    let code_unit = input.code_unit_at(cursor).to_int()
    if code_unit >= 0x41 && code_unit <= 0x5A {
      cursor = cursor + 1
    } else {
      break
    }
  }
  guard cursor > name_start &&
    cursor < input.length() &&
    is_html_whitespace_code_unit(input.code_unit_at(cursor).to_int()) else {
    return None
  }
  find_ascii_delimiter(input, cursor + 1, ">")
}

///|
fn classify_inline_html_at(input : String, start : Int) -> InlineAngleMatch? {
  guard start < input.length() && input.code_unit_at(start).to_int() == 0x3C else {
    return None
  }
  let end = if start + 9 <= input.length() &&
    input[start:start + 9].to_owned() == "<![CDATA[" {
    find_ascii_delimiter(input, start + 9, "]]>")
  } else if start + 4 <= input.length() &&
    input[start:start + 4].to_owned() == "<!--" {
    classify_inline_comment_at(input, start)
  } else if start + 2 <= input.length() &&
    input[start:start + 2].to_owned() == "<?" {
    find_ascii_delimiter(input, start + 2, "?>")
  } else if start + 2 <= input.length() &&
    input[start:start + 2].to_owned() == "</" {
    classify_inline_close_tag_at(input, start)
  } else if start + 2 <= input.length() &&
    input[start:start + 2].to_owned() == "<!" {
    classify_inline_declaration_at(input, start)
  } else {
    classify_inline_open_tag_at(input, start)
  }
  end.map(end => ({ kind: InlineHtmlAngle, end } : InlineAngleMatch))
}

///|
fn classify_uri_autolink_at(input : String, start : Int) -> InlineAngleMatch? {
  guard start + 4 <= input.length() &&
    input.code_unit_at(start).to_int() == 0x3C &&
    is_ascii_letter_code_unit(input.code_unit_at(start + 1).to_int()) else {
    return None
  }
  let scheme_start = start + 1
  let mut cursor = scheme_start + 1
  while cursor < input.length() &&
        cursor - scheme_start < 32 &&
        is_uri_scheme_code_unit(input.code_unit_at(cursor).to_int()) {
    cursor = cursor + 1
  }
  guard cursor - scheme_start >= 2 &&
    cursor - scheme_start <= 32 &&
    cursor < input.length() &&
    input.code_unit_at(cursor).to_int() == 0x3A else {
    return None
  }
  cursor = cursor + 1
  while cursor < input.length() &&
        is_autolink_uri_body_code_unit(input.code_unit_at(cursor).to_int()) {
    cursor = cursor + 1
  }
  if cursor < input.length() && input.code_unit_at(cursor).to_int() == 0x3E {
    Some({ kind: UriAutolink, end: cursor + 1 })
  } else {
    None
  }
}

///|
fn classify_inline_angle_at(input : String, start : Int) -> InlineAngleMatch? {
  match classify_uri_autolink_at(input, start) {
    Some(candidate) => Some(candidate)
    None =>
      match classify_email_autolink_at(input, start) {
        Some(candidate) => Some(candidate)
        None => classify_inline_html_at(input, start)
      }
  }
}

///|
fn classify_inline_angle_text(text : String) -> InlineAngleMatch? {
  match classify_inline_angle_at(text, 0) {
    Some(candidate) if candidate.end == text.length() => Some(candidate)
    _ => None
  }
}

///|
fn normalize_autolink_uri_destination(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    match ch {
      '[' => buf.write_string("%5B")
      '\\' => buf.write_string("%5C")
      ']' => buf.write_string("%5D")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}
