// value_convert.mbt — SyntaxNode → JsonValue conversion via CST fold.

///|
/// Parse JSON string escapes from raw token text (includes quotes).
pub fn parse_json_string(raw : String) -> String {
  // Strip surrounding quotes
  if raw.length() < 2 {
    return raw
  }
  let inner = raw[1:raw.length() - 1]
  // Process escape sequences
  let buf = StringBuilder::new()
  let len = inner.length()
  let mut i = 0
  while i < len {
    let code = inner.code_unit_at(i).to_int()
    match code.to_char() {
      Some('\\') =>
        if i + 1 < len {
          let next_code = inner.code_unit_at(i + 1).to_int()
          match next_code.to_char() {
            Some('"') => {
              buf.write_char('"')
              i = i + 2
            }
            Some('\\') => {
              buf.write_char('\\')
              i = i + 2
            }
            Some('/') => {
              buf.write_char('/')
              i = i + 2
            }
            Some('b') => {
              buf.write_char('\u0008')
              i = i + 2
            }
            Some('f') => {
              buf.write_char('\u000C')
              i = i + 2
            }
            Some('n') => {
              buf.write_char('\n')
              i = i + 2
            }
            Some('r') => {
              buf.write_char('\r')
              i = i + 2
            }
            Some('t') => {
              buf.write_char('\t')
              i = i + 2
            }
            Some('u') =>
              // \uXXXX — parse 4 hex digits
              if i + 5 < len {
                let hex = inner[i + 2:i + 6].to_owned()
                let cp = @string.parse_int(hex, base=16) catch {
                  _ => {
                    buf.write_char('\\')
                    i = i + 1
                    continue
                  }
                }
                if cp >= 0xD800 && cp <= 0xDBFF {
                  // High surrogate — look for low surrogate \uXXXX
                  if i + 11 < len && inner[i + 6:i + 8].to_owned() == "\\u" {
                    let low_hex = inner[i + 8:i + 12].to_owned()
                    let low = @string.parse_int(low_hex, base=16) catch {
                      _ => -1
                    }
                    if low >= 0xDC00 && low <= 0xDFFF {
                      let codepoint = (cp - 0xD800) * 1024 +
                        (low - 0xDC00) +
                        0x10000
                      match codepoint.to_char() {
                        Some(ch) => buf.write_char(ch)
                        None => buf.write_char('\uFFFD')
                      }
                      i = i + 12 // consumed both \uXXXX\uXXXX
                    } else {
                      buf.write_char('\uFFFD') // invalid low surrogate
                      i = i + 6
                    }
                  } else {
                    buf.write_char('\uFFFD') // lone high surrogate
                    i = i + 6
                  }
                } else if cp >= 0xDC00 && cp <= 0xDFFF {
                  buf.write_char('\uFFFD') // lone low surrogate
                  i = i + 6
                } else {
                  match cp.to_char() {
                    Some(ch) => buf.write_char(ch)
                    None => buf.write_char('\uFFFD')
                  }
                  i = i + 6
                }
              } else {
                buf.write_char('\\')
                i = i + 1
              }
            _ => {
              buf.write_char('\\')
              i = i + 1
            }
          }
        } else {
          buf.write_char('\\')
          i = i + 1
        }
      Some(c) => {
        buf.write_char(c)
        i = i + 1
      }
      None =>
        // Could be a UTF-16 surrogate pair (non-BMP character)
        if code >= 0xD800 && code <= 0xDBFF && i + 1 < len {
          // High surrogate — read low surrogate
          let low = inner.code_unit_at(i + 1).to_int()
          if low >= 0xDC00 && low <= 0xDFFF {
            let codepoint = (code - 0xD800) * 1024 + (low - 0xDC00) + 0x10000
            match codepoint.to_char() {
              Some(ch) => buf.write_char(ch)
              None => ()
            }
            i = i + 2
          } else {
            i = i + 1
          }
        } else {
          i = i + 1
        }
    }
  }
  buf.to_string()
}

///|
/// Algebra for CstFold: per-node conversion with framework-managed recursion.
pub fn json_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> JsonValue,
) -> JsonValue {
  match SyntaxKind::from_raw(node.kind()) {
    RootNode =>
      // Root has one child: the value
      match node.nth_child(0) {
        Some(child) => recurse(child)
        None => JsonValue::Error("empty document")
      }
    ObjectNode => {
      let member_nodes = node.direct_children_of_kind(MemberNode.to_raw())
      let members = member_nodes
        .iter()
        .filter_map(child => {
          // Get key from first direct StringToken child only (not recursive).
          // This prevents picking up the value's string when the key is missing.
          match child.direct_token_of_kind(StringToken.to_raw()) {
            Some(t) => {
              let key = t.text()
              let parsed_key = if key.length() >= 2 {
                parse_json_string(key)
              } else {
                key
              }
              let value = match child.nth_child(0) {
                Some(v) => recurse(v)
                None => JsonValue::Error("missing member value")
              }
              Some((parsed_key, value))
            }
            None => None
          }
        })
        .to_array()
      if members.length() < member_nodes.length() {
        JsonValue::Error("missing member key")
      } else {
        JsonValue::Object(members)
      }
    }
    ArrayNode => JsonValue::Array(node.children().map(recurse))
    StringValue =>
      match node.direct_token_of_kind(StringToken.to_raw()) {
        Some(tok) => {
          let text = tok.text()
          if text.length() >= 2 {
            JsonValue::String(parse_json_string(text))
          } else {
            JsonValue::Error("malformed string")
          }
        }
        None => JsonValue::Error("missing string token")
      }
    NumberValue =>
      match node.direct_token_of_kind(NumberToken.to_raw()) {
        Some(tok) => {
          let text = tok.text()
          let n = @string.parse_double(text) catch {
            _ => return JsonValue::Error("invalid number: " + text)
          }
          JsonValue::Number(n)
        }
        None => JsonValue::Error("missing number token")
      }
    BoolValue =>
      match node.direct_token_of_kind(TrueKeyword.to_raw()) {
        Some(_) => JsonValue::Bool(true)
        None =>
          match node.direct_token_of_kind(FalseKeyword.to_raw()) {
            Some(_) => JsonValue::Bool(false)
            None => JsonValue::Error("missing boolean token")
          }
      }
    NullValue => JsonValue::Null
    ErrorNode => JsonValue::Error("parse error")
    _ =>
      JsonValue::Error(
        "unknown node: " + SyntaxKind::from_raw(node.kind()).to_string(),
      )
  }
}

///|
/// Convenience wrapper: convert a SyntaxNode to JsonValue without caching.
/// Delegates to json_fold_node with itself as the recursion function.
pub fn syntax_node_to_json(root : @seam.SyntaxNode) -> JsonValue {
  json_fold_node(root, syntax_node_to_json)
}
