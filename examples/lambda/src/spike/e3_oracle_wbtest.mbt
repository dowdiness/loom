///|
/// E3 SECOND-GRAMMAR PROBE
///
/// Goal: demonstrate that the extended IR (Seq + RepeatWhile + Choice +
/// Emit + Expect + PrattBinary + PrattApp) generalises to a grammar whose
/// structure was determined externally — not reverse-engineered to fit the
/// combinators.
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
///   Source   → Value
///   Value    → Integer | Identifier | Hole | Array | Object
///   Array    → '(' (Value (',' Value)*)? ')'
///   Object   → '{' (Member (',' Member)*)? '}'
///   Member   → Identifier '=' Value
///
/// GrammarIr field mapping:
///   source     = e3_source
///   definition = e3_value
///   expression = e3_array
///   binary     = e3_object
///   application = e3_member
///   atom, param_list = Empty (unused)
///
/// E1 measurement: 5/5 rules declarative (Source=Ref, Value=Choice,
///   Array=Seq+RepeatWhile, Object=Seq+RepeatWhile, Member=Seq). No escape
///   hatches. This proves the combinators generalise beyond lambda's grammar.

///|
fn e3_grammar_ir() -> GrammarIr {
  GrammarIr::{
    // Source: the whole input is a single JSON value; trailing non-trivia
    // tokens are consumed into an error node.
    source: Expr::Seq([
      Expr::Ref(RuleId::Definition),
      Expr::Choice([
        Alt::{ starts: t => t == @token.EOF, body: Expr::Empty },
        Alt::{
          starts: _t => true,
          body: Expr::ErrorUntil(
            t => t == @token.EOF,
            "unexpected tokens after JSON value",
          ),
        },
      ]),
    ]),
    // Value: JSON value dispatch.
    definition: Expr::Choice([
      Alt::{
        starts: t => t == @token.Integer,
        body: Expr::Node(
          @syntax.IntLiteral,
          Expr::Emit(@token.Integer, @syntax.IntToken),
        ),
      },
      Alt::{
        starts: t => t == @token.Identifier,
        body: Expr::Node(
          @syntax.VarRef,
          Expr::Emit(@token.Identifier, @syntax.IdentToken),
        ),
      },
      Alt::{
        starts: t => t == @token.Hole,
        body: Expr::Node(
          @syntax.HoleLiteral,
          Expr::Emit(@token.Hole, @syntax.HoleToken),
        ),
      },
      Alt::{
        starts: t => t == @token.LeftParen,
        body: Expr::Ref(RuleId::Expression),
      },
      Alt::{
        starts: t => t == @token.LBrace,
        body: Expr::Ref(RuleId::Binary),
      },
      Alt::{
        starts: _t => true,
        body: Expr::ErrorUntil(
          spike_is_sync_point,
          "Unexpected JSON token",
        ),
      },
    ]),
    // Array: '(' (Value (',' Value)*)? ')'
    expression: Expr::Node(
      @syntax.ParenExpr,
      Expr::Seq([
        Expr::Emit(@token.LeftParen, @syntax.LeftParenToken),
        Expr::Choice([
          // empty array: next token is the closing ')'
          Alt::{ starts: t => t == @token.RightParen, body: Expr::Empty },
          // non-empty: first element then comma-separated rest
          Alt::{
            starts: _t => true,
            body: Expr::Seq([
              Expr::Ref(RuleId::Definition),
              Expr::RepeatWhile(
                t => t == @token.Comma,
                Expr::Seq([
                  Expr::Emit(@token.Comma, @syntax.CommaToken),
                  Expr::Ref(RuleId::Definition),
                ]),
              ),
            ]),
          },
        ]),
        Expr::Expect(@token.RightParen, @syntax.RightParenToken, "expected )"),
      ]),
    ),
    // Object: '{' (Member (',' Member)*)? '}'
    binary: Expr::Node(
      @syntax.BlockExpr,
      Expr::Seq([
        Expr::Emit(@token.LBrace, @syntax.LBraceToken),
        Expr::Choice([
          // empty object: next token is the closing '}'
          Alt::{ starts: t => t == @token.RBrace, body: Expr::Empty },
          // non-empty: first member then comma-separated rest
          Alt::{
            starts: _t => true,
            body: Expr::Seq([
              Expr::Ref(RuleId::Application),
              Expr::RepeatWhile(
                t => t == @token.Comma,
                Expr::Seq([
                  Expr::Emit(@token.Comma, @syntax.CommaToken),
                  Expr::Ref(RuleId::Application),
                ]),
              ),
            ]),
          },
        ]),
        Expr::Expect(@token.RBrace, @syntax.RBraceToken, "expected }"),
      ]),
    ),
    // Member: Identifier '=' Value
    application: Expr::Node(
      @syntax.LetDef,
      Expr::Seq([
        Expr::Emit(@token.Identifier, @syntax.IdentToken),
        Expr::Expect(@token.Eq, @syntax.EqToken, "expected ="),
        Expr::Ref(RuleId::Definition),
      ]),
    ),
    atom: Expr::Empty,
    param_list: Expr::Empty,
  }
}

///|
fn build_e3_grammar() -> @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] {
  let spec = @core.LanguageSpec::new(
    @syntax.WhitespaceToken,
    @syntax.ErrorToken,
    @syntax.SourceFile,
    @token.EOF,
    parse_root=interpret(e3_grammar_ir()),
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
    e3_check_step(
      parser,
      grammar,
      @core.Edit::new(1, 4, 0),
      "(foo, 3)",
    ),
    content="true",
  )
  // Edit 3: insert ", 99" (4 chars) before ')' at offset 7 → "(foo, 3, 99)".
  inspect(
    e3_check_step(
      parser,
      grammar,
      @core.Edit::new(7, 0, 4),
      "(foo, 3, 99)",
    ),
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
    e3_check_step(
      parser,
      grammar,
      @core.Edit::new(7, 0, 7),
      "{x = 42, y = 0}",
    ),
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
/// E3 probe: trailing tokens after a JSON value are rejected and D1 holds.
test "e3: trailing token rejected — D1 parity" {
  let grammar = build_e3_grammar()
  let initial = "(1)"
  let parser = @loom.new_syntax_parser(initial, grammar)
  // Append " 2" after the array: trailing Integer token should produce a
  // diagnostic; both incremental and fresh parse must agree (D1).
  inspect(
    e3_check_step(
      parser,
      grammar,
      @core.Edit::new(3, 0, 2),
      "(1) 2",
    ),
    content="true",
  )
}
