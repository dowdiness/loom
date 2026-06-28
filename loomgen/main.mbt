///|
/// loomgen: code generator for loom/seam/projection pipeline.
/// Usage: loomgen [--seed <syntax_kind.mbt>] [--skip-syntax] <token.mbt> [token_out_dir] [syntax_out_dir]
///
/// Reads annotated MoonBit source, emits token_impls.g.mbt and syntax_kind.mbt.
/// --seed: seed raw-kind numbers from existing syntax_kind.mbt for idempotent re-generation.
fn parse_int(s : String) -> Int {
  for i = 0, n = 0; i < s.length(); {
    let c = s[i]
    if c >= '0' && c <= '9' {
      continue i + 1, n * 10 + (c.to_int() - 48)
    }
    continue i + 1, n
  } nobreak {
    n
  }
}

///|
fn is_all_digits(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i in 0..<s.length() {
    if s[i] < '0' || s[i] > '9' {
      return false
    }
  }
  true
}

///|
/// Extract (kind_name, raw) pairs from an existing syntax_kind.mbt file.
/// Scans lines for `Name => number` or `Name => @seam.RawKind(number)` patterns
/// in the ToRawKind impl or equivalent raw-kind assignment arms.
fn extract_raw_pairs(source : String) -> Array[(String, Int)] {
  let pairs : Array[(String, Int)] = []
  let lines = source.split("\n").to_array()
  for line in lines {
    let trimmed = line.trim().to_owned()
    let parts = trimmed.split(" => ").to_array()
    if parts.length() != 2 {
      continue
    }
    let name = parts[0].to_owned()
    let raw_str = parts[1].to_owned()
    let first_char = name[0]
    if first_char < 'A' || first_char > 'Z' {
      continue
    }
    // Accept bare numbers (Name => 14) or RawKind wrapper (Name => @seam.RawKind(14))
    let raw_val = if is_all_digits(raw_str) {
      Some(parse_int(raw_str))
    } else {
      // Try to extract from RawKind(N) wrapper
      let stripped = raw_str.trim().to_owned()
      // Match @seam.RawKind(N) or bare RawKind(N), no other prefix.
      let inner_text : String? = if stripped.has_prefix("@seam.RawKind(") {
        Some(stripped["@seam.RawKind(".length():].to_owned())
      } else if stripped.has_prefix("RawKind(") {
        Some(stripped["RawKind(".length():].to_owned())
      } else {
        None
      }
      match inner_text {
        Some(body) => {
          // Find closing paren position
          let mut close = -1
          for j = 0; j < body.length(); j = j + 1 {
            if body[j] == ')' {
              close = j
              break
            }
          }
          if close >= 0 {
            let inner = body[:close].trim().to_owned()
            if is_all_digits(inner) {
              Some(parse_int(inner))
            } else {
              None
            }
          } else {
            None
          }
        }
        None => None
      }
    }
    match raw_val {
      Some(raw) => pairs.push((name, raw))
      None => continue
    }
  }
  pairs
}

///|
/// Parse tombstoned raw numbers from a previously-generated syntax_kind.mbt (or .g.mbt).
fn extract_retired_raws(source : String) -> Array[Int] {
  let raws : Array[Int] = []
  let lines = source.split("\n").to_array()
  for line in lines {
    let trimmed = line.trim().to_owned()
    let prefix = "// #loom.retired: "
    if trimmed.has_prefix(prefix) {
      let suffix = trimmed[prefix.length():].trim().to_owned()
      for part in suffix.split(",").to_array() {
        let raw_str = part.trim().to_owned()
        if is_all_digits(raw_str) {
          raws.push(parse_int(raw_str))
        }
      }
    }
  }
  raws
}

///|
fn first_value(arr : Array[String]) -> String? {
  if arr.length() > 0 {
    Some(arr[0])
  } else {
    None
  }
}

///|
/// Check that a name is a valid MoonBit identifier (alphanumeric + underscores).
fn is_valid_mbt_ident(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  let first = s[0]
  if !(first >= 'a' && first <= 'z') &&
    !(first >= 'A' && first <= 'Z') &&
    first != '_' {
    return false
  }
  for i in 1..<s.length() {
    let c = s[i]
    if !(c >= 'a' && c <= 'z') &&
      !(c >= 'A' && c <= 'Z') &&
      !(c >= '0' && c <= '9') &&
      c != '_' {
      return false
    }
  }
  true
}

///|
fn parse_args(argv : Array[String]) -> Result[@argparse.Matches, String] {
  let cmd = @argparse.Command(
    "loomgen",
    about="Generate loom code from annotated MoonBit source files.",
    flags=[
      @argparse.FlagArg("skip-syntax", about="Skip generating syntax_kind.mbt"),
    ],
    options=[
      @argparse.OptionArg(
        "seed",
        about="Seed raw-kind numbers from existing syntax_kind.mbt",
      ),
      @argparse.OptionArg(
        "term",
        about="Term-annotated source file for #loom.term enum",
      ),
      @argparse.OptionArg(
        "spec",
        about="Output path for generated spec (.g.mbt)",
      ),
      @argparse.OptionArg(
        "language",
        about="Language name for generated spec function",
      ),
      @argparse.OptionArg(
        "token-qual",
        default_values=["@token"],
        about="Package qualifier for token type",
      ),
      @argparse.OptionArg(
        "syntax-qual",
        default_values=["@syntax"],
        about="Package qualifier for syntax kind type",
      ),
      @argparse.OptionArg(
        "core-qual",
        default_values=["@core"],
        about="Package qualifier for core types",
      ),
      @argparse.OptionArg(
        "token-type",
        about="Token type name override (default: from source)",
      ),
      @argparse.OptionArg(
        "syntax-type",
        about="Syntax kind type name override (default: from source)",
      ),
    ],
    positionals=[
      @argparse.PositionArg("source", about="Annotated token enum source file"),
      @argparse.PositionArg(
        "token-out",
        num_args=@argparse.ValueRange(lower=0, upper=1),
        about="Token output directory",
      ),
      @argparse.PositionArg(
        "syntax-out",
        num_args=@argparse.ValueRange(lower=0, upper=1),
        about="Syntax output directory",
      ),
    ],
  )
  let m = cmd.parse(argv~, env={}) catch { err => return Err(err.to_string()) }
  Ok(m)
}

///|
/// Phase 1: Create and seed the raw-kind registry from an existing file (--seed)
/// and auto-restore tombstoned raws from prior output.
fn setup_registry(
  seed_path : String?,
  skip_syntax : Bool,
  token_out : String,
  syntax_out : String,
) -> Result[RawKindRegistry, Unit] {
  let registry = RawKindRegistry::new()

  // Seed from existing syntax_kind.mbt if --seed provided
  match seed_path {
    Some(path) => {
      let seed_src = @fs.read_file_to_string(path) catch {
        _ => {
          println("Error reading " + path)
          return Err(())
        }
      }
      let seed_pairs = extract_raw_pairs(seed_src)
      println(
        "Seeded " +
        seed_pairs.length().to_string() +
        " raw kind entries from " +
        path,
      )
      registry.seed(seed_pairs)
    }
    None => ()
  }

  // Auto-restore tombstoned raws from prior output.
  // When --skip-syntax, the companion file (loom.registry.g.txt) takes priority;
  let mut registry_path = syntax_out + "/syntax_kind.mbt"
  // Backward compat: fall back to old .g.mbt filename
  if !@fs.path_exists(registry_path) {
    let old_path = syntax_out + "/syntax_kind.g.mbt"
    if @fs.path_exists(old_path) {
      registry_path = old_path
    }
  }
  if skip_syntax {
    let companion = token_out + "/loom.registry.g.txt"
    if @fs.path_exists(companion) {
      registry_path = companion
    }
  }
  if @fs.path_exists(registry_path) {
    let prev_src = @fs.read_file_to_string(registry_path) catch { _ => "" }
    if prev_src.length() > 0 {
      let retired_raws = extract_retired_raws(prev_src)
      if retired_raws.length() > 0 {
        registry.seed_retired(retired_raws)
        println(
          "Restored " +
          retired_raws.length().to_string() +
          " tombstoned raws from " +
          registry_path,
        )
      }
    }
  }
  Ok(registry)
}

///|
struct KindBuildResult {
  kinds : Array[(String, Int)]
  term_kinds : Array[(String, Int)]
  trivia_set : @hashset.HashSet[String]
  error_set : @hashset.HashSet[String]
  error_node_name : String?
}

///|
/// Phase 2: Build kind entries from annotated enums, collect trivia/error sets,
/// and validate cross-enum collisions.
fn build_kinds(
  te : EnumDecl,
  registry : RawKindRegistry,
  term_enum_decl : EnumDecl?,
) -> Result[KindBuildResult, Unit] {
  let kinds = build_kind_entries(te, registry)
  let trivia_set : @hashset.HashSet[String] = @hashset.HashSet([])
  let error_set : @hashset.HashSet[String] = @hashset.HashSet([])
  for v in te.variants {
    match v.role {
      Some(Trivia) =>
        trivia_set.add(derive_kind_name(v.name, Trivia, v.kind_override))
      Some(ErrorToken) =>
        error_set.add(derive_kind_name(v.name, ErrorToken, v.kind_override))
      _ => ()
    }
  }
  // Process term enum if present
  let term_kinds = match term_enum_decl {
    Some(term_enum) => build_kind_entries(term_enum, registry)
    None => []
  }
  // Cross-enum collision: a derived token kind must not share a name
  // with a term kind, or the generated SyntaxKind enum will have
  // duplicate variants.
  if term_kinds.length() > 0 {
    let token_names : @hashset.HashSet[String] = @hashset.HashSet([])
    for pair in kinds {
      let (name, _) = pair
      token_names.add(name)
    }
    for pair in term_kinds {
      let (name, _) = pair
      if token_names.contains(name) {
        println(
          "error: token kind \"" +
          name +
          "\" conflicts with a term kind of the same name\n" +
          "  Both enums define \"" +
          name +
          "\". Rename the term variant or adjust the token annotation.",
        )
        return Err(())
      }
    }
  }
  // Find error_node_name from term enum for from_raw fallback
  let mut error_node_name : String? = None
  match term_enum_decl {
    Some(term_enum) =>
      for v in term_enum.variants {
        match v.role {
          Some(ErrorNode) =>
            error_node_name = Some(
              derive_kind_name(v.name, ErrorNode, v.kind_override),
            )
          _ => ()
        }
      }
    None => ()
  }
  Ok({ kinds, term_kinds, trivia_set, error_set, error_node_name })
}

///|
/// Phase 3: Write all output files — token_impls.g.mbt, syntax_kind.mbt,
/// companion registry file, and optional spec file.
fn write_outputs(
  te : EnumDecl,
  kinds : Array[(String, Int)],
  term_kinds : Array[(String, Int)],
  trivia_set : @hashset.HashSet[String],
  error_set : @hashset.HashSet[String],
  error_node_name : String?,
  retired_rawns : Array[Int],
  skip_syntax : Bool,
  token_out : String,
  syntax_out : String,
  spec_path : String?,
  language_name : String?,
  cli_token_type : String?,
  cli_syntax_type : String?,
  token_qual : String,
  syntax_qual : String,
  core_qual : String,
  term_enum_decl : EnumDecl?,
) -> Result[Unit, Unit] {
  let token_impls_content = emit_token_impls(te, kinds)
  // Write token_impls.g.mbt
  @fs.write_string_to_file(
    token_out + "/token_impls.g.mbt",
    token_impls_content,
  ) catch {
    _ => {
      println("Error writing " + token_out + "/token_impls.g.mbt")
      return Err(())
    }
  }

  // Write syntax_kind.mbt (only when --skip-syntax is not set)
  if !skip_syntax {
    let syntax_kind_content = emit_syntax_kind(
      kinds, term_kinds, trivia_set, error_set, error_node_name, retired_rawns,
    )
    @fs.write_string_to_file(
      syntax_out + "/syntax_kind.mbt",
      syntax_kind_content,
    ) catch {
      _ => {
        println("Error writing " + syntax_out + "/syntax_kind.mbt")
        return Err(())
      }
    }
    println("  " + syntax_out + "/syntax_kind.mbt")
  }

  // Write element_props.g.mbt (only when syntax kinds are generated and term enum exists)
  if !skip_syntax {
    match term_enum_decl {
      Some(term_enum_val) =>
        match emit_element_props(term_enum_val) {
          Some(content) => {
            @fs.write_string_to_file(
              syntax_out + "/element_props.g.mbt",
              content,
            ) catch {
              _ => {
                println("Error writing " + syntax_out + "/element_props.g.mbt")
                return Err(())
              }
            }
            println("  " + syntax_out + "/element_props.g.mbt")
          }
          None =>
            // Remove stale file when no variants are flagged
            @fs.remove_file(syntax_out + "/element_props.g.mbt") catch {
              _ => ()
            }
        }
      None =>
        // Remove stale file when term enum is entirely absent
        @fs.remove_file(syntax_out + "/element_props.g.mbt") catch {
          _ => ()
        }
    }
  }

  // Write lexmode.g.mbt (lex mode dispatch) when term variants have #loom.lexmode annotations.
  if !skip_syntax {
    match term_enum_decl {
      Some(term_enum_val) =>
        match emit_lexmode(term_enum_val) {
          Some(content) => {
            @fs.write_string_to_file(syntax_out + "/lexmode.g.mbt", content) catch {
              _ => {
                println("Error writing " + syntax_out + "/lexmode.g.mbt")
                return Err(())
              }
            }
            println("  " + syntax_out + "/lexmode.g.mbt")
          }
          None =>
            // Remove stale file when no variants have lexmode annotations
            @fs.remove_file(syntax_out + "/lexmode.g.mbt") catch {
              _ => ()
            }
        }
      None =>
        // Remove stale file when term enum is entirely absent
        @fs.remove_file(syntax_out + "/lexmode.g.mbt") catch {
          _ => ()
        }
    }
  }

  // Persist retired raws for next --seed round-trip.
  // Always write the companion file in skip-syntax mode, even when empty,
  // so stale entries from previous runs are cleared.
  if skip_syntax {
    let parts = retired_rawns.map(fn(r) { r.to_string() })
    let line = "// #loom.retired: " + parts.join(", ")
    @fs.write_string_to_file(token_out + "/loom.registry.g.txt", line) catch {
      _ => ()
    }
  }

  // Write spec file if --spec is given and term_enum is present
  match spec_path {
    Some(sp) =>
      match term_enum_decl {
        None => {
          println(
            "--spec requires a #loom.term enum (use --term or annotate term enum in source)",
          )
          return Err(())
        }
        Some(term_enum_val) => {
          let lang = match language_name {
            Some(name) => name
            None => {
              println("--spec requires --language <name>")
              return Err(())
            }
          }
          if lang.length() == 0 {
            println("--language must be a non-empty name")
            return Err(())
          }
          if !is_valid_mbt_ident(lang) {
            println(
              "--language must be a valid MoonBit identifier (alphanumeric, underscores)",
            )
            return Err(())
          }
          let token_type_name = match cli_token_type {
            Some(n) => n
            None => te.name
          }
          let syntax_type_name = match cli_syntax_type {
            Some(n) => n
            None => term_enum_val.name
          }
          match
            emit_spec(
              te, term_enum_val, lang, token_type_name, syntax_type_name, token_qual,
              syntax_qual, core_qual,
            ) {
            Ok(content) => {
              @fs.write_string_to_file(sp, content) catch {
                _ => {
                  println("Error writing " + sp)
                  return Err(())
                }
              }
              println("  " + sp)
            }
            Err(msg) => {
              println("error: " + msg)
              return Err(())
            }
          }
        }
      }
    None => ()
  }

  // Write views.g.mbt (view accessors) when term_enum has #loom.view variants.
  // Always check for stale file to remove, even when no term enum exists.
  let views_path = syntax_out + "/views.g.mbt"
  let mut views_written = false
  match term_enum_decl {
    Some(term_enum_val) if !skip_syntax => {
      let syntax_type_name = "SyntaxKind"
      let content = emit_view_accessors(term_enum_val, syntax_type_name)
      if content.length() > 0 {
        @fs.write_string_to_file(views_path, content) catch {
          _ => {
            println("Error writing " + views_path)
            return Err(())
          }
        }
        println("  " + views_path)
        views_written = true
      }
    }
    _ => ()
  }
  if !views_written && !skip_syntax && @fs.path_exists(views_path) {
    @fs.remove_file(views_path) catch {
      _ => println("Warning: could not remove stale " + views_path)
    }
  }

  println("  " + token_out + "/token_impls.g.mbt")
  Ok(())
}

///|
/// Read, parse, and annotate a source file. Returns the AnnotatedEnums on success.
fn read_and_parse(source_path : String) -> Result[AnnotatedEnums, Unit] {
  let src = @fs.read_file_to_string(source_path) catch {
    _ => {
      println("Error reading " + source_path)
      return Err(())
    }
  }
  match parse_annotations(src) {
    Err(msg) => {
      println("Parse error: " + msg)
      Err(())
    }
    Ok(a) => Ok(a)
  }
}

///|
/// Read and parse a --term file, validate it, and merge into term_enum_decl.
/// Returns Some(term_enum) on success, Err on failure (already printed).
fn load_term_enum(term_path : String) -> Result[AnnotatedEnums, Unit] {
  let term_src = @fs.read_file_to_string(term_path) catch {
    _ => {
      println("Error reading " + term_path)
      return Err(())
    }
  }
  match parse_annotations(term_src) {
    Err(msg) => {
      println("Error parsing term source " + term_path + ": " + msg)
      Err(())
    }
    Ok(a) => {
      // Reject #loom.token in the term file
      if a.token_enum is Some(_) {
        println("--term file should not contain a #loom.token enum")
        return Err(())
      }
      Ok(a)
    }
  }
}

///|
fn main {
  let argv = @sys.get_cli_args()
  let matches = match parse_args(argv[1:].to_owned()) {
    Ok(m) => m
    Err(msg) => {
      println(msg)
      @sys.exit(1)
      return
    }
  }

  let seed_path = first_value(matches.values.get_or_default("seed", []))
  let skip_syntax = matches.flags.get_or_default("skip-syntax", false)
  let term_path = first_value(matches.values.get_or_default("term", []))
  let spec_path = first_value(matches.values.get_or_default("spec", []))
  let language_name = first_value(matches.values.get_or_default("language", []))
  let token_qual = first_value(
    matches.values.get_or_default("token-qual", ["@token"]),
  ).unwrap_or("@token")
  let syntax_qual = first_value(
    matches.values.get_or_default("syntax-qual", ["@syntax"]),
  ).unwrap_or("@syntax")
  let core_qual = first_value(
    matches.values.get_or_default("core-qual", ["@core"]),
  ).unwrap_or("@core")
  let cli_token_type = first_value(
    matches.values.get_or_default("token-type", []),
  )
  let cli_syntax_type = first_value(
    matches.values.get_or_default("syntax-type", []),
  )
  let source_path = match
    first_value(matches.values.get_or_default("source", [])) {
    Some(p) => p
    None => {
      println("error: source file required")
      @sys.exit(1)
      return
    }
  }
  let token_out = first_value(matches.values.get_or_default("token-out", [])).unwrap_or(
    ".",
  )
  let syntax_out = first_value(matches.values.get_or_default("syntax-out", [])).unwrap_or(
    token_out,
  )

  let annotated = match read_and_parse(source_path) {
    Err(_) => {
      @sys.exit(1)
      return
    }
    Ok(a) => a
  }
  let te = match annotated.token_enum {
    None => {
      println("No #loom.token enum found in " + source_path)
      @sys.exit(1)
      return
    }
    Some(e) => e
  }

  // Track term_enum: from primary source or --term file
  let mut term_enum_decl = annotated.term_enum

  // If --term is given, parse that file and merge term_enum
  match term_path {
    Some(tp) => {
      let term_annotated = match load_term_enum(tp) {
        Err(_) => {
          @sys.exit(1)
          return
        }
        Ok(a) => a
      }
      // Reject duplicate term_enum
      if term_enum_decl is Some(_) && term_annotated.term_enum is Some(_) {
        println("Both primary source and --term provide a #loom.term enum")
        @sys.exit(1)
        return
      }
      // Merge term_enum from term file
      if term_annotated.term_enum is Some(_) {
        term_enum_decl = term_annotated.term_enum
      }
    }
    None => ()
  }

  // Create output directories if they don't exist
  for dir in [token_out, syntax_out] {
    if !@fs.path_exists(dir) {
      @fs.create_dir(dir) catch {
        _ => {
          println("Error creating directory " + dir)
          @sys.exit(1)
          return
        }
      }
    }
  }

  let registry = match
    setup_registry(seed_path, skip_syntax, token_out, syntax_out) {
    Err(_) => {
      @sys.exit(1)
      return
    }
    Ok(r) => r
  }

  let build_result = match build_kinds(te, registry, term_enum_decl) {
    Err(_) => {
      @sys.exit(1)
      return
    }
    Ok(r) => r
  }

  let retired_rawns = registry.tombstoned_rawns()

  match
    write_outputs(
      te,
      build_result.kinds,
      build_result.term_kinds,
      build_result.trivia_set,
      build_result.error_set,
      build_result.error_node_name,
      retired_rawns,
      skip_syntax,
      token_out,
      syntax_out,
      spec_path,
      language_name,
      cli_token_type,
      cli_syntax_type,
      token_qual,
      syntax_qual,
      core_qual,
      term_enum_decl,
    ) {
    Err(_) => {
      @sys.exit(1)
      return
    }
    Ok(_) => ()
  }
}
