///|
/// Emit `spec.g.mbt` — a `make_*_spec` factory function that fills in
/// whitespace_kind, error_kind, root_kind, and eof_token from annotation
/// metadata while leaving non-derivable parameters (parse_root, etc.) explicit.
///
/// The generated function lives in the grammar package (e.g. examples/lambda/)
/// which imports `token`, `syntax`, and `core` packages with the given qualifiers.
///
/// Design note: uses `is` pattern matching instead of `==` on SyntaxRole
/// because SyntaxRole does not derive Eq (it has payload-bearing variants).

///|
/// True when two SyntaxRole values are the same nullary role.
/// SyntaxRole does not derive Eq, so matching requires explicit `is` patterns.
fn roles_match(a : SyntaxRole, b : SyntaxRole) -> Bool {
  (a is Trivia && b is Trivia) ||
  (a is ErrorToken && b is ErrorToken) ||
  (a is Eof && b is Eof) ||
  (a is Root && b is Root) ||
  (a is Leaf && b is Leaf) ||
  (a is Node && b is Node) ||
  (a is ErrorNode && b is ErrorNode) ||
  (a is Ident && b is Ident) ||
  (a is Literal && b is Literal) ||
  (a is Delimiter && b is Delimiter)
}

///|
/// Find the first variant with the given nullary SyntaxRole.
fn find_variant_with_role(
  enum_decl : EnumDecl,
  role : SyntaxRole,
) -> VariantDecl? {
  for v in enum_decl.variants {
    match v.role {
      Some(r) if roles_match(r, role) => return Some(v)
      _ => ()
    }
  }
  None
}

///|
/// True when the enum declares two or more variants with the given role.
fn has_duplicate(enum_decl : EnumDecl, role : SyntaxRole) -> Bool {
  let mut found = false
  for v in enum_decl.variants {
    match v.role {
      Some(r) if roles_match(r, role) => {
        if found {
          return true
        }
        found = true
      }
      _ => ()
    }
  }
  false
}

///|
/// Emit a `make_<language>_spec` factory function.
///
/// `token_enum` — the #loom.token annotated enum (must have #loom.trivia,
///                                           #loom.error, #loom.eof)
/// `term_enum`  — the #loom.term annotated enum (must have #loom.root)
/// `language_name` — used for the function name: `make_<name>_spec`
/// Token and SyntaxKind type references are constructed as
/// `token_qual.TokenName` / `syntax_qual.SyntaxKindName`.
/// Those qualifiers get prefixed to kind/value refs (a dot is appended).
/// Empty qualifier = unqualified name (same-package usage).
fn emit_spec(
  token_enum : EnumDecl,
  term_enum : EnumDecl,
  language_name : String,
  token_type_name : String,
  syntax_type_name : String,
  token_qual : String,
  syntax_qual : String,
  core_qual : String,
) -> Result[String, String] {
  // Look up required variants by role
  let trivia_var = find_variant_with_role(token_enum, Trivia)
  let error_var = find_variant_with_role(token_enum, ErrorToken)
  let eof_var = find_variant_with_role(token_enum, Eof)
  let root_var = find_variant_with_role(term_enum, Root)

  // Validate required annotations
  if error_var is None {
    return Err(
      "#loom.token enum " + token_enum.name + " missing #loom.error variant",
    )
  }
  if eof_var is None {
    return Err(
      "#loom.token enum " + token_enum.name + " missing #loom.eof variant",
    )
  }
  if root_var is None {
    return Err(
      "#loom.term enum " + term_enum.name + " missing #loom.root variant",
    )
  }
  if trivia_var is None {
    return Err(
      "#loom.token enum " + token_enum.name + " missing #loom.trivia variant",
    )
  }

  // Spec-scalar roles: only one variant of each is allowed for spec generation.
  if has_duplicate(token_enum, Trivia) {
    return Err(
      "#loom.token enum " +
      token_enum.name +
      " has multiple #loom.trivia variants; at most one allowed",
    )
  }
  if has_duplicate(token_enum, ErrorToken) {
    return Err(
      "#loom.token enum " +
      token_enum.name +
      " has multiple #loom.error variants; at most one allowed",
    )
  }
  if has_duplicate(token_enum, Eof) {
    return Err(
      "#loom.token enum " +
      token_enum.name +
      " has multiple #loom.eof variants; at most one allowed",
    )
  }
  if has_duplicate(term_enum, Root) {
    return Err(
      "#loom.term enum " +
      term_enum.name +
      " has multiple #loom.root variants; at most one allowed",
    )
  }

  let error_v = error_var.unwrap()
  let eof_v = eof_var.unwrap()
  let root_v = root_var.unwrap()
  let trivia_v = trivia_var.unwrap()

  let whitespace_kind_name = derive_kind_name(
    trivia_v.name,
    Trivia,
    trivia_v.kind_override,
  )
  let error_kind_name = derive_kind_name(
    error_v.name,
    ErrorToken,
    error_v.kind_override,
  )
  let root_kind_name = derive_kind_name(root_v.name, Root, root_v.kind_override)
  let eof_token_name = eof_v.name
  let token_type = if token_qual.length() > 0 {
    token_qual + "." + token_type_name
  } else {
    token_type_name
  }
  let syntax_type = if syntax_qual.length() > 0 {
    syntax_qual + "." + syntax_type_name
  } else {
    syntax_type_name
  }

  // Build qualified value prefixes (qualifier + "." unless empty)
  let token_prefix = if token_qual.length() > 0 { token_qual + "." } else { "" }
  let syntax_prefix = if syntax_qual.length() > 0 {
    syntax_qual + "."
  } else {
    ""
  }
  let core_prefix = if core_qual.length() > 0 { core_qual + "." } else { "" }

  let func_name = "make_" + to_lowercase_first(language_name) + "_spec"
  Ok(
    StringBuilder()
    ..write_string("///|\n")
    ..write_string("/// Generated factory: fills derived LanguageSpec fields\n")
    ..write_string("/// from annotation metadata.\n")
    ..write_string("pub fn ")
    ..write_string(func_name)
    ..write_string("(\n")
    ..write_string("  parse_root : (")
    ..write_string(core_prefix)
    ..write_string("ParserContext[")
    ..write_string(token_type)
    ..write_string(", ")
    ..write_string(syntax_type)
    ..write_string("]) -> Unit,\n")
    ..write_string("  reuse_size_threshold? : Int = 64,\n")
    ..write_string("  incomplete_kind? : ")
    ..write_string(syntax_type)
    ..write_string(" = ")
    ..write_string(syntax_prefix)
    ..write_string(error_kind_name)
    ..write_string(",\n")
    ..write_string(") -> ")
    ..write_string(core_prefix)
    ..write_string("LanguageSpec[")
    ..write_string(token_type)
    ..write_string(", ")
    ..write_string(syntax_type)
    ..write_string("] {\n")
    ..write_string("  ")
    ..write_string(core_prefix)
    ..write_string("LanguageSpec::new(\n")
    ..write_string("    ")
    ..write_string(syntax_prefix)
    ..write_string(whitespace_kind_name)
    ..write_string(",\n")
    ..write_string("    ")
    ..write_string(syntax_prefix)
    ..write_string(error_kind_name)
    ..write_string(",\n")
    ..write_string("    ")
    ..write_string(syntax_prefix)
    ..write_string(root_kind_name)
    ..write_string(",\n")
    ..write_string("    ")
    ..write_string(token_prefix)
    ..write_string(eof_token_name)
    ..write_string(",\n")
    ..write_string("    parse_root=parse_root,\n")
    ..write_string("    reuse_size_threshold=reuse_size_threshold,\n")
    ..write_string("    incomplete_kind=incomplete_kind,\n")
    ..write_string("  )\n")
    ..write_string("}\n")
    .to_string(),
  )
}
