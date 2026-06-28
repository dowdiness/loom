///|
/// Whitebox tests for the conservative nullable-pattern guard (#521).
/// Soundness: a genuinely nullable pattern must NEVER be classified `false`.

///|
test "is_nullable_pattern: nullable forms are rejected" {
  // empty pattern
  inspect(is_nullable_pattern(""), content="true")
  // every atom optional
  inspect(is_nullable_pattern("[a-z]*"), content="true")
  inspect(is_nullable_pattern("(foo)?"), content="true")
  inspect(is_nullable_pattern("a*b?"), content="true")
  // alternation with an empty branch
  inspect(is_nullable_pattern("a|"), content="true")
  inspect(is_nullable_pattern("(a|)"), content="true")
  // zero-width anchor
  inspect(is_nullable_pattern("$"), content="true")
  // bounded quantifier with zero lower bound
  inspect(is_nullable_pattern("x{0,3}"), content="true")
  // quantified group
  inspect(is_nullable_pattern("(ab)*"), content="true")
  // POSIX class quantified to optional — the inner `]` of `[:digit:]` must not
  // terminate the class early (regression: was accepted-but-nullable).
  inspect(is_nullable_pattern("[[:digit:]]*"), content="true")
  inspect(is_nullable_pattern("[[:alpha:]]?"), content="true")
}

///|
test "is_nullable_pattern: patterns with a required atom are accepted" {
  inspect(is_nullable_pattern("[0-9]+"), content="false")
  // identifier: required leading class, optional tail
  inspect(is_nullable_pattern("[a-zA-Z_][a-zA-Z0-9_\\-]*"), content="false")
  // whitespace run
  inspect(is_nullable_pattern("[ \t\r\n]+"), content="false")
  // literal keyword-shaped pattern
  inspect(is_nullable_pattern("let"), content="false")
  inspect(is_nullable_pattern("a+"), content="false")
  // number with optional fraction — leading [0-9]+ is required
  inspect(is_nullable_pattern("[0-9]+(\\.[0-9]+)?"), content="false")
  // bounded quantifier with non-zero lower bound
  inspect(is_nullable_pattern("x{2,4}"), content="false")
  // alternation where every branch has a required atom
  inspect(is_nullable_pattern("(ab)+cd"), content="false")
  // POSIX class with a required quantifier — the recommended replacement for
  // the deprecated `\d+`; must stay accepted after the class-scan fix.
  inspect(is_nullable_pattern("[[:digit:]]+"), content="false")
  inspect(is_nullable_pattern("[[:alpha:]][[:alnum:]]*"), content="false")
}
