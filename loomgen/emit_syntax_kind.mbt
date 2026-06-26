///|
/// Emit `syntax_kind.g.mbt` — SyntaxKind enum with seam traits.
fn capitalize(s : String) -> String {
  if s.length() == 0 {
    s
  } else {
    let first = s[0:1].to_owned().to_upper()
    first + s[1:].to_owned()
  }
}

///|
fn derive_kind_name(
  variant_name : String,
  role : TokenRole,
  kind_override : String?,
) -> String {
  match kind_override {
    Some(name) => name
    None =>
      match role {
        Keyword(s) => capitalize(s) + "Keyword"
        Punct(_) => variant_name + "Token"
        Ident => "IdentToken"
        Literal => variant_name + "Token"
        Trivia => variant_name + "Token"
        Delimiter => variant_name + "Token"
        ErrorToken => "ErrorToken"
        Eof => "EofToken"
      }
  }
}

///|
pub fn build_kind_entries(
  enum_decl : EnumDecl,
  registry : RawKindRegistry,
) -> Array[(String, Int)] {
  let kinds : Array[(String, Int)] = []
  for variant in enum_decl.variants {
    let role = match variant.token_role {
      Some(r) => r
      None => continue
    }
    let kind_name = derive_kind_name(variant.name, role, variant.kind_override)
    kinds.push((kind_name, registry.assign(kind_name)))
  }
  kinds
}

///|
pub fn emit_syntax_kind(
  token_kinds : Array[(String, Int)],
  term_kinds : Array[(String, Int)],
  trivia_set : @hashset.HashSet[String],
  error_set : @hashset.HashSet[String],
) -> String {
  let all = token_kinds + term_kinds
  let b = StringBuilder::new()

  b.write_string("///|\n")
  b.write_string("pub(all) enum SyntaxKind {\n")
  for i = 0; i < all.length(); i = i + 1 {
    let (name, _) = all[i]
    let sep = if i == all.length() - 1 { "" } else { "\n" }
    b.write_string("  " + name + sep)
  }
  b.write_string("\n} derive(Debug, Eq)\n\n")

  b.write_string("///|\n")
  b.write_string(
    "pub impl Show for SyntaxKind with fn output(self, logger) {\n",
  )
  b.write_string("  logger.write_string(@debug.to_string(self))\n")
  b.write_string("}\n\n")

  b.write_string("///|\n")
  b.write_string("pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {\n")
  b.write_string("  match self {\n")
  for i = 0; i < token_kinds.length(); i = i + 1 {
    let (name, _) = token_kinds[i]
    let prefix = if i == 0 { "    " } else { "    | " }
    let suffix = if i == token_kinds.length() - 1 { " => true\n" } else { "\n" }
    b.write_string(prefix + name + suffix)
  }
  b.write_string("    _ => false\n")
  b.write_string("  }\n")
  b.write_string("}\n\n")

  b.write_string("///|\n")
  b.write_string(
    "pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {\n",
  )
  b.write_string("  let n : Int = match self {\n")
  for pair in all {
    let (name, raw) = pair
    b.write_string("    " + name + " => " + raw.to_string() + "\n")
  }
  b.write_string("  }\n")
  b.write_string("  @seam.RawKind(n)\n")
  b.write_string("}\n\n")

  b.write_string("///|\n")
  b.write_string(
    "pub impl @seam.FromRawKind for SyntaxKind with fn from_raw(raw) {\n",
  )
  b.write_string("  let @seam.RawKind(n) = raw\n")
  b.write_string("  match n {\n")
  for pair in all {
    let (name, raw) = pair
    b.write_string("    " + raw.to_string() + " => " + name + "\n")
  }
  b.write_string("    _ => ErrorToken\n")
  b.write_string("  }\n")
  b.write_string("}\n\n")

  b.write_string("///|\n")
  b.write_string(
    "pub impl @seam.IsTrivia for SyntaxKind with fn is_trivia(self) {\n",
  )
  let trivia_names = trivia_set.to_array()
  if trivia_names.length() == 0 {
    b.write_string("  false\n")
  } else {
    let parts = trivia_names.map(fn(n) { "self == " + n })
    b.write_string("  " + parts.join(" || ") + "\n")
  }
  b.write_string("}\n\n")

  b.write_string("///|\n")
  b.write_string(
    "pub impl @seam.IsError for SyntaxKind with fn is_error(self) {\n",
  )
  let error_names = error_set.to_array()
  if error_names.length() == 0 {
    b.write_string("  false\n")
  } else {
    let parts = error_names.map(fn(n) { "self == " + n })
    b.write_string("  " + parts.join(" || ") + "\n")
  }
  b.write_string("}\n")

  b.to_string()
}
