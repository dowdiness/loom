// TreeNode and Renderable implementations for JsonValue.
// Enables projectional editing via framework/core (ProjNode, SourceMap, reconcile).

///|
pub impl @core.TreeNode for JsonValue with fn children(self) {
  match self {
    Array(items) => items
    Object(members) => members.map(m => m.1)
    _ => []
  }
}

///|
pub impl @core.TreeNode for JsonValue with fn same_kind(self, other) {
  match (self, other) {
    (Null, Null) => true
    (Bool(_), Bool(_)) => true
    (Number(_), Number(_)) => true
    (String(_), String(_)) => true
    (Array(_), Array(_)) => true
    (Object(_), Object(_)) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
pub impl @core.Renderable for JsonValue with fn kind_tag(self) {
  match self {
    Null => "Null"
    Bool(_) => "Bool"
    Number(_) => "Number"
    String(_) => "String"
    Array(_) => "Array"
    Object(_) => "Object"
    Error(_) => "Error"
  }
}

///|
pub impl @core.Renderable for JsonValue with fn label(self) {
  match self {
    Null => "null"
    Bool(b) => b.to_string()
    Number(n) => {
      let s = n.to_string()
      if s.has_suffix(".0") {
        s[0:s.length() - 2].to_owned()
      } else {
        s
      }
    }
    String(s) =>
      if s.length() > 20 {
        "\"" + s[0:20].to_owned() + "...\""
      } else {
        "\"" + s + "\""
      }
    Array(items) => "[" + items.length().to_string() + " items]"
    Object(members) => "{" + members.map(m => m.0).join(", ") + "}"
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl @core.Renderable for JsonValue with fn placeholder(self) {
  match self {
    // Carve-out (hand-written): Error's placeholder `"null"` is a
    // deliberate UX choice that masks error nodes in the output stream
    // (same masking pattern used by `unparse` at `Error(_) => "null"`).
    // Canonical's `Error("?")` pretty-prints to `"<error: ?>"`, which
    // would surface the error rather than hide it — that's a behavior
    // change, not a refactor. Keep hand-written.
    Error(_) => "null"
    // Fitting variants — delegate to canonical + pretty_unparse.
    _ => @core.default_placeholder_via_canonical(self)
  }
}

///|
pub impl @core.Renderable for JsonValue with fn unparse(self) {
  json_unparse(self, 0)
}

///|
fn json_unparse(value : JsonValue, depth : Int) -> String {
  match value {
    Null => "null"
    Bool(b) => b.to_string()
    Number(n) => {
      let s = n.to_string()
      if s.has_suffix(".0") {
        s[0:s.length() - 2].to_owned()
      } else {
        s
      }
    }
    String(s) => "\"" + json_escape_string(s) + "\""
    Array(items) =>
      if items.is_empty() {
        "[]"
      } else {
        let indent = "  ".repeat(depth + 1)
        let close_indent = "  ".repeat(depth)
        let parts = items.map(item => indent + json_unparse(item, depth + 1))
        "[\n" + parts.join(",\n") + "\n" + close_indent + "]"
      }
    Object(members) =>
      if members.is_empty() {
        "{}"
      } else {
        let indent = "  ".repeat(depth + 1)
        let close_indent = "  ".repeat(depth)
        let parts = members.map(m => {
          indent +
          "\"" +
          json_escape_string(m.0) +
          "\": " +
          json_unparse(m.1, depth + 1)
        })
        "{\n" + parts.join(",\n") + "\n" + close_indent + "}"
      }
    Error(_) => "null"
  }
}

///|
fn json_escape_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}
