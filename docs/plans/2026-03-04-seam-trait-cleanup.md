# Seam trait cleanup + token_at_offset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace seven `LanguageSpec` closures with trait bounds on `T` and `K`, and add `CstNode::first_token` + `SyntaxNode::token_at_offset` to seam.

**Architecture:** Two phases. Phase 1 defines four K-traits (`ToRawKind`, `FromRawKind`, `IsTrivia`, `IsError`) in seam, implements them on `SyntaxKind`, drops three K-side closures from `LanguageSpec`, and adds the two new seam traversal APIs. Phase 2 adds `IsEof`, implements T-traits on `Token`, drops four T-side closures. Each phase ends with a green test suite.

**Tech Stack:** MoonBit, `moon` build tool, seam CST library, loom parser framework, lambda calculus example.

**Design doc:** `docs/plans/2026-03-04-seam-trait-cleanup-design.md`

---

## Background: what changes and why

`LanguageSpec[T, K]` in `loom/src/core/parser.mbt` currently carries closures that duplicate
knowledge the language types already have:

```moonbit
kind_to_raw   : (K) -> @seam.RawKind      // same as k.to_raw()
raw_is_trivia : (@seam.RawKind) -> Bool    // same as raw == spec.whitespace_kind.to_raw()
raw_is_error  : (@seam.RawKind) -> Bool    // same as raw == spec.error_kind.to_raw()
tokens_equal  : (T, T) -> Bool             // same as a == b (Token derives Eq)
token_is_trivia : (T) -> Bool              // same as t == Token::Whitespace
token_is_eof  : (T) -> Bool               // same as t == Token::EOF
print_token   : (T) -> String             // same as t.to_string() with manual Show impl
```

After this plan, `LanguageSpec` retains only `cst_token_matches` and `parse_root` (both are
cross-layer/grammar-specific and cannot be replaced by a simple trait).

---

## Phase 1 — K-traits + new SyntaxNode APIs

---

### Task 1: Define K-traits in seam

**Files:**
- Create: `seam/kind_traits.mbt`
- Modify: `seam/pkg.generated.mbti` (regenerate at end)

**Step 1: Create `seam/kind_traits.mbt`**

```moonbit
///|
/// Convert a language-specific syntax kind to its language-agnostic RawKind.
/// Implement this on any syntax-kind type used with LanguageSpec.
pub(open) trait ToRawKind {
  to_raw(Self) -> RawKind
}

///|
/// Construct a language-specific syntax kind from a language-agnostic RawKind.
/// Used by seam internals for round-trip conversions (e.g. first_token filtering).
pub(open) trait FromRawKind {
  from_raw(RawKind) -> Self
}

///|
/// Classify a token or syntax-kind as trivia (whitespace, comments).
/// Trivia is skipped during non-trivia token queries.
pub(open) trait IsTrivia {
  is_trivia(Self) -> Bool
}

///|
/// Classify a token or syntax-kind as an error sentinel.
pub(open) trait IsError {
  is_error(Self) -> Bool
}

///|
/// Classify a token as end-of-input.
/// Implement this on the token type T used with LanguageSpec.
pub(open) trait IsEof {
  is_eof(Self) -> Bool
}
```

(All five traits go in one file — `IsEof` is used in Phase 2 but cheap to define now.)

**Step 2: Run `moon check` from `seam/`**

```bash
cd /path/to/loom/seam && moon check
```

Expected: no errors.

**Step 3: Regenerate interface**

```bash
cd /path/to/loom/seam && moon info && moon fmt
```

**Step 4: Commit**

```bash
git add seam/kind_traits.mbt seam/pkg.generated.mbti
git commit -m "feat(seam): add ToRawKind, FromRawKind, IsTrivia, IsError, IsEof traits"
```

---

### Task 2: Implement K-traits on SyntaxKind

**Files:**
- Modify: `examples/lambda/src/syntax/syntax_kind.mbt`
- Create: `examples/lambda/src/syntax/syntax_kind_test.mbt`
- Modify: `examples/lambda/src/syntax/pkg.generated.mbti` (regenerate)

**Step 1: Write failing tests in `examples/lambda/src/syntax/syntax_kind_test.mbt`**

```moonbit
///|
test "SyntaxKind: WhitespaceToken is trivia" {
  inspect(@syntax.WhitespaceToken.is_trivia(), content="true")
}

///|
test "SyntaxKind: LambdaToken is not trivia" {
  inspect(@syntax.LambdaToken.is_trivia(), content="false")
}

///|
test "SyntaxKind: ErrorToken is error" {
  inspect(@syntax.ErrorToken.is_error(), content="true")
}

///|
test "SyntaxKind: LambdaToken is not error" {
  inspect(@syntax.LambdaToken.is_error(), content="false")
}
```

**Step 2: Run tests to verify they fail**

```bash
cd /path/to/loom/examples/lambda && moon test -p dowdiness/lambda/syntax
```

Expected: compile error — `is_trivia`/`is_error` not found.

**Step 3: Replace plain functions with trait impls in `syntax_kind.mbt`**

Find the existing plain functions:

```moonbit
pub fn SyntaxKind::to_raw(self : SyntaxKind) -> @seam.RawKind { ... }
pub fn SyntaxKind::from_raw(raw : @seam.RawKind) -> SyntaxKind { ... }
```

Replace them with trait impls (keep identical bodies):

```moonbit
///|
pub impl @seam.ToRawKind for SyntaxKind with to_raw(self) {
  let n : Int = match self {
    LambdaToken => 0
    DotToken => 1
    LeftParenToken => 2
    RightParenToken => 3
    PlusToken => 4
    MinusToken => 5
    IfKeyword => 6
    ThenKeyword => 7
    ElseKeyword => 8
    IdentToken => 9
    IntToken => 10
    WhitespaceToken => 11
    ErrorToken => 12
    EofToken => 13
    LambdaExpr => 14
    AppExpr => 15
    BinaryExpr => 16
    IfExpr => 17
    ParenExpr => 18
    IntLiteral => 19
    VarRef => 20
    ErrorNode => 21
    SourceFile => 22
    LetKeyword => 23
    InKeyword => 24
    EqToken => 25
    LetExpr => 26
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for SyntaxKind with from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => LambdaToken
    1 => DotToken
    2 => LeftParenToken
    3 => RightParenToken
    4 => PlusToken
    5 => MinusToken
    6 => IfKeyword
    7 => ThenKeyword
    8 => ElseKeyword
    9 => IdentToken
    10 => IntToken
    11 => WhitespaceToken
    12 => ErrorToken
    13 => EofToken
    14 => LambdaExpr
    15 => AppExpr
    16 => BinaryExpr
    17 => IfExpr
    18 => ParenExpr
    19 => IntLiteral
    20 => VarRef
    21 => ErrorNode
    22 => SourceFile
    23 => LetKeyword
    24 => InKeyword
    25 => EqToken
    26 => LetExpr
    _ => ErrorNode
  }
}

///|
pub impl @seam.IsTrivia for SyntaxKind with is_trivia(self) {
  self == WhitespaceToken
}

///|
pub impl @seam.IsError for SyntaxKind with is_error(self) {
  self == ErrorToken
}
```

**Step 4: Run tests and verify they pass**

```bash
cd /path/to/loom/examples/lambda && moon test -p dowdiness/lambda/syntax
```

Expected: 4 tests pass. Also run full lambda suite:

```bash
cd /path/to/loom/examples/lambda && moon test
```

Expected: all tests pass (call sites using `SyntaxKind::to_raw` / `SyntaxKind::from_raw` still resolve — trait impls use the same method name).

**Step 5: Regenerate interface and commit**

```bash
cd /path/to/loom/examples/lambda && moon info && moon fmt
git add examples/lambda/src/syntax/syntax_kind.mbt \
        examples/lambda/src/syntax/syntax_kind_test.mbt \
        examples/lambda/src/syntax/pkg.generated.mbti
git commit -m "feat(lambda): implement ToRawKind, FromRawKind, IsTrivia, IsError on SyntaxKind"
```

---

### Task 3: Drop K-side closures from LanguageSpec

**Files:**
- Modify: `loom/src/core/parser.mbt`
- Modify: `loom/src/core/reuse_cursor.mbt`
- Modify: `examples/lambda/src/lambda_spec.mbt`
- Modify: `loom/pkg.generated.mbti` (regenerate)

This task removes `kind_to_raw`, `raw_is_trivia`, `raw_is_error` from `LanguageSpec` and
adds `K: @seam.ToRawKind` bounds where needed. All existing tests remain the regression.

**Step 1: Update `LanguageSpec` struct in `loom/src/core/parser.mbt`**

Remove `kind_to_raw` field (line ~62):

```moonbit
// REMOVE this line:
  kind_to_raw : (K) -> @seam.RawKind
```

Remove `raw_is_trivia` and `raw_is_error` fields (lines ~72-73):

```moonbit
// REMOVE these lines:
  raw_is_trivia : (@seam.RawKind) -> Bool
  raw_is_error : (@seam.RawKind) -> Bool
```

**Step 2: Update `LanguageSpec::new` constructor in `loom/src/core/parser.mbt`**

Add `K: @seam.ToRawKind` bound and remove the three parameters:

```moonbit
pub fn[T, K : @seam.ToRawKind] LanguageSpec::new(
  // REMOVE: kind_to_raw : (K) -> @seam.RawKind,
  token_is_eof : (T) -> Bool,
  token_is_trivia : (T) -> Bool,
  tokens_equal : (T, T) -> Bool,
  print_token : (T) -> String,
  whitespace_kind : K,
  error_kind : K,
  root_kind : K,
  eof_token : T,
  // REMOVE: raw_is_trivia? : ... = ...,
  // REMOVE: raw_is_error? : ... = ...,
  cst_token_matches? : (@seam.RawKind, String, T) -> Bool = fn(_, _, _) { false },
  parse_root? : (ParserContext[T, K]) -> Unit = _ => (),
) -> LanguageSpec[T, K] {
  {
    // REMOVE: kind_to_raw,
    token_is_eof,
    token_is_trivia,
    tokens_equal,
    print_token,
    whitespace_kind,
    error_kind,
    root_kind,
    eof_token,
    // REMOVE: raw_is_trivia,
    // REMOVE: raw_is_error,
    cst_token_matches,
    parse_root,
  }
}
```

**Step 3: Replace `spec.kind_to_raw` call sites in `loom/src/core/parser.mbt`**

Grep for all usages:

```bash
grep -n "kind_to_raw" loom/src/core/parser.mbt
```

For each `(self.spec.kind_to_raw)(k)` or `(spec.kind_to_raw)(k)`, replace with `k.to_raw()`.
The function that contains the call site will need a `K : @seam.ToRawKind` bound added to
its signature if it doesn't already have one.

Key patterns to replace (line numbers from your current file — verify with grep):
- `(self.spec.kind_to_raw)(self.spec.whitespace_kind)` → `self.spec.whitespace_kind.to_raw()`
- `(self.spec.kind_to_raw)(kind)` → `kind.to_raw()`
- `(self.spec.kind_to_raw)(self.spec.error_kind)` → `self.spec.error_kind.to_raw()`
- `(self.spec.kind_to_raw)(self.spec.root_kind)` → `self.spec.root_kind.to_raw()`
- `(spec.kind_to_raw)(spec.root_kind)` → `spec.root_kind.to_raw()`
- `(spec.kind_to_raw)(spec.whitespace_kind)` → `spec.whitespace_kind.to_raw()`

For each function modified, add `K : @seam.ToRawKind` to its type parameter list.

**Step 4: Replace `spec.raw_is_trivia` and `spec.raw_is_error` in `loom/src/core/reuse_cursor.mbt`**

Grep for usages:

```bash
grep -n "raw_is_trivia\|raw_is_error" loom/src/core/reuse_cursor.mbt
```

Replace:
- `(spec.raw_is_trivia)(t.kind)` → `t.kind == spec.whitespace_kind.to_raw()`
- `(spec.raw_is_error)(t.kind)` → `t.kind == spec.error_kind.to_raw()`
- `(spec.raw_is_error)(n.kind)` → `n.kind == spec.error_kind.to_raw()`

Add `K : @seam.ToRawKind` to each affected `fn[T, K]` signature in `reuse_cursor.mbt`.
Also add the bound to `ReuseCursor::new` signature since it constructs the cursor.

**Step 5: Update `lambda_spec.mbt` — drop three arguments**

```moonbit
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  // REMOVE: @syntax.SyntaxKind::to_raw,   ← was kind_to_raw
  fn(t) { t == @token.EOF },
  fn(t) { t == @token.Whitespace },
  fn(a, b) { a == b },
  @token.print_token,
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  // REMOVE: raw_is_trivia=fn(raw) { raw == @syntax.WhitespaceToken.to_raw() },
  // REMOVE: raw_is_error=fn(raw) { raw == @syntax.ErrorToken.to_raw() },
  cst_token_matches=...,
  parse_root=parse_lambda_root,
)
```

**Step 6: Run `moon check` from each module**

```bash
cd /path/to/loom/loom && moon check
cd /path/to/loom/examples/lambda && moon check
```

Fix any remaining compile errors (missed call sites or missing `ToRawKind` bounds).

**Step 7: Run full test suites**

```bash
cd /path/to/loom/loom && moon test
cd /path/to/loom/examples/lambda && moon test
```

Expected: all tests pass.

**Step 8: Regenerate interfaces and commit**

```bash
cd /path/to/loom/loom && moon info && moon fmt
cd /path/to/loom/examples/lambda && moon info && moon fmt
git add loom/src/core/parser.mbt loom/src/core/reuse_cursor.mbt \
        loom/pkg.generated.mbti \
        examples/lambda/src/lambda_spec.mbt \
        examples/lambda/pkg.generated.mbti
git commit -m "refactor(loom): drop kind_to_raw, raw_is_trivia, raw_is_error from LanguageSpec"
```

---

### Task 4: Add `CstNode::first_token` + clean up reuse_cursor helpers

**Files:**
- Modify: `seam/cst_node.mbt`
- Modify: `seam/cst_node_wbtest.mbt`
- Modify: `loom/src/core/reuse_cursor.mbt`
- Modify: `seam/pkg.generated.mbti` (regenerate)

**Step 1: Write failing tests in `seam/cst_node_wbtest.mbt`**

```moonbit
///|
test "CstNode::first_token: returns first non-trivia token" {
  // ws token (kind 11 = WhitespaceToken), then ident token (kind 9 = IdentToken)
  let ws = CstToken::new(RawKind(11), " ")
  let id = CstToken::new(RawKind(9), "x")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(ws), CstElement::Token(id)])
  let is_trivia = fn(k : RawKind) { k == RawKind(11) }
  match cst.first_token(is_trivia) {
    Some(t) => inspect(t.text, content="x")
    None => inspect("none", content="x")
  }
}

///|
test "CstNode::first_token: descends into child nodes" {
  let id = CstToken::new(RawKind(9), "y")
  let inner = CstNode::new(RawKind(20), [CstElement::Token(id)])
  let outer = CstNode::new(RawKind(22), [CstElement::Node(inner)])
  let is_trivia = fn(_k : RawKind) { false }
  match outer.first_token(is_trivia) {
    Some(t) => inspect(t.text, content="y")
    None => inspect("none", content="y")
  }
}

///|
test "CstNode::first_token: returns None for empty node" {
  let cst = CstNode::new(RawKind(22), [])
  let is_trivia = fn(_k : RawKind) { false }
  inspect(cst.first_token(is_trivia) is None, content="true")
}

///|
test "CstNode::first_token: returns None when all tokens are trivia" {
  let ws = CstToken::new(RawKind(11), " ")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(ws)])
  let is_trivia = fn(k : RawKind) { k == RawKind(11) }
  inspect(cst.first_token(is_trivia) is None, content="true")
}
```

**Step 2: Run tests to verify they fail**

```bash
cd /path/to/loom/seam && moon test
```

Expected: compile error — `first_token` not found on `CstNode`.

**Step 3: Add `CstNode::first_token` to `seam/cst_node.mbt`**

```moonbit
///|
/// First non-trivia token in this subtree (depth-first, left-to-right).
/// `is_trivia` classifies tokens to skip (e.g. whitespace).
/// Returns None when the subtree contains no non-trivia tokens.
pub fn CstNode::first_token(
  self : CstNode,
  is_trivia : (RawKind) -> Bool,
) -> CstToken? {
  for child in self.children {
    match child {
      CstElement::Token(t) =>
        if not(is_trivia(t.kind)) {
          return Some(t)
        }
      CstElement::Node(n) =>
        match n.first_token(is_trivia) {
          Some(_) as found => return found
          None => ()
        }
    }
  }
  None
}
```

**Step 4: Run seam tests to verify they pass**

```bash
cd /path/to/loom/seam && moon test
```

Expected: 4 new tests pass, all others still pass.

**Step 5: Replace `first_token_text` / `first_token_kind` in `loom/src/core/reuse_cursor.mbt`**

Delete the two private helpers (`first_token_text` and `first_token_kind` functions — grep
to find them).

Rewrite `leading_token_matches` (the only caller):

```moonbit
fn[T, K : @seam.ToRawKind] leading_token_matches(
  node : @seam.CstNode,
  cursor : ReuseCursor[T, K],
  token_pos : Int,
) -> Bool {
  if token_pos >= cursor.token_count {
    return false
  }
  let expected_token = (cursor.get_token)(token_pos)
  let is_trivia = fn(r : @seam.RawKind) {
    r == cursor.spec.whitespace_kind.to_raw()
  }
  match node.first_token(is_trivia) {
    None => false
    Some(tok) =>
      (cursor.spec.cst_token_matches)(tok.kind, tok.text, expected_token)
  }
}
```

**Step 6: Run full test suites**

```bash
cd /path/to/loom/seam && moon test
cd /path/to/loom/loom && moon test
cd /path/to/loom/examples/lambda && moon test
```

Expected: all pass.

**Step 7: Regenerate and commit**

```bash
cd /path/to/loom/seam && moon info && moon fmt
git add seam/cst_node.mbt seam/cst_node_wbtest.mbt seam/pkg.generated.mbti \
        loom/src/core/reuse_cursor.mbt
git commit -m "feat(seam): add CstNode::first_token; remove reuse_cursor private helpers"
```

---

### Task 5: Add `TokenAtOffset` + `SyntaxNode::token_at_offset`

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`
- Modify: `seam/pkg.generated.mbti` (regenerate)

**Step 1: Write failing tests in `seam/syntax_node_wbtest.mbt`**

```moonbit
///|
test "SyntaxNode::token_at_offset: Single (offset inside token)" {
  // token "hello" spans [0,5), query offset=2 → Single
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  match root.token_at_offset(2) {
    Single(t) => inspect(t.text(), content="hello")
    _ => inspect("wrong", content="hello")
  }
}

///|
test "SyntaxNode::token_at_offset: Single (offset at start)" {
  let tok = CstToken::new(RawKind(9), "hi")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  // offset=0 is inside "hi"[0,2) → Single
  match root.token_at_offset(0) {
    Single(t) => inspect(t.text(), content="hi")
    _ => inspect("wrong", content="hi")
  }
}

///|
test "SyntaxNode::token_at_offset: Between (offset at boundary)" {
  // "ab"[0,2) then "cd"[2,4), query offset=2 → Between
  let t1 = CstToken::new(RawKind(9), "ab")
  let t2 = CstToken::new(RawKind(9), "cd")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(t1), CstElement::Token(t2)])
  let root = SyntaxNode::from_cst(cst)
  match root.token_at_offset(2) {
    Between(l, r) => {
      inspect(l.text(), content="ab")
      inspect(r.text(), content="cd")
    }
    _ => inspect("wrong", content="ab")
  }
}

///|
test "SyntaxNode::token_at_offset: None (empty tree)" {
  let cst = CstNode::new(RawKind(22), [])
  let root = SyntaxNode::from_cst(cst)
  match root.token_at_offset(0) {
    TokenAtOffset::None => inspect("none", content="none")
    _ => inspect("wrong", content="none")
  }
}

///|
test "SyntaxNode::token_at_offset: None (offset past end)" {
  let tok = CstToken::new(RawKind(9), "x")
  let cst = CstNode::new(RawKind(22), [CstElement::Token(tok)])
  let root = SyntaxNode::from_cst(cst)
  // "x"[0,1), offset=5 → None
  match root.token_at_offset(5) {
    TokenAtOffset::None => inspect("none", content="none")
    _ => inspect("wrong", content="none")
  }
}
```

**Step 2: Run tests to verify they fail**

```bash
cd /path/to/loom/seam && moon test
```

Expected: compile error — `TokenAtOffset` and `token_at_offset` not found.

**Step 3: Add `TokenAtOffset` enum and `token_at_offset` to `seam/syntax_node.mbt`**

Add the enum near the top of the file (after the `SyntaxElement` enum):

```moonbit
///|
/// Result of a position query on a syntax tree.
///
/// - `None`: no tokens cover the offset (empty tree or out-of-range offset).
/// - `Single`: offset falls strictly inside one token's span.
/// - `Between`: offset sits exactly on the boundary between two adjacent tokens
///   (`left.end() == offset == right.start()`). The IDE caller should prefer
///   the right token for most completion/hover uses.
pub enum TokenAtOffset {
  None
  Single(SyntaxToken)
  Between(SyntaxToken, SyntaxToken)
} derive(Show, Debug, Eq)
```

Add the method to `SyntaxNode`:

```moonbit
///|
/// All leaf tokens in this subtree, depth-first left-to-right, with absolute offsets.
fn SyntaxNode::tokens_dfs(self : SyntaxNode) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  fn collect(node : SyntaxNode) {
    let mut pos = node.offset
    for elem in node.cst.children {
      match elem {
        CstElement::Token(tok) => {
          result.push(SyntaxToken::new(tok, pos))
          pos = pos + tok.text_len()
        }
        CstElement::Node(child_cst) => {
          collect(SyntaxNode::new(child_cst, None, pos))
          pos = pos + child_cst.text_len
        }
      }
    }
  }
  collect(self)
  result
}

///|
/// Find the token(s) at a byte offset.
///
/// Returns `Single` when `offset` falls strictly inside a token's span.
/// Returns `Between` when `offset` sits exactly on the boundary between two
/// adjacent tokens (`left.end() == offset == right.start()`).
/// Returns `None` when no token covers the offset.
pub fn SyntaxNode::token_at_offset(self : SyntaxNode, offset : Int) -> TokenAtOffset {
  let mut left : SyntaxToken? = None
  let mut right : SyntaxToken? = None
  for tok in self.tokens_dfs() {
    if tok.start() <= offset && offset < tok.end() {
      return Single(tok)
    }
    if tok.end() == offset {
      left = Some(tok)
    }
    if tok.start() == offset {
      right = Some(tok)
    }
  }
  match (left, right) {
    (Some(l), Some(r)) => Between(l, r)
    (Some(l), None) => Single(l) // cursor at end of last token
    _ => TokenAtOffset::None
  }
}
```

**Step 4: Run tests and verify they pass**

```bash
cd /path/to/loom/seam && moon test
```

Expected: 5 new tests pass, all previous tests still pass.

**Step 5: Regenerate and commit**

```bash
cd /path/to/loom/seam && moon info && moon fmt
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt seam/pkg.generated.mbti
git commit -m "feat(seam): add TokenAtOffset enum and SyntaxNode::token_at_offset"
```

---

## Phase 2 — T-traits + LanguageSpec T-side cleanup

---

### Task 6: Implement T-traits on Token

**Files:**
- Modify: `examples/lambda/src/token/token.mbt`
- Create: `examples/lambda/src/token/token_test.mbt`
- Modify: `examples/lambda/src/token/pkg.generated.mbti` (regenerate)

**Step 1: Write failing tests in `examples/lambda/src/token/token_test.mbt`**

```moonbit
///|
test "Token: Whitespace is trivia" {
  inspect(@token.Whitespace.is_trivia(), content="true")
}

///|
test "Token: Lambda is not trivia" {
  inspect(@token.Lambda.is_trivia(), content="false")
}

///|
test "Token: EOF is_eof" {
  inspect(@token.EOF.is_eof(), content="true")
}

///|
test "Token: Lambda is not eof" {
  inspect(@token.Lambda.is_eof(), content="false")
}
```

**Step 2: Run tests to verify they fail**

```bash
cd /path/to/loom/examples/lambda && moon test -p dowdiness/lambda/token
```

Expected: compile error — `is_trivia`/`is_eof` not found.

**Step 3: Add trait impls and manual `Show` impl to `token.mbt`**

Replace `derive(Show, Eq)` with `derive(Eq, Debug)` and add manual impls:

```moonbit
} derive(Eq, Debug)
```

Then add below the enum:

```moonbit
///|
pub impl Show for Token with output(self, logger) {
  logger.write_string(
    match self {
      Lambda => "λ"
      Dot => "."
      LeftParen => "("
      RightParen => ")"
      Plus => "+"
      Minus => "-"
      If => "if"
      Then => "then"
      Else => "else"
      Let => "let"
      In => "in"
      Eq => "="
      Identifier(name) => name
      Integer(n) => n.to_string()
      Whitespace => "whitespace"
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
```

**Step 4: Check that existing `Show`-dependent tests still pass**

The existing `print_token` function in `token.mbt` produces the same strings. The manual
`Show` impl should match it. Run:

```bash
cd /path/to/loom/examples/lambda && moon test
```

Expected: all tests pass including the 4 new ones.

**Step 5: Regenerate and commit**

```bash
cd /path/to/loom/examples/lambda && moon info && moon fmt
git add examples/lambda/src/token/token.mbt \
        examples/lambda/src/token/token_test.mbt \
        examples/lambda/src/token/pkg.generated.mbti
git commit -m "feat(lambda): implement IsTrivia, IsEof on Token; manual Show; derive Debug"
```

---

### Task 7: Drop T-side closures from LanguageSpec

**Files:**
- Modify: `loom/src/core/parser.mbt`
- Modify: `loom/src/core/reuse_cursor.mbt`
- Modify: `examples/lambda/src/lambda_spec.mbt`
- Modify: `loom/pkg.generated.mbti` (regenerate)

**Step 1: Remove four fields from `LanguageSpec` struct in `loom/src/core/parser.mbt`**

```moonbit
// REMOVE these four lines from the struct:
  token_is_eof    : (T) -> Bool
  token_is_trivia : (T) -> Bool
  tokens_equal    : (T, T) -> Bool
  print_token     : (T) -> String
```

**Step 2: Update `LanguageSpec::new` constructor**

Add trait bounds `T : Eq + Show + @seam.IsTrivia + @seam.IsEof` and remove the four params:

```moonbit
pub fn[T : Eq + Show + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind] LanguageSpec::new(
  // REMOVE: token_is_eof : (T) -> Bool,
  // REMOVE: token_is_trivia : (T) -> Bool,
  // REMOVE: tokens_equal : (T, T) -> Bool,
  // REMOVE: print_token : (T) -> String,
  whitespace_kind : K,
  error_kind : K,
  root_kind : K,
  eof_token : T,
  cst_token_matches? : ... ,
  parse_root? : ... ,
) -> LanguageSpec[T, K]
```

**Step 3: Replace T-closure call sites in `loom/src/core/parser.mbt`**

Grep for all usages:

```bash
grep -n "token_is_eof\|token_is_trivia\|tokens_equal\|print_token\|spec\.eof" \
  loom/src/core/parser.mbt
```

Replace each pattern:
- `(self.spec.token_is_trivia)(t)` → `t.is_trivia()`
- `(self.spec.token_is_eof)(t)` → `t.is_eof()`
- `(self.spec.tokens_equal)(a, b)` → `a == b`
- `(self.spec.print_token)(t)` → `t.to_string()`

Add `T : Eq + Show + @seam.IsTrivia + @seam.IsEof` to each affected function signature.

**Step 4: Do the same for `reuse_cursor.mbt`**

```bash
grep -n "token_is_eof\|token_is_trivia\|tokens_equal\|print_token" \
  loom/src/core/reuse_cursor.mbt
```

Apply the same replacements. Add trait bounds to affected `fn[T, K]` signatures.

**Step 5: Update `lambda_spec.mbt` — drop four arguments**

```moonbit
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  // REMOVE: fn(t) { t == @token.EOF },          ← was token_is_eof
  // REMOVE: fn(t) { t == @token.Whitespace },    ← was token_is_trivia
  // REMOVE: fn(a, b) { a == b },                 ← was tokens_equal
  // REMOVE: @token.print_token,                  ← was print_token
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  cst_token_matches=...,
  parse_root=parse_lambda_root,
)
```

**Step 6: Run `moon check` across all modules**

```bash
cd /path/to/loom/loom && moon check
cd /path/to/loom/examples/lambda && moon check
```

Fix any remaining compile errors.

**Step 7: Run full test suites**

```bash
cd /path/to/loom/seam && moon test
cd /path/to/loom/loom && moon test
cd /path/to/loom/examples/lambda && moon test
```

Expected: all tests pass.

**Step 8: Regenerate interfaces and commit**

```bash
cd /path/to/loom/loom && moon info && moon fmt
cd /path/to/loom/examples/lambda && moon info && moon fmt
git add loom/src/core/parser.mbt loom/src/core/reuse_cursor.mbt \
        loom/pkg.generated.mbti \
        examples/lambda/src/lambda_spec.mbt \
        examples/lambda/pkg.generated.mbti
git commit -m "refactor(loom): drop T-side closures from LanguageSpec; add T trait bounds"
```

---

## Completion checklist

- [ ] `seam/kind_traits.mbt` exists with all 5 traits
- [ ] `SyntaxKind` implements `ToRawKind`, `FromRawKind`, `IsTrivia`, `IsError`
- [ ] `Token` implements `IsTrivia`, `IsEof`, manual `Show`, `derive(Debug)`
- [ ] `LanguageSpec` has no closure fields except `cst_token_matches` and `parse_root`
- [ ] `LanguageSpec::new` signature matches the above
- [ ] `CstNode::first_token(is_trivia)` exists in seam
- [ ] `TokenAtOffset` enum + `SyntaxNode::token_at_offset` exist in seam
- [ ] `reuse_cursor.mbt` private helpers `first_token_text`/`first_token_kind` deleted
- [ ] `moon test` green in `seam/`, `loom/`, `examples/lambda/`
- [ ] All `.mbti` files regenerated via `moon info && moon fmt`
