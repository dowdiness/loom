///|
/// E3 SECOND-GRAMMAR PROBE
///
/// Goal: demonstrate that the reified `@grammar` IR + the shared
/// `@grammar.interpret` interpreter generalise to a grammar whose structure was
/// determined externally — not reverse-engineered to fit the combinators. Unlike
/// lambda, JSON needs NO probe: it uses `@grammar.interpret` directly (no
/// `ManualNewlineAppExpr`, no cripple toggle), so it is the cross-language
/// evidence that the contract stands on its own.
///
/// Grammar specification source: JSON (RFC 8259).
/// Token mapping (lambda lexer, no new lexer needed):
///   Integer      → number literal
///   Identifier   → string-like value
///   Hole (_)     → null
///   LeftParen    → [ (array open)
///   RightParen   → ] (array close)
///   LBrace       → { (object open)
///   RBrace       → } (object close)
///   Comma        → ,
///   Eq           → : (key/value separator)
///
/// Rules (5 total, all encoded declaratively):
///   source → value
///   value  → Integer | Identifier | Hole | array | object
///   array  → '(' (value (',' value)*)? ')'
///   object → '{' (member (',' member)*)? '}'
///   member → Identifier '=' value

///|
/// JSON value-position sync points: the structural closers and separator that
/// bound a JSON value (`]` = RightParen, `}` = RBrace, `,` = Comma) plus EOF.
/// JSON carries no lambda keywords, so recovery must NOT sync on
/// `lambda_sync_points()` — this keeps the E3 demonstration grammar self-
/// consistent with the JSON token mapping above.
fn json_sync_points() -> @grammar.Pred[@token.Token] {
  @grammar.Pred::OneOf([
    @token.RightParen,
    @token.RBrace,
    @token.Comma,
    @token.EOF,
  ])
}

///|
fn e3_grammar_ir() -> @grammar.GrammarIr[@token.Token, @syntax.SyntaxKind] {
  let rules : Map[String, @grammar.Expr[@token.Token, @syntax.SyntaxKind]] = {
    // Source: the whole input is a single JSON value; trailing non-trivia
    // tokens are consumed into an error node.
    "source": @grammar.Expr::Seq([
      @grammar.Expr::Ref("value"),
      @grammar.Expr::Choice([
        @grammar.Alt::{
          starts: @grammar.Pred::IsToken(@token.EOF),
          body: @grammar.Expr::Empty,
        },
        @grammar.Alt::{
          starts: @grammar.Pred::Any,
          body: @grammar.Expr::ErrorUntil(
            @grammar.Pred::IsToken(@token.EOF),
            "unexpected tokens after JSON value",
          ),
        },
      ]),
    ]),
    // Value: JSON value dispatch.
    "value": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Integer),
        body: @grammar.Expr::Node(
          @syntax.IntLiteral,
          @grammar.Expr::Emit(@token.Integer, @syntax.IntToken),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Identifier),
        body: @grammar.Expr::Node(
          @syntax.VarRef,
          @grammar.Expr::Emit(@token.Identifier, @syntax.IdentToken),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.Hole),
        body: @grammar.Expr::Node(
          @syntax.HoleLiteral,
          @grammar.Expr::Emit(@token.Hole, @syntax.HoleToken),
        ),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.LeftParen),
        body: @grammar.Expr::Ref("array"),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken(@token.LBrace),
        body: @grammar.Expr::Ref("object"),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::Any,
        body: @grammar.Expr::ErrorUntil(
          json_sync_points(),
          "Unexpected JSON token",
        ),
      },
    ]),
    // Array: '(' (value (',' value)*)? ')'
    "array": @grammar.Expr::Node(
      @syntax.ParenExpr,
      @grammar.Expr::Seq([
        @grammar.Expr::Emit(@token.LeftParen, @syntax.LeftParenToken),
        @grammar.Expr::Choice([
          @grammar.Alt::{
            starts: @grammar.Pred::IsToken(@token.RightParen),
            body: @grammar.Expr::Empty,
          },
          @grammar.Alt::{
            starts: @grammar.Pred::Any,
            body: @grammar.Expr::Seq([
              @grammar.Expr::Ref("value"),
              @grammar.Expr::RepeatWhile(
                @grammar.Pred::IsToken(@token.Comma),
                @grammar.Expr::Seq([
                  @grammar.Expr::Emit(@token.Comma, @syntax.CommaToken),
                  @grammar.Expr::Ref("value"),
                ]),
              ),
            ]),
          },
        ]),
        @grammar.Expr::Expect(@token.RightParen, @syntax.RightParenToken),
      ]),
    ),
    // Object: '{' (member (',' member)*)? '}'
    "object": @grammar.Expr::Node(
      @syntax.BlockExpr,
      @grammar.Expr::Seq([
        @grammar.Expr::Emit(@token.LBrace, @syntax.LBraceToken),
        @grammar.Expr::Choice([
          @grammar.Alt::{
            starts: @grammar.Pred::IsToken(@token.RBrace),
            body: @grammar.Expr::Empty,
          },
          @grammar.Alt::{
            starts: @grammar.Pred::Any,
            body: @grammar.Expr::Seq([
              @grammar.Expr::Ref("member"),
              @grammar.Expr::RepeatWhile(
                @grammar.Pred::IsToken(@token.Comma),
                @grammar.Expr::Seq([
                  @grammar.Expr::Emit(@token.Comma, @syntax.CommaToken),
                  @grammar.Expr::Ref("member"),
                ]),
              ),
            ]),
          },
        ]),
        @grammar.Expr::Expect(@token.RBrace, @syntax.RBraceToken),
      ]),
    ),
    // Member: Identifier '=' value. Expect (not Emit) so a missing key emits a
    // diagnostic.
    "member": @grammar.Expr::Node(
      @syntax.LetDef,
      @grammar.Expr::Seq([
        @grammar.Expr::Expect(@token.Identifier, @syntax.IdentToken),
        @grammar.Expr::Expect(@token.Eq, @syntax.EqToken),
        @grammar.Expr::Ref("value"),
      ]),
    ),
  }
  @grammar.GrammarIr::GrammarIr(rules, root="source")
}

///|
fn build_e3_grammar() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] raise @grammar.GrammarCompileError {
  let parse_root = @grammar.interpret(e3_grammar_ir())
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root~,
    reuse_size_threshold=0,
  )
  @loom.SyntaxGrammar::new(
    spec~,
    lex=@lexer.lex,
    incremental_relex_enabled=false,
    block_reparse_spec=None,
  )
}

///|
/// Apply one edit to an E3 grammar parser and check D1:
/// incremental result == fresh parse of the new source.
fn e3_check_step(
  parser : @loom.SyntaxParser,
  grammar : @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind],
  edit : @core.Edit,
  after : String,
) -> Bool {
  parser.apply_edit(edit, after)
  let snap = parser.snapshot().read_or_abort()
  check_d1(after, snap, grammar)
}

///|
/// E3 probe: array literal with element edits.
/// Input is structurally JSON (nested arrays/objects), not lambda.
test "e3: array literal D1 parity across element edits" {
  let grammar = build_e3_grammar()
  let initial = "(1, foo, 3)"
  let parser = @loom.new_syntax_parser(initial, grammar)
  // Edit 1: change integer element 1→42.
  inspect(
    e3_check_step(parser, grammar, @core.Edit::new(1, 1, 2), "(42, foo, 3)"),
    content="true",
  )
  // Edit 2: remove "42, " (4 chars) at offset 1 → "(foo, 3)".
  inspect(
    e3_check_step(parser, grammar, @core.Edit::new(1, 4, 0), "(foo, 3)"),
    content="true",
  )
  // Edit 3: insert ", 99" (4 chars) before ')' at offset 7 → "(foo, 3, 99)".
  inspect(
    e3_check_step(parser, grammar, @core.Edit::new(7, 0, 4), "(foo, 3, 99)"),
    content="true",
  )
}

///|
/// E3 probe: object literal with member value edits.
test "e3: object literal D1 parity across member value edits" {
  let grammar = build_e3_grammar()
  let initial = "{x = 1}"
  let parser = @loom.new_syntax_parser(initial, grammar)
  // Edit 1: change value 1→42.
  inspect(
    e3_check_step(parser, grammar, @core.Edit::new(5, 1, 2), "{x = 42}"),
    content="true",
  )
  // Edit 2: add a second member.
  inspect(
    e3_check_step(parser, grammar, @core.Edit::new(7, 0, 7), "{x = 42, y = 0}"),
    content="true",
  )
}

///|
/// E3 probe: nested array-of-objects structure.
test "e3: nested array-of-objects D1 parity" {
  let grammar = build_e3_grammar()
  let initial = "({a = 1}, {b = 2})"
  let parser = @loom.new_syntax_parser(initial, grammar)
  // Edit: change inner value 1→99. '1' is at offset 6 in "({a = 1}, {b = 2})".
  inspect(
    e3_check_step(
      parser,
      grammar,
      @core.Edit::new(6, 1, 2),
      "({a = 99}, {b = 2})",
    ),
    content="true",
  )
}

///|
/// E3 probe: a missing member key emits EXACTLY ONE diagnostic (Expect not
/// Emit). `expect` emits the diagnostic + placeholder itself, so the interpreter
/// must not add a second — this is the positive control for the double-report
/// fix (P2). In `{= 1}` only the member-key `Expect(Identifier)` misses (it sees
/// `=`); the following `Expect(Eq)` then matches the still-unconsumed `=`, and
/// `1`/`}` match cleanly, so the missing-token path contributes one diagnostic.
/// D1 still holds: both incremental and fresh parse agree on the error tree.
test "e3: missing member key emits exactly one diagnostic — D1 parity" {
  let grammar = build_e3_grammar()
  let initial = "{= 1}"
  let parser = @loom.new_syntax_parser(initial, grammar)
  let snap = parser.snapshot().read_or_abort()
  // D1: incremental == fresh (check_d1 does tree_diff + diag equality).
  inspect(check_d1(initial, snap, grammar), content="true")
  // Exactly one diagnostic on the missing-token path (no double-report).
  inspect(snap.diagnostics.length() == 1, content="true")
}

///|
/// E3 probe: trailing tokens after a JSON value are rejected and D1 holds.
test "e3: trailing token rejected — D1 parity" {
  let grammar = build_e3_grammar()
  let initial = "(1)"
  let parser = @loom.new_syntax_parser(initial, grammar)
  // Append " 2" after the array: trailing Integer token should produce a
  // diagnostic; both incremental and fresh parse must agree (D1).
  inspect(
    e3_check_step(parser, grammar, @core.Edit::new(3, 0, 2), "(1) 2"),
    content="true",
  )
}
