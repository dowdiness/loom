# Public API Reference

Lambda calculus parser — user-facing API for tokenizing, parsing, pretty printing, and error handling.

## 1. Parsing Functions

### `parse`

```moonbit
pub fn parse(String) -> Term raise
```

Parses an input string directly into a `Term` AST. Raises errors if tokenization fails or if the input contains syntax errors. The simplest entry point when only the semantic AST is needed.

### `parse_source_file_term`

```moonbit
pub fn parse_source_file_term(String) -> (Term, Array[Diagnostic]) raise @core.LexError
```

Parses a multi-expression source file — a sequence of top-level `let` definitions optionally followed by a final expression — and converts to `Term`. Definitions are right-folded into nested `Let` terms. Returns both the term and any parse diagnostics (does not raise on parse errors). Use this for file-level input.

```
let id = λx. x
let const = λx. λy. x
```

### `parse_cst`

```moonbit
pub fn parse_cst(String) -> @seam.CstNode raise
```

Parses a string into an immutable `CstNode` tree — a lossless CST with structural hashing. Raises on tokenization failure. All whitespace is preserved as trivia nodes.

### `parse_cst_recover`

```moonbit
pub fn parse_cst_recover(String) -> (@seam.CstNode, Array[Diagnostic]) raise
```

Like `parse_cst` but returns error nodes instead of raising, paired with a diagnostic list. Prefer this when the caller needs to continue despite syntax errors (e.g., editors, IDEs, incremental pipelines).

---

## 2. Tokenization

```moonbit
pub fn tokenize(String) -> Array[Token] raise @core.LexError
```

Converts an input string into an array of tokens. Raises `@core.LexError` if the input contains invalid characters.

**Example:**

```moonbit
let tokens = tokenize("λx.x + 1")
// [Lambda, Identifier("x"), Dot, Identifier("x"), Plus, Integer(1), EOF]
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
let ast = parse("λx.x + 1")
let output = print_term(ast)
// "(λx. (x + 1))"
```

### `term_to_dot`

```moonbit
pub fn term_to_dot(Term) -> String
```

Renders a `Term` AST as a GraphViz DOT string. Produces the same format as `@loom/viz.to_dot` — same header/footer, node naming (`node0`, `node1`, …), and dark-theme attribute style. Useful for visualizing the semantic AST in tools like the web demo.

**Example:**

```moonbit
let term = parse("λx.x + 1")
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
pub suberror ParseError (String, Token)
```

**Example:**

```moonbit
try {
  let result = parse("λ.x")  // Missing parameter name
} catch {
  ParseError((msg, token)) => {
    println("Parse error: " + msg)
    println("At token: " + print_token(token))
  }
}
```

---

## 5. CST Key Types

All CST types come from the `seam` package (`seam/`).

- **`CstNode`** — Immutable CST node: kind, children, text length, structural hash, token count. Position-independent; structurally shareable. `text_len`, `hash`, and `token_count` are cached at construction time.
- **`CstToken`** — Leaf token with kind, text, and cached structural hash.
- **`SyntaxNode`** — Ephemeral positioned view over a `CstNode`. Computes absolute byte offsets on demand via parent pointers; not stored persistently.
- **`RawKind`** — Language-agnostic node/token kind (a newtype over `Int`).

**Example:**

```moonbit
let cst = parse_cst("λx.x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
// syntax.start() == 0, syntax.end() == 8

let term = parse("λx.x + 1")
// Term::Lam("x", Term::BinOp(Plus, Term::Var("x"), Term::Int(1)))

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
  tokenize     : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  to_ast       : (@seam.SyntaxNode) -> Ast
  on_lex_error : (String) -> Ast
}
```

Describes a complete language grammar. Construct with `Grammar::new(spec~, tokenize~, to_ast~)`. The lambda implementation is `@lambda.lambda_grammar`.

### `new_imperative_parser`

```moonbit
pub fn[T, K, Ast] new_imperative_parser(
  source  : String,
  grammar : Grammar[T, K, Ast],
) -> @incremental.ImperativeParser[Ast]
```

Creates an `ImperativeParser` for the given source and grammar. Supports `parse()`, `edit(Edit, String)`, and `reset(String)`.

### `new_parser`

```moonbit
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast : Eq] new_parser(
  source   : String,
  grammar  : Grammar[T, K, Ast],
  runtime? : @incr.Runtime,
) -> @pipeline.Parser[Ast]
```

Creates the unified `Parser[Ast]` reactive handle (post Stage 6, ADR
[2026-04-17-unified-parser-proposal.md](../decisions/2026-04-17-unified-parser-proposal.md)).
`Parser[Ast]` wraps `ImperativeParser` and publishes source + syntax + AST +
diagnostics as `@incr.Signal` / `@incr.Memo` cells. One type, two update
paths (`apply_edit` + `set_source`); downstream consumers attach reactive
memos via `parser.runtime()`.

`new_parser` is intentionally stricter than `new_imperative_parser`: the
AST type `Ast` must implement `Eq`. The memo graph does structural-equality
backdating at the AST boundary, so equality is part of the public contract.

**Example:**

```moonbit
let p = @loom.new_parser("λx.x + 1", @lambda.lambda_grammar)
let term = p.runtime().read(p.ast())            // Ast type parameter of the Grammar
p.set_source("λx.x + 2")
let updated = p.runtime().read(p.ast())         // re-runs syntax + AST stages only if source changed
let diags   = p.runtime().read(p.diagnostics()) // Array[String], empty on success
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
let identity = parse("λx.x")
print_term(identity)
// "(λx. x)"
```

### Function Application

```moonbit
let apply = parse("(λx.x) 42")
print_term(apply)
// "((λx. x) 42)"
```

### Arithmetic Operations

```moonbit
let arithmetic = parse("10 - 5 + 2")
print_term(arithmetic)
// "((10 - 5) + 2)"
```

### Conditional Expressions

```moonbit
let conditional = parse("if x then y else z")
print_term(conditional)
// "if x then y else z"
```

### Complex Nested Expression

```moonbit
let complex = parse("(λf.λx.if f x then x + 1 else x - 1)")
print_term(complex)
// "(λf. (λx. if (f x) then (x + 1) else (x - 1)))"
```

### Church Numerals

```moonbit
// Church encoding of number 2
let two = parse("λf.λx.f (f x)")
print_term(two)
// "(λf. (λx. (f (f x))))"
```
