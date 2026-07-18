///|
/// Emit `line_lexer.g.mbt`, the generated line-mode lexer functions driven by
/// `#loom.line_pattern` annotations.
///
/// For each `#loom.line_mode` lexmode, generates a per-mode function that:
///   1. Reads the current line (pos → newline)
///   2. Tries each `#loom.line_pattern` regex in declaration order
///   3. Produces the matching token (via `#loom.custom_lex` when specified)
///   4. Delegates no-match input to `#loom.fallback_lex` when declared, or
///      preserves the existing `Invalid` step otherwise.
/// Generated functions follow the same signature as `emit_lexer_skeleton` stubs:
/// `(source: String, pos: Int) -> (@core.LexStep[Token], LexMode)`.

///|
/// Collect line_pattern variants from a token enum.
/// Returns `None` when no token variant has `#loom.line_pattern`.
fn collect_line_patterns(token_enum : EnumDecl) -> Array[VariantDecl]? {
  let candidates : Array[VariantDecl] = []
  for v in token_enum.variants {
    if v.line_pattern is Some(_) {
      candidates.push(v)
    }
  }
  if candidates.length() == 0 {
    return None
  }
  Some(candidates)
}

///|
/// Lexicographic (codepoint) comparator for mode names. MoonBit's built-in
/// string ordering is not guaranteed to be lexicographic, so compare explicitly
/// for a stable, well-defined order.
fn compare_mode_names(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    let ca = a[i].to_int()
    let cb = b[i].to_int()
    if ca < cb {
      return -1
    }
    if ca > cb {
      return 1
    }
  }
  if a.length() < b.length() {
    return -1
  } else if a.length() > b.length() {
    return 1
  } else {
    return 0
  }
}

///|
/// Collect `#loom.line_mode` lex mode names from a term enum, returned in a
/// deterministic lexicographic (codepoint) order via `compare_mode_names`.
/// Returns an empty array when no term enum is available or none of its
/// variants are line modes.
fn collect_line_lexer_modes(term_enum_decl : EnumDecl?) -> Array[String] {
  let line_modes : @hashset.HashSet[String] = @hashset.HashSet([])
  match term_enum_decl {
    Some(term_enum) =>
      for v in term_enum.variants {
        if v.line_mode {
          match v.lexmode_name {
            Some(mode_name) => line_modes.add(mode_name)
            None => ()
          }
        }
      }
    None => ()
  }
  let arr = line_modes.to_array()
  arr.sort_by(compare_mode_names)
  arr
}

///|
/// Generate the line-mode lexer function for a single mode.
fn emit_mode_line_lexer(
  b : StringBuilder,
  mode_name : String,
  candidates : Array[VariantDecl],
  token_type : String,
  core_qual : String,
  fn_name : String,
  fallback_lex : String?,
) -> Unit raise {
  b.write_string(
    "fn " +
    fn_name +
    "(source : String, pos : Int) -> (" +
    core_qual +
    ".LexStep[" +
    token_type +
    "], LexMode) {\n",
  )
  b.write_string(
    "  if pos >= source.length() {\n    return (Done, " + mode_name + ")\n  }\n",
  )
  // Find end of current line
  b.write_string("  let mut line_end = pos\n")
  b.write_string("  while line_end < source.length() {\n")
  b.write_string("    match source[line_end:line_end + 1].to_owned() {\n")
  b.write_string("      \"\\r\" | \"\\n\" => break\n")
  b.write_string("      _ => line_end = line_end + 1\n")
  b.write_string("    }\n  }\n")
  b.write_string("  let rest = source[pos:line_end].view()\n\n")
  // Emit each line_pattern check in declaration order.
  // Only emit candidates whose lexmode_name matches the enclosing mode (or
  // candidates with no lexmode_name, which apply to all line_mode modes).
  // Nullary tokens use the candidate's declared lexmode_name as the transition
  // target when present, falling back to the enclosing mode_name.
  for v in candidates {
    // Skip candidates explicitly assigned to a different mode
    match v.lexmode_name {
      Some(name) if name != mode_name => continue
      _ => ()
    }
    let pattern = v.line_pattern.unwrap()
    // Escape double quotes for re"..." literal
    let safe_pattern = pattern.replace(old="\"", new="\\\"")
    // Determine transition target: candidate's lexmode_name, or enclosing mode
    let transition = match v.lexmode_name {
      Some(name) => name
      None => mode_name
    }
    b.write_string("  // " + v.name + "\n")
    if v.payloads.length() == v.arg_count &&
      v.arg_count > 0 &&
      v.custom_lex is None {
      let args = v.payloads
        .map(expr => rewrite_payload_expr(expr, "m"))
        .join(", ")
      b.write_string(
        "  match re\"^(?:" +
        safe_pattern +
        ")\".execute(rest) {\n    Some(m) => {\n",
      )
      b.write_string("    let len = m.content().length()\n")
      b.write_string(
        "    return (Produced(" +
        core_qual +
        ".TokenInfo::new(" +
        v.name +
        "(" +
        args +
        "), len), next_offset=pos + len), " +
        transition +
        ")\n",
      )
      b.write_string("    }\n  }\n    None => ()\n  }\n")
    } else {
      b.write_string(
        "  if rest =~ (re\"^(?:" + safe_pattern + ")\", after=after) {\n",
      )
      b.write_string("    let len = rest.length() - after.length()\n")
      match v.custom_lex {
        Some(lex_fn) =>
          b.write_string("    return " + lex_fn + "(source, pos, len)\n")
        None =>
          if v.arg_count == 0 {
            b.write_string(
              "    return (Produced(" +
              core_qual +
              ".TokenInfo::new(" +
              v.name +
              ", len), next_offset=pos + len), " +
              transition +
              ")\n",
            )
          } else {
            b.write_string(
              "    return (" +
              core_qual +
              ".LexStep::Invalid(at=pos, width=len, message=\"line_pattern token " +
              v.name +
              " needs custom_lex\"), " +
              mode_name +
              ")\n",
            )
          }
      }
      b.write_string("  }\n")
    }
  }
  // No pattern matched — delegate to the fallback when declared, otherwise
  // preserve the existing Invalid recovery step.
  match fallback_lex {
    Some(fn_name) => b.write_string("  return " + fn_name + "(source, pos)\n")
    None => {
      b.write_string(
        "  let next = " + core_qual + ".next_char_offset(source, pos)\n",
      )
      b.write_string(
        "  (" +
        core_qual +
        ".LexStep::Invalid(at=pos, width=next - pos, " +
        "message=\"Not a block-level token (line_pattern)\"), " +
        mode_name +
        ")\n",
      )
    }
  }
  b.write_string("}\n")
}

///|
/// Emit the full `line_lexer.g.mbt` content for all line_mode modes.
/// Returns `None` when no mode has line_pattern candidates.
fn emit_line_lexer(
  token_enum : EnumDecl,
  term_enum_decl : EnumDecl?,
  core_qual : String,
) -> String? {
  let candidates = match collect_line_patterns(token_enum) {
    None => return None
    Some(c) => c
  }
  let fallback_by_mode : Map[String, String] = Map([])
  // Collect fallback-by-mode declarations from the term enum (independent of
  // the line-mode set used for emission).
  match term_enum_decl {
    Some(term_enum) =>
      for v in term_enum.variants {
        if v.line_mode {
          match v.lexmode_name {
            Some(mode_name) =>
              match v.fallback_lex {
                Some(fn_name) => fallback_by_mode.set(mode_name, fn_name)
                None => ()
              }
            None => ()
          }
        }
      }
    None => ()
  }
  // Collect the deterministically sorted set of line modes and bail out when
  // there are none.
  let line_modes = collect_line_lexer_modes(term_enum_decl)
  if line_modes.length() == 0 {
    return None
  }
  let token_type = token_enum.name
  let b = StringBuilder()
  b.write_string("// Generated by loomgen — do not edit.\n\n")
  b.write_string("///|\n")
  b.write_string("/// Line-mode lexer functions for #loom.line_mode modes.\n")
  b.write_string(
    "/// Each function matches #loom.line_pattern tokens against whole lines.\n\n",
  )
  // so the helpers integrate with the skeleton's lex_<mode> override points.
  for mode in line_modes {
    emit_mode_line_lexer(
      b,
      mode,
      candidates,
      token_type,
      core_qual,
      generated_line_lexer_fn_name(mode),
      fallback_by_mode.get(mode),
    ) catch {
      PayloadExprError::Invalid(msg) => abort(msg)
      _ => return None
    }
  }
  Some(b.to_string())
}
