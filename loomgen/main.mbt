///|
/// loomgen: code generator for loom/seam/projection pipeline.
/// Usage: loomgen [--seed <syntax_kind.mbt>] [--skip-syntax] <token.mbt> [token_out_dir] [syntax_out_dir]
///
/// Reads annotated MoonBit source, emits token_impls.g.mbt and syntax_kind.mbt.
/// --seed: seed raw-kind numbers from existing syntax_kind.mbt for idempotent re-generation.
///   When omitted, loomgen auto-detects the prior output in the syntax_out directory.

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
/// Extract the immediate parent directory from a file path.
/// A bare filename maps to the current directory. No filesystem
/// canonicalization is performed.
fn path_parent(path : String) -> String {
  match path.rev_find("/") {
    None => "."
    Some(separator) => path[:separator].to_owned()
  }
}

///|
/// Textually normalize a directory path for comparison by stripping one trailing
/// `/` (except root) and one leading `./`.
fn normalize_dir(s : String) -> String {
  let without_trailing = if s.length() > 1 && s[s.length() - 1] == '/' {
    s[:s.length() - 1].to_owned()
  } else {
    s
  }
  if without_trailing.length() >= 2 &&
    without_trailing[0] == '.' &&
    without_trailing[1] == '/' {
    without_trailing[2:].to_owned()
  } else {
    without_trailing
  }
}

///|
/// Check whether generated line helpers will share the skeleton's package.
fn line_lexer_shares_syntax_output(
  line_lexer_path : String,
  syntax_out : String,
) -> Bool {
  normalize_dir(path_parent(line_lexer_path)) == normalize_dir(syntax_out)
}

///|
fn parse_args(argv : Array[String]) -> Result[@argparse.Matches, String] {
  let cmd = @argparse.Command(
    "loomgen",
    about="Generate loom code from annotated MoonBit source files.",
    flags=[
      @argparse.FlagArg("skip-syntax", about="Skip generating syntax_kind.mbt"),
      @argparse.FlagArg(
        "force-lexer",
        about="Overwrite existing lexer skeleton file",
      ),
      @argparse.FlagArg(
        "regenerate-fixtures",
        about="Regenerate all fixture .g.mbt files; run moon fmt loomgen/fixtures/ fixtures/line_lexer_regression afterward.",
      ),
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
      @argparse.OptionArg(
        "lexer",
        about="Output path for generated step lexer (.g.mbt)",
      ),
      @argparse.OptionArg(
        "line-lexer",
        about="Output path for generated line-mode lexer functions (.g.mbt) (#561)",
      ),
      @argparse.OptionArg(
        "grammar-ir",
        about="Output path for generated GrammarIr from #loom.rule annotations (.g.mbt)",
      ),
      @argparse.OptionArg(
        "grammar-file",
        about="Input .loomgrammar file whose productions override/extend #loom.rule annotations (#523)",
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
  let m = cmd.parse(argv~, env=Map([])) catch {
    err => return Err(err.to_string())
  }
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
    None => {
      // Auto-seed from existing syntax output for stable raw-kind numbers.
      let prior_path = syntax_out + "/syntax_kind.mbt"
      let prior = if @fs.path_exists(prior_path) {
        prior_path
      } else {
        let alt = syntax_out + "/syntax_kind.g.mbt"
        if @fs.path_exists(alt) {
          alt
        } else {
          // loom.registry.g.txt only stores retired raws (comments), not
          // active (name, raw) pairs — extract_raw_pairs returns nothing.
          // No auto-seed is better than a silent no-op.
          ""
        }
      }
      if prior.length() > 0 && @fs.path_exists(prior) {
        let seed_src = @fs.read_file_to_string(prior) catch { _ => "" }
        if seed_src.length() > 0 {
          let seed_pairs = extract_raw_pairs(seed_src)
          if seed_pairs.length() > 0 {
            println(
              "Auto-seeded " +
              seed_pairs.length().to_string() +
              " raw kind entries from " +
              prior,
            )
            registry.seed(seed_pairs)
          }
        }
      } else {
        println(
          "Note: no --seed flag given and no prior output found in " +
          syntax_out +
          "; raw-kind numbers may differ from previous runs",
        )
      }
    }
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
      let retired_raws = extract_retired_rawns(prev_src)
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
) -> Result[KindBuildResult, String] {
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
        return Err(
          "token kind \"" +
          name +
          "\" conflicts with a term kind of the same name\n" +
          "  Both enums define \"" +
          name +
          "\". Rename the term variant or adjust the token annotation.",
        )
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
  force_lexer : Bool,
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
  line_lexer_modes : Array[String]?,
) -> Result[Unit, Unit] {
  let token_type_name = match cli_token_type {
    Some(n) => n
    None => te.name
  }
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
  // Write sync_point.g.mbt (generated is_sync_point from #loom.recovery("sync") annotations)
  let sync_point_content = emit_sync_point(te)
  @fs.write_string_to_file(token_out + "/sync_point.g.mbt", sync_point_content) catch {
    _ => {
      println("Error writing " + token_out + "/sync_point.g.mbt")
      return Err(())
    }
  }
  println("  " + token_out + "/sync_point.g.mbt")

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

  // Clean up stale lexmode.g.mbt when syntax generation is skipped
  if skip_syntax {
    @fs.remove_file(syntax_out + "/lexmode.g.mbt") catch {
      _ => ()
    }
  }

  // Write lexer_skeleton.g.mbt (mode-dispatch skeleton, once semantics).
  // A valid --line-lexer request also needs this dispatcher when syntax output
  // is otherwise skipped, but ordinary --skip-syntax behavior still removes it.
  if !skip_syntax || line_lexer_modes is Some(_) {
    let skel_path = syntax_out + "/lexer_skeleton.g.mbt"
    match term_enum_decl {
      Some(term_enum_val) => {
        let modes = collect_lexmodes(term_enum_val)
        if modes.length() > 0 {
          if !@fs.path_exists(skel_path) || force_lexer {
            let content = match line_lexer_modes {
              Some(line_modes) =>
                emit_lexer_skeleton_with_line_delegates(
                  modes, line_modes, token_type_name, core_qual,
                )
              None => emit_lexer_skeleton(modes, token_type_name, core_qual)
            }
            @fs.write_string_to_file(skel_path, content) catch {
              _ => {
                println("Error writing " + skel_path)
                return Err(())
              }
            }
            println("  " + skel_path)
          } else {
            match line_lexer_modes {
              Some(line_modes) => {
                let existing = @fs.read_file_to_string(skel_path) catch {
                  _ => {
                    println("Error reading " + skel_path)
                    return Err(())
                  }
                }
                let integrated = integrate_line_lexer_skeleton(
                  existing, line_modes, token_type_name, core_qual,
                )
                if integrated != existing {
                  @fs.write_string_to_file(skel_path, integrated) catch {
                    _ => {
                      println("Error writing " + skel_path)
                      return Err(())
                    }
                  }
                  println("  " + skel_path)
                }
              }
              None => ()
            }
          }
        } else {
          // Remove stale file when no modes are declared.
          @fs.remove_file(skel_path) catch {
            _ => ()
          }
        }
      }
      None =>
        // Remove stale file when term enum is absent.
        @fs.remove_file(skel_path) catch {
          _ => ()
        }
    }
  }
  if skip_syntax && line_lexer_modes is None {
    @fs.remove_file(syntax_out + "/lexer_skeleton.g.mbt") catch {
      _ => ()
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
/// Read and parse a `.loomgrammar` file (#523) into a `name -> RuleAst` map for
/// `emit_grammar_ir`. Parse errors are prefixed with the file path so they point at
/// a real file position. A production that also has a `#loom.rule` annotation on its
/// term variant emits a warning (the file takes precedence), enabling incremental
/// migration off annotations. Returns Err on read/parse failure (already printed).
fn load_grammar_file(
  path : String,
  term_enum : EnumDecl,
) -> Result[(Map[String, RuleAst], Map[String, Int]), Unit] {
  let src = @fs.read_file_to_string(path) catch {
    _ => {
      println("Error reading " + path)
      return Err(())
    }
  }
  let prods = match parse_grammar_file(src) {
    Ok(p) => p
    Err(m) => {
      println("error: " + path + ": " + m)
      return Err(())
    }
  }
  let annotated : @hashset.HashSet[String] = @hashset.HashSet([])
  for v in term_enum.variants {
    if v.rule is Some(_) {
      annotated.add(v.name)
    }
  }
  let file_rules : Map[String, RuleAst] = Map([])
  let file_lines : Map[String, Int] = Map([])
  for p in prods {
    let (name, ast, line) = p
    if annotated.contains(name) {
      println(
        "warning: " +
        path +
        ": production '" +
        name +
        "' overrides its #loom.rule annotation",
      )
    }
    file_rules.set(name, ast)
    file_lines.set(name, line)
  }
  Ok((file_rules, file_lines))
}

///|
/// Write a preflighted line-mode helper before installing a skeleton delegate
/// that calls it, so helper-write failures cannot leave a dangling reference.
fn write_line_lexer_job(
  job : (String, String, Array[String])?,
) -> Result[Unit, String] {
  match job {
    None => Ok(())
    Some((path, content, _)) => {
      @fs.write_string_to_file(path, content) catch {
        _ => return Err("Error writing " + path)
      }
      println("  " + path)
      Ok(())
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
  if matches.flags.get_or_default("regenerate-fixtures", false) {
    match regenerate_fixtures() {
      Ok(_) => ()
      Err(msg) => {
        println("error: fixture regeneration failed — " + msg)
        @sys.exit(1)
      }
    }
    return
  }
  let seed_path = first_value(matches.values.get_or_default("seed", []))
  let skip_syntax = matches.flags.get_or_default("skip-syntax", false)
  let force_lexer = matches.flags.get_or_default("force-lexer", false)
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
  let lexer_path = first_value(matches.values.get_or_default("lexer", []))
  let line_lexer_path = first_value(
    matches.values.get_or_default("line-lexer", []),
  )
  let grammar_ir_path = first_value(
    matches.values.get_or_default("grammar-ir", []),
  )
  let grammar_file_path = first_value(
    matches.values.get_or_default("grammar-file", []),
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

  // #523: --grammar-file is an INPUT; --grammar-ir names the OUTPUT path. A grammar
  // file with no --grammar-ir has nowhere to emit, so fail closed rather than
  // silently ignore it. Check BEFORE creating output directories so a wrong CLI
  // invocation is side-effect free.
  if grammar_file_path is Some(_) && grammar_ir_path is None {
    println(
      "error: --grammar-file requires --grammar-ir <out> (the grammar file is an input; --grammar-ir names the generated GrammarIr output)",
    )
    @sys.exit(1)
    return
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
    Err(message) => {
      println("error: " + message)
      @sys.exit(1)
      return
    }
    Ok(r) => r
  }

  let retired_rawns = registry.tombstoned_rawns()

  // Preflight the step lexer BEFORE writing any output, so an invalid --lexer
  // request (nullable/unsupported pattern, unlexable variant) fails fast instead
  // of leaving token_impls.g.mbt / syntax_kind.mbt half-written. #521
  let lexer_job : (String, String)? = match lexer_path {
    Some(path) =>
      match emit_lexer(te, core_qual, "step_lex") {
        Ok(content) => Some((path, content))
        Err(msg) => {
          println("error: " + msg)
          @sys.exit(1)
          return
        }
      }
    None => None
  }

  // Before line-lexer preflight, validate the same-directory constraint:
  // generated helpers use unqualified calls, so line_lexer.g.mbt must share
  // the same MoonBit package as lexer_skeleton.g.mbt (syntax_out).
  match line_lexer_path {
    Some(path) =>
      if !line_lexer_shares_syntax_output(path, syntax_out) {
        println(
          "error: --line-lexer path \"" +
          path +
          "\" is not in --syntax-out directory \"" +
          syntax_out +
          "\"; generated helpers and skeleton must share the same package",
        )
        @sys.exit(1)
        return
      }
    None => ()
  }

  // Preflight the line-mode lexer (#561) BEFORE writing any output.
  let line_lexer_job : (String, String, Array[String])? = match
    line_lexer_path {
    Some(path) =>
      match emit_line_lexer(te, term_enum_decl, core_qual) {
        Some(content) =>
          Some((path, content, collect_line_lexer_modes(term_enum_decl)))
        None => {
          println(
            "error: --line-lexer requires #loom.line_pattern annotations on token variants and #loom.line_mode annotations on #loom.lexmode term variants",
          )
          @sys.exit(1)
          return
        }
      }
    None => None
  }
  // `emit_line_lexer` only succeeds with line modes; retain the explicit
  // non-empty guard so --skip-syntax keeps its historical cleanup behavior if
  // that invariant changes.
  let line_lexer_modes : Array[String]? = match line_lexer_job {
    Some((_, _, modes)) if modes.length() > 0 => Some(modes)
    _ => None
  }

  // Preflight the GrammarIr emission BEFORE writing any output, so an invalid
  // --grammar-ir request (unknown symbol, left recursion, malformed rule string)
  // fails fast instead of leaving other outputs half-written. #522
  let grammar_ir_job : (String, String)? = match grammar_ir_path {
    Some(path) =>
      match term_enum_decl {
        None => {
          println(
            "error: --grammar-ir requires a #loom.term enum (use --term or annotate one in source)",
          )
          @sys.exit(1)
          return
        }
        Some(term) => {
          let lang = match language_name {
            Some(l) => l
            None => "loom"
          }
          // value_name is spliced into a generated `pub let`, so lang must be a
          // valid identifier or the output won't compile. Fail closed.
          guard is_mbt_identifier(lang) else {
            println(
              "error: --language '" +
              lang +
              "' is not a valid MoonBit identifier; it is used as the generated GrammarIr value name",
            )
            @sys.exit(1)
            return
          }
          let value_name = lang + "_grammar_ir"
          // #523: load the optional .loomgrammar file; its productions override the
          // #loom.rule annotations (with a warning) before lowering.
          let (file_rules, file_lines) = match grammar_file_path {
            Some(gf) =>
              match load_grammar_file(gf, term) {
                Ok(fr) => fr
                Err(_) => {
                  @sys.exit(1)
                  return
                }
              }
            None => (Map([]), Map([]))
          }
          match
            emit_grammar_ir(
              term,
              te,
              token_qual,
              syntax_qual,
              "@grammar",
              value_name,
              file_rules~,
              file_lines~,
            ) {
            Ok(content) => Some((path, content))
            Err(msg) => {
              println("error: " + msg)
              @sys.exit(1)
              return
            }
          }
        }
      }
    None => None
  }

  // Write the preflighted line-mode lexer before any skeleton can delegate to it.
  match write_line_lexer_job(line_lexer_job) {
    Err(msg) => {
      println(msg)
      @sys.exit(1)
      return
    }
    Ok(_) => ()
  }

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
      force_lexer,
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
      line_lexer_modes,
    ) {
    Err(_) => {
      @sys.exit(1)
      return
    }
    Ok(_) => ()
  }

  // Write the preflighted step lexer (already built + validated above). #521
  match lexer_job {
    Some((path, content)) => {
      @fs.write_string_to_file(path, content) catch {
        _ => {
          println("Error writing " + path)
          @sys.exit(1)
          return
        }
      }
      println("  " + path)
    }
    None => ()
  }

  // Write the preflighted GrammarIr (already built + validated above). #522
  match grammar_ir_job {
    Some((path, content)) => {
      @fs.write_string_to_file(path, content) catch {
        _ => {
          println("Error writing " + path)
          @sys.exit(1)
          return
        }
      }
      println("  " + path)
    }
    None => ()
  }
}
