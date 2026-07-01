///|
/// Emit `lexer_skeleton.g.mbt` — a `lex` dispatch function that switches on
/// `LexMode` and delegates to per-mode stub functions.
///
/// Skeleton-once semantics: the generated file is a starting scaffold the user
/// fills in with character-level lex logic. It is not overwritten on re-run
/// (handled by the caller via file-existence check / `--force-lexer`).

///|
/// Convert a CamelCase `LexMode` variant name to a snake_case lex function
fn mode_to_fn_name(mode : String) -> String {
  let b = StringBuilder()
  b.write_string("lex_")
  for i = 0; i < mode.length(); i = i + 1 {
    let ch = mode[i]
    if i > 0 && ch >= 'A' && ch <= 'Z' {
      b.write_string("_")
    }
    b.write_string(mode[i:i+1].to_string())
  }
  b.to_string().to_lower()
}

///|
/// Generate the skeleton content for `lexer_skeleton.g.mbt`.
/// `modes` are deduplicated mode names (sorted, same order as `LexMode` enum).
fn emit_lexer_skeleton(
  modes : Array[String],
  token_type : String,
  core_qual : String,
) -> String {
  let b = StringBuilder()
  b.write_string("///|\n")
  b.write_string("/// Generated lex dispatch skeleton.\n")
  b.write_string("/// Fill in the mode-specific `lex_*` functions below.\n")
  b.write_string("pub fn lex(\n")
  b.write_string("  source : String,\n")
  b.write_string("  pos : Int,\n")
  b.write_string("  mode : LexMode,\n")
  b.write_string(
    ") -> (" + core_qual + ".LexStep[" + token_type + "], LexMode) {\n",
  )
  b.write_string("  match mode {\n")
  for mode in modes {
    b.write_string("    " + mode + " => " + mode_to_fn_name(mode) + "(source, pos)\n")
  }
  b.write_string("  }\n")
  b.write_string("}\n")
  b.write_string("\n")
  for i = 0; i < modes.length(); i = i + 1 {
    let mode = modes[i]
    let fn_name = mode_to_fn_name(mode)
    b.write_string(
      "fn " +
      fn_name +
      "(source : String, pos : Int) -> (" +
      core_qual +
      ".LexStep[" +
      token_type +
      "], LexMode) {\n",
    )
    b.write_string("  abort(\"" + fn_name + " not implemented\")\n")
    b.write_string("}\n")
    if i < modes.length() - 1 {
      b.write_string("\n")
    }
  }
  b.to_string()
}
