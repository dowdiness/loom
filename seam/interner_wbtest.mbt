///|
test "Interner: same (kind, text) returns same token" {
  let interner = Interner::new()
  let k = RawKind(1)
  let t1 = interner.intern_token(k, "x")
  let t2 = interner.intern_token(k, "x")
  inspect(t1 == t2, content="true")
}

///|
test "Interner: different text returns different tokens" {
  let interner = Interner::new()
  let k = RawKind(1)
  let a = interner.intern_token(k, "x")
  let b = interner.intern_token(k, "y")
  inspect(a == b, content="false")
}

///|
test "Interner: different kind returns different tokens" {
  let interner = Interner::new()
  let a = interner.intern_token(RawKind(1), "x")
  let b = interner.intern_token(RawKind(2), "x")
  inspect(a == b, content="false")
}

///|
test "Interner: size counts distinct pairs only" {
  let interner = Interner::new()
  let k = RawKind(1)
  let _ = interner.intern_token(k, "x")
  let _ = interner.intern_token(k, "x") // duplicate — no size increase
  let _ = interner.intern_token(k, "y")
  inspect(interner.size(), content="2")
}

///|
test "Interner: clear resets size to zero" {
  let interner = Interner::new()
  let _ = interner.intern_token(RawKind(1), "x")
  inspect(interner.size(), content="1")
  interner.clear()
  inspect(interner.size(), content="0")
}

///|
test "Interner: intern_token result matches CstToken::new structurally" {
  let interner = Interner::new()
  let k = RawKind(7)
  let text = "lambda"
  let interned = interner.intern_token(k, text)
  let direct = CstToken::CstToken(k, text)
  inspect(interned == direct, content="true")
}

///|
test "Interner: source-backed view is copied into canonical token" {
  let interner = Interner::new()
  let source = "alpha beta"
  let token = interner.intern_token(
    RawKind(7),
    source.view(start_offset=6, end_offset=10),
  )
  inspect(token.text(), content="beta")
  inspect(physical_equal(token.source(), source), content="false")
}

///|
test "Interner: intern_token works correctly after clear" {
  let interner = Interner::new()
  let k = RawKind(1)
  let _ = interner.intern_token(k, "x")
  interner.clear()
  let _ = interner.intern_token(k, "x")
  inspect(interner.size(), content="1")
}
