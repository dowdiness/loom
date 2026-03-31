///|
fn json_punc(s : String) -> @pretty.Layout[@pretty.SyntaxCategory] {
  @pretty.annotate(@pretty.SyntaxCategory::Punctuation, @pretty.text(s))
}

///|
fn escape_json_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\b' => buf.write_string("\\b")
      '\u000C' => buf.write_string("\\f")
      ch => {
        let code = ch.to_uint()
        if code < 0x20 {
          let hex = b"0123456789abcdef"
          buf.write_string("\\u00")
          buf.write_char(
            hex[(code >> 4).reinterpret_as_int()].to_int().unsafe_to_char(),
          )
          buf.write_char(
            hex[(code & 0xf).reinterpret_as_int()].to_int().unsafe_to_char(),
          )
        } else {
          buf.write_char(ch)
        }
      }
    }
  }
  buf.to_string()
}

///|
fn json_to_layout(value : JsonValue) -> @pretty.Layout[@pretty.SyntaxCategory] {
  match value {
    Null =>
      @pretty.annotate(@pretty.SyntaxCategory::Keyword, @pretty.text("null"))
    Bool(b) =>
      @pretty.annotate(
        @pretty.SyntaxCategory::Keyword,
        @pretty.text(b.to_string()),
      )
    Number(n) => {
      let s = n.to_string()
      let display = if s.has_suffix(".0") {
        s[0:s.length() - 2].to_string()
      } else {
        s
      }
      @pretty.annotate(@pretty.SyntaxCategory::Number, @pretty.text(display))
    }
    String(s) =>
      @pretty.annotate(
        @pretty.SyntaxCategory::StringLit,
        @pretty.text("\"" + escape_json_string(s) + "\""),
      )
    Array([]) => json_punc("[]")
    Array(elems) => {
      let items = elems.map(json_to_layout)
      let sep = json_punc(",") + @pretty.line()
      @pretty.group(
        json_punc("[") +
        @pretty.nest(@pretty.softline() + @pretty.separate(sep, items)) +
        @pretty.softline() +
        json_punc("]"),
      )
    }
    Object([]) => json_punc("{}")
    Object(pairs) => {
      let entries = pairs.map(fn(pair) {
        let (key, val) = pair
        @pretty.annotate(
          @pretty.SyntaxCategory::StringLit,
          @pretty.text("\"" + escape_json_string(key) + "\""),
        ) +
        json_punc(":") +
        @pretty.text(" ") +
        json_to_layout(val)
      })
      let sep = json_punc(",") + @pretty.line()
      @pretty.group(
        json_punc("{") +
        @pretty.nest(@pretty.softline() + @pretty.separate(sep, entries)) +
        @pretty.softline() +
        json_punc("}"),
      )
    }
    Error(msg) =>
      @pretty.annotate(
        @pretty.SyntaxCategory::Error,
        @pretty.text("<error: " + msg + ">"),
      )
  }
}

///|
pub impl @pretty.Pretty for JsonValue with to_layout(self) {
  json_to_layout(self)
}

///|
/// Source for JSON: produces valid, compact JSON text.
pub impl @pretty.Source for JsonValue with to_source(self) {
  @pretty.render_string(json_to_layout(self), width=1000000)
}

///|
pub impl @pretty.Printable for JsonValue
