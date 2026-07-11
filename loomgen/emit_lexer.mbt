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
/// Default regex pattern for a syntax role when no explicit `#loom.pattern`
/// annotation is present. Returns `None` for roles without a sensible default.
fn default_pattern_for_role(role : SyntaxRole?) -> String? {
  match role {
    Some(Ident) => Some("[a-zA-Z_][a-zA-Z0-9_]*")
    Some(Trivia) => Some("[ \\t\\r\\n]+")
    Some(Literal) => Some("[0-9]+(\\.[0-9]+)?")
    _ => None
  }
}

///|
/// The effective pattern for a variant: either its explicit `#loom.pattern`,
/// or the default pattern for its role, or `None`.
fn effective_pattern(v : VariantDecl) -> String? {
  // Custom-lex variants short-circuit before the regex pass — they must not
  // also get a pattern branch (explicit or default). The custom_lex hook is
  // the sole producer for the variant.
  if v.custom_lex is Some(_) {
    return None
  }
  match v.pattern {
    Some(p) => Some(p)
    None => default_pattern_for_role(v.role)
  }
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
      // Pattern-backed idents (explicit or default) participate in the regex
      // pass and set best_ident for keyword post-classification. A
      // #loom.custom_lex ident short-circuits before the regex pass and never
      // triggers classification.
      Some(Ident) => if v.custom_lex is None { ident_count = ident_count + 1 }
      Some(Keyword(kw)) => keywords.push((kw, v.name))
      _ => ()
    }
    if v.custom_lex is Some(fn_name) {
      custom_lex_fns.push(fn_name)
    }
  }
  for v in variants {
    // #loom.line_pattern variants are produced by the line-mode lexer, not the
    // character-level lexer — skip them entirely.
    if v.line_pattern is Some(_) {
      continue
    }
    let is_candidate = v.pattern is Some(_) ||
      v.custom_lex is Some(_) ||
      v.role is Some(Punct(_)) ||
      default_pattern_for_role(v.role) is Some(_)
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
    if (effective_pattern(v) is Some(_) || v.role is Some(Punct(_))) &&
      v.arg_count > 0 {
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
  // Filter out #loom.line_pattern variants — they're produced by the line-mode
  // lexer, not the character-level lexer.
  let char_variants = variants.filter(fn(v) { v.line_pattern is None })
  // Skip line_pattern variants in keyword/punct collision check
  for kw in keywords {
    let (kw_text, kw_name) = kw
    for v in char_variants {
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
  Ok({
    variants: char_variants,
    keywords,
    custom_lex_fns,
    has_keywords: keywords.length() > 0,
  })
}

///|
/// Emit a regex `view =~ (re"^(?:PATTERN)", after=rest)` match branch for a
/// pattern-backed token variant.  Updates `best_len`, `best`, and (when
/// `has_keywords`) `best_ident` if the match beats the current best.
fn emit_pattern_check(
  b : StringBuilder,
  pattern : String,
  variant_name : String,
  is_ident : Bool,
  has_keywords : Bool,
) -> Unit {
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
  // rest.length()` is the consumed code-unit count regardless of binder type.
  b.write_string("  if view =~ (re\"^(?:" + pattern + ")\", after=rest) {\n")
  b.write_string("    let len = view.length() - rest.length()\n")
  b.write_string("    if len > best_len {\n")
  b.write_string("      best_len = len\n")
  b.write_string("      best = Some(" + variant_name + ")\n")
  if has_keywords {
    b.write_string(
      "      best_ident = " + (if is_ident { "true" } else { "false" }) + "\n",
    )
  }
  b.write_string("    }\n  }\n")
}

///|
/// Emit a `cursor.starts_with("LIT")` match branch for a punctuation token
/// variant.  Unlike the regex pass, punct checks are pure substring lookups on
/// the cursor — no `let view = cursor.view()` or `after=` computation needed.
fn emit_punct_check(
  b : StringBuilder,
  lit : String,
  variant_name : String,
  has_keywords : Bool,
) -> Unit {
  let len = lit.length().to_string()
  b.write_string(
    "  if cursor.starts_with(\"" +
    escape_string(lit) +
    "\") && " +
    len +
    " > best_len {\n",
  )
  b.write_string("    best_len = " + len + "\n")
  b.write_string("    best = Some(" + variant_name + ")\n")
  if has_keywords {
    b.write_string("    best_ident = false\n")
  }
  b.write_string("  }\n")
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
  let has_patterns = inputs.variants
    .iter()
    .any(fn(v) { effective_pattern(v) is Some(_) })
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
    match effective_pattern(v) {
      Some(p) =>
        emit_pattern_check(b, p, v.name, v.role is Some(Ident), has_keywords)
      None =>
        match v.role {
          Some(Punct(lit)) => emit_punct_check(b, lit, v.name, has_keywords)
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
