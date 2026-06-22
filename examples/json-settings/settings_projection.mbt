// settings_projection.mbt — pure CST → raw-settings projection.
//
// Walks a `@seam.SyntaxNode` produced by `@json.json_grammar` and enforces the
// three settings rules the grammar cannot: root is an object, every value is a
// number, no duplicate keys. The projection is a pure function of the CST — it
// never touches the identity tracker or the last-good document.
//
// The rules are expressed as composed `required_direct_*` calls returning
// `Result[_, @seam.ProjectionShapeError]` (see seam/pkg.generated.mbti), rather
// than hand-rolled match-on-kind shape checking. Each shape error's `message`
// becomes one projection diagnostic.

///|
/// One projected entry before identity allocation. Carries the decoded key, the
/// decoded numeric value, and the UTF-16 offsets of the key token (used to build
/// a `@loom.ProjectionLeaf` for stable-identity realignment).
priv struct RawSetting {
  key : String
  value : Double
  key_start : Int
  key_end : Int
} derive(Eq)

///|
/// Project a settings document from a recovered syntax tree.
///
/// Returns `Ok(raws)` in document order when all three rules hold, or
/// `Err(messages)` with one message per violated rule.
fn project_settings(
  root : @seam.SyntaxNode,
) -> Result[Array[RawSetting], Array[String]] {
  // Rule 1: the document root must contain a single JSON object.
  let object = match
    root.required_direct_child_of_kind(
      @json.SyntaxKind::ObjectNode.to_raw(),
      message="settings document root must be a JSON object",
    ) {
    Ok(obj) => obj
    Err(e) => return Err([e.message])
  }
  let raws : Array[RawSetting] = []
  let errors : Array[String] = []
  let seen : Map[String, Bool] = {}
  for
    member_node in object.direct_children_of_kind(
      @json.SyntaxKind::MemberNode.to_raw(),
    ) {
    let key_token = match
      member_node.required_direct_token_of_kind(
        @json.SyntaxKind::StringToken.to_raw(),
        message="settings member must have a string key",
      ) {
      Ok(t) => t
      Err(e) => {
        errors.push(e.message)
        continue
      }
    }
    let key = @json.parse_json_string(key_token.text())
    // Rule 2: a member's value must be a JSON number.
    let number_token = match
      member_node.required_direct_child_of_kind(
        @json.SyntaxKind::NumberValue.to_raw(),
        message="value of '" + key + "' must be a number",
      ) {
      Ok(number_value) =>
        match
          number_value.required_direct_token_of_kind(
            @json.SyntaxKind::NumberToken.to_raw(),
            message="value of '" + key + "' must be a number literal",
          ) {
          Ok(t) => t
          Err(e) => {
            errors.push(e.message)
            continue
          }
        }
      Err(e) => {
        errors.push(e.message)
        continue
      }
    }
    let value = @string.parse_double(number_token.text()) catch {
      _ => {
        errors.push(
          "value of '" + key + "' is not a valid number: " + number_token.text(),
        )
        continue
      }
    }
    // Rule 3: keys must be unique within the document.
    if seen.contains(key) {
      errors.push("duplicate settings key: '" + key + "'")
      continue
    }
    seen[key] = true
    raws.push({
      key,
      value,
      key_start: key_token.start(),
      key_end: key_token.end(),
    })
  }
  if errors.length() > 0 {
    Err(errors)
  } else {
    Ok(raws)
  }
}

///|
/// Build an identity leaf from a raw setting: the key token's UTF-16 span plus
/// the decoded key as the domain equality key.
fn raw_setting_to_leaf(raw : RawSetting) -> @loom.ProjectionLeaf {
  @loom.ProjectionLeaf::new(raw.key_start, raw.key_end, raw.key)
}
