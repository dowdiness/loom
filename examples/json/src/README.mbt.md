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

## Editor role spans

`project_json_roles` is the pure CST-to-role projection. Role spans describe the
current recovered syntax. Parser diagnostics remain available separately from
`parser.diagnostics()`; syntax highlighting does not use last-good semantic
retention.

`JsonRoleSpan` keeps the typed local role enum and UTF-16 source offsets. This
package does not expose editor-neutral export adapters yet; downstream editor
code can map `JsonRole` values after the projection shape is proven.

```mbt check
///|
test "quick start: parser-backed JSON role spans" {
  let parser = @loom.new_syntax_parser(
    "{\"x\": 1}",
    json_grammar.to_syntax_grammar(),
  )
  let roles = project_json_roles(parser.syntax_tree().read_or_abort())
  inspect(roles.length() > 0, content="true")
  assert_true(roles[0].role() == Punctuation)
  inspect(parser.diagnostics().read_or_abort().is_empty(), content="true")
}
```

## Running

```bash
cd examples/json
moon test                    # parser, lexer, incremental, error recovery, block reparse
                             # — includes doctested Quick Start from this README
moon bench --release         # benchmarks
```

## Spec compliance tests

`src/json_testsuite_generated_wbtest.mbt` embeds the pinned
[`nst/JSONTestSuite`](https://github.com/nst/JSONTestSuite) `test_parsing`
fixtures so CI stays hermetic. The suite is the practical spec-compliance gate
for the strict parser API:

- `y_*.json` fixtures must be accepted by `parse(...)`.
- `n_*.json` fixtures must be rejected by `parse(...)`.
- `i_*.json` fixtures are implementation-defined by JSONTestSuite; they are
  listed in the generated file but not asserted.
- non-UTF-8 fixtures are outside this parser's current public API boundary
  because `parse(...)` accepts MoonBit `String`, not raw `Bytes`.

This supports the precise claim that strict `parse(...)` passes the pinned
JSONTestSuite required cases representable as MoonBit `String`. It is not a
formal proof of RFC 8259/JSON.org compliance, and it does not cover raw byte
encoding validation.

Regenerate the embedded fixtures after intentionally updating the upstream
revision in `tools/update_json_conformance_tests.py`:

```bash
python3 tools/update_json_conformance_tests.py
# NEW_MOON_MOD=0 keeps MoonBit on this repo's module-state cache mode
# for incremental rebuilds with local workspace dependencies.
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon fmt
moon test src/json_testsuite_generated_wbtest.mbt
```

## Learn More

- [`@loom` Quick Start](../../loom/README.md#quick-start) — consumer-side
  flow including `apply_edit`
- [Architecture overview](../../docs/architecture/overview.md) — layer
  diagram and design principles
- [`examples/lambda`](../lambda/) — the other reference grammar
