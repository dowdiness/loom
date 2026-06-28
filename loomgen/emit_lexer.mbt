///|
/// Emit `lexer.g.mbt` — a longest-match step lexer driven by `#loom.pattern`,
/// `#loom.punct`, `#loom.keyword`, and `#loom.custom_lex` annotations (#521).
///
/// The generated lexer matches each candidate with MoonBit's compile-time regex
/// literal `cursor.view() =~ (re"^PATTERN" as m)` (the leading `^` anchors the
/// match to the current position; `m.length()` is the matched length). Patterns
/// are emitted VERBATIM — the `re"..."` literal does not process string escapes,
/// so the annotation author writes engine-valid regex (`\-`, `\.`, ...).

///|
/// Validated lexer-generation inputs derived from a `#loom.token` enum.
struct LexerInputs {
  variants : Array[VariantDecl]
  keywords : Array[(String, String)] // (keyword text, variant name)
  custom_lex_fns : Array[String] // function names, declaration order
  has_keywords : Bool
}

///|
/// Collect and validate lexer candidates. Returns an error string for any
/// state the generated scanner could not lex (unreachable variant, keyword
/// without an identifier source, embeddable-pattern violations).
fn collect_lexer_inputs(token_enum : EnumDecl) -> Result[LexerInputs, String] {
  let variants = token_enum.variants
  let keywords : Array[(String, String)] = []
  let custom_lex_fns : Array[String] = []
  let mut ident_count = 0
  for v in variants {
    match v.role {
      // Only a PATTERN-backed ident participates in keyword post-classification:
      // it wins the regex pass and sets best_ident. A #loom.custom_lex ident
      // short-circuits before the regex pass and never triggers classification,
      // so it does not count as a keyword source.
      Some(Ident) => if v.pattern is Some(_) { ident_count = ident_count + 1 }
      Some(Keyword(kw)) => keywords.push((kw, v.name))
      _ => ()
    }
    if v.custom_lex is Some(fn_name) {
      custom_lex_fns.push(fn_name)
    }
  }
  for v in variants {
    let is_candidate = v.pattern is Some(_) ||
      v.custom_lex is Some(_) ||
      v.role is Some(Punct(_))
    let is_exempt = match v.role {
      Some(Keyword(_) | Eof | ErrorToken) => true
      _ => false
    }
    if !is_candidate && !is_exempt {
      return Err(
        "token variant " +
        v.name +
        " has no #loom.pattern, #loom.punct, or #loom.custom_lex; the generated lexer cannot produce it",
      )
    }
    // Pattern and punct candidates are emitted as nullary constructors.
    if (v.pattern is Some(_) || v.role is Some(Punct(_))) && v.arg_count > 0 {
      return Err(
        "token variant " +
        v.name +
        " is a lexer candidate but has constructor arguments; pattern/punct candidates must be nullary",
      )
    }
    // Keywords are post-classified as nullary constructors (`"let" => Let`), so a
    // payload-bearing keyword variant would emit a call the generated lexer
    // cannot type-check.
    if v.role is Some(Keyword(_)) && v.arg_count > 0 {
      return Err(
        "#loom.keyword variant " +
        v.name +
        " has constructor arguments; the generated lexer post-classifies keywords as nullary constructors and cannot supply a payload",
      )
    }
    if v.pattern is Some(p) && p.contains("\"") {
      return Err(
        "token variant " +
        v.name +
        " has a #loom.pattern containing a double-quote, which cannot be embedded in a generated re\"...\" literal; use #loom.custom_lex for this token",
      )
    }
  }
  if keywords.length() > 0 && ident_count == 0 {
    return Err(
      "#loom.token enum has #loom.keyword variants but no pattern-backed #loom.ident variant to post-classify from; keywords are classified from the #loom.ident regex match, so the identifier must use #loom.pattern (a #loom.custom_lex identifier bypasses the regex pass and would never be reclassified as a keyword)",
    )
  }
  // Keyword post-classification keys off a single `best_ident` flag set by the
  // winning ident regex branch. Two pattern-backed idents both set it, so the
  // keyword table would be applied to whichever wins longest-match — ambiguous.
  if keywords.length() > 0 && ident_count > 1 {
    return Err(
      "#loom.token enum has #loom.keyword variants and more than one pattern-backed #loom.ident variant; keyword post-classification is ambiguous (it keys off a single identifier match). Keep exactly one #loom.ident, or handle the others via #loom.custom_lex",
    )
  }
  // A #loom.punct whose text equals a keyword shadows it: the punct wins
  // longest-match at equal length, so the keyword variant would never be
  // produced. (General #loom.pattern/keyword overlap is the author's
  // responsibility — it cannot be decided statically.)
  for kw in keywords {
    let (kw_text, kw_name) = kw
    for v in variants {
      if v.role is Some(Punct(lit)) && lit == kw_text {
        return Err(
          "#loom.punct variant " +
          v.name +
          " has text \"" +
          lit +
          "\" identical to #loom.keyword \"" +
          kw_text +
          "\" (variant " +
          kw_name +
          "); the punct wins longest-match, so the keyword would never be produced",
        )
      }
    }
  }
  Ok({ variants, keywords, custom_lex_fns, has_keywords: keywords.length() > 0 })
}

///|
/// Emit the generated `lexer.g.mbt` source, or an error describing why the
/// token enum cannot drive a generated lexer.
fn emit_lexer(
  token_enum : EnumDecl,
  core_qual : String,
  step_name : String,
) -> Result[String, String] {
  let inputs = match collect_lexer_inputs(token_enum) {
    Err(e) => return Err(e)
    Ok(i) => i
  }
  let token_type = token_enum.name
  let has_keywords = inputs.has_keywords
  let has_patterns = inputs.variants.iter().any(fn(v) { v.pattern is Some(_) })
  let b = StringBuilder::new()
  b.write_string("// Generated by loomgen (#521) — do not edit.\n\n")
  b.write_string("///|\n")
  b.write_string(
    "/// Step-based lexer (longest-match; declaration order breaks ties).\n",
  )
  b.write_string(
    "pub fn " +
    step_name +
    "(source : String, pos : Int) -> " +
    core_qual +
    ".LexStep[" +
    token_type +
    "] {\n",
  )
  b.write_string(
    "  let cursor = " + core_qual + ".LexCursor::new(source, pos)\n",
  )
  b.write_string("  if cursor.is_done() {\n    return Done\n  }\n")
  // custom_lex escape hatches run first, in declaration order.
  for fn_name in inputs.custom_lex_fns {
    b.write_string(
      "  // custom_lex hook — expected signature: (String, Int) -> " +
      core_qual +
      ".LexStep[" +
      token_type +
      "]\n",
    )
    b.write_string("  match " + fn_name + "(source, pos) {\n")
    b.write_string("    Done => ()\n")
    b.write_string("    other => return other\n")
    b.write_string("  }\n")
  }
  if has_patterns {
    b.write_string("  let view = cursor.view()\n")
  }
  b.write_string("  let mut best_len = 0\n")
  b.write_string("  let mut best : " + token_type + "? = None\n")
  if has_keywords {
    b.write_string("  let mut best_ident = false\n")
  }
  // Candidate checks in declaration order; strict `>` keeps the earlier
  // declaration on equal-length ties.
  for v in inputs.variants {
    match v.pattern {
      Some(p) => {
        let is_ident = v.role is Some(Ident)
        // Wrap the whole pattern in a non-capturing group so the leading `^`
        // anchors the ENTIRE pattern. A bare `re"^foo|bar"` would parse as
        // `(^foo)|(bar)`, letting the search-based `=~` match the unanchored
        // branch mid-view; the `^(?:..)` wrap binds the anchor to the whole
        // pattern. (Alternation itself is rejected at validation — it is
        // leftmost-match, not longest-match — so the wrap is a defensive
        // structural guarantee, not an alternation feature.)
        //
        // The match span is computed from the `after=` remainder rather than a
        // `... as m` binder: for a pattern that statically matches exactly one
        // character (`[0-9]`, `.`) the `as` binder is a `Char`, which has no
        // `.length()`, so `m.length()` would not type-check. `view.length() -
        // rest.length()` is the consumed code-unit count regardless of binder
        // type.
        b.write_string("  if view =~ (re\"^(?:" + p + ")\", after=rest) {\n")
        b.write_string("    let len = view.length() - rest.length()\n")
        b.write_string("    if len > best_len {\n")
        b.write_string("      best_len = len\n")
        b.write_string("      best = Some(" + v.name + ")\n")
        if has_keywords {
          b.write_string(
            "      best_ident = " +
            (if is_ident { "true" } else { "false" }) +
            "\n",
          )
        }
        b.write_string("    }\n  }\n")
      }
      None =>
        match v.role {
          Some(Punct(lit)) => {
            let len = lit.length().to_string()
            b.write_string(
              "  if cursor.starts_with(\"" +
              escape_string(lit) +
              "\") && " +
              len +
              " > best_len {\n",
            )
            b.write_string("    best_len = " + len + "\n")
            b.write_string("    best = Some(" + v.name + ")\n")
            if has_keywords {
              b.write_string("    best_ident = false\n")
            }
            b.write_string("  }\n")
          }
          _ => ()
        }
    }
  }
  // Resolve the winner: no match -> Invalid advancing one scalar; otherwise
  // advance by the winning length, post-classify keywords, and produce.
  b.write_string("  match best {\n")
  b.write_string("    None =>\n")
  b.write_string("      " + core_qual + ".LexStep::Invalid(\n")
  b.write_string("        at=pos,\n")
  b.write_string(
    "        width=" + core_qual + ".next_char_offset(source, pos) - pos,\n",
  )
  b.write_string("        message=\"Unexpected character\",\n")
  b.write_string("      )\n")
  b.write_string("    Some(tok) => {\n")
  b.write_string("      cursor.advance_code_units(best_len)\n")
  if has_keywords {
    b.write_string("      let final_tok = if best_ident {\n")
    b.write_string("        match source[pos:pos + best_len].to_owned() {\n")
    for kw in inputs.keywords {
      let (text, name) = kw
      b.write_string(
        "          \"" + escape_string(text) + "\" => " + name + "\n",
      )
    }
    b.write_string("          _ => tok\n")
    b.write_string("        }\n")
    b.write_string("      } else {\n        tok\n      }\n")
    b.write_string("      cursor.produced(final_tok)\n")
  } else {
    b.write_string("      cursor.produced(tok)\n")
  }
  b.write_string("    }\n")
  b.write_string("  }\n")
  b.write_string("}\n")
  Ok(b.to_string())
}
