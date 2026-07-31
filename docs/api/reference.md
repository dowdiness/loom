# Public API Reference

Lambda calculus parser — user-facing API for tokenizing, parsing, pretty printing, and error handling.

## 1. Parsing Functions

### `parse`

```moonbit
pub fn parse(@core.SourceId, String) -> Term raise ParseError
```

Parses an identified source string directly into a `Term` AST. Raises
`ParseError` if tokenization fails or the input contains syntax errors. The
simplest entry point when only the semantic AST is needed.

### `parse_term`

```moonbit
pub fn parse_term(
  @core.SourceId,
  String,
) -> (Term, @core.DiagnosticSet) raise @core.LexError
```

Parses a multi-expression source file — a sequence of top-level `let` value declarations or `fn` definitions optionally followed by a final expression — and converts to `Term`. Function parameters lower to nested `Lam` terms. Returns both the term and any parse diagnostics (does not raise on parse errors). Use this for file-level input.

```
fn id(x) { x }
fn const(x, y) { x }
```

### `parse_cst`

```moonbit
pub fn parse_cst(
  @core.SourceId,
  String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError
```

Parses a string into an immutable `CstNode` tree — a lossless CST with
structural hashing — and returns its structured diagnostics. Parser recovery
produces error nodes instead of raising; lexical infrastructure failures may
still raise `LexError`. All whitespace is preserved as trivia nodes.

The `SourceId` passed to all parsing functions is caller-owned source identity.
Keep it stable across revisions of the same source and distinct across different
sources. It is not `DiagnosticSource`, which identifies the diagnostic
producer, and it must not be derived from text or diagnostic presentation.

Structured locations are carried by `DiagnosticLabel` values, not by a
source-less primary range. A label preserves its `Primary` or `Secondary`
`LabelStyle`, `SourceSpan`, and optional message. A `SourceSpan` combines a
`SourceId` with a validated half-open UTF-16 code-unit `TextRange`; one
diagnostic may therefore describe multiple sources. Diagnostic fields are
private, and collection accessors return defensive copies.

---

## 2. Tokenization

```moonbit
pub fn tokenize(String) -> Array[Token] raise @core.LexError
```

Converts an input string into an array of tokens. Raises `@core.LexError` if the input contains invalid characters.

**Example:**

```moonbit
let tokens = tokenize("(x) => x + 1")
// [LeftParen, Identifier, RightParen, FatArrow, Identifier, Plus, Integer, EOF]
```

---

## 3. Pretty Printing

### `print_term`

```moonbit
pub fn print_term(Term) -> String
```

Converts a `Term` AST back into a human-readable string representation. May add extra parentheses for unambiguous output.

**Example:**

```moonbit
let source_id = @loom.SourceId("pretty-print-document")
let ast = parse(source_id, "(x) => x + 1")
let output = print_term(ast)
// "(x) => (x + 1)"
```

### `term_to_dot`

```moonbit
pub fn term_to_dot(Term) -> String
```

Renders a `Term` AST as a GraphViz DOT string. Produces the same format as `@loom/viz.to_dot` — same header/footer, node naming (`node0`, `node1`, …), and dark-theme attribute style. Useful for visualizing the semantic AST in tools like the web demo.

**Example:**

```moonbit
let source_id = @loom.SourceId("dot-document")
let term = parse(source_id, "(x) => x + 1")
let dot = term_to_dot(term)
// "digraph {\n  bgcolor=\"transparent\";\n  ..."
```

### `print_token`

```moonbit
pub fn print_token(Token) -> String
```

Converts a single token to its string representation. Useful in error messages.

### `print_tokens`

```moonbit
pub fn print_tokens(Array[Token]) -> String
```

Converts an array of tokens to a bracketed, comma-separated string.

---

## 4. Error Types

### `Term::Error`

Not a raised error — a `Term` variant returned when a CST error node is converted. Replaces the old `Term::Var("<error>")` sentinel.

```moonbit
pub(all) enum Term {
  ...
  Error(String)   // error message from the parse diagnostic
}
```

`print_term` renders it as `<error: msg>`. Callers that need to check for parse errors should inspect `diagnostics()` on the parser rather than matching `Term::Error`.

`Term` also implements `ToJson` for use as a CRDT JSON bridge — e.g. serializing the AST for transport over a CRDT log.

### `@core.LexError`

Raised when the lexer encounters an invalid character or encoding issue.

```moonbit
pub(all) suberror LexError String  // defined in @core
```

**Example:**

```moonbit
try {
  let result = tokenize("@invalid")
} catch {
  @core.LexError(msg) => println("Lex error: " + msg)
}
```

### `ParseError`

Raised when the parser encounters unexpected tokens or malformed syntax.

```moonbit
pub suberror ParseError {
  ParseError(String)
}
```

**Example:**

```moonbit
try {
  let source_id = @loom.SourceId("parse-error-document")
  let result = parse(source_id, "() => x") // Missing parameter name
} catch {
  ParseError(msg) => println("Parse error: " + msg)
}
```

---

## 5. CST Key Types

All CST types come from the `seam` package (`seam/`).

- **`CstNode`** — Immutable CST node: kind, children, text length, structural hash, token count. Node offsets are external; unchanged regions are structurally shareable. `text_len`, `hash`, and `token_count` are cached at construction time.
- **`CstToken`** — Leaf token with kind, source-span text, and cached structural hash.
- **`SyntaxNode`** — Ephemeral positioned view over a `CstNode`. Computes absolute UTF-16 code-unit offsets on demand via parent pointers; not stored persistently.
- **`RawKind`** — Language-agnostic node/token kind (a newtype over `Int`).

**Example:**

```moonbit
let source_id = @loom.SourceId("cst-document")
let (cst, diagnostics) = parse_cst(source_id, "(x) => x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
// syntax.start() == 0, syntax.end() == 12

let term = parse(source_id, "(x) => x + 1")
// Term::Lam("x", Term::Bop(Plus, Term::Var("x"), Term::Int(1)))

for child in syntax.children() {
  // child.start(), child.end(), child.kind()
}
```

---

## 6. Parser Factories

The loom root package (`loom/src/`) provides the primary way to construct parsers from a `Grammar` description. These factories erase the token type `T` and kind type `K` so callers only see the `Ast` type.

See [choosing-a-parser.md](choosing-a-parser.md) to decide which parser to use.

### `Grammar`

```moonbit
pub struct Grammar[T, K, Ast] {
  spec         : @core.LanguageSpec[T, K]
  lex          : (@core.SourceId, String) -> @core.LexResult[T]
  fold_node    : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  incremental_relex_enabled : Bool
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
  mode_relex   : @core.ModeRelexFactory[T]?
}
```

Describes a complete language grammar. Construct with
`Grammar::new(spec~, lex~, fold_node~)`. The lambda implementation is
`@lambda.lambda_grammar`.

`lex` is the high-level parser boundary. It returns tokens, token starts, and
lexer diagnostics in one `LexResult`; malformed user input should be recovered
into error tokens plus diagnostics instead of escaping as `LexError`.

The factory no longer catches a raising tokenizer. Recovery policy belongs in
the grammar's `lex` implementation. `incremental_relex_enabled=false` marks
lexers that must be rerun on the whole source instead of arbitrary text slices.
For mode-aware grammars, build `mode_relex` with `erase_mode_lexer` and provide
an error token so invalid or incomplete mode steps become structured lexer
diagnostics plus recoverable error tokens.

### `new_imperative_parser`

```moonbit
pub fn[T, K, Ast] new_imperative_parser(
  source_id : @core.SourceId,
  source  : String,
  grammar : Grammar[T, K, Ast],
) -> @incremental.ImperativeParser[Ast]
```

Creates an `ImperativeParser` for the given source and grammar. Supports
`parse()`, `edit(Edit, String)`, and `reset(String)`, each returning
`ParseSnapshot[Ast]`.

### `new_parser`

```moonbit
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast : Eq] new_parser(
  source_id : @core.SourceId,
  source   : String,
  grammar  : Grammar[T, K, Ast],
  runtime? : @incr.Runtime,
) -> @pipeline.Parser[Ast]
```

Creates the unified `Parser[Ast]` reactive handle (post Stage 6, ADR
[2026-04-17-unified-parser-proposal.md](../decisions/2026-04-17-unified-parser-proposal.md)).
`Parser[Ast]` wraps `ImperativeParser` and publishes a coherent
`ParseSnapshot[Ast]` plus derived source, syntax, AST, and diagnostics views.
One type, two update paths (`apply_edit` + `set_source`); downstream consumers
attach reactive derived cells via `parser.runtime()`.

Runtime ownership follows the parser surface: omitting `runtime?` creates a
fresh parser-owned runtime, while supplying `runtime?` joins a caller-owned
graph. Parser-attached pipeline scopes should come from `parser.runtime()`.
For the `Scope` / `Watch` / priming / `dispose()` lifecycle, see
[choosing a parser](choosing-a-parser.md#runtime-ownership-and-attachments).

`new_parser` is intentionally stricter than `new_imperative_parser`: the
AST type `Ast` must implement `Eq`. The derived graph does structural-equality
backdating at the AST boundary, so equality is part of the public contract.

**Example:**

```moonbit
let source_id = @loom.SourceId("reactive-lambda-document")
let p = @loom.new_parser(
  source_id,
  "(x) => x + 1",
  @lambda.lambda_grammar,
)
let term = p.ast().read_or_abort()            // Ast type parameter of the Grammar
p.set_source("(x) => x + 2")
let updated = p.ast().read_or_abort()         // re-runs syntax + AST stages only if source changed
let diags = p.diagnostics().read_or_abort()   // DiagnosticSet, empty on success
```

The pre-Stage 6 reactive parser factory and struct have been removed — use
`new_parser` / `Parser[Ast]` instead. See
[archive/pipeline-api-contract.md](../archive/pipeline-api-contract.md) for
the pre-consolidation contract and [api/choosing-a-parser.md](choosing-a-parser.md)
for when to reach for `ImperativeParser` directly.

---

## 7. Usage Examples

### Identity Function

```moonbit
let source_id = @loom.SourceId("identity-document")
let identity = parse(source_id, "(x) => x")
print_term(identity)
// "(x) => x"
```

### Function Application

```moonbit
let source_id = @loom.SourceId("application-document")
let apply = parse(source_id, "((x) => x) 42")
print_term(apply)
// "(((x) => x) 42)"
```

### Arithmetic Operations

```moonbit
let source_id = @loom.SourceId("arithmetic-document")
let arithmetic = parse(source_id, "10 - 5 + 2")
print_term(arithmetic)
// "((10 - 5) + 2)"
```

### Conditional Expressions

```moonbit
let source_id = @loom.SourceId("conditional-document")
let conditional = parse(source_id, "if x then y else z")
print_term(conditional)
// "if x then y else z"
```

### Complex Nested Expression

```moonbit
let source_id = @loom.SourceId("nested-document")
let complex = parse(source_id, "(f, x) => if f x then x + 1 else x - 1")
print_term(complex)
// "(f, x) => (if (f x) then (x + 1) else (x - 1))"
```

### Church Numerals

```moonbit
// Church encoding of number 2
let source_id = @loom.SourceId("church-document")
let two = parse(source_id, "(f, x) => f (f x)")
print_term(two)
// "(f, x) => (f (f x))"
```
