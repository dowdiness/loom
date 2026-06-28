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
  let b = StringBuilder()
  if void_kinds.length() > 0 {
    b.write_string("///|\n")
    b.write_string("pub fn is_void_element(kind : SyntaxKind) -> Bool {\n")
    b.write_string("  match kind {\n")
    b.write_string("    ")
    b.write_string(void_kinds.join(" | "))
    b.write_string(" => true\n")
    b.write_string("    _ => false\n")
    b.write_string("  }\n")
    b.write_string("}\n")
  }
  if rawtext_kinds.length() > 0 {
    if void_kinds.length() > 0 {
      b.write_string("\n")
    }
    b.write_string("///|\n")
    b.write_string("pub fn is_raw_text_element(kind : SyntaxKind) -> Bool {\n")
    b.write_string("  match kind {\n")
    b.write_string("    ")
    b.write_string(rawtext_kinds.join(" | "))
    b.write_string(" => true\n")
    b.write_string("    _ => false\n")
    b.write_string("  }\n")
    b.write_string("}\n")
  }
  Some(b.to_string())
}
