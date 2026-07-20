///|
/// Emit `element_props.g.mbt` — lookup tables for element properties derived from
/// `#loom.void` and `#loom.rawtext` annotation modifiers on term variants.
///
/// `is_void_element(kind)` returns `true` for variants annotated with `#loom.void`.
/// `is_raw_text_element(kind)` returns `true` for variants annotated with `#loom.rawtext`.
///
/// Each function is omitted when no variant has the corresponding flag.
/// Kinds are consolidated into a single alternation arm (e.g. `Br | Img => true`).
fn emit_element_props(term_enum_decl : EnumDecl) -> String? {
  let void_kinds : Array[String] = []
  let rawtext_kinds : Array[String] = []
  let tagged : Array[(String, String)] = []
  for v in term_enum_decl.variants {
    match v.role {
      Some(Leaf | Node | ErrorNode | Root) => {
        if v.is_void {
          void_kinds.push(v.name)
        }
        if v.is_rawtext {
          rawtext_kinds.push(v.name)
        }
        match v.tag_name {
          Some(tag) => tagged.push((tag, v.name))
          None => ()
        }
      }
      _ => ()
    }
  }
  if void_kinds.length() == 0 &&
    rawtext_kinds.length() == 0 &&
    tagged.length() == 0 {
    return None
  }
  let mut b : StringBuilder? = None
  if tagged.length() > 0 {
    let builder = StringBuilder()
    builder
    ..write_string("///|\n")
    ..write_string(
      "fn classify_element_ascii_lower(name : String) -> String {\n",
    )
    ..write_string("  let out = StringBuilder()\n")
    ..write_string("  for c in name {\n")
    ..write_string(
      "    out.write_char(if c >= 'A' && c <= 'Z' { c.to_ascii_lowercase() } else { c })\n",
    )
    ..write_string("  }\n")
    ..write_string("  out.to_string()\n")
    ..write_string("}\n\n")
    ..write_string("///|\n")
    ..write_string("pub fn classify_element(name : String) -> SyntaxKind? {\n")
    .write_string("  match classify_element_ascii_lower(name) {\n")
    for entry in tagged {
      let tag = entry.0
      let kind = entry.1
      builder
      ..write_string("    \"")
      ..write_string(tag)
      ..write_string("\" => Some(")
      ..write_string(kind)
      .write_string(")\n")
    }
    builder
    ..write_string("    _ => None\n")
    ..write_string("  }\n")
    .write_string("}\n")
    b = Some(builder)
  }
  if void_kinds.length() > 0 {
    let builder = match b {
      Some(existing) => {
        existing.write_string("\n")
        existing
      }
      None => StringBuilder()
    }
    b = Some(
      builder
      ..write_string("///|\n")
      ..write_string("pub fn is_void_element(kind : SyntaxKind) -> Bool {\n")
      ..write_string("  match kind {\n")
      ..write_string("    ")
      ..write_string(void_kinds.join(" | "))
      ..write_string(" => true\n")
      ..write_string("    _ => false\n")
      ..write_string("  }\n")
      ..write_string("}\n"),
    )
  }
  if rawtext_kinds.length() > 0 {
    let builder = match b {
      Some(existing) => {
        existing.write_string("\n")
        existing
      }
      None => StringBuilder()
    }
    b = Some(
      builder
      ..write_string("///|\n")
      ..write_string(
        "pub fn is_raw_text_element(kind : SyntaxKind) -> Bool {\n",
      )
      ..write_string("  match kind {\n")
      ..write_string("    ")
      ..write_string(rawtext_kinds.join(" | "))
      ..write_string(" => true\n")
      ..write_string("    _ => false\n")
      ..write_string("  }\n")
      ..write_string("}\n"),
    )
  }
  Some(b.unwrap().to_string())
}
