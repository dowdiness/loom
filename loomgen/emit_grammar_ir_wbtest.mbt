///|
/// Whitebox tests for #522 GrammarIr generation from #loom.rule annotations.

///|
/// Parse a fixture/inline annotated source and return its (token, term) enums,
/// or abort. The GrammarIr emitter needs both: the token enum resolves rule
/// terminals to `@token` variants and their CST kinds, the term enum supplies
/// the rules and their node kinds.
fn enums_of(src : String) -> (EnumDecl, EnumDecl) {
  match parse_annotations(src) {
    Ok(a) =>
      match (a.token_enum, a.term_enum) {
        (Some(te), Some(tm)) => (te, tm)
        _ => abort("expected both a #loom.token and a #loom.term enum")
      }
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "emit_grammar_ir golden: smallest terminals-only Seq production" {
  let src = read_fixture("fixtures/rule_grammar_fixture.mbt")
  let golden = read_fixture("fixtures/rule_grammar_fixture.g.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "mini_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  assert_eq(generated, golden)
}

///|
/// Drives `lower_repetition`: the FIRST-set-dependent constructs. Asserts on the
/// semantic essentials (which `Expr` constructor, which `Pred`) rather than exact
/// formatting, so a correct lowering passes regardless of whitespace. `Item* Eof`
/// must gate the repeat on `FIRST(Item) = {A, B}` (a `OneOf`), and `(A | B)` must
/// become a two-alt `Choice` each gated on its single token.
test "emit_grammar_ir lowers Choice and Star with FIRST-set predicates" {
  let src = read_fixture("fixtures/rule_choice_fixture.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "t_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  // Items := Item* Eof  →  RepeatWhile gated on FIRST(Item) = {A, B}.
  inspect(generated.contains("@grammar.Expr::RepeatWhile("), content="true")
  inspect(
    generated.contains("@grammar.Pred::OneOf([@token.A, @token.B])"),
    content="true",
  )
  inspect(generated.contains("@grammar.Expr::Ref(\"Item\")"), content="true")
  // Item := (A | B)  →  Choice with two Alts, each gated on its single token.
  inspect(generated.contains("@grammar.Expr::Choice(["), content="true")
  inspect(
    generated.contains("@grammar.Pred::IsToken(@token.A)"),
    content="true",
  )
  inspect(
    generated.contains("@grammar.Pred::IsToken(@token.B)"),
    content="true",
  )
}

///|
/// The nullable-prefix correctness case. `Number := Sign? Digits` has a nullable
/// leading element, so `FIRST(Number)` must include `Digits`. The `(Number | Word)`
/// alternative's `starts` predicate must therefore be `OneOf([Sign, Digits])`; a
/// head-only FIRST would emit `IsToken(Sign)` and silently drop unsigned numbers.
test "emit_grammar_ir unions FIRST through a nullable prefix" {
  let src = read_fixture("fixtures/rule_nullable_prefix_fixture.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "n_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  // Number alternative gate unions through the nullable `Sign?`.
  inspect(
    generated.contains("@grammar.Pred::OneOf([@token.Sign, @token.Digits])"),
    content="true",
  )
  // The repeat gate over `(Number | Word)` covers all three FIRST tokens.
  inspect(
    generated.contains(
      "@grammar.Pred::OneOf([@token.Sign, @token.Digits, @token.Word])",
    ),
    content="true",
  )
}

///|
/// Run the full pipeline on an inline source and return the emitter's error, or
/// abort if it unexpectedly succeeds.
fn emit_err_of(src : String) -> String {
  let (token_enum, term_enum) = enums_of(src)
  match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(_) => abort("expected emit_grammar_ir to fail closed, but it succeeded")
    Err(m) => m
  }
}

///|
/// A left-recursive rule reached through a repeat gate must fail closed (its
/// FIRST set cannot be computed).
test "emit_grammar_ir rejects left recursion" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("Expr* Eof")
      #|  Start
      #|  #loom.node
      #|  #loom.rule("Expr A")
      #|  Expr
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("left-recursive"), content="true")
}

///|
/// Plain-position left recursion: `Expr := Expr A` sits in a `Seq`/`Node` body
/// that never feeds a Choice/Repeat gate, so `first_set` is never consulted on
/// it. The dedicated build-time leading-cycle walk must still reject it —
/// otherwise generation succeeds and `@grammar.interpret` infinite-loops.
test "emit_grammar_ir rejects plain-position left recursion" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("Expr Eof")
      #|  Start
      #|  #loom.node
      #|  #loom.rule("Expr A")
      #|  Expr
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("left-recursive"), content="true")
}

///|
/// A fragment in leading position is an opaque leaf, not a left-recursion edge —
/// `Foo := @bar` followed by recursion through `@bar` must NOT false-positive.
/// (Fragments are hand-authored and outside the analyzable subset.)
test "emit_grammar_ir does not false-positive a leading fragment" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("Foo Eof")
    #|  Start
    #|  #loom.node
    #|  #loom.rule("@bar A")
    #|  Foo
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => inspect(s.contains("@grammar.Expr::Ref(\"bar\")"), content="true")
    Err(m) => abort("leading fragment must not be rejected, got: " + m)
  }
}

///|
/// A symbol that is neither a token nor a term must fail closed.
test "emit_grammar_ir rejects an unknown symbol" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("Bogus Eof")
      #|  Start
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("unknown symbol"), content="true")
}

///|
/// Leaf ruling: a referenced #loom.leaf with no #loom.rule fails closed rather
/// than emitting an unresolvable `Ref`.
test "emit_grammar_ir rejects a referenced ruleless leaf" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("Leafy Eof")
      #|  Start
      #|  #loom.leaf
      #|  Leafy
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("has no #loom.rule"), content="true")
}

///|
/// A term enum with no #loom.root cannot name the GrammarIr root.
test "emit_grammar_ir rejects a missing root" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.node
      #|  #loom.rule("A Eof")
      #|  Foo
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("no #loom.root"), content="true")
}

///|
/// A malformed rule string (unbalanced parenthesis) fails closed at parse time.
test "emit_grammar_ir rejects an unbalanced rule string" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("(A Eof")
      #|  Start
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("unbalanced"), content="true")
}
