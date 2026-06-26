///|
/// loomgen: code generator for loom/seam/projection pipeline.
/// Usage: loomgen [--seed <syntax_kind.mbt>] <token.mbt> [output_dir]
///
/// Reads annotated MoonBit source, emits .g.mbt files.
/// --seed: seed raw-kind numbers from existing syntax_kind.mbt for idempotent re-generation.
fn parse_int(s : String) -> Int {
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - 48)
    }
  }
  n
}

///|
fn is_all_digits(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] < '0' || s[i] > '9' {
      return false
    }
  }
  true
}

///|
/// Extract (kind_name, raw) pairs from an existing syntax_kind.mbt file.
/// Scans for `Name => number` patterns in the ToRawKind impl.
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
    if !is_all_digits(raw_str) {
      continue
    }
    pairs.push((name, parse_int(raw_str)))
  }
  pairs
}

///|
fn main {
  let args = @sys.get_cli_args()
  let mut arg_idx = 1
  let mut seed_path : String? = None

  // Parse optional --seed flag
  while arg_idx < args.length() && args[arg_idx] == "--seed" {
    if arg_idx + 1 >= args.length() {
      println("--seed requires an argument")
      return
    }
    seed_path = Some(args[arg_idx + 1])
    arg_idx = arg_idx + 2
  }

  if arg_idx >= args.length() {
    println(
      "Usage: loomgen [--seed <syntax_kind.mbt>] <token.mbt> [output_dir]",
    )
    return
  }
  let source_path = args[arg_idx]
  let out_dir = if arg_idx + 1 < args.length() {
    args[arg_idx + 1]
  } else {
    "."
  }

  let src = @fs.read_file_to_string(source_path) catch {
    _ => {
      println("Error reading " + source_path)
      return
    }
  }

  let result = parse_annotations(src)
  let te = match result {
    Err(msg) => {
      println("Parse error: " + msg)
      return
    }
    Ok(a) =>
      match a.token_enum {
        None => {
          println("No #loom.token enum found in " + source_path)
          return
        }
        Some(e) => e
      }
  }

  // Create output directory if it doesn't exist
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir) catch {
      _ => {
        println("Error creating directory " + out_dir)
        return
      }
    }
  }

  let registry = RawKindRegistry::new()

  // Seed from existing syntax_kind.mbt if --seed provided
  match seed_path {
    Some(path) => {
      let seed_src = @fs.read_file_to_string(path) catch {
        _ => {
          println("Error reading " + path)
          return
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

  let kinds = build_kind_entries(te, registry)
  let trivia_set : @hashset.HashSet[String] = @hashset.HashSet([])
  let error_set : @hashset.HashSet[String] = @hashset.HashSet([])
  for v in te.variants {
    match v.token_role {
      Some(Trivia) =>
        trivia_set.add(derive_kind_name(v.name, Trivia, v.kind_override))
      Some(ErrorToken) => error_set.add("ErrorToken")
      _ => ()
    }
  }
  let empty_term_kinds : Array[(String, Int)] = []

  let syntax_kind_content = emit_syntax_kind(
    kinds, empty_term_kinds, trivia_set, error_set,
  )
  let token_impls_content = emit_token_impls(te, kinds)

  // Write both .g.mbt files
  // (syntax_kind.g.mbt is a token-only subset; not meant to replace existing hand-written
  //  syntax_kind.mbt that also includes term kinds)
  @fs.write_string_to_file(out_dir + "/syntax_kind.g.mbt", syntax_kind_content) catch {
    _ => {
      println("Error writing " + out_dir + "/syntax_kind.g.mbt")
      return
    }
  }
  @fs.write_string_to_file(out_dir + "/token_impls.g.mbt", token_impls_content) catch {
    _ => {
      println("Error writing " + out_dir + "/token_impls.g.mbt")
      return
    }
  }

  println("Generated:")
  println("  " + out_dir + "/syntax_kind.g.mbt")
  println("  " + out_dir + "/token_impls.g.mbt")
}
