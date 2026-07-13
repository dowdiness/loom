///|
/// Emit `lexer_skeleton.g.mbt` — a `lex` dispatch function that switches on
/// `LexMode` and delegates to per-mode stub functions.
///
/// Skeleton-once semantics: the generated file is a starting scaffold the user
/// fills in with character-level lex logic. It is not overwritten on re-run
/// (handled by the caller via file-existence check / `--force-lexer`).

///|
/// Convert a CamelCase `LexMode` variant name to a snake_case lex function
/// name with `lex_` prefix. Examples:
///   "Content"   -> "lex_content"
///   "LineStart" -> "lex_line_start"
fn mode_to_fn_name(mode : String) -> String {
  let b = StringBuilder()..write_string("lex_")
  for i = 0; i < mode.length(); i = i + 1 {
    let ch = mode[i]
    if i > 0 && ch >= 'A' && ch <= 'Z' {
      b.write_string("_")
    }
    b.write_string(mode[i:i + 1].to_owned())
  }
  b.to_string().to_lower()
}

///|
/// Convert a line_mode name to its generated helper function name. The
/// `generated_` prefix keeps generated line helpers separate from the
/// user-owned `lex_<mode>` override points in `lexer_skeleton.g.mbt`.
///   "LineStart" -> "generated_lex_line_start"
fn generated_line_lexer_fn_name(mode : String) -> String {
  "generated_" + mode_to_fn_name(mode)
}

///|
/// Shared skeleton renderer. For each mode it emits a `lex_<mode>` function that
/// either delegates to the `generated_lex_<mode>` helper (when `mode` is in
/// `line_modes`) or keeps the canonical "not implemented" aborting stub.
/// `modes` are deduplicated mode names (same order as the `LexMode` enum).
fn render_lexer_skeleton(
  modes : Array[String],
  line_modes : Array[String],
  token_type : String,
  core_qual : String,
) -> String {
  let b = StringBuilder()
    ..write_string("///|\n")
    ..write_string("/// Generated lex dispatch skeleton.\n")
    ..write_string("/// Fill in the mode-specific `lex_*` functions below.\n")
    ..write_string("pub fn lex(\n")
    ..write_string("  source : String,\n")
    ..write_string("  pos : Int,\n")
    ..write_string("  mode : LexMode,\n")
    ..write_string(
      ") -> (" + core_qual + ".LexStep[" + token_type + "], LexMode) {\n",
    )
    ..write_string("  match mode {\n")
  for mode in modes {
    b.write_string(
      "    " + mode + " => " + mode_to_fn_name(mode) + "(source, pos)\n",
    )
  }
  b.write_string("  }\n}\n\n")
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
    if is_line_mode(line_modes, mode) {
      b.write_string(
        "  " + generated_line_lexer_fn_name(mode) + "(source, pos)\n",
      )
    } else {
      b.write_string("  abort(\"" + fn_name + " not implemented\")\n")
    }
    b.write_string("}\n")
    if i < modes.length() - 1 {
      b.write_string("\n")
    }
  }
  b.to_string()
}

///|
/// Returns `true` when `mode` is one of the requested line modes.
fn is_line_mode(line_modes : Array[String], mode : String) -> Bool {
  for m in line_modes {
    if m == mode {
      return true
    }
  }
  false
}

///|
/// Generate the skeleton content for `lexer_skeleton.g.mbt` with all-mode
/// aborting stubs (no line-mode delegates). Preserves the historical
/// `emit_lexer_skeleton` output for non-line-lexer generation.
/// `modes` are deduplicated mode names (same order as `LexMode` enum).
fn emit_lexer_skeleton(
  modes : Array[String],
  token_type : String,
  core_qual : String,
) -> String {
  render_lexer_skeleton(modes, [], token_type, core_qual)
}

///|
/// Generate a skeleton where each requested line mode delegates to its
/// `generated_lex_<mode>` helper and every non-line mode keeps the aborting
/// stub. Used when a new skeleton is emitted together with `--line-lexer`.
fn emit_lexer_skeleton_with_line_delegates(
  modes : Array[String],
  line_modes : Array[String],
  token_type : String,
  core_qual : String,
) -> String {
  render_lexer_skeleton(modes, line_modes, token_type, core_qual)
}

///|
/// Migrate an existing skeleton for `--line-lexer` generation. Each requested
/// line mode's exact historical Loom aborting stub is replaced with a delegate
/// to the `generated_lex_<mode>` helper. A non-identical (handwritten)
/// `lex_<mode>` body is left byte-for-byte unchanged, because the exact stub
/// text is never present. The replacement is a fixed-string swap — no broad
/// function-name or regular-expression rewrite — so it is deterministic and
/// idempotent: a second pass leaves the file untouched.
fn integrate_line_lexer_skeleton(
  existing : String,
  line_modes : Array[String],
  token_type : String,
  core_qual : String,
) -> String {
  let mut result = existing
  for mode in line_modes {
    let fn_name = mode_to_fn_name(mode)
    let old_stub = "fn " +
      fn_name +
      "(source : String, pos : Int) -> (" +
      core_qual +
      ".LexStep[" +
      token_type +
      "], LexMode) {\n  abort(\"" +
      fn_name +
      " not implemented\")\n}"
    let new_delegate = "fn " +
      fn_name +
      "(source : String, pos : Int) -> (" +
      core_qual +
      ".LexStep[" +
      token_type +
      "], LexMode) {\n  " +
      generated_line_lexer_fn_name(mode) +
      "(source, pos)\n}"
    result = result.replace(old=old_stub, new=new_delegate)
  }
  result
}
