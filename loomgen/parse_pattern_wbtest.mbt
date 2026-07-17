///|
/// Whitebox tests for the #529 allowlist pattern parser.
///
/// These tests intentionally precede the parser implementation. They define the
/// accepted MoonBit `re` subset and the fail-closed boundaries.

///|
fn expect_pattern_ok(pattern : String) -> Unit {
  match parse_pattern(pattern) {
    Ok(_) => ()
    Err(error) =>
      abort(
        "expected pattern to parse: " + pattern + "; got " + error.to_string(),
      )
  }
}

///|
fn expect_pattern_err(pattern : String) -> Unit {
  match parse_pattern(pattern) {
    Ok(_) => abort("expected pattern rejection: " + pattern)
    Err(_) => ()
  }
}

///|
fn expect_malformed(pattern : String, at : Int) -> Unit {
  match parse_pattern(pattern) {
    Err(PatternError::Malformed(found, _)) =>
      if found != at {
        abort(
          "expected malformed position " +
          at.to_string() +
          ", got " +
          found.to_string(),
        )
      }
    Err(PatternError::Unsupported(found, _)) =>
      abort(
        "expected malformed pattern error at " +
        at.to_string() +
        ", got unsupported at " +
        found.to_string(),
      )
    Ok(_) => abort("expected malformed pattern rejection: " + pattern)
  }
}

///|
fn expect_unsupported(pattern : String, at : Int) -> Unit {
  match parse_pattern(pattern) {
    Err(PatternError::Unsupported(found, _)) =>
      if found != at {
        abort(
          "expected unsupported position " +
          at.to_string() +
          ", got " +
          found.to_string(),
        )
      }
    Err(PatternError::Malformed(found, _)) =>
      abort(
        "expected unsupported pattern error at " +
        at.to_string() +
        ", got malformed at " +
        found.to_string(),
      )
    Ok(_) => abort("expected unsupported pattern rejection: " + pattern)
  }
}

///|
fn expect_nullable(pattern : String, expected : Bool) -> Unit {
  match parse_pattern(pattern) {
    Ok(parsed) =>
      if parsed.is_nullable() != expected {
        abort("unexpected nullability for " + pattern)
      }
    Err(error) =>
      abort("expected nullable test pattern to parse: " + error.to_string())
  }
}

///|
test "pattern parser accepts atoms and greedy quantifiers" {
  for
    pattern in [
      "a", "\\.", "\\x41", "^a$", "(ab)+", "a*", "a+", "a?b", "a*?", "a+?", "a??", "a{1,3}?",
      "a{2}", "a{2,4}", "a{2,}", "a{0,3}", "a{0}", "[a-z]", "[a|b]", "[a\\-z]", "[^a]",
    ] {
    expect_pattern_ok(pattern)
  }
}

///|
test "pattern parser accepts every supported POSIX class" {
  for
    name in [
      "alnum", "alpha", "ascii", "blank", "digit", "lower", "space", "upper", "word",
      "xdigit",
    ] {
    expect_pattern_ok("[[:" + name + ":]]")
  }
}

///|
test "pattern parser preserves false POSIX class content" {
  expect_pattern_ok("[a[:z]X")
}

///|
test "pattern parser rejects unsupported POSIX classes" {
  for
    pattern in [
      "[[:cntrl:]]", "[[:graph:]]", "[[:print:]]", "[[:punct:]]", "[[:not_a_real_class:]]",
      "[[:]]", "[[:digit]", "[[:alpha_1:]]",
    ] {
    expect_pattern_err(pattern)
  }
}

///|
test "pattern parser rejects unsupported constructs at every group depth" {
  for
    pattern in [
      "(?ab)", "(foo|bar)", "(foo|foobar)", "\\bfoo", "\\d+", "foo|bar",
    ] {
    expect_pattern_err(pattern)
  }
}

///|
test "pattern parser rejects malformed delimiters with precedence" {
  for pattern in ["a)b", "(a", "[abc", "a\\", "a{2", "(?:a", "(?a{2"] {
    expect_pattern_err(pattern)
  }
}

///|
test "pattern parser rejects invalid class boundaries" {
  for pattern in ["[]", "[]a]", "[a--z]", "[a-z-]", "[-abc]", "[abc-]"] {
    expect_pattern_err(pattern)
  }
}

///|
test "pattern parser rejects orphan and stacked quantifiers" {
  for pattern in ["*a", "+a", "?a", "{2}a", "a**", "a++", "a{2}{3}", "a{,3}"] {
    expect_pattern_err(pattern)
  }
}

///|
test "pattern parser preserves malformed-before-unsupported precedence" {
  expect_malformed("(?:a", 0)
  expect_malformed("(?a{2", 0)
}

///|
test "pattern parser reports nested false-POSIX unsupported construct" {
  expect_pattern_ok("[a[:z]X")
  expect_unsupported("[a[:z](?:x)", 6)
}

///|
test "pattern parser exposes IR nullability" {
  expect_nullable("", true)
  expect_nullable("^", true)
  expect_nullable("a*", true)
  expect_nullable("(foo)?", true)
  expect_nullable("a*b?", true)
  expect_nullable("x{0,3}", true)
  expect_nullable("a{0}", true)
  expect_nullable("a+", false)
  expect_nullable("[[:digit:]]+", false)
  expect_nullable("a{2}", false)
}

///|
test "pattern parser rejects unknown and malformed escapes" {
  for pattern in ["\\q", "\\x", "\\x1", "\\xZZ", "[\\d]", "[\\q]", "[\\x1]"] {
    expect_pattern_err(pattern)
  }
}

///|
test "pattern parser rejects malformed POSIX attempts after class content" {
  expect_pattern_err("[a[:alpha_1:]]")
  expect_pattern_err("[a[:not_a_real_class:]]")
  expect_pattern_err("[a[:digit]")
  expect_pattern_ok("[a[:z]X")
  expect_pattern_ok("[a[:z][[:digit:]]")
}
