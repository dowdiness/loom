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
/// Collect all variants with the given nullary SyntaxRole.
fn find_all_variants_with_role(
  enum_decl : EnumDecl,
  role : SyntaxRole,
) -> Array[VariantDecl] {
  let result : Array[VariantDecl] = []
  for v in enum_decl.variants {
    match v.role {
      Some(r) if roles_match(r, role) => result.push(v)
      _ => ()
    }
  }
  result
}

///|
/// True when the enum declares two or more variants with the given role.
fn has_duplicate(enum_decl : EnumDecl, role : SyntaxRole) -> Bool {
  find_all_variants_with_role(enum_decl, role).length() > 1
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
  let trivia_vars = find_all_variants_with_role(token_enum, Trivia)
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
  if trivia_vars.length() == 0 {
    return Err(
      "#loom.token enum " + token_enum.name + " missing #loom.trivia variant",
    )
  }

  // Spec-scalar roles: error and eof must still be unique.
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
  // First trivia variant is the primary whitespace_kind (LanguageSpec scalar).
  // Additional variants are covered by the generated is_*_trivia_kind helper below.
  let trivia_v = trivia_vars[0]

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
  let b = StringBuilder()
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
  // When there are multiple trivia variants, emit an is_*_trivia_kind helper.
  // The primary whitespace_kind covers the auto-skip path in LanguageSpec;
  // this helper lets grammar code test whether any CST kind is trivia.
  if trivia_vars.length() > 1 {
    let helper_name = "is_" + to_lowercase_first(language_name) + "_trivia_kind"
    let arms = trivia_vars.map(fn(v) {
      syntax_prefix + derive_kind_name(v.name, Trivia, v.kind_override)
    })
    b.write_string("\n///|\n")
    b.write_string("/// Returns true for all trivia syntax kinds in this language.\n")
    b.write_string("/// Generated from all #loom.trivia-annotated token variants.\n")
    b.write_string("pub fn ")
    b.write_string(helper_name)
    b.write_string("(kind : ")
    b.write_string(syntax_type)
    b.write_string(") -> Bool {\n")
    b.write_string("  match kind {\n    ")
    b.write_string(arms.join(" | "))
    b.write_string(" => true\n")
    b.write_string("    _ => false\n")
    b.write_string("  }\n}\n")
  }
  Ok(b.to_string())
}
