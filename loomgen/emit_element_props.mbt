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
  for v in term_enum_decl.variants {
    match v.role {
      Some(Leaf | Node | ErrorNode | Root) => {
        if v.is_void {
          void_kinds.push(v.name)
        }
        if v.is_rawtext {
          rawtext_kinds.push(v.name)
        }
      }
      _ => ()
    }
  }
  if void_kinds.length() == 0 && rawtext_kinds.length() == 0 {
    return None
  }
  let mut b : StringBuilder? = None
  if void_kinds.length() > 0 {
    b = Some(
      StringBuilder()
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
