# `dowdiness/json`

JSON parser example for [`dowdiness/loom`](../../loom/).

Demonstrates the full `@loom.Grammar::new` surface — step-based prefix
lexer, block reparse spec, and error tokens — on a small, familiar
language.

## Public API

```mbt nocheck
// ── Grammar ───────────────────────────────────────────────────────────────────

pub let json_grammar : @loom.Grammar[Token, SyntaxKind, JsonValue]
pub let json_block_reparse_spec : @core.BlockReparseSpec[Token, SyntaxKind]

// ── High-level parsing ────────────────────────────────────────────────────────

pub fn parse(String) -> JsonValue raise                                   // strict: raises on any diagnostic
pub fn parse_json(String) -> (JsonValue, @core.DiagnosticSet)  // returns diagnostics
  raise @core.LexError
pub fn parse_cst(String) -> (@seam.CstNode, @core.DiagnosticSet)
  raise @core.LexError

// ── CST → AST ─────────────────────────────────────────────────────────────────

pub fn json_fold_node(@seam.SyntaxNode, (@seam.SyntaxNode) -> JsonValue) -> JsonValue
pub fn syntax_node_to_json(@seam.SyntaxNode) -> JsonValue

// ── CST → editor roles ────────────────────────────────────────────────────────

pub(all) enum JsonRole {
  PropertyKey
  StringValue
  NumberLiteral
  BooleanLiteral
  NullLiteral
  Punctuation
  Error
}

pub struct JsonRoleSpan { /* private fields */ }
pub fn JsonRoleSpan::JsonRoleSpan(
  role~ : JsonRole,
  start~ : Int,
  end~ : Int,
) -> JsonRoleSpan
pub fn JsonRoleSpan::role(JsonRoleSpan) -> JsonRole
pub fn JsonRoleSpan::start(JsonRoleSpan) -> Int
pub fn JsonRoleSpan::end(JsonRoleSpan) -> Int

pub fn project_json_roles(@seam.SyntaxNode) -> Array[JsonRoleSpan]

// ── Lexing ────────────────────────────────────────────────────────────────────

pub fn tokenize(String) -> Array[@core.TokenInfo[Token]] raise @core.LexError
pub fn json_step_lexer(String, Int) -> @core.LexStep[Token]

// ── Errors ────────────────────────────────────────────────────────────────────

pub suberror ParseError { ParseError(String) }
```

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

## Grammar

`json_grammar` is the single integration surface. Pass it to
[`@loom`](../../loom/) factories:

```mbt check
///|
test "quick start: reactive parser on a JSON object" {
  let parser = @loom.new_parser("{\"x\": 1}", json_grammar)
  let value : JsonValue = parser.ast().read_or_abort()
  inspect(
    value,
    content=(
      #|Object([("x", Number(1))])
    ),
  )
}

///|
test "quick start: set_source re-runs the reactive graph" {
  let parser = @loom.new_parser("[1]", json_grammar)
  parser.set_source("[2, 3]")
  inspect(
    parser.ast().read_or_abort(),
    content=(
      #|Array([Number(2), Number(3)])
    ),
  )
}

///|
test "quick start: strict parse raises nothing for valid JSON" {
  inspect(try! parse("null"), content="Null")
  inspect(try! parse("true"), content="Bool(true)")
  inspect(
    try! parse("42"),
    content=(
      #|Number(42)
    ),
  )
}
```

`json_grammar` is constructed with every optional field
`@loom.Grammar::new` accepts — a good template for grammars that need
incremental parsing, error recovery, and subtree block reparse:

```mbt nocheck
///|
pub let json_grammar : @loom.Grammar[Token, SyntaxKind, JsonValue] = @loom.Grammar::new(
  spec=json_spec,
  lex~,
  fold_node=json_fold_node,
  incremental_relex_enabled=false,
  block_reparse_spec=Some(json_block_reparse_spec),
)
```

`lex` makes `LexStep::Invalid` and `LexStep::Incomplete` recoverable instead
of fatal. It preserves messages in emitted `Error(message)` tokens while
`TokenBuffer` records the same messages as structured lexer diagnostics.
Strict `tokenize` remains available for tests and batch consumers that want
fail-fast lexing.

## `JsonValue`

```mbt nocheck
///|
pub(all) enum JsonValue {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[JsonValue])
  Object(Array[(String, JsonValue)])
  Error(String)
} derive(Eq, ToJson, Debug)
```

Also implements `Show`, `@pretty.Pretty`, `@pretty.Printable`,
`@pretty.Source`, `@core.Renderable`, and `@core.TreeNode` — useful when
wiring the example into a pretty-printer or a projection renderer.

`JsonValue::Error(String)` is returned for recovered CST error nodes. Lexer
problems remain visible as structured diagnostics on parser snapshots.

## Running

```bash
cd examples/json
moon test                    # parser, lexer, incremental, error recovery, block reparse
                             # — includes doctested Quick Start from this README
moon bench --release         # benchmarks
```

## Learn More

- [`@loom` Quick Start](../../loom/README.md#quick-start) — consumer-side
  flow including `apply_edit`
- [Architecture overview](../../docs/architecture/overview.md) — layer
  diagram and design principles
- [`examples/lambda`](../lambda/) — the other reference grammar
