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
/// Differential oracle for #523: the `.loomgrammar` front-end and the `#loom.rule`
/// annotation front-end feed the SAME emitter, so the same grammar expressed each
/// way must emit byte-identical GrammarIr. Two independent input parsers converging
/// on the golden is real signal (unlike a fresh emitter-generated golden, which
/// would only pin the emitter to itself). The term enum still supplies roles, kinds
/// and the root; the file supplies the production body, overriding the annotation.
test "emit_grammar_ir: .loomgrammar path matches the annotation path byte-for-byte" {
  let src = read_fixture("fixtures/rule_grammar_fixture.mbt")
  let golden = read_fixture("fixtures/rule_grammar_fixture.g.mbt")
  let (token_enum, term_enum) = enums_of(src)
  // The same single production, written as a grammar file instead of an annotation.
  let gf = read_fixture("fixtures/parens.loomgrammar")
  let file_rules : Map[String, RuleAst] = Map([])
  match parse_grammar_file(gf) {
    Ok(prods) =>
      for p in prods {
        let (name, ast, _) = p
        file_rules.set(name, ast)
      }
    Err(m) => abort("grammar file parse failed: " + m)
  }
  let generated = match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "mini_grammar_ir",
      file_rules~,
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
    generated.contains("@grammar.Pred::OneOf(") &&
    generated.contains("@token.A") &&
    generated.contains("@token.B"),
    content="true",
  )
  inspect(generated.contains("@grammar.Expr::Ref("), content="true")
  // Item := (A | B)  →  Choice with two Alts, each gated on its single token.
  inspect(
    generated.contains("@grammar.Expr::Choice(") &&
    generated.contains("@token.A") &&
    generated.contains("@token.B"),
    content="true",
  )
  inspect(
    generated.contains("@grammar.Pred::IsToken(") &&
    generated.contains("@token.A"),
    content="true",
  )
  inspect(
    generated.contains("@grammar.Pred::IsToken(") &&
    generated.contains("@token.B"),
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
    generated.contains("@grammar.Pred::OneOf(") &&
    generated.contains("@token.Sign") &&
    generated.contains("@token.Digits"),
    content="true",
  )
  // The repeat gate over `(Number | Word)` covers all three FIRST tokens.
  inspect(
    generated.contains("@grammar.Pred::OneOf(") &&
    generated.contains("@token.Sign") &&
    generated.contains("@token.Digits") &&
    generated.contains("@token.Word"),
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
/// @fragment references now emit a mangled `Ref("__loom_frag__<name>")` that the
/// caller supplies via the `fragments~` map parameter. The mangled prefix avoids
/// collision with bare variant names in the `GrammarIr.rules` map.
test "emit_grammar_ir accepts @fragment references with mangled Ref" {
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
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for @fragment refs but got: " + m)
  }
  inspect(generated.contains("__loom_frag__bar"), content="true")
  inspect(generated.contains("fragments~"), content="true")
}

///|
/// A fragment in a FIRST-requiring position via a nullable prefix (e.g.
/// `A? @frag` as a Choice branch) must fail closed. The fragment's body is
/// opaque at emit time, so its FIRST set is unknown; gating on only the visible
/// prefix (`A`) would silently exclude tokens from the fragment body.
test "emit_grammar_ir: @fragment in leading position via nullable prefix fails" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.punct("b")
      #|  B
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("Pick Eof")
      #|  Start
      #|  #loom.node
      #|  #loom.rule("(A? @frag | B)")
      #|  Pick
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("FIRST-requiring position"), content="true")
}

///|
/// A REQUIRED alternation `(A | B)` must emit a trailing
/// `Alt{starts: Pred::Any, body: Fail(...)}`. The interpreter's `Choice`
/// silently no-ops when no alt's FIRST matches (interpreter.mbt), so without the
/// fallback a required alternation given an out-of-set token would consume
/// nothing and emit no diagnostic — silently accepting malformed input.
test "emit_grammar_ir gives a required alternation an Any error fallback" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.punct("b")
    #|  B
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("(A | B)")
    #|  Pick
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(generated.contains("@grammar.Pred::Any"), content="true")
  inspect(generated.contains("@grammar.Expr::Fail("), content="true")
}

///|
/// An optional `A?` must NOT get the Any/Fail fallback — "absent" is valid, not
/// an error. Locks the required-vs-optional distinction: both `?` and `|` lower
/// through `Choice`, but only the required form gets the error branch.
test "emit_grammar_ir does not add an error fallback to an optional" {
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
    #|  #loom.rule("A?")
    #|  Maybe
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(generated.contains("@grammar.Expr::Fail("), content="false")
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
  inspect(msg.contains("has no grammar rule"), content="true")
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

///|
/// The single #loom.root variant must itself carry a #loom.rule. Otherwise its
/// production is never emitted into the rules map, but `root=` still names it —
/// `@grammar.compile` then raises MissingRoot. Fail closed instead.
test "emit_grammar_ir rejects a #loom.root variant with no #loom.rule" {
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
      #|  Start
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("has no grammar rule"), content="true")
}

///|
/// Alternatives must have disjoint FIRST sets. `(A B | A C)` both begin with A,
/// so the interpreter's first-match Choice would always run branch 1 and branch 2
/// is dead. Reject the ambiguity rather than emit a silently-shadowing parser.
test "emit_grammar_ir rejects an ambiguous alternation (overlapping FIRST)" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.punct("b")
      #|  B
      #|  #loom.punct("c")
      #|  C
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("(A B | A C)")
      #|  Pick
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("ambiguous"), content="true")
  // The diagnostic must carry the remedy, not just the constraint — §6.1 of the
  // contract claims "the fix is local", so the message says what the fix is.
  inspect(msg.contains("factor the common prefix"), content="true")
}

///|
/// A bare `@fragment` alternative has an empty FIRST set (fragments are opaque
/// at emit time), so its `Choice` branch would gate on a predicate that matches
/// nothing — a dead branch. Reject rather than emit it.
test "emit_grammar_ir rejects an alternative with an empty FIRST set" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.punct("b")
      #|  B
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("(@frag | B)")
      #|  Pick
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("empty FIRST set"), content="true")
}

///|
/// A nullable alternative (`A?`) makes the alternation ε-derivable, but the
/// emitted required `Choice` appends an `Any → Fail` fallback — silently turning
/// "match empty" into a runtime parse error. The subset computes no FOLLOW sets,
/// so it cannot decide the ε case; fail closed at emit time instead.
test "emit_grammar_ir rejects a nullable alternative in a required alternation" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.punct("b")
      #|  B
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("(A? | B) Eof")
      #|  Pick
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("nullable alternative"), content="true")
}

///|
/// `--language` is spliced into a generated `pub let <lang>_grammar_ir`, so it
/// must be a valid identifier — guarding it keeps the emitter from producing
/// uncompilable output.
test "is_mbt_identifier accepts identifiers and rejects the rest" {
  inspect(is_mbt_identifier("loom"), content="true")
  inspect(is_mbt_identifier("my_lang2"), content="true")
  inspect(is_mbt_identifier("_x"), content="true")
  inspect(is_mbt_identifier(""), content="false")
  inspect(is_mbt_identifier("123"), content="false")
  inspect(is_mbt_identifier("my-lang"), content="false")
  inspect(is_mbt_identifier("a b"), content="false")
}

///|
/// Parse `fixtures/file_only_grammar.mbt` (roles-only term enum, NO annotations)
/// and the given grammar-file source into the (token, term, file_rules, file_lines)
/// the emitter needs. Aborts on a grammar-file parse error, since these tests supply
/// well-formed files and want emitter behavior, not parse behavior. `file_lines`
/// lets the reject tests assert the `line N:` prefix the emitter now attaches.
fn file_only_inputs(
  gf : String,
) -> (EnumDecl, EnumDecl, Map[String, RuleAst], Map[String, Int]) {
  let (token_enum, term_enum) = enums_of(
    read_fixture("fixtures/file_only_grammar.mbt"),
  )
  let file_rules : Map[String, RuleAst] = Map([])
  let file_lines : Map[String, Int] = Map([])
  match parse_grammar_file(gf) {
    Ok(prods) =>
      for p in prods {
        let (name, ast, line) = p
        file_rules.set(name, ast)
        file_lines.set(name, line)
      }
    Err(m) => abort("grammar file parse failed: " + m)
  }
  (token_enum, term_enum, file_rules, file_lines)
}

///|
/// The headline #523 path the differential test does NOT cover: a term enum with
/// roles but NO `#loom.rule` annotations, whose every production body comes solely
/// from the grammar file. This is what exercises emission gated on `ctx.rules`
/// (not `v.rule`): annotation rules are empty, so the root check and the emit loop
/// both key off the file-supplied map. It is also multi-production with a cross-rule
/// `Ref` (Pair -> Inner) and a root designated by `#loom.root` but bodied by the
/// file — none of which the single-production override fixture runs through emission.
test "emit_grammar_ir: file-only term enum (no annotations) emits multi-production output with a cross-Ref and file root" {
  let (token_enum, term_enum, file_rules, file_lines) = file_only_inputs(
    read_fixture("fixtures/file_only.loomgrammar"),
  )
  let generated = match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "fo_grammar_ir",
      file_rules~,
      file_lines~,
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed (file-only path): " + m)
  }
  // Assert the FULL emitted source against a committed golden (not boolean
  // `inspect(contains(...))` — a `moon test --update` would silently flip those
  // true→false and mask a regression). The golden pins every property this path
  // must have: both `Pair` and `Inner` Nodes, the cross-rule `Ref("Inner")`,
  // Inner's single `Expect(@token.Comma, ...)`, and `root="Pair"` taken from the
  // #loom.root variant but bodied entirely by the file.
  assert_eq(generated, read_fixture("fixtures/file_only.g.mbt"))
}

///|
/// A file production with an `@fragment` body now emits a mangled `Ref` that the
/// caller supplies via the `fragments~` map. The fragment reference routes through
/// the shared emission path, same as annotation fragments.
test "emit_grammar_ir: file production with @fragment body emits mangled Ref" {
  let (token_enum, term_enum, file_rules, file_lines) = file_only_inputs(
    "Pair = LParen Inner RParen\nInner = @custom_inner",
  )
  let generated = match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "fo_grammar_ir",
      file_rules~,
      file_lines~,
    ) {
    Ok(s) => s
    Err(m) =>
      abort("emit should succeed for @fragment file production but got: " + m)
  }
  inspect(generated.contains("__loom_frag__custom_inner"), content="true")
  inspect(generated.contains("fragments~"), content="true")
}

///|
/// A file production whose name is not a `#loom.term` variant must fail closed —
/// it has no role to supply a CST kind. `NotATerm` is absent from the term enum.
test "emit_grammar_ir: a file production naming a non-term symbol fails closed" {
  let (token_enum, term_enum, file_rules, file_lines) = file_only_inputs(
    "Pair = LParen Inner RParen\nInner = Comma\nNotATerm = Comma",
  )
  match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "fo_grammar_ir",
      file_rules~,
      file_lines~,
    ) {
    Ok(_) => abort("expected a non-term file production to fail closed")
    Err(m) => {
      inspect(
        m.contains(
          "grammar file production 'NotATerm' is not a #loom.term variant",
        ),
        content="true",
      )
      // `NotATerm` is on line 3 of the grammar file; the error points there.
      inspect(m.contains("line 3: "), content="true")
    }
  }
}

///|
/// Exercises the lowering-catch prefix site (the most complex one — it wraps any
/// `RuleLowerError` with the rule's file line). An ambiguous alternation
/// `Comma RParen | Comma LParen` (both alts begin with `Comma`) is detected during
/// lowering of `Pair`, so its error must carry `Pair`'s line (1).
test "emit_grammar_ir: a lowering error in a file rule carries the file line" {
  let (token_enum, term_enum, file_rules, file_lines) = file_only_inputs(
    "Pair = Comma RParen | Comma LParen",
  )
  match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "fo_grammar_ir",
      file_rules~,
      file_lines~,
    ) {
    Ok(_) => abort("expected an ambiguous file alternation to fail closed")
    Err(m) => {
      inspect(m.contains("ambiguous alternation"), content="true")
      inspect(m.contains("line 1: "), content="true")
    }
  }
}

///|
/// Migration path: a variant with a broken `#loom.rule` annotation that also has
/// a grammar-file production must succeed. Before the fix, `parse_rule_string`
/// would fire for the broken annotation and return early before the `file_rules`
/// overlay applied, making it impossible to migrate off a broken annotation by
/// moving it to the grammar file.
test "emit_grammar_ir: grammar-file rule overrides a broken #loom.rule annotation" {
  let src =
    #|#loom.token
    #|pub(all) enum MigrTok {
    #|  #loom.punct("(")
    #|  LParen
    #|  #loom.punct(")")
    #|  RParen
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq, Debug)
    #|
    #|#loom.term
    #|pub(all) enum MigrTerm {
    #|  #loom.root
    #|  #loom.rule("( A |")
    #|  Parens
    #|} derive(Eq, Debug)
  let (token_enum, term_enum) = enums_of(src)
  let file_rules : Map[String, RuleAst] = Map([])
  let file_lines : Map[String, Int] = Map([])
  match parse_grammar_file("Parens = LParen RParen") {
    Ok(prods) =>
      for p in prods {
        let (name, ast, line) = p
        file_rules.set(name, ast)
        file_lines.set(name, line)
      }
    Err(m) => abort("unexpected grammar file parse failure: " + m)
  }
  match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "migr_grammar_ir",
      file_rules~,
      file_lines~,
    ) {
    Ok(_) => ()
    Err(m) =>
      abort("grammar-file rule should override broken annotation but got: " + m)
  }
}

///|
/// #loom.rule is only meaningful on #loom.term variants. On a #loom.token variant
/// it would be silently dropped by build_lower_ctx, so reject it at parse time.
test "parse_annotations rejects #loom.rule on a token variant" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  #loom.rule("A B")
      #|  A
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
    ),
    "token variant",
  )
}

///|
/// Golden test for M16 #598 ~ (Emit), #599 ! (EmitOr), #600 @until (ErrorUntil).
test "emit_grammar_ir golden: ~ ! @until lower to Emit EmitOr ErrorUntil" {
  let src = read_fixture("fixtures/rule_emit_fixture.mbt")
  let golden = read_fixture("fixtures/rule_emit_fixture.g.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "emit_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  assert_eq(generated, golden)
}

///|
/// Golden test for #601 Pratt: `@prefix`, `@prec`, `@skip` lower to PrattApp /
/// PrattBinary without an outer `Node` wrapper.
test "emit_grammar_ir golden: Pratt lowers to PrattApp and PrattBinary" {
  let src = read_fixture("fixtures/pratt_grammar_fixture.mbt")
  let golden = read_fixture("fixtures/pratt_grammar_fixture.g.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "pratt_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  assert_eq(generated, golden)
}

///|
/// #523 + #601: Pratt grammar file path must match annotation path byte-for-byte.
test "emit_grammar_ir: pratt .loomgrammar matches annotation path" {
  let src = read_fixture("fixtures/pratt_grammar_fixture.mbt")
  let golden = read_fixture("fixtures/pratt_grammar_fixture.g.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let file_rules : Map[String, RuleAst] = Map([])
  match parse_grammar_file(read_fixture("fixtures/pratt.loomgrammar")) {
    Ok(prods) =>
      for p in prods {
        let (name, ast, _) = p
        file_rules.set(name, ast)
      }
    Err(m) => abort("grammar file parse failed: " + m)
  }
  let generated = match
    emit_grammar_ir(
      term_enum,
      token_enum,
      "@token",
      "@syntax",
      "@grammar",
      "pratt_grammar_ir",
      file_rules~,
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  assert_eq(generated, golden)
}

///|
/// Pratt `first_set` delegates through `@prefix`, so a `Ref` to a Pratt rule
/// inherits the prefix chain's FIRST tokens for upstream Choice / RepeatWhile.
test "emit_grammar_ir: Pratt FIRST propagates through Ref chain" {
  let src = read_fixture("fixtures/pratt_grammar_fixture.mbt")
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "pratt_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(generated.contains("@grammar.Expr::PrattApp("), content="true")
  inspect(
    generated.contains("@grammar.Pred::IsToken(") &&
    generated.contains("@token.Id"),
    content="true",
  )
  inspect(
    // PrattApp should be used for AppExpr, not Node (the FIRST propagates
    // through the Ref chain, so PrattApp starts at Atom's FIRST token).
    generated.contains("@grammar.Expr::PrattApp("),
    content="true",
  )
}

///|
test "emit_grammar_ir rejects Pratt self-reference via @prefix" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("+")
    #|  Plus
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq, Debug)
    #|
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("@prefix Expr @prec[Plus]")
    #|  Expr
    #|} derive(Eq, Debug)
  let (token_enum, term_enum) = enums_of(src)
  match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "bad_grammar_ir",
    ) {
    Ok(_) => abort("expected left-recursion rejection")
    Err(m) => inspect(m.contains("left-recursive rule 'Expr'"), content="true")
  }
}

///|
test "emit_grammar_ir rejects nullable Pratt prefix in analysis phase" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("i")
    #|  Id
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq, Debug)
    #|
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("@prefix NullableAtom")
    #|  App
    #|  #loom.node
    #|  #loom.rule("Id?")
    #|  NullableAtom
    #|} derive(Eq, Debug)
  let (token_enum, term_enum) = enums_of(src)
  match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "bad_grammar_ir",
    ) {
    Ok(_) => abort("expected nullable-prefix rejection")
    Err(m) =>
      inspect(
        m.contains("nullable @prefix rule 'NullableAtom'"),
        content="true",
      )
  }
}

///|
/// `@app` overrides the Pratt node kind on both PrattApp and PrattBinary.
test "emit_grammar_ir: @app overrides Pratt node kind" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("i")
    #|  Id
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq, Debug)
    #|
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("@prefix Atom @app BinaryExpr")
    #|  AppExpr
    #|  #loom.node
    #|  #loom.rule("Id")
    #|  Atom
    #|  #loom.node
    #|  BinaryExpr
    #|} derive(Eq, Debug)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", "app_grammar_ir",
    ) {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(
    generated.contains(
      "@grammar.Expr::PrattApp(\n        \"Atom\",\n        @syntax.BinaryExpr,",
    ),
    content="true",
  )
}

///|
test "emit_grammar_ir: @native(ident) lowers to Expr::Native" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.punct("b")
    #|  B
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("A @native(parse_tag) B Eof")
    #|  Start
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for @native but got: " + m)
  }
  inspect(generated.contains("Expr::Native"), content="true")
  inspect(generated.contains("parse_tag"), content="true")
}

///|
/// A `@native` in the final Choice position is treated as a catch-all: emitted
/// with `Pred::Any` (always-matching) instead of participating in FIRST-set
/// dispatch. The catch-all replaces the required Any→Fail fallback — it IS the
/// fallback, consuming whatever earlier branches did not match.
/// `(A | B | @native(fallback))` should have two `Pred::Any` alts:
/// one for the catch-all and NONE for an additional Fail.
test "emit_grammar_ir: @native in final Choice position is catch-all with Pred::Any" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.punct("b")
    #|  B
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("(A | B | @native(fallback))")
    #|  Pick
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for catch-all @native but got: " + m)
  }
  // The catch-all alt gets Pred::Any.
  inspect(generated.contains("@grammar.Pred::Any"), content="true")
  // The catch-all body is Expr::Native("fallback").
  inspect(
    generated.contains("Expr::Native") && generated.contains("fallback"),
    content="true",
  )
  // No required Fail fallback — the catch-all IS the fallback.
  inspect(generated.contains("@grammar.Expr::Fail("), content="false")
  // Each non-catch-all branch still has its FIRST-set predicate.
  inspect(generated.contains("@grammar.Pred::IsToken("), content="true")
}

///|
/// A `@native` in a non-last position of a Choice must fail closed — it would
/// shadow all following branches via its always-matching Pred::Any.
test "emit_grammar_ir: @native in non-final Choice position is rejected" {
  let msg = emit_err_of(
    (
      #|#loom.token
      #|pub(all) enum Tok {
      #|  #loom.punct("a")
      #|  A
      #|  #loom.punct("b")
      #|  B
      #|  #loom.eof
      #|  Eof
      #|} derive(Eq)
      #|#loom.term
      #|pub(all) enum T {
      #|  #loom.root
      #|  #loom.rule("(A | @native(fallback) | B)")
      #|  Pick
      #|} derive(Eq)
    ),
  )
  inspect(msg.contains("@native must be the final alternative in an alternation"), content="true")
}

///|
/// A `(A | @native(catch))` Choice with the catch-all as the second of two
/// branches: the non-catch-all branch gets its FIRST-set predicate, the
/// catch-all gets Pred::Any, and no additional Fail fallback is emitted.
test "emit_grammar_ir: @native catch-all as second of two Choice branches" {
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
    #|  #loom.rule("(A | @native(catch))")
    #|  Pick
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for 2-branch catch-all but got: " + m)
  }
  // The A branch has IsToken(A).
  inspect(
    generated.contains("@grammar.Pred::IsToken(") &&
    generated.contains("@token.A"),
    content="true",
  )
  // The catch-all branch has Pred::Any.
  inspect(generated.contains("@grammar.Pred::Any"), content="true")
  // The catch-all body is Expr::Native("catch").
  inspect(
    generated.contains("Expr::Native") && generated.contains("catch"),
    content="true",
  )
  // No required Fail fallback — the catch-all replaces it.
  inspect(generated.contains("@grammar.Expr::Fail("), content="false")
}

///|
test "emit_grammar_ir: @error_node(Kind, Token) lowers to Expr::ErrorNodeUntil" {
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
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("@error_node(ErrorNode, Eof)")
    #|  Source
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for @error_node but got: " + m)
  }
  inspect(generated.contains("@grammar.Expr::ErrorNodeUntil("), content="true")
  inspect(generated.contains("@grammar.Pred::IsToken("), content="true")
  inspect(generated.contains("@token.Eof"), content="true")
  inspect(generated.contains("@syntax.ErrorNode"), content="true")
}

///|
test "emit_grammar_ir: @error_node(Kind, A | B) lowers with Pred::OneOf" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct(",")
    #|  Comma
    #|  #loom.punct(";")
    #|  Semicolon
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("@error_node(ErrorNode, Comma | Semicolon)")
    #|  Source
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for @error_node but got: " + m)
  }
  inspect(generated.contains("Expr::ErrorNodeUntil("), content="true")
  inspect(generated.contains("Pred::OneOf"), content="true")
  inspect(generated.contains("@token.Comma"), content="true")
  inspect(generated.contains("@token.Semicolon"), content="true")
}

///|
test "emit_grammar_ir rejects @error_node with wrong kind name" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct(",")
    #|  Comma
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("@error_node(WrongKind, Eof)")
    #|  Source
    #|} derive(Eq)
  let msg = emit_err_of(src)
  inspect(msg.contains("not a #loom.errornode variant"), content="true")
}

///|
test "emit_grammar_ir rejects @error_node when term enum has no errornode" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct(",")
    #|  Comma
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.root
    #|  #loom.rule("@error_node(ErrorNode, Eof)")
    #|  Source
    #|} derive(Eq)
  let msg = emit_err_of(src)
  inspect(msg.contains("not a #loom.errornode variant"), content="true")
  inspect(msg.contains("no #loom.errornode variant"), content="true")
}

///|
test "emit_grammar_ir rejects @error_node with unknown token" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct(",")
    #|  Comma
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("@error_node(ErrorNode, UnknownToken)")
    #|  Source
    #|} derive(Eq)
  let msg = emit_err_of(src)
  inspect(msg.contains("not a #loom.token variant"), content="true")
}

///|
/// A `(A | @error_node(ErrorNode, B))` Choice with @error_node as the second
/// of two branches: @error_node is a catch-all, so it gets Pred::Any treatment
/// and replaces the required Fail fallback.
test "emit_grammar_ir: @error_node as catch-all in final Choice position" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.punct("b")
    #|  B
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("(A | @error_node(ErrorNode, B))")
    #|  Pick
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for @error_node catch-all but got: " + m)
  }
  // The @error_node alt gets Pred::Any (catch-all).
  inspect(generated.contains("@grammar.Pred::Any"), content="true")
  // The catch-all body is Expr::ErrorNodeUntil.
  inspect(
    generated.contains("Expr::ErrorNodeUntil") && generated.contains("@syntax.ErrorNode"),
    content="true",
  )
  // No required Fail fallback — the catch-all replaces it.
  inspect(generated.contains("@grammar.Expr::Fail("), content="false")
  // The non-catch-all branch still has its FIRST-set predicate.
  inspect(generated.contains("@grammar.Pred::IsToken("), content="true")
  inspect(generated.contains("@token.A"), content="true")
}

///|
test "emit_grammar_ir: @error_node in non-final Choice position is rejected" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.punct("b")
    #|  B
    #|  #loom.punct("c")
    #|  C
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("(A | @error_node(ErrorNode, B) | C)")
    #|  Pick
    #|} derive(Eq)
  let msg = emit_err_of(src)
  inspect(msg.contains("@error_node must be the final alternative"), content="true")
}

///|
/// A `(A | B | @error_node(ErrorNode, C))` Choice: at most one Pred::Any
/// (for the catch-all). No required Fail fallback — the catch-all replaces it.
test "emit_grammar_ir: @error_node catch-all as third of three Choice branches" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("a")
    #|  A
    #|  #loom.punct("b")
    #|  B
    #|  #loom.punct("c")
    #|  C
    #|  #loom.eof
    #|  Eof
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum T {
    #|  #loom.errornode
    #|  ErrorNode
    #|  #loom.root
    #|  #loom.rule("(A | B | @error_node(ErrorNode, C))")
    #|  Pick
    #|} derive(Eq)
  let (token_enum, term_enum) = enums_of(src)
  let generated = match
    emit_grammar_ir(term_enum, token_enum, "@token", "@syntax", "@grammar", "g") {
    Ok(s) => s
    Err(m) => abort("emit should succeed for @error_node catch-all but got: " + m)
  }
  // The @error_node alt gets Pred::Any (catch-all).
  inspect(generated.contains("@grammar.Pred::Any"), content="true")
  // The catch-all body is Expr::ErrorNodeUntil.
  inspect(
    generated.contains("Expr::ErrorNodeUntil") && generated.contains("@syntax.ErrorNode"),
    content="true",
  )
  // No required Fail fallback — the catch-all replaces it.
  inspect(generated.contains("@grammar.Expr::Fail("), content="false")
  // Non-catch-all branches have their FIRST-set predicates.
  inspect(generated.contains("@grammar.Pred::IsToken("), content="true")
  inspect(generated.contains("@token.A") && generated.contains("@token.B"), content="true")
}
