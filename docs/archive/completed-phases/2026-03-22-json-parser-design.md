# JSON Parser for Loom — Design Spec

**Status:** Complete

**Date:** 2026-03-22
**Status:** Draft
**Scope:** `loom/examples/json/` — new module, pure parser (no CRDT)

---

## Goal

Add a JSON parser (RFC 8259) as the second loom example language. Proves the framework generalizes beyond lambda calculus, exercises block reparse with `{}` and `[]` containers, and creates a genuinely useful collaborative editing target.

---

## Grammar (RFC 8259)

```ebnf
Value    ::= Object | Array | String | Number | 'true' | 'false' | 'null'
Object   ::= '{' (Member (',' Member)*)? '}'
Member   ::= String ':' Value
Array    ::= '[' (Value (',' Value)*)? ']'
String   ::= '"' chars '"'
Number   ::= '-'? (0 | [1-9][0-9]*) ('.' [0-9]+)? ([eE][+-]?[0-9]+)?
```

Strict RFC 8259: no trailing commas, no comments, no single quotes. These are parse errors with error recovery.

---

## Tokens (12)

| Token | Example | Notes |
|---|---|---|
| `LBrace` | `{` | |
| `RBrace` | `}` | |
| `LBracket` | `[` | |
| `RBracket` | `]` | |
| `Colon` | `:` | |
| `Comma` | `,` | |
| `StringLit(String)` | `"hello"` | Raw text including quotes — escape parsing deferred to CST→AST |
| `NumberLit(String)` | `42`, `3.14e-2` | Raw text — parsed to Double in CST→AST to preserve lexeme for reuse |
| `True` | `true` | |
| `False` | `false` | |
| `Null` | `null` | |
| `Whitespace` | ` `, `\t`, `\n`, `\r` | Trivia |
| `Error(String)` | | Lexer error placeholder |
| `EOF` | | End of input |

### String lexing

Full RFC 8259 string support:
- Escape sequences: `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`
- Unicode escapes: `\uXXXX` (4 hex digits)
- Surrogate pairs: `\uD800\uDC00` — lexer accepts the raw text; CST→AST decodes to codepoint
- Unescaped control characters `U+0000`–`U+001F` are lexer errors (RFC 8259 §7)
- Unterminated strings are lexer errors (not aborts)
- Malformed `\uXXXX` (non-hex digits) are lexer errors

### Number lexing

Full RFC 8259 number support:
- Optional leading `-`
- Integer part: `0` or `[1-9][0-9]*` (no leading zeros except bare `0`)
- Optional fractional: `.` followed by one or more digits
- Optional exponent: `e` or `E`, optional `+` or `-`, one or more digits
- Lexer produces raw text as `NumberLit(String)` — preserves lexeme for `cst_token_matches` reuse
- CST→AST converts to `Double` via `parse_double`

---

## Syntax Kinds (23)

**Token kinds (14):**
LBraceToken, RBraceToken, LBracketToken, RBracketToken, ColonToken, CommaToken, StringToken, NumberToken, TrueKeyword, FalseKeyword, NullKeyword, WhitespaceToken, ErrorToken, EofToken

**Node kinds (9):**
ObjectNode, ArrayNode, MemberNode, StringValue, NumberValue, BoolValue, NullValue, ErrorNode, RootNode

### to_raw numbering

| Kind | Raw |
|---|---|
| LBraceToken | 0 |
| RBraceToken | 1 |
| LBracketToken | 2 |
| RBracketToken | 3 |
| ColonToken | 4 |
| CommaToken | 5 |
| StringToken | 6 |
| NumberToken | 7 |
| TrueKeyword | 8 |
| FalseKeyword | 9 |
| NullKeyword | 10 |
| WhitespaceToken | 11 |
| ErrorToken | 12 |
| EofToken | 13 |
| ObjectNode | 14 |
| ArrayNode | 15 |
| MemberNode | 16 |
| StringValue | 17 |
| NumberValue | 18 |
| BoolValue | 19 |
| NullValue | 20 |
| ErrorNode | 21 |
| RootNode | 22 |

---

## AST

```moonbit
pub(all) enum JsonValue {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[JsonValue])
  Object(Array[(String, JsonValue)])
  Error(String)
} derive(Show, Eq, Debug)
```

No `Unit` variant needed (JSON always has a root value). `Error(String)` for malformed/missing nodes, matching the lambda pattern.

---

## Module Structure

Flat package at `loom/examples/json/`:

```
loom/examples/json/
  moon.mod.json           # module: dowdiness/json
  src/
    moon.pkg              # imports: loom, seam, quickcheck
    token.mbt             # Token enum + Show + print_token
    syntax_kind.mbt       # SyntaxKind enum + to_raw/from_raw/is_token
    lexer.mbt             # step_lex, tokenize (step-based for incremental)
    ast.mbt               # JsonValue enum
    json_spec.mbt         # LanguageSpec + syntax_kind_to_token_kind
    cst_parser.mbt        # parse_value, parse_object, parse_array, parse_member
    grammar.mbt           # json_grammar (Grammar[Token, SyntaxKind, JsonValue])
    value_convert.mbt     # CST → JsonValue fold
    block_reparse.mbt     # BlockReparseSpec for Object + Array
    parser.mbt            # pub fn parse(String) -> JsonValue
    lexer_test.mbt
    parser_test.mbt
    cst_tree_test.mbt
    error_recovery_test.mbt
    incremental_test.mbt
    block_reparse_test.mbt
```

**Dependencies:** `dowdiness/loom`, `dowdiness/seam`, `moonbitlang/quickcheck`. No event-graph-walker.

One package — no sub-package overhead. All types accessible without import qualifiers within the package.

---

## Parser Functions

### parse_value

Entry point. Dispatches on current token:

```
fn parse_value(ctx) {
  match ctx.peek() {
    LBrace    => parse_object(ctx)
    LBracket  => parse_array(ctx)
    StringLit => ctx.node(StringValue, fn() { ctx.emit_token(StringToken) })
    NumberLit => ctx.node(NumberValue, fn() { ctx.emit_token(NumberToken) })
    True      => ctx.node(BoolValue, fn() { ctx.emit_token(TrueKeyword) })
    False     => ctx.node(BoolValue, fn() { ctx.emit_token(FalseKeyword) })
    Null      => ctx.node(NullValue, fn() { ctx.emit_token(NullKeyword) })
    _         => error + recovery
  }
}
```

### parse_object

Uses `ctx.node` for reuse-aware node construction (matches lambda pattern):

```
fn parse_object(ctx) {
  ctx.node(ObjectNode, fn() {
    ctx.emit_token(LBraceToken)        // {
    if ctx.peek() != RBrace {
      parse_member(ctx)                 // first member
      while ctx.peek() == Comma {
        ctx.emit_token(CommaToken)      // ,
        if ctx.peek() == RBrace {       // trailing comma
          ctx.error("Trailing comma")
          break
        }
        parse_member(ctx)
      }
      // Missing comma recovery: if next token starts a value/member
      // but isn't Comma or RBrace, emit error and continue parsing
      while is_value_start(ctx.peek()) {
        ctx.error("Expected ',' between members")
        parse_member(ctx)
        // Consume optional comma after recovery
        while ctx.peek() == Comma {
          ctx.emit_token(CommaToken)
          if ctx.peek() == RBrace { ctx.error("Trailing comma"); break }
          parse_member(ctx)
        }
      }
    }
    expect(ctx, RBrace, RBraceToken)    // }
  })
}
```

### parse_array

```
fn parse_array(ctx) {
  ctx.node(ArrayNode, fn() {
    ctx.emit_token(LBracketToken)       // [
    if ctx.peek() != RBracket {
      parse_value(ctx)                   // first element
      while ctx.peek() == Comma {
        ctx.emit_token(CommaToken)       // ,
        if ctx.peek() == RBracket {      // trailing comma
          ctx.error("Trailing comma")
          break
        }
        parse_value(ctx)
      }
      // Missing comma recovery
      while is_value_start(ctx.peek()) {
        ctx.error("Expected ',' between elements")
        parse_value(ctx)
        while ctx.peek() == Comma {
          ctx.emit_token(CommaToken)
          if ctx.peek() == RBracket { ctx.error("Trailing comma"); break }
          parse_value(ctx)
        }
      }
    }
    expect(ctx, RBracket, RBracketToken) // ]
  })
}
```

### is_value_start (helper)

```
fn is_value_start(token) -> Bool {
  match token {
    LBrace | LBracket | StringLit(_) | NumberLit(_)
    | True | False | Null => true
    _ => false
  }
}
```

### parse_member

```
fn parse_member(ctx) {
  let mark = ctx.mark()
  if ctx.peek() is StringLit {
    ctx.emit_token(StringToken)
  } else {
    ctx.error("Expected string key")
    ctx.emit_error_placeholder()
  }
  expect(ctx, Colon, ColonToken)       // :
  parse_value(ctx)                     // value
  ctx.start_at(mark, MemberNode)
  ctx.finish_node()
}
```

### Root parse

```
fn parse_root(ctx) {
  parse_value(ctx)
  // Trailing tokens after root value are errors
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after JSON value")
    skip_until(ctx, fn(t) { t == EOF })
  }
}
```

---

## CST → AST Conversion

`json_fold_node` maps SyntaxKind to JsonValue:

| SyntaxKind | JsonValue |
|---|---|
| ObjectNode | `Object(members.map(convert_member))` |
| ArrayNode | `Array(elements.map(recurse))` |
| MemberNode | Extract key (StringToken text) + value (recurse child) |
| StringValue | `String(parse_string_escapes(token_text))` |
| NumberValue | `Number(Double::from_string(token_text))` |
| BoolValue(TrueKeyword) | `Bool(true)` |
| BoolValue(FalseKeyword) | `Bool(false)` |
| NullValue | `Null` |
| ErrorNode | `Error(message)` |
| RootNode | recurse first child |

String escape parsing happens at the AST level, not the lexer. The lexer produces raw string text including quotes; `value_convert.mbt` strips quotes and interprets escape sequences.

---

## Block Reparse

Both `ObjectNode` and `ArrayNode` are reparseable containers.

### BlockReparseSpec

```moonbit
is_reparseable: fn(kind) {
  kind == ObjectNode.to_raw() || kind == ArrayNode.to_raw()
}

get_reparser: fn(kind) {
  if kind == ObjectNode.to_raw() { Some(parse_object) }
  else if kind == ArrayNode.to_raw() { Some(parse_array) }
  else { None }
}

is_balanced: fn(tokens) {
  let mut brace_depth = 0
  let mut bracket_depth = 0
  for token in tokens {
    match token.token {
      LBrace => brace_depth += 1
      RBrace => brace_depth -= 1
      LBracket => bracket_depth += 1
      RBracket => bracket_depth -= 1
      _ => ()
    }
    if brace_depth < 0 || bracket_depth < 0 { return false }
  }
  brace_depth == 0 && bracket_depth == 0
}
```

### Five properties satisfied

1. **Lexical containment:** Context-free lexer — `{`, `[`, `"` have fixed meaning regardless of position
2. **Syntactic independence:** `parse_object` and `parse_array` produce complete subtrees without surrounding context
3. **Structural integrity:** Bracket/brace balance check
4. **Deterministic discovery:** Walk ancestors for ObjectNode or ArrayNode
5. **Boundary stability:** Editing inside `{ ... }` or `[ ... ]` doesn't move delimiters

---

## Error Recovery

**Sync points:** `}`, `]`, `,`, `EOF`

| Error | Recovery |
|---|---|
| Missing `}` or `]` | Close node at EOF or next matching delimiter |
| Missing `,` between elements | Emit error, continue parsing next element |
| Missing `:` in member | Emit error, treat next token as value |
| Trailing comma `[1,]` | Emit "Trailing comma" diagnostic, close container |
| Unexpected token | Skip until sync point, wrap skipped tokens in ErrorNode |
| Unterminated string | Lexer produces Error token, parser wraps in ErrorNode |

---

## Testing Strategy

### Lexer tests
- All token types: `{`, `}`, `[`, `]`, `:`, `,`, `true`, `false`, `null`
- Strings: empty `""`, escapes `"\n"`, unicode `"\u0041"`, unterminated
- Numbers: `0`, `-0`, `42`, `3.14`, `1e10`, `-2.5E-3`, leading zeros (error)
- Whitespace: spaces, tabs, newlines, mixed

### Parse tests (CST → AST)
- All JSON value types
- Nested: `{"a": [1, {"b": true}]}`
- Empty containers: `{}`, `[]`
- Deep nesting: 10+ levels

### Error recovery
- Missing delimiters, commas, colons
- Trailing commas
- Unterminated strings
- Unexpected tokens
- Verify CST completeness (every byte accounted for)

### Incremental parse
- Edit value inside object → correct reparse
- Edit key string → correct reparse
- Add/remove member → correct reparse

### Block reparse
- Edit inside `{}` triggers block reparse (reuse_count == 1)
- Edit inside `[]` triggers block reparse
- Nested: edit in inner object reparses inner, not outer
- Edit touching `{`/`}` falls through
- Compare against full reparse for correctness

---

## Out of Scope

- Comments (JSONC)
- Trailing commas as valid syntax (JSON5)
- Single-quoted strings
- Unquoted keys
- BigInt / arbitrary precision numbers
- CRDT integration (event-graph-walker)
- Projectional editing (canopy editor layer)
- Web frontend

---

## References

- [RFC 8259 — The JavaScript Object Notation (JSON) Data Interchange Format](https://www.rfc-editor.org/rfc/rfc8259)
- `loom/examples/lambda/` — existing loom parser example (structural reference)
- `loom/docs/architecture/block-reparse.md` — block reparse properties
