# JSON Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an RFC 8259 JSON parser as the second loom example language, proving the framework generalizes and exercising block reparse with `{}` and `[]`.

**Architecture:** Flat package at `loom/examples/json/src/` (no sub-packages). Mirrors lambda patterns: Token enum, SyntaxKind enum, step-based lexer, recursive descent parser, CST→AST fold, Grammar wiring, BlockReparseSpec for Object/Array. Pure parser — no CRDT dependency.

**Tech Stack:** MoonBit, loom parser framework, seam CST library

**Design spec:** `loom/docs/plans/2026-03-22-json-parser-design.md`

---

## File Map

All paths relative to `loom/examples/json/`.

| File | Action | Responsibility |
|------|--------|---------------|
| `moon.mod.json` | Create | Module definition: `dowdiness/json` |
| `src/moon.pkg` | Create | Package imports: loom, seam |
| `src/token.mbt` | Create | Token enum (14 variants) + Show + print_token |
| `src/syntax_kind.mbt` | Create | SyntaxKind enum (23 variants) + to_raw/from_raw/is_token |
| `src/ast.mbt` | Create | JsonValue enum |
| `src/lexer.mbt` | Create | step_lex, json_step_lexer, tokenize |
| `src/json_spec.mbt` | Create | LanguageSpec + syntax_kind_to_token_kind + cst_token_matches |
| `src/cst_parser.mbt` | Create | parse_root, parse_value, parse_object, parse_array, parse_member |
| `src/value_convert.mbt` | Create | CST→JsonValue fold |
| `src/grammar.mbt` | Create | json_grammar (Grammar wiring) |
| `src/block_reparse.mbt` | Create | BlockReparseSpec for Object + Array |
| `src/parser.mbt` | Create | pub fn parse, parse_json, parse_cst |
| `src/lexer_test.mbt` | Create | Lexer tests |
| `src/parser_test.mbt` | Create | Parse + CST→AST tests |
| `src/error_recovery_test.mbt` | Create | Error recovery tests |
| `src/incremental_test.mbt` | Create | Incremental + block reparse tests |

---

## Task 1: Module Scaffold + Foundation Types

**Files:**
- Create: `moon.mod.json`, `src/moon.pkg`, `src/token.mbt`, `src/syntax_kind.mbt`, `src/ast.mbt`

- [ ] **Step 1: Create module config**

Create `loom/examples/json/moon.mod.json`:

```json
{
  "name": "dowdiness/json",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "dowdiness/loom": { "path": "../../loom" },
    "dowdiness/seam": { "path": "../../seam" },
    "moonbitlang/quickcheck": "0.9.10"
  },
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/loom",
  "license": "Apache-2.0",
  "keywords": ["json", "parser", "example"],
  "description": "JSON parser example for dowdiness/loom"
}
```

- [ ] **Step 2: Create package config**

Create `loom/examples/json/src/moon.pkg`:

```
import {
  "dowdiness/loom/core" @core,
  "dowdiness/seam" @seam,
  "dowdiness/loom" @loom,
  "moonbitlang/core/strconv",
}
```

- [ ] **Step 3: Create Token enum**

Create `src/token.mbt`:

```moonbit
///|
pub(all) enum Token {
  LBrace // {
  RBrace // }
  LBracket // [
  RBracket // ]
  Colon // :
  Comma // ,
  StringLit(String) // "hello" (raw text including quotes)
  NumberLit(String) // 42, 3.14e-2 (raw text)
  True // true
  False // false
  Null // null
  Whitespace // spaces, tabs, newlines, carriage returns
  Error(String) // lexer error
  EOF // end of input
} derive(Eq, Debug)

///|
pub impl Show for Token with output(self, logger) {
  logger.write_string(
    match self {
      LBrace => "{"
      RBrace => "}"
      LBracket => "["
      RBracket => "]"
      Colon => ":"
      Comma => ","
      StringLit(s) => s
      NumberLit(n) => n
      True => "true"
      False => "false"
      Null => "null"
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for Token with is_eof(self) {
  self == EOF
}

///|
pub fn print_token(token : Token) -> String {
  token.to_string()
}
```

- [ ] **Step 4: Create SyntaxKind enum**

Create `src/syntax_kind.mbt`:

```moonbit
///|
pub(all) enum SyntaxKind {
  // Token kinds
  LBraceToken
  RBraceToken
  LBracketToken
  RBracketToken
  ColonToken
  CommaToken
  StringToken
  NumberToken
  TrueKeyword
  FalseKeyword
  NullKeyword
  WhitespaceToken
  ErrorToken
  EofToken
  // Node kinds
  ObjectNode
  ArrayNode
  MemberNode
  StringValue
  NumberValue
  BoolValue
  NullValue
  ErrorNode
  RootNode
} derive(Show, Eq)

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    LBraceToken | RBraceToken | LBracketToken | RBracketToken | ColonToken
    | CommaToken | StringToken | NumberToken | TrueKeyword | FalseKeyword
    | NullKeyword | WhitespaceToken | ErrorToken | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with to_raw(self) {
  match self {
    LBraceToken => @seam.RawKind(0)
    RBraceToken => @seam.RawKind(1)
    LBracketToken => @seam.RawKind(2)
    RBracketToken => @seam.RawKind(3)
    ColonToken => @seam.RawKind(4)
    CommaToken => @seam.RawKind(5)
    StringToken => @seam.RawKind(6)
    NumberToken => @seam.RawKind(7)
    TrueKeyword => @seam.RawKind(8)
    FalseKeyword => @seam.RawKind(9)
    NullKeyword => @seam.RawKind(10)
    WhitespaceToken => @seam.RawKind(11)
    ErrorToken => @seam.RawKind(12)
    EofToken => @seam.RawKind(13)
    ObjectNode => @seam.RawKind(14)
    ArrayNode => @seam.RawKind(15)
    MemberNode => @seam.RawKind(16)
    StringValue => @seam.RawKind(17)
    NumberValue => @seam.RawKind(18)
    BoolValue => @seam.RawKind(19)
    NullValue => @seam.RawKind(20)
    ErrorNode => @seam.RawKind(21)
    RootNode => @seam.RawKind(22)
  }
}

///|
pub fn SyntaxKind::from_raw(raw : @seam.RawKind) -> SyntaxKind {
  match raw.0 {
    0 => LBraceToken
    1 => RBraceToken
    2 => LBracketToken
    3 => RBracketToken
    4 => ColonToken
    5 => CommaToken
    6 => StringToken
    7 => NumberToken
    8 => TrueKeyword
    9 => FalseKeyword
    10 => NullKeyword
    11 => WhitespaceToken
    12 => ErrorToken
    13 => EofToken
    14 => ObjectNode
    15 => ArrayNode
    16 => MemberNode
    17 => StringValue
    18 => NumberValue
    19 => BoolValue
    20 => NullValue
    21 => ErrorNode
    22 => RootNode
    _ => ErrorToken
  }
}
```

- [ ] **Step 5: Create AST**

Create `src/ast.mbt`:

```moonbit
///|
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

- [ ] **Step 6: Verify compiles**

Run: `cd loom/examples/json && moon update && moon check`
Expected: No errors (warnings about unused types are OK)

- [ ] **Step 7: Commit**

```bash
cd loom/examples/json && moon info && moon fmt
git add -A
git commit -m "feat(json): module scaffold + Token, SyntaxKind, JsonValue types"
```

---

## Task 2: Lexer

**Files:**
- Create: `src/lexer.mbt`, `src/lexer_test.mbt`

- [ ] **Step 1: Write lexer tests**

Create `src/lexer_test.mbt`:

```moonbit
///|
test "lex simple object" {
  let tokens = tokenize("{}") catch { _ => abort("lex error") }
  inspect(tokens.length(), content="3") // LBrace, RBrace, EOF
}

///|
test "lex string" {
  let tokens = tokenize("\"hello\"") catch { _ => abort("lex error") }
  inspect(tokens[0].token is StringLit(_), content="true")
}

///|
test "lex number integer" {
  let tokens = tokenize("42") catch { _ => abort("lex error") }
  inspect(tokens[0].token is NumberLit(_), content="true")
}

///|
test "lex number float" {
  let tokens = tokenize("3.14") catch { _ => abort("lex error") }
  inspect(tokens[0].token is NumberLit(_), content="true")
}

///|
test "lex number scientific" {
  let tokens = tokenize("1e10") catch { _ => abort("lex error") }
  inspect(tokens[0].token is NumberLit(_), content="true")
}

///|
test "lex keywords" {
  let t1 = tokenize("true") catch { _ => abort("lex error") }
  inspect(t1[0].token, content="true")
  let t2 = tokenize("false") catch { _ => abort("lex error") }
  inspect(t2[0].token, content="false")
  let t3 = tokenize("null") catch { _ => abort("lex error") }
  inspect(t3[0].token, content="null")
}

///|
test "lex whitespace" {
  let tokens = tokenize("  \t\n  42") catch { _ => abort("lex error") }
  inspect(tokens[0].token, content=" ")
  inspect(tokens[1].token is NumberLit(_), content="true")
}

///|
test "lex string with escapes" {
  let tokens = tokenize("\"hello\\nworld\"") catch { _ => abort("lex error") }
  inspect(tokens[0].token is StringLit(_), content="true")
}

///|
test "lex full object" {
  let tokens = tokenize("{\"key\": 42, \"arr\": [1, true, null]}") catch {
    _ => abort("lex error")
  }
  // Should not error — verify token count is reasonable
  inspect(tokens.length() > 10, content="true")
}
```

- [ ] **Step 2: Implement lexer**

Create `src/lexer.mbt`. The lexer uses loom's step-based pattern. Key functions:

- `step_lex(input, pos) -> @core.LexStep[Token]` — main lexer, handles:
  - Single-char: `{`, `}`, `[`, `]`, `:`, `,`
  - Whitespace: spaces, tabs, `\n`, `\r`
  - Strings: `"..."` with escape sequences, control char rejection
  - Numbers: `-?[0-9]+(.[0-9]+)?([eE][+-]?[0-9]+)?`
  - Keywords: `true`, `false`, `null`
  - Unknown chars: produce `Error` token

- `pub fn json_step_lexer(source, start) -> @core.LexStep[Token]` — public wrapper
- `pub fn tokenize(input) -> Array[@core.TokenInfo[Token]] raise @core.LexError` — batch tokenize. Implement a local `tokenize_via_steps` helper (same as lambda's `lexer.mbt` lines 57-80 — loop calling `step_lex` until `Done`, collecting `TokenInfo` results). This is NOT a loom framework function — each grammar implements its own.

**String lexer details:**
- Consume opening `"`
- Loop: consume chars, handle `\` escapes (`\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`)
- Reject unescaped control chars (0x00-0x1F)
- On closing `"`, produce `StringLit(raw_text)` including quotes
- On EOF without closing `"`, produce `Error("unterminated string")`

**Number lexer details:**
- Optional `-`
- Integer: `0` or `[1-9][0-9]*`
- Optional `.` + digits
- Optional `e`/`E` + optional `+`/`-` + digits
- Produce `NumberLit(raw_text)`

**Implementation note:** Read `loom/examples/lambda/src/lexer/lexer.mbt` for the exact `LexStep::Produced(TokenInfo::new(token, len), next_offset=pos + len)` pattern. Use `@core.tokenize_via_steps` for the batch tokenize function.

- [ ] **Step 3: Run tests**

Run: `cd loom/examples/json && moon test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
moon info && moon fmt
git add src/lexer.mbt src/lexer_test.mbt
git add -A
git commit -m "feat(json): step-based lexer for JSON tokens"
```

---

## Task 3: LanguageSpec

**Files:**
- Create: `src/json_spec.mbt`

- [ ] **Step 1: Create json_spec.mbt**

Mirror the lambda pattern in `lambda_spec.mbt`:

```moonbit
///|
fn syntax_kind_to_token_kind(kind : @seam.RawKind) -> Token? {
  match SyntaxKind::from_raw(kind) {
    LBraceToken => Some(LBrace)
    RBraceToken => Some(RBrace)
    LBracketToken => Some(LBracket)
    RBracketToken => Some(RBracket)
    ColonToken => Some(Colon)
    CommaToken => Some(Comma)
    TrueKeyword => Some(True)
    FalseKeyword => Some(False)
    NullKeyword => Some(Null)
    _ => None
  }
}

///|
let cst_token_matches : (@seam.RawKind, String, Token) -> Bool = fn(
  raw, text, tok
) {
  match SyntaxKind::from_raw(raw) {
    // Payload tokens: compare by text content
    StringToken =>
      match tok {
        StringLit(s) => s == text
        _ => false
      }
    NumberToken =>
      match tok {
        NumberLit(n) => n == text
        _ => false
      }
    // Fixed tokens: compare by kind
    _ =>
      match syntax_kind_to_token_kind(raw) {
        Some(expected) => expected == tok
        None => false
      }
  }
}

///|
let json_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  cst_token_matches~,
  parse_root=parse_json_root,
)
```

**Note:** `parse_json_root` doesn't exist yet — it will be created in Task 4. The spec references it forward. If MoonBit doesn't allow forward references, create a stub first:

```moonbit
fn parse_json_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ()
}
```

- [ ] **Step 2: Verify compiles**

Run: `cd loom/examples/json && moon check`

- [ ] **Step 3: Commit**

```bash
moon info && moon fmt
git add src/json_spec.mbt
git add -A
git commit -m "feat(json): LanguageSpec with token matching"
```

---

## Task 4: Parser

**Files:**
- Create: `src/cst_parser.mbt`

- [ ] **Step 1: Implement parser**

Create `src/cst_parser.mbt` with these functions:

```moonbit
///|
fn is_value_start(token : Token) -> Bool {
  match token {
    LBrace | LBracket | StringLit(_) | NumberLit(_) | True | False | Null => true
    _ => false
  }
}

///|
fn is_sync_point(token : Token) -> Bool {
  match token {
    RBrace | RBracket | Comma | EOF => true
    _ => false
  }
}

///|
fn json_expect(
  ctx : @core.ParserContext[Token, SyntaxKind],
  expected : Token,
  kind : SyntaxKind,
) -> Bool {
  if ctx.peek() == expected {
    ctx.emit_token(kind)
    true
  } else {
    ctx.error("Expected " + expected.to_string())
    false
  }
}

///|
fn parse_value(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  match ctx.peek() {
    LBrace => parse_object(ctx)
    LBracket => parse_array(ctx)
    StringLit(_) =>
      ctx.node(StringValue, fn() { ctx.emit_token(StringToken) })
    NumberLit(_) =>
      ctx.node(NumberValue, fn() { ctx.emit_token(NumberToken) })
    True =>
      ctx.node(BoolValue, fn() { ctx.emit_token(TrueKeyword) })
    False =>
      ctx.node(BoolValue, fn() { ctx.emit_token(FalseKeyword) })
    Null =>
      ctx.node(NullValue, fn() { ctx.emit_token(NullKeyword) })
    _ => {
      ctx.error("Expected JSON value")
      if is_sync_point(ctx.peek()) {
        ctx.start_node(ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        let _ = ctx.skip_until(is_sync_point)
      }
    }
  }
}

///|
pub fn parse_object(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ObjectNode, fn() {
    ctx.emit_token(LBraceToken) // {
    if ctx.peek() != RBrace && ctx.peek() != EOF {
      parse_member(ctx)
      while ctx.peek() == Comma {
        ctx.emit_token(CommaToken)
        if ctx.peek() == RBrace {
          ctx.error("Trailing comma")
          break
        }
        parse_member(ctx)
      }
      // Missing comma recovery: only recover on string key (member start)
      while ctx.peek() is StringLit(_) {
        ctx.error("Expected ',' between members")
        parse_member(ctx)
        while ctx.peek() == Comma {
          ctx.emit_token(CommaToken)
          if ctx.peek() == RBrace {
            ctx.error("Trailing comma")
            break
          }
          parse_member(ctx)
        }
      }
    }
    let _ = json_expect(ctx, RBrace, RBraceToken)
  })
}

///|
pub fn parse_array(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ArrayNode, fn() {
    ctx.emit_token(LBracketToken) // [
    if ctx.peek() != RBracket && ctx.peek() != EOF {
      parse_value(ctx)
      while ctx.peek() == Comma {
        ctx.emit_token(CommaToken)
        if ctx.peek() == RBracket {
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
          if ctx.peek() == RBracket {
            ctx.error("Trailing comma")
            break
          }
          parse_value(ctx)
        }
      }
    }
    let _ = json_expect(ctx, RBracket, RBracketToken)
  })
}

///|
fn parse_member(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let mark = ctx.mark()
  match ctx.peek() {
    StringLit(_) => ctx.emit_token(StringToken)
    _ => {
      ctx.error("Expected string key")
      ctx.emit_error_placeholder()
    }
  }
  let _ = json_expect(ctx, Colon, ColonToken)
  parse_value(ctx)
  ctx.start_at(mark, MemberNode)
  ctx.finish_node()
}

///|
fn parse_json_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  if ctx.peek() == EOF {
    ctx.error("Empty JSON input")
    return
  }
  parse_value(ctx)
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after JSON value")
    let _ = ctx.skip_until(fn(t) { t == EOF })
  }
}
```

**Implementation note:** Read the actual `ParserContext` API from `loom/src/core/parser.mbt` for exact method names. Key methods: `peek()`, `emit_token(kind)`, `node(kind, body)`, `start_node(kind)`, `finish_node()`, `mark()`, `start_at(mark, kind)`, `error(msg)`, `emit_error_placeholder()`, `skip_until(predicate)`.

Replace the stub `parse_json_root` in `json_spec.mbt` if one was created.

- [ ] **Step 2: Verify compiles**

Run: `cd loom/examples/json && moon check`

- [ ] **Step 3: Commit**

```bash
moon info && moon fmt
git add src/cst_parser.mbt src/json_spec.mbt
git add -A
git commit -m "feat(json): recursive descent parser with error recovery"
```

---

## Task 5: CST→AST Conversion

**Files:**
- Create: `src/value_convert.mbt`

- [ ] **Step 1: Implement fold_node**

Create `src/value_convert.mbt`:

```moonbit
///|
/// Parse JSON string escapes from raw token text (includes quotes).
fn parse_json_string(raw : String) -> String {
  // Strip surrounding quotes
  let inner = raw.substring(start=1, end=raw.length() - 1)
  // Process escape sequences
  let buf = StringBuilder::new()
  let mut i = 0
  while i < inner.length() {
    let c = inner[i]
    if c == '\\' && i + 1 < inner.length() {
      let next = inner[i + 1]
      match next {
        '"' | '\\' | '/' => { buf.write_char(next); i = i + 2 }
        'b' => { buf.write_char('\x08'); i = i + 2 }
        'f' => { buf.write_char('\x0C'); i = i + 2 }
        'n' => { buf.write_char('\n'); i = i + 2 }
        'r' => { buf.write_char('\r'); i = i + 2 }
        't' => { buf.write_char('\t'); i = i + 2 }
        'u' => {
          // \uXXXX — parse 4 hex digits
          if i + 5 < inner.length() {
            let hex = inner.substring(start=i + 2, end=i + 6)
            match @strconv.parse_int(hex, base=16) {
              Ok(cp) => {
                buf.write_char(Char::from_int(cp))
                i = i + 6
              }
              Err(_) => { buf.write_char('\\'); i = i + 1 }
            }
          } else {
            buf.write_char('\\')
            i = i + 1
          }
        }
        _ => { buf.write_char('\\'); i = i + 1 }
      }
    } else {
      buf.write_char(c)
      i = i + 1
    }
  }
  buf.to_string()
}

///|
pub fn json_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> JsonValue,
) -> JsonValue {
  match SyntaxKind::from_raw(node.kind()) {
    RootNode => {
      // Root has one child: the value
      match node.nth_child(0) {
        Some(child) => recurse(child)
        None => JsonValue::Error("empty document")
      }
    }
    ObjectNode => {
      let members : Array[(String, JsonValue)] = []
      for child in node.children() {
        match SyntaxKind::from_raw(child.kind()) {
          MemberNode => {
            let key = child.token_text(StringToken.to_raw())
            let parsed_key = if key.length() >= 2 {
              parse_json_string(key)
            } else {
              key
            }
            let value = match child.nth_child(0) {
              Some(v) => recurse(v)
              None => JsonValue::Error("missing member value")
            }
            members.push((parsed_key, value))
          }
          _ => ()
        }
      }
      JsonValue::Object(members)
    }
    ArrayNode => {
      let elements : Array[JsonValue] = []
      for child in node.children() {
        elements.push(recurse(child))
      }
      JsonValue::Array(elements)
    }
    StringValue => {
      let text = node.token_text(StringToken.to_raw())
      if text.length() >= 2 {
        JsonValue::String(parse_json_string(text))
      } else {
        JsonValue::Error("malformed string")
      }
    }
    NumberValue => {
      let text = node.token_text(NumberToken.to_raw())
      match @strconv.parse_double(text) {
        Ok(n) => JsonValue::Number(n)
        Err(_) => JsonValue::Error("invalid number: " + text)
      }
    }
    BoolValue => {
      let text = node.token_text(TrueKeyword.to_raw())
      if text == "true" {
        JsonValue::Bool(true)
      } else {
        JsonValue::Bool(false)
      }
    }
    NullValue => JsonValue::Null
    ErrorNode => JsonValue::Error("parse error")
    _ => JsonValue::Error("unknown node: " + SyntaxKind::from_raw(node.kind()).to_string())
  }
}

///|
pub fn syntax_node_to_json(root : @seam.SyntaxNode) -> JsonValue {
  json_fold_node(root, syntax_node_to_json)
}
```

**Implementation notes:**
- `node.token_text(kind_raw)` gets the text of the first token child with that kind. Read `seam/syntax_node.mbt` to verify this method exists and its exact signature.
- `node.nth_child(0)` gets the first node child (skipping tokens). This is the value in a MemberNode.
- String escape parsing is done here, not in the lexer (raw token text includes quotes).
- `@strconv.parse_double` and `@strconv.parse_int` — these may use `raise` (not `Result`). Check lambda's `views.mbt` for the exact pattern. Use `try { @strconv.parse_int(...) } catch { ... }` or match on the result type, whichever the current MoonBit stdlib uses.

- [ ] **Step 2: Verify compiles**

Run: `cd loom/examples/json && moon check`

- [ ] **Step 3: Commit**

```bash
moon info && moon fmt
git add src/value_convert.mbt
git add -A
git commit -m "feat(json): CST to JsonValue fold conversion"
```

---

## Task 6: Grammar + Public API

**Files:**
- Create: `src/grammar.mbt`, `src/parser.mbt`

- [ ] **Step 1: Create grammar.mbt**

```moonbit
///|
pub let json_grammar : @loom.Grammar[Token, SyntaxKind, JsonValue] = @loom.Grammar::new(
  spec=json_spec,
  tokenize=tokenize,
  fold_node=json_fold_node,
  on_lex_error=fn(msg) { JsonValue::Error("lex error: " + msg) },
  error_token=Some(Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=json_step_lexer)),
)
```

- [ ] **Step 2: Create parser.mbt (public API)**

```moonbit
///|
pub suberror ParseError {
  ParseError(String, Token)
}

///|
pub fn parse(input : String) -> JsonValue raise {
  let (value, diags) = parse_json(input) catch {
    @core.LexError(msg) => raise ParseError(msg, EOF)
  }
  if diags.length() > 0 {
    raise ParseError(@core.format_diagnostic(diags[0]), diags[0].got_token)
  }
  value
}

///|
pub fn parse_json(
  source : String,
) -> (JsonValue, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  let (cst, diags) = parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_json(syntax), diags)
}

///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  let tokens = tokenize(source)
  let starts = @core.build_starts(tokens)
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + tokens[i].len },
    json_spec,
  )
  (cst, diagnostics)
}
```

- [ ] **Step 3: Verify compiles and write basic parse test**

Add to `src/parser_test.mbt`:

```moonbit
///|
test "parse null" {
  let v = parse("null") catch { _ => abort("parse error") }
  inspect(v, content="Null")
}

///|
test "parse true" {
  let v = parse("true") catch { _ => abort("parse error") }
  inspect(v, content="Bool(true)")
}

///|
test "parse number" {
  let v = parse("42") catch { _ => abort("parse error") }
  inspect(v, content="Number(42.0)")
}

///|
test "parse string" {
  let v = parse("\"hello\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"hello\")")
}

///|
test "parse empty object" {
  let v = parse("{}") catch { _ => abort("parse error") }
  inspect(v, content="Object([])")
}

///|
test "parse empty array" {
  let v = parse("[]") catch { _ => abort("parse error") }
  inspect(v, content="Array([])")
}

///|
test "parse simple object" {
  let v = parse("{\"key\": 42}") catch { _ => abort("parse error") }
  let printed = v.to_string()
  inspect(printed.contains("key"), content="true")
  inspect(printed.contains("42"), content="true")
}

///|
test "parse nested structure" {
  let v = parse("{\"a\": [1, true, null]}") catch { _ => abort("parse error") }
  let printed = v.to_string()
  inspect(printed.contains("a"), content="true")
}

///|
test "parse string with escapes" {
  let v = parse("\"hello\\nworld\"") catch { _ => abort("parse error") }
  inspect(v, content="String(\"hello\\nworld\")")
}
```

Run: `cd loom/examples/json && moon test`
Expected: All tests pass. Use `moon test --update` for snapshot content if needed.

- [ ] **Step 4: Commit**

```bash
moon info && moon fmt
git add src/grammar.mbt src/parser.mbt src/parser_test.mbt
git add -A
git commit -m "feat(json): Grammar wiring + public parse API with tests"
```

---

## Task 7: BlockReparseSpec

**Files:**
- Create: `src/block_reparse.mbt`

- [ ] **Step 1: Create block_reparse.mbt**

```moonbit
///|
pub let json_block_reparse_spec : @loom.BlockReparseSpec[Token, SyntaxKind] = {
  is_reparseable: fn(kind) {
    kind == ObjectNode.to_raw() || kind == ArrayNode.to_raw()
  },
  get_reparser: fn(kind) {
    if kind == ObjectNode.to_raw() {
      Some(parse_object)
    } else if kind == ArrayNode.to_raw() {
      Some(parse_array)
    } else {
      None
    }
  },
  is_balanced: fn(tokens) {
    let mut brace_depth = 0
    let mut bracket_depth = 0
    for token in tokens {
      match token.token {
        LBrace => brace_depth = brace_depth + 1
        RBrace => brace_depth = brace_depth - 1
        LBracket => bracket_depth = bracket_depth + 1
        RBracket => bracket_depth = bracket_depth - 1
        _ => ()
      }
      if brace_depth < 0 || bracket_depth < 0 {
        return false
      }
    }
    brace_depth == 0 && bracket_depth == 0
  },
}
```

- [ ] **Step 2: Wire into grammar**

Update `src/grammar.mbt` — add `block_reparse_spec=Some(json_block_reparse_spec)` to the Grammar::new call.

- [ ] **Step 3: Verify**

Run: `cd loom/examples/json && moon check && moon test`

- [ ] **Step 4: Commit**

```bash
moon info && moon fmt
git add src/block_reparse.mbt src/grammar.mbt
git add -A
git commit -m "feat(json): BlockReparseSpec for Object and Array"
```

---

## Task 8: Error Recovery + Incremental + Block Reparse Tests

**Files:**
- Create: `src/error_recovery_test.mbt`, `src/incremental_test.mbt`

- [ ] **Step 1: Write error recovery tests**

Create `src/error_recovery_test.mbt`:

```moonbit
///|
test "error recovery: trailing comma in object" {
  let (cst, diagnostics) = parse_cst("{\"a\": 1,}") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"a\": 1,}".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: trailing comma in array" {
  let (cst, diagnostics) = parse_cst("[1,]") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "[1,]".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing colon" {
  let (cst, diagnostics) = parse_cst("{\"key\" 42}") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"key\" 42}".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: missing closing brace" {
  let (cst, diagnostics) = parse_cst("{\"a\": 1") catch {
    _ => abort("lex error")
  }
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end() == "{\"a\": 1".length(), content="true")
  inspect(diagnostics.length() > 0, content="true")
}

///|
test "error recovery: empty input" {
  let (cst, diagnostics) = parse_cst("") catch { _ => abort("lex error") }
  let tree = @seam.SyntaxNode::from_cst(cst)
  inspect(tree.end(), content="0")
  inspect(diagnostics.length() > 0, content="true") // "Empty JSON input"
}
```

- [ ] **Step 2: Write incremental + block reparse tests**

Create `src/incremental_test.mbt`:

```moonbit
///|
test "incremental: edit value in object matches full reparse" {
  let source = "{\"a\": 1}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "{\"a\": 2}"
  let edit = @core.Edit::new(6, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = parse(new_source) catch { _ => abort("parse error") }
  inspect(incr.to_string(), content=full.to_string())
}

///|
test "incremental: edit value in array matches full reparse" {
  let source = "[1, 2, 3]"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "[1, 9, 3]"
  let edit = @core.Edit::new(4, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = parse(new_source) catch { _ => abort("parse error") }
  inspect(incr.to_string(), content=full.to_string())
}

///|
test "block reparse: edit inside object uses block reparse" {
  let source = "{\"x\": {\"a\": 1}, \"y\": 2}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  // Edit inside inner object: change 1 to 9
  let new_source = "{\"x\": {\"a\": 9}, \"y\": 2}"
  let edit = @core.Edit::new(12, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = parse(new_source) catch { _ => abort("parse error") }
  inspect(incr.to_string(), content=full.to_string())
  // Block reparse should have been used
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: edit inside array uses block reparse" {
  let source = "{\"arr\": [1, 2, 3]}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "{\"arr\": [1, 9, 3]}"
  let edit = @core.Edit::new(12, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = parse(new_source) catch { _ => abort("parse error") }
  inspect(incr.to_string(), content=full.to_string())
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: no container falls through" {
  let source = "42"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "99"
  let edit = @core.Edit::new(0, 2, 2)
  let incr = parser.edit(edit, new_source)
  let full = parse(new_source) catch { _ => abort("parse error") }
  inspect(incr.to_string(), content=full.to_string())
  // No block reparse — reuse_count != 1
  inspect(parser.get_last_reuse_count() != 1, content="true")
}
```

- [ ] **Step 3: Run all tests**

Run: `cd loom/examples/json && moon test`
Expected: All pass. Fix edit offsets if needed (count characters carefully).

- [ ] **Step 4: Commit**

```bash
moon info && moon fmt
git add src/error_recovery_test.mbt src/incremental_test.mbt
git add -A
git commit -m "test(json): error recovery, incremental, and block reparse tests"
```

---

## Task 9: Final Verification

- [ ] **Step 1: Run all tests**

```bash
cd loom/examples/json && moon test
```

- [ ] **Step 2: Run moon check**

```bash
moon check
```
Expected: 0 errors

- [ ] **Step 3: Verify loom + seam tests still pass**

```bash
cd ../../loom && moon test
cd ../seam && moon test
```

- [ ] **Step 4: Update interfaces and format**

```bash
cd examples/json && moon info && moon fmt
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(json): update interfaces"
```

---

## Dependency Graph

```text
Task 1 (Scaffold + Types)
    ↓
Task 2 (Lexer)
    ↓
Task 3 (LanguageSpec)
    ↓
Task 4 (Parser)
    ↓
Task 5 (CST→AST)
    ↓
Task 6 (Grammar + API)
    ↓
Task 7 (BlockReparseSpec)
    ↓
Task 8 (Tests)
    ↓
Task 9 (Final Verification)
```

All tasks are sequential.

---

## Notes for Implementer

1. **Flat package:** Everything is in `src/` — no sub-packages. All types and functions are accessible without import qualifiers within the package. This is intentional and different from lambda's sub-package structure.

2. **moon.pkg imports:** The package needs `dowdiness/loom/core`, `dowdiness/seam`, and `dowdiness/loom`. May also need `moonbitlang/core/strconv` for `parse_double` and `parse_int`. Check MoonBit stdlib availability.

3. **String indexing:** MoonBit string indexing may use `s[i]` returning `Char` or a different API. Check existing lexer code in lambda for the exact pattern (`input.charCodeAt(pos)` or similar).

4. **StringBuilder:** For string escape parsing, check if `StringBuilder` exists or if `Buffer` is the right type. Lambda uses `@buffer.Buffer` in some places.

5. **Token comparison:** `ctx.peek() == RBrace` compares Token variants. Since Token derives `Eq`, this works for keyword tokens. For payload tokens (`StringLit`, `NumberLit`), use pattern matching: `ctx.peek() is StringLit(_)`.

6. **Forward references:** MoonBit allows forward references within the same package. `json_spec` can reference `parse_json_root` defined in a different file (`cst_parser.mbt`).

7. **`moon update`:** Run `moon update` before first `moon check` to fetch dependencies (quickcheck).

8. **Snapshot tests:** Use `moon test --update` to auto-fill `inspect` content values, then verify they're correct.

9. **BoolValue ambiguity:** Both `true` and `false` produce `BoolValue` CST nodes. In `value_convert.mbt`, distinguish by checking which token kind the node contains (TrueKeyword vs FalseKeyword). Use `node.token_text(TrueKeyword.to_raw())` — if it returns non-empty, it's true; otherwise check FalseKeyword.

10. **LanguageSpec::new:** Check the exact constructor signature. Lambda uses positional args for some and labelled for others. Read `loom/src/core/parser.mbt` for the current signature. It may need `incomplete_kind` parameter too.
