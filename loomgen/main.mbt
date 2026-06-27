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
/// Parse tombstoned raw numbers from a previously-generated syntax_kind.g.mbt.
/// Looks for comments matching `// #loom.retired: raw1, raw2, raw3`.
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
      "Usage: loomgen [--seed <syntax_kind.mbt>] <token.mbt> [token_out_dir] [syntax_out_dir]",
    )
    return
  }
  let source_path = args[arg_idx]
  // token_impls.g.mbt output directory
  let token_out = if arg_idx + 1 < args.length() {
    args[arg_idx + 1]
  } else {
    "."
  }
  // syntax_kind.g.mbt output directory (defaults to token_out for backward compat)
  let syntax_out = if arg_idx + 2 < args.length() {
    args[arg_idx + 2]
  } else {
    token_out
  }
  // Reject extra arguments beyond the two output directories
  if arg_idx + 3 < args.length() {
    println(
      "Too many arguments. Usage: loomgen [--seed <syntax_kind.mbt>] <token.mbt> [token_out_dir] [syntax_out_dir]",
    )
    return
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

  // Create output directories if they don't exist
  for dir in [token_out, syntax_out] {
    if !@fs.path_exists(dir) {
      @fs.create_dir(dir) catch {
        _ => {
          println("Error creating directory " + dir)
          return
        }
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

  // Auto-restore tombstoned raws from the previous generated syntax_kind.g.mbt, if any.
  // This ensures retired raw numbers survive regeneration cycles.
  let prev_gen_path = syntax_out + "/syntax_kind.g.mbt"
  if @fs.path_exists(prev_gen_path) {
    let prev_src = @fs.read_file_to_string(prev_gen_path) catch { _ => "" }
    if prev_src.length() > 0 {
      let retired_raws = extract_retired_raws(prev_src)
      if retired_raws.length() > 0 {
        registry.seed_retired(retired_raws)
        println(
          "Restored " +
          retired_raws.length().to_string() +
          " tombstoned raws from " +
          prev_gen_path,
        )
      }
    }
  }

  let kinds = build_kind_entries(te, registry)
  let trivia_set : @hashset.HashSet[String] = @hashset.HashSet([])
  let error_set : @hashset.HashSet[String] = @hashset.HashSet([])
  for v in te.variants {
    match v.token_role {
      Some(Trivia) =>
        trivia_set.add(derive_kind_name(v.name, Trivia, v.kind_override))
      Some(ErrorToken) =>
        error_set.add(derive_kind_name(v.name, ErrorToken, v.kind_override))
      _ => ()
    }
  }
  let empty_term_kinds : Array[(String, Int)] = []
  let token_impls_content = emit_token_impls(te, kinds)
  let syntax_kind_content = emit_syntax_kind(
    kinds,
    empty_term_kinds,
    trivia_set,
    error_set,
    registry.tombstoned_rawns(),
  )
  // Write files to their respective target directories
  // (syntax_kind.g.mbt is a token-only subset; not meant to replace existing hand-written
  //  syntax_kind.mbt that also includes term kinds)
  @fs.write_string_to_file(
    syntax_out + "/syntax_kind.g.mbt",
    syntax_kind_content,
  ) catch {
    _ => {
      println("Error writing " + syntax_out + "/syntax_kind.g.mbt")
      return
    }
  }
  @fs.write_string_to_file(
    token_out + "/token_impls.g.mbt",
    token_impls_content,
  ) catch {
    _ => {
      println("Error writing " + token_out + "/token_impls.g.mbt")
      return
    }
  }

  println("Generated:")
  println("  " + syntax_out + "/syntax_kind.g.mbt")
  println("  " + token_out + "/token_impls.g.mbt")
}
