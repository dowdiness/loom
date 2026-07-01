///|
/// Emit `lexmode.g.mbt` — a `LexMode` enum and dispatch function derived from
/// `#loom.lexmode("ModeName")` annotation modifiers on term variants.
///
/// Generates:
/// - `pub(all) enum LexMode { Mode1, Mode2, ... } derive(Eq, Debug)`
/// - `pub fn lexmode_for_kind(kind : SyntaxKind) -> LexMode?`
///
/// Returns `None` when no variants have `#loom.lexmode` annotations.
fn emit_lexmode(term_enum_decl : EnumDecl) -> String? {
  // Collect unique mode names and their associated kind names.
  // Mode ordering is deterministic across runs (verified by CI golden diff).
  // Kind lists within each mode are sorted for stable output.
  let mode_to_kinds : Map[String, Array[String]] = Map([])
  for v in term_enum_decl.variants {
    match v.lexmode_name {
      Some(mode) =>
        if mode_to_kinds.contains(mode) {
          mode_to_kinds[mode].push(v.name)
        } else {
          mode_to_kinds.set(mode, [v.name])
        }
      None => ()
    }
  }
  if mode_to_kinds.length() == 0 {
    return None
  }
  // Sort mode names alphabetically for deterministic output
  let modes : Array[String] = []
  for mode, _kinds in mode_to_kinds {
    modes.push(mode)
  }
  modes.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  // Sort kind lists within each mode for stable match-arm output
  for mode in modes {
    mode_to_kinds[mode].sort()
  }
  let b = StringBuilder::new()
  b.write_string("///|\n")
  b.write_string("pub(all) enum LexMode {\n")
  for i = 0; i < modes.length(); i = i + 1 {
    b.write_string("  ")
    b.write_string(modes[i])
    if i < modes.length() - 1 {
      b.write_string("\n")
    }
  }
  b.write_string("\n} derive(Eq, Debug)\n")
  b.write_string("\n")
  b.write_string("///|\n")
  b.write_string("pub fn lexmode_for_kind(kind : SyntaxKind) -> LexMode? {\n")
  b.write_string("  match kind {\n")
  for mode in modes {
    let kinds = mode_to_kinds[mode]
    b.write_string("    ")
    b.write_string(kinds.join(" | "))
    b.write_string(" => Some(")
    b.write_string(mode)
    b.write_string(")\n")
  }
  b.write_string("    _ => None\n")
  b.write_string("  }\n")
  b.write_string("}\n")
  Some(b.to_string())
}

///|
/// Collect deduplicated `LexMode` variant names from term variants that have
/// `#loom.lexmode("ModeName")`. Returns modes sorted alphabetically, matching
/// the order `emit_lexmode` produces in the `LexMode` enum.
/// Returns an empty array when no variants have a lexmode annotation.
fn collect_lexmodes(decl : EnumDecl) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  for v in decl.variants {
    match v.lexmode_name {
      Some(mode) => seen.set(mode, true)
      None => ()
    }
  }
  let modes : Array[String] = []
  for mode, _ in seen {
    modes.push(mode)
  }
  modes.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  modes
}
