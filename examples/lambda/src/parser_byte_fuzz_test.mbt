// Raw byte-stream fuzz tests for parser robustness.
//
// These tests verify the parser never panics or aborts on arbitrary input,
// including control characters, null bytes, high Unicode, and random binary data.
// Parse errors are expected and acceptable; crashes are not.
//
// Note: Characters in the surrogate range (0xD800–0xDFFF) are excluded because
// they produce invalid UTF-16 strings, which is a string encoding issue, not a
// parser robustness issue.

///|
/// Deterministic PRNG (same LCG as imperative_differential_fuzz_test.mbt).
fn bf_next_seed(seed : Int) -> Int {
  let a = 1103515245
  let c = 12345
  let m = 2147483647
  (seed * a + c) % m
}

///|
/// Generate a random codepoint avoiding the surrogate range (0xD800–0xDFFF).
fn bf_random_codepoint(seed : Int) -> (Int, Int) {
  let s = bf_next_seed(seed)
  // BMP minus surrogates: 0x0001–0xD7FF, 0xE000–0xFFFF = 63487 valid codepoints
  let range = 0xD7FF + (0xFFFF - 0xE000 + 1) // 63487
  let raw = s.abs() % range + 1
  let codepoint = if raw <= 0xD7FF { raw } else { raw - 0xD7FF + 0xE000 - 1 }
  (codepoint, s)
}

///|
/// Build a string of `len` characters drawn from the full BMP range
/// (excluding surrogates), including control chars, null bytes, and
/// non-ASCII codepoints.
fn bf_make_raw_string(seed : Int, len : Int) -> (String, Int) {
  let buf = StringBuilder::new()
  let mut s = seed
  for _i = 0; _i < len; _i = _i + 1 {
    let (codepoint, next_s) = bf_random_codepoint(s)
    s = next_s
    buf.write_char(codepoint.unsafe_to_char())
  }
  (buf.to_string(), s)
}

///|
/// Build a string mixing raw bytes with valid lambda syntax fragments.
/// This exercises paths where the lexer partially recognizes tokens
/// before hitting unexpected bytes.
fn bf_make_mixed_string(seed : Int, len : Int) -> (String, Int) {
  let fragments = [
    "x", "λ", "\\", ".", "(", ")", "+", "-", "if", "then", "else", "let", " = ",
    "\n", "\t", "\u{00}", "42", "  ",
  ]
  let buf = StringBuilder::new()
  let mut s = seed
  let frag_len = fragments.length()
  for _i = 0; _i < len; _i = _i + 1 {
    s = bf_next_seed(s)
    let choice = s.abs() % 3
    if choice == 0 {
      // Raw character from full BMP range (no surrogates)
      let (codepoint, next_s) = bf_random_codepoint(s)
      s = next_s
      buf.write_char(codepoint.unsafe_to_char())
    } else {
      // Valid/semi-valid fragment
      let idx = s.abs() % frag_len
      buf.write_string(fragments[idx])
    }
  }
  (buf.to_string(), s)
}

///|
/// Slice a string safely, returning empty string on invalid range.
fn bf_slice(s : String, start : Int, end : Int) -> String {
  if start < 0 || end < start || start > s.length() || end > s.length() {
    return ""
  }
  s[start:end].to_string()
}

///|
/// Property: parse() never aborts on arbitrary byte streams.
test "fuzz: parse handles raw byte streams" {
  for case_i = 0; case_i < 100; case_i = case_i + 1 {
    let seed = 7 + case_i * 71
    let len = seed.abs() % 50 + 1
    let (input, _) = bf_make_raw_string(seed, len)
    try {
      let _term = parse(input)
    } catch {
      _ => () // Parse error is expected, abort is not
    }
  }
}

///|
/// Property: parse_term() never aborts on arbitrary byte streams.
test "fuzz: parse_term handles raw byte streams" {
  for case_i = 0; case_i < 100; case_i = case_i + 1 {
    let seed = 13 + case_i * 83
    let len = seed.abs() % 50 + 1
    let (input, _) = bf_make_raw_string(seed, len)
    try {
      let (_term, _diags) = parse_term(input)
    } catch {
      _ => ()
    }
  }
}

///|
/// Property: ImperativeParser never aborts on arbitrary byte streams.
test "fuzz: imperative parser handles raw byte streams" {
  for case_i = 0; case_i < 50; case_i = case_i + 1 {
    let seed = 31 + case_i * 67
    let len = seed.abs() % 50 + 1
    let (input, _) = bf_make_raw_string(seed, len)
    let parser = @loom.new_imperative_parser(input, lambda_grammar)
    let _term = parser.parse()
  }
}

///|
/// Property: Incremental edits with raw bytes never abort.
/// Starts with random source, applies random raw-byte edits.
test "fuzz: incremental edit with raw byte streams" {
  for case_i = 0; case_i < 30; case_i = case_i + 1 {
    let mut seed = 41 + case_i * 59
    let len = seed.abs() % 30 + 5
    let (source, next_seed) = bf_make_raw_string(seed, len)
    seed = next_seed
    let parser = @loom.new_imperative_parser(source, lambda_grammar)
    let _ = parser.parse()
    let mut current_source = source
    for _edit_i = 0; _edit_i < 8; _edit_i = _edit_i + 1 {
      // Generate a random raw-byte fragment to insert/replace
      seed = bf_next_seed(seed)
      let frag_len = seed.abs() % 10 + 1
      let (frag, next_seed2) = bf_make_raw_string(seed, frag_len)
      seed = next_seed2
      let src_len = current_source.length()
      // Pick random edit position and type
      seed = bf_next_seed(seed)
      let op = seed.abs() % 3
      seed = bf_next_seed(seed)
      if op == 0 || src_len == 0 {
        // Insert
        let pos = if src_len == 0 { 0 } else { seed.abs() % src_len }
        let left = bf_slice(current_source, 0, pos)
        let right = bf_slice(current_source, pos, src_len)
        let new_source = left + frag + right
        let edit = @core.Edit::insert(pos, frag.length())
        let _ = parser.edit(edit, new_source)
        current_source = new_source
      } else if op == 1 && src_len > 0 {
        // Delete
        let start = seed.abs() % src_len
        seed = bf_next_seed(seed)
        let end = start + seed.abs() % (src_len - start + 1)
        let left = bf_slice(current_source, 0, start)
        let right = bf_slice(current_source, end, src_len)
        let new_source = left + right
        let edit = @core.Edit::delete(start, end)
        let _ = parser.edit(edit, new_source)
        current_source = new_source
      } else if src_len > 0 {
        // Replace
        let start = seed.abs() % src_len
        seed = bf_next_seed(seed)
        let end = start + seed.abs() % (src_len - start + 1)
        let left = bf_slice(current_source, 0, start)
        let right = bf_slice(current_source, end, src_len)
        let new_source = left + frag + right
        let edit = @core.Edit::replace(start, end, start + frag.length())
        let _ = parser.edit(edit, new_source)
        current_source = new_source
      }
    }
  }
}

///|
/// Property: Mixed valid syntax + raw bytes never abort.
/// This catches edge cases where the lexer partially tokenizes before
/// hitting unexpected bytes.
test "fuzz: parse handles mixed syntax and raw bytes" {
  for case_i = 0; case_i < 100; case_i = case_i + 1 {
    let seed = 19 + case_i * 97
    let len = seed.abs() % 40 + 5
    let (input, _) = bf_make_mixed_string(seed, len)
    try {
      let _term = parse(input)
    } catch {
      _ => ()
    }
  }
}

///|
/// Property: Strings with only control characters and null bytes.
test "fuzz: parse handles control characters" {
  for case_i = 0; case_i < 50; case_i = case_i + 1 {
    let buf = StringBuilder::new()
    let mut seed = 3 + case_i * 37
    let len = seed.abs() % 20 + 1
    for _i = 0; _i < len; _i = _i + 1 {
      seed = bf_next_seed(seed)
      // Control characters: 0x00–0x1F
      let c = seed.abs() % 0x20
      buf.write_char(c.unsafe_to_char())
    }
    let input = buf.to_string()
    try {
      let _term = parse(input)
    } catch {
      _ => ()
    }
  }
}

///|
/// Property: Strings with high Unicode codepoints (emoji, CJK, etc.).
test "fuzz: parse handles high unicode" {
  let inputs = [
    "λx.x", "let x = 42", "if x then y else z", "\\x. x + 1", "\u{FEFF}x + 1", "\u{200B}42\u{200B}",
    "x\u{0000}y", "\u{D7FF}\u{E000}", // Just below and above surrogate range
  ]
  for input in inputs {
    try {
      let _term = parse(input)
    } catch {
      _ => ()
    }
  }
}
