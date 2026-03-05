// Deterministic differential fuzz tests for incremental parsing.
//
// Oracle:
//   ImperativeParser::edit(new_source) == full parse of new_source
// where full parse uses parse_cst_recover (or tokenization error node).

///|
fn idf_next_seed(seed : Int) -> Int {
  let a = 1103515245
  let c = 12345
  let m = 2147483647
  (seed * a + c) % m
}

///|
fn idf_clamp(pos : Int, len : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > len {
    len
  } else {
    pos
  }
}

///|
fn idf_slice_string(s : String, start : Int, end : Int) -> String? {
  let res : Result[StringView, Error] = try? s[start:end]
  match res {
    Ok(view) => Some(view.to_string())
    Err(_) => None
  }
}

///|
fn idf_pool(allow_invalid : Bool) -> Array[String] {
  if allow_invalid {
    [
      "x", "y", "z", "0", "1", "2", "if", "then", "else", "\\", ".", "(", ")", "+",
      "-", " ", "@", "#", "$", "]", "[",
    ]
  } else {
    [
      "x", "y", "z", "0", "1", "2", "if", "then", "else", "\\", ".", "(", ")", "+",
      "-", " ",
    ]
  }
}

///|
fn idf_make_fragment(seed : Int, allow_invalid : Bool) -> String {
  let pool = idf_pool(allow_invalid)
  let mut s = seed
  let mut out = ""
  let count = seed.abs() % 4 + 1
  let pool_len = pool.length()
  for _i = 0; _i < count; _i = _i + 1 {
    s = idf_next_seed(s)
    let idx = s.abs() % pool_len
    out = out + pool[idx]
  }
  out
}

///|
fn idf_make_source(seed : Int, allow_invalid : Bool) -> String {
  let pool = idf_pool(allow_invalid)
  let mut s = seed
  let mut out = ""
  let count = seed.abs() % 10 + 3
  let pool_len = pool.length()
  for _i = 0; _i < count; _i = _i + 1 {
    s = idf_next_seed(s)
    let idx = s.abs() % pool_len
    out = out + pool[idx]
  }
  out
}

///|
fn idf_apply_random_edit(
  source : String,
  seed : Int,
  allow_invalid : Bool,
) -> (String, @core.Edit, Int) {
  let len = source.length()
  let mut s = idf_next_seed(seed)
  let op = s.abs() % 3 // 0 insert, 1 delete, 2 replace
  let frag = idf_make_fragment(s, allow_invalid)
  s = idf_next_seed(s)
  if op == 0 || len == 0 {
    // Insert
    let start_raw = s.abs() % (len + 1)
    let start = idf_clamp(start_raw, len)
    let left = idf_slice_string(source, 0, start)
    let right = idf_slice_string(source, start, len)
    match (left, right) {
      (Some(l), Some(r)) => {
        let new_source = l + frag + r
        let edit = @core.Edit::insert(start, frag.length())
        (new_source, edit, s)
      }
      _ => (source, @core.Edit::insert(0, 0), s)
    }
  } else {
    let start_raw = s.abs() % (len + 1)
    s = idf_next_seed(s)
    let end_raw = s.abs() % (len + 1)
    let start0 = idf_clamp(start_raw, len)
    let end0 = idf_clamp(end_raw, len)
    let from = if start0 <= end0 { start0 } else { end0 }
    let to = if start0 <= end0 { end0 } else { start0 }
    let left = idf_slice_string(source, 0, from)
    let right = idf_slice_string(source, to, len)
    match (left, right) {
      (Some(l), Some(r)) =>
        if op == 1 {
          // Delete
          let new_source = l + r
          let edit = @core.Edit::delete(from, to)
          (new_source, edit, s)
        } else {
          // Replace
          let new_source = l + frag + r
          let edit = @core.Edit::replace(from, to, from + frag.length())
          (new_source, edit, s)
        }
      _ => (source, @core.Edit::insert(0, 0), s)
    }
  }
}

///|
fn idf_assert_incremental_matches_full(
  incremental : @seam.SyntaxNode,
  full : @ast.Term,
  context : String,
) -> Unit {
  let incremental_str = @ast.print_term(syntax_node_to_term(incremental))
  let full_str = @ast.print_term(full)
  if incremental_str != full_str {
    abort(
      "Differential mismatch (" +
      context +
      "): incremental=" +
      incremental_str +
      ", full=" +
      full_str,
    )
  }
}

///|
test "differential-fast: deterministic random edit sequences" {
  // Fast PR check target: modest amount of deterministic fuzz.
  let mut checked_cases = 0
  for case_i = 0; case_i < 30; case_i = case_i + 1 {
    let mut seed = 17 + case_i * 97
    let mut source = idf_make_source(seed, false)
    let parser = @loom.new_imperative_parser(source, lambda_grammar)
    let _ = parser.parse()
    for edit_i = 0; edit_i < 8; edit_i = edit_i + 1 {
      let (new_source, edit, next_seed) = idf_apply_random_edit(
        source, seed, false,
      )
      let incremental = parser.edit(edit, new_source)
      let (cst, errors) = parse_cst_recover(new_source) catch {
        _ => {
          source = new_source
          seed = next_seed
          continue
        }
      }
      // Phase 4 correctness today is strongest on well-formed inputs.
      if errors.length() == 0 {
        let full = syntax_node_to_term(@seam.SyntaxNode::from_cst(cst))
        idf_assert_incremental_matches_full(
          incremental,
          full,
          "case=\{case_i}, edit=\{edit_i}, source=\{new_source}",
        )
        checked_cases += 1
      }
      source = new_source
      seed = next_seed
    }
  }
  // Guard against a vacuous pass if generators drift toward malformed strings.
  assert_true(checked_cases > 0)
}

///|
test "differential-fast: malformed input sequences terminate" {
  // Includes invalid characters to exercise tokenization-error paths.
  for case_i = 0; case_i < 20; case_i = case_i + 1 {
    let mut seed = 43 + case_i * 131
    let mut source = idf_make_source(seed, true)
    let parser = @loom.new_imperative_parser(source, lambda_grammar)
    let _ = parser.parse()
    for edit_i = 0; edit_i < 8; edit_i = edit_i + 1 {
      let (new_source, edit, next_seed) = idf_apply_random_edit(
        source, seed, true,
      )
      let incremental = parser.edit(edit, new_source)
      // Ignore result — just verify both paths terminate without panic.
      try {
        let _ = parse_cst_recover(new_source)
      } catch {
        _ => ()
      }
      assert_true(incremental.start() >= 0)
      source = new_source
      seed = next_seed
    }

    // After malformed churn, parser should still recover on valid input.
    let repair = "x + 1"
    let repair_edit = @core.Edit::replace(0, source.length(), repair.length())
    let repaired = parser.edit(repair_edit, repair)
    let full_repaired = parse(repair) catch {
      _ => abort("parse failed on repair")
    }
    idf_assert_incremental_matches_full(
      repaired,
      full_repaired,
      "repair case=\{case_i}",
    )
  }
}

///|
test "differential-long: larger deterministic random edit sequences" {
  // Longer local/nightly target. Keep deterministic for reproducibility.
  let mut checked_cases = 0
  for case_i = 0; case_i < 80; case_i = case_i + 1 {
    let mut seed = 101 + case_i * 193
    let mut source = idf_make_source(seed, false)
    let parser = @loom.new_imperative_parser(source, lambda_grammar)
    let _ = parser.parse()
    for edit_i = 0; edit_i < 16; edit_i = edit_i + 1 {
      let (new_source, edit, next_seed) = idf_apply_random_edit(
        source, seed, false,
      )
      let incremental = parser.edit(edit, new_source)
      let (cst, errors) = parse_cst_recover(new_source) catch {
        _ => {
          source = new_source
          seed = next_seed
          continue
        }
      }
      if errors.length() == 0 {
        let full = syntax_node_to_term(@seam.SyntaxNode::from_cst(cst))
        idf_assert_incremental_matches_full(
          incremental,
          full,
          "long case=\{case_i}, edit=\{edit_i}",
        )
        checked_cases += 1
      }
      source = new_source
      seed = next_seed
    }
  }
  assert_true(checked_cases > 0)
}
