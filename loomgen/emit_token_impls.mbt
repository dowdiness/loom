///|
/// Emit `token_impls.g.mbt` — Show, IsTrivia, IsEof, ToRawKind for Token.

///|
/// Escape special characters for MoonBit string literal embedding.
fn escape_string(s : String) -> String {
  let b = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    match s[i] {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      '\n' => b.write_string("\\n")
      '\r' => b.write_string("\\r")
      '\t' => b.write_string("\\t")
      _ => b.write_string(s[i:i + 1].to_owned())
    }
  }
  b.to_string()
}

///|
/// Emit `token_impls.g.mbt` — Show, IsTrivia, IsEof, ToRawKind for Token.
fn kind_name_to_raw(kinds : Array[(String, Int)], kind_name : String) -> Int {
  for i = 0; i < kinds.length(); i = i + 1 {
    let (kn, raw) = kinds[i]
    if kn == kind_name {
      return raw
    }
  }
  abort("kind not found: " + kind_name)
}

///|
fn to_lowercase_first(s : String) -> String {
  if s.length() == 0 {
    s
  } else {
    let first = s[0:1].to_owned().to_lower()
    first + s[1:].to_owned()
  }
}

///|
/// Generate the match arm pattern for a variant.
/// `for_show`: if true, Error variants with args use named binding for string concat.
fn pattern_for(variant : VariantDecl, for_show : Bool) -> String {
  if variant.has_args {
    let is_error = match variant.token_role {
      Some(ErrorToken) => true
      _ => false
    }
    if for_show && is_error {
      if variant.arg_count != 1 {
        abort(
          "ErrorToken variant " +
          variant.name +
          " has " +
          variant.arg_count.to_string() +
          " payload fields; Show expects exactly 1 (msg).",
        )
      }
      variant.name + "(msg)"
    } else {
      let parts : Array[String] = []
      for i = 0; i < variant.arg_count; i = i + 1 {
        parts.push("_")
      }
      variant.name + "(" + parts.join(", ") + ")"
    }
  } else {
    variant.name
  }
}

///|
/// Returns the full RHS expression for the Show match arm (the part after `=>`).
fn show_expr_for(variant : VariantDecl) -> String {
  match variant.token_role {
    Some(ErrorToken) if variant.has_args =>
      // Error(msg) => "<error: " + msg + ">"
      "\"<error: \" + msg + \">\""
    _ => {
      // Simple string literal
      let s = show_literal_for(variant)
      "\"" + escape_string(s) + "\""
    }
  }
}

///|
fn show_literal_for(variant : VariantDecl) -> String {
  match variant.token_role {
    Some(Keyword(s)) => s
    Some(Punct(s)) => s
    Some(Ident) => "<ident>"
    Some(Literal) => "<int>"
    Some(Trivia) => to_lowercase_first(variant.name)
    Some(Delimiter) => to_lowercase_first(variant.name)
    Some(ErrorToken) => "<error>"
    Some(Eof) => "EOF"
    None => abort("unannotated variant: " + variant.name)
  }
}

///|
pub fn emit_token_impls(
  token_enum : EnumDecl,
  token_kinds : Array[(String, Int)],
) -> String {
  let annotated = token_enum.variants.filter(fn(v) { v.token_role is Some(_) })
  let b = StringBuilder::new()

  // Show
  b.write_string("///|\n")
  b.write_string("pub impl Show for " + token_enum.name)
  b.write_string(" with fn output(self, logger) {\n")
  b.write_string("  logger.write_string(\n")
  b.write_string("    match self {\n")
  for v in annotated {
    let pat = pattern_for(v, true)
    let expr = show_expr_for(v)
    b.write_string("      " + pat + " => " + expr + "\n")
  }
  b.write_string("    },\n")
  b.write_string("  )\n")
  b.write_string("}\n\n")

  // IsTrivia
  let trivia_variants = annotated.filter(fn(v) {
    match v.token_role {
      Some(Trivia) => true
      _ => false
    }
  })
  b.write_string("///|\n")
  b.write_string("pub impl @seam.IsTrivia for " + token_enum.name)
  b.write_string(" with fn is_trivia(self) {\n")
  if trivia_variants.length() == 0 {
    b.write_string("  false\n")
  } else {
    b.write_string("  match self {\n")
    for v in trivia_variants {
      let pat = pattern_for(v, false)
      b.write_string("    " + pat + " => true\n")
    }
    b.write_string("    _ => false\n")
    b.write_string("  }\n")
  }
  b.write_string("}\n\n")

  // IsEof
  let eof_variants = annotated.filter(fn(v) {
    match v.token_role {
      Some(Eof) => true
      _ => false
    }
  })
  b.write_string("///|\n")
  b.write_string("pub impl @seam.IsEof for " + token_enum.name)
  b.write_string(" with fn is_eof(self) {\n")
  if eof_variants.length() == 0 {
    b.write_string("  false\n")
  } else {
    b.write_string("  match self {\n")
    for v in eof_variants {
      let pat = pattern_for(v, false)
      b.write_string("    " + pat + " => true\n")
    }
    b.write_string("    _ => false\n")
    b.write_string("  }\n")
  }
  b.write_string("}\n\n")

  // ToRawKind
  b.write_string("///|\n")
  b.write_string("/// Maps tokens to the same raw-kind space as SyntaxKind.\n")
  b.write_string("pub impl @seam.ToRawKind for " + token_enum.name)
  b.write_string(" with fn to_raw(self) {\n")
  b.write_string("  let n : Int = match self {\n")
  for v in annotated {
    let pat = pattern_for(v, false)
    let kind_name = derive_kind_name(
      v.name,
      v.token_role.unwrap(),
      v.kind_override,
    )
    let raw = kind_name_to_raw(token_kinds, kind_name)
    b.write_string("    " + pat + " => " + raw.to_string() + "\n")
  }
  b.write_string("  }\n")
  b.write_string("  @seam.RawKind(n)\n")
  b.write_string("}\n")

  b.to_string()
}
