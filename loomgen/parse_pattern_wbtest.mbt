///|
/// Whitebox tests for the #529 allowlist pattern parser.
///
/// These tests intentionally precede the parser implementation. They define the
/// accepted MoonBit `re` subset and the fail-closed boundaries.
fn format_pattern_error(error : PatternError) -> String {
  match error {
    Malformed(at, reason) => "Malformed(" + at.to_string() + "): " + reason
    Unsupported(at, reason) => "Unsupported(" + at.to_string() + "): " + reason
  }
}

///|
fn repeat_bounds_max(bounds : RepeatBounds) -> Int? {
  match bounds {
    Exact(max) => Some(max.to_int())
    AtLeast(_) => None
    Range(bounds) => Some(bounds.max.to_int())
  }
}

///|
fn expect_pattern_ok(pattern : String) -> Unit {
  match parse_pattern(pattern) {
    Ok(_) => ()
    Err(error) =>
      abort(
        "expected pattern to parse: " +
        pattern +
        "; got " +
        format_pattern_error(error),
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
      abort(
        "expected nullable test pattern to parse: " +
        format_pattern_error(error),
      )
  }
}

///|
enum ExpectedBoundShape {
  ExactShape
  AtLeastShape
  RangeShape
}

///|
fn expect_counted_bounds(
  pattern : String,
  expected_shape : ExpectedBoundShape,
  expected_min : Int,
  expected_max : Int?,
) -> Unit {
  match parse_pattern(pattern) {
    Ok(Quantified(_, { kind: Counted(bounds) })) => {
      let shape_ok = match expected_shape {
        ExactShape => bounds is Exact(_)
        AtLeastShape => bounds is AtLeast(_)
        RangeShape => bounds is Range(_)
      }
      if !shape_ok ||
        bounds.min() != expected_min ||
        repeat_bounds_max(bounds) != expected_max {
        abort("unexpected counted bounds: " + pattern)
      }
    }
    Ok(_) => abort("expected counted quantifier: " + pattern)
    Err(error) =>
      abort("expected counted pattern: " + format_pattern_error(error))
  }
}

///|
test "quantifier AST preserves bound values and shapes" {
  expect_counted_bounds("a{2}", ExactShape, 2, Some(2))
  expect_counted_bounds("a{2,}", AtLeastShape, 2, None)
  expect_counted_bounds("a{2,4}", RangeShape, 2, Some(4))
  expect_counted_bounds("a{1,256}", RangeShape, 1, Some(256))
  expect_counted_bounds("a{000256}", ExactShape, 256, Some(256))
}

///|
test "quantifier parser consumes lazy syntax before policy rejection" {
  let parser = PatternParser::PatternParser("a*?")
  let parsed = parser.parse_top()
  assert_true(parsed is Quantified(_, { kind: ZeroOrMore }))
  match parser.first_unsupported {
    Some(pos) => assert_true(pos == 2)
    None => fail("expected lazy quantifier rejection")
  }
}

///|
test "repeat bound constructors reject invalid semantic values" {
  assert_true(checked_count(257) is None)
  assert_true(checked_count(256) is Some(_))
  assert_true(RepeatBounds::exact(257) is None)
  assert_true(RepeatBounds::at_least(-1) is None)
  assert_true(RepeatBounds::range(4, 2) is None)
  match RepeatBounds::range(1, 256) {
    Some(bounds) => assert_true(repeat_bounds_max(bounds) == Some(256))
    None => fail("expected max boundary range")
  }
}

///|
test "pattern parser accepts atoms and greedy quantifiers" {
  for
    pattern in [
      "a", "\\.", "\\x41", "\\t", "\\r", "\\n", "a\"b", "^a$", "(ab)+", "a*", "a+",
      "a?b", "a{2}", "a{2,4}", "a{2,}", "a{0,3}", "a{0}", "[a-z]", "[a|b]", "[a\\-z]",
      "[^a]",
    ] {
    expect_pattern_ok(pattern)
  }
}

///|
test "pattern parser rejects reversed and oversized counted quantifiers" {
  for
    pattern in [
      "a{4,2}", "a{257}", "a{1,257}", "a{,}", "a{,2}", "a{999999999999999999999999999999999999999999}",
      "a{1,999999999999999999999999999999999999999999}",
    ] {
    expect_pattern_err(pattern)
  }
  expect_pattern_ok("a{0004,0004}")
  expect_pattern_ok("a{0000,0004}")
}

///|
test "counted quantifier recovery consumes malformed bodies" {
  for
    pattern in [
      "a{,}b", "a{,2}b", "a{2,x}b", "a{2,4x}b", "a{4,2}b", "a{257}b", "a{2", "a{2,4",
      "a{999999999999999999999999999999999999999999}b",
    ] {
    let parser = PatternParser::PatternParser(pattern)
    let _ = parser.parse_top()
    assert_true(parser.pos == parser.length)
  }
}

///|
test "native re accepts the counted quantifier limit" {
  let view = "a"
  let _rest = ""
  let _ = view =~ (re"^(?:a{256})", after=_rest)
}

///|
test "pattern parser rejects lazy quantifiers" {
  expect_unsupported("a*?", 2)
  expect_unsupported("a+?", 2)
  expect_unsupported("a??", 2)
  expect_unsupported("a{1,3}?", 6)
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
