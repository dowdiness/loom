# Typed SyntaxNode Views Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `AstNode` with rust-analyzer-style typed view types (`LambdaExprView`, `AppExprView`, etc.) so callers navigate the CST with named, typed accessors instead of raw kind integers and positional children.

**Architecture:** Typed views are thin newtype wrappers over `SyntaxNode` — no separate tree allocation. The framework gets two navigation helpers (`nth_child`, `child_of_kind`) and a minimal `AstView` trait. The lambda example gets eight view types, loses `AstNode`/`cst_convert.mbt`, and wires `Grammar[…, SyntaxNode]` with an identity `to_ast`.

**Tech Stack:** MoonBit, `seam` (CST layer), `loom/core` (parser framework), `examples/lambda` (reference grammar)

**Design doc:** `docs/plans/2026-03-03-typed-syntax-node-views-design.md`

---

## Quick orientation

```
seam/syntax_node.mbt          ← add nth_child, child_of_kind, Eq, ToJson
loom/src/core/lib.mbt         ← add AstView trait
loom/src/loom.mbt             ← export AstView
examples/lambda/src/
  views.mbt                   ← NEW — 8 typed view types
  grammar.mbt                 ← change Ast type to SyntaxNode
  lambda.mbt                  ← update pub API facade
  ast/ast.mbt                 ← delete AstNode/AstKind, keep Term/Bop
  cst_convert.mbt             ← DELETE
  imperative_parser_test.mbt  ← update assertions
  reactive_parser_test.mbt    ← update assertions
  parser_test.mbt             ← update assertions
  parse_tree_test.mbt         ← update assertions
  cst_tree_test.mbt           ← update assertions
  (other *_test.mbt files)    ← scan and update as needed
```

---

## Task 1: Add `nth_child` and `child_of_kind` to seam

**Files:**
- Modify: `seam/syntax_node.mbt`

**Step 1: Write failing tests**

Add to `seam/syntax_node_wbtest.mbt` (or create `seam/syntax_node_helpers_test.mbt`):

```moonbit
///|
test "nth_child: returns None on empty node" {
  let cst = CstNode::new(RawKind(0), [])
  let syn = SyntaxNode::from_cst(cst)
  inspect(syn.nth_child(0) is None, content="true")
}

///|
test "nth_child: returns first interior child" {
  let leaf = CstElement::Node(CstNode::new(RawKind(1), []))
  let root = CstNode::new(RawKind(0), [leaf])
  let syn = SyntaxNode::from_cst(root)
  inspect(syn.nth_child(0) is Some(_), content="true")
}

///|
test "nth_child: skips token children" {
  let tok = CstElement::Token(CstToken::new(RawKind(99), "x"))
  let inner = CstElement::Node(CstNode::new(RawKind(1), []))
  let root = CstNode::new(RawKind(0), [tok, inner])
  let syn = SyntaxNode::from_cst(root)
  // nth_child(0) skips the token, returns the node
  inspect(syn.nth_child(0) is Some(_), content="true")
  // nth_child(1) is None — only one inner node
  inspect(syn.nth_child(1) is None, content="true")
}

///|
test "child_of_kind: finds matching child" {
  let inner = CstElement::Node(CstNode::new(RawKind(7), []))
  let root = CstNode::new(RawKind(0), [inner])
  let syn = SyntaxNode::from_cst(root)
  inspect(syn.child_of_kind(RawKind(7)) is Some(_), content="true")
  inspect(syn.child_of_kind(RawKind(99)) is None, content="true")
}
```

**Step 2: Run tests to verify they fail**

```bash
cd seam && moon test -p dowdiness/seam 2>&1 | head -30
```
Expected: compile error — `nth_child` and `child_of_kind` undefined.

**Step 3: Implement the two methods**

Append to `seam/syntax_node.mbt` (after the `find_at` function):

```moonbit
///|
/// Return the nth interior-node child (0-indexed, skipping token children).
/// Returns None if there are fewer than n+1 interior children.
pub fn SyntaxNode::nth_child(self : SyntaxNode, n : Int) -> SyntaxNode? {
  let mut count = 0
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        if count == n {
          return Some(SyntaxNode::new(child_cst, Some(self), offset))
        }
        count = count + 1
        offset = offset + child_cst.text_len
      }
      CstElement::Token(tok) => offset = offset + tok.text_len()
    }
  }
  None
}

///|
/// First interior-node child whose kind matches `kind`, or None.
pub fn SyntaxNode::child_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxNode? {
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        if child_cst.kind == kind {
          return Some(SyntaxNode::new(child_cst, Some(self), offset))
        }
        offset = offset + child_cst.text_len
      }
      CstElement::Token(tok) => offset = offset + tok.text_len()
    }
  }
  None
}
```

**Step 4: Run tests**

```bash
cd seam && moon test -p dowdiness/seam
```
Expected: all seam tests pass.

**Step 5: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt seam/pkg.generated.mbti
git commit -m "feat(seam): add SyntaxNode::nth_child and child_of_kind"
```

---

## Task 2: Add `Eq` and `ToJson` to `SyntaxNode` in seam

**Files:**
- Modify: `seam/syntax_node.mbt`

**Step 1: Write failing tests**

Add to `seam/syntax_node_wbtest.mbt`:

```moonbit
///|
test "SyntaxNode Eq: same CstNode pointer = equal" {
  let cst = CstNode::new(RawKind(0), [])
  let s1 = SyntaxNode::from_cst(cst)
  let s2 = SyntaxNode::from_cst(cst)
  inspect(s1 == s2, content="true")
}

///|
test "SyntaxNode Eq: different offset = still equal (offset ignored)" {
  let cst = CstNode::new(RawKind(0), [])
  let s1 = SyntaxNode::new(cst, None, 0)
  let s2 = SyntaxNode::new(cst, None, 99)
  inspect(s1 == s2, content="true")
}

///|
test "SyntaxNode Eq: different CstNode kind = not equal" {
  let s1 = SyntaxNode::from_cst(CstNode::new(RawKind(1), []))
  let s2 = SyntaxNode::from_cst(CstNode::new(RawKind(2), []))
  inspect(s1 == s2, content="false")
}

///|
test "SyntaxNode ToJson: produces kind, start, end, children keys" {
  let cst = CstNode::new(RawKind(5), [])
  let syn = SyntaxNode::new(cst, None, 10)
  let j = syn.to_json()
  let s = j.to_string()
  inspect(s.contains("\"kind\""), content="true")
  inspect(s.contains("\"start\""), content="true")
  inspect(s.contains("\"end\""), content="true")
}
```

**Step 2: Run tests to confirm they fail**

```bash
cd seam && moon test -p dowdiness/seam 2>&1 | head -20
```

**Step 3: Implement `Eq` and `ToJson`**

Append to `seam/syntax_node.mbt`:

```moonbit
///|
/// Structure-only equality: two SyntaxNodes are equal iff their underlying
/// CstNodes are equal. Offset and parent are intentionally excluded so that
/// Memo[SyntaxNode] correctly skips recomputation when only positions shift
/// (e.g. after inserting a leading space) but the tree structure is unchanged.
pub impl Eq for SyntaxNode with equal(self, other : SyntaxNode) -> Bool {
  self.cst == other.cst
}

///|
/// Generic JSON serialization of a SyntaxNode.
/// Produces: { "kind": <raw int>, "start": <int>, "end": <int>, "children": [...] }
/// Tokens appear as: { "kind": <raw int>, "text": <string>, "start": <int>, "end": <int> }
/// For typed semantic JSON, use the view types in your language package instead.
pub impl ToJson for SyntaxNode with to_json(self) -> Json {
  let RawKind(k) = self.cst.kind
  let children_json : Array[Json] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        let RawKind(tk) = tok.kind
        children_json.push(
          {
            "kind": (tk : Int),
            "text": tok.text,
            "start": (offset : Int),
            "end": offset + tok.text_len(),
          },
        )
        offset = offset + tok.text_len()
      }
      CstElement::Node(child_cst) => {
        let child_syn = SyntaxNode::new(child_cst, Some(self), offset)
        children_json.push(child_syn.to_json())
        offset = offset + child_cst.text_len
      }
    }
  }
  {
    "kind": (k : Int),
    "start": (self.offset : Int),
    "end": (self.end() : Int),
    "children": children_json,
  }
}
```

**Step 4: Run tests**

```bash
cd seam && moon test -p dowdiness/seam
```

**Step 5: Run seam full test suite**

```bash
cd seam && moon test
```
Expected: all pass.

**Step 6: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt seam/pkg.generated.mbti
git commit -m "feat(seam): add SyntaxNode::Eq (structure-only) and ToJson"
```

---

## Task 3: Add `AstView` trait to loom/core and export it

**Files:**
- Modify: `loom/src/core/lib.mbt`
- Modify: `loom/src/loom.mbt`

**Step 1: Write a failing test**

Add to `loom/src/core/lib.mbt` (at the end of the tests section):

```moonbit
///|
test "AstView: a concrete impl exposes its SyntaxNode" {
  struct FooView { node : @seam.SyntaxNode }
  impl AstView for FooView with syntax_node(self) { self.node }

  let cst = @seam.CstNode::new(@seam.RawKind(0), [])
  let syn = @seam.SyntaxNode::from_cst(cst)
  let v = FooView::{ node: syn }
  inspect(v.syntax_node() == syn, content="true")
}
```

**Step 2: Run test to verify failure**

```bash
cd loom && moon test -p dowdiness/loom/core 2>&1 | head -10
```

**Step 3: Add the trait**

In `loom/src/core/lib.mbt`, insert before the existing tests block (after the `parse_tokens_indexed` function):

```moonbit
///|
/// Marker trait for typed SyntaxNode view types.
///
/// Every view type in your language package should implement this trait
/// and also provide a `pub fn ViewType::cast(n : @seam.SyntaxNode) -> Self?`
/// static function (can't be in the trait — MoonBit traits require self
/// as first parameter).
///
/// Example:
///   pub struct LambdaExprView { node : @seam.SyntaxNode }
///   pub impl AstView for LambdaExprView with syntax_node(self) { self.node }
///   pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? { ... }
pub trait AstView {
  /// Return the underlying raw SyntaxNode.
  syntax_node(Self) -> @seam.SyntaxNode
}
```

**Step 4: Export from `loom/src/loom.mbt`**

Add to the end of `loom/src/loom.mbt`:

```moonbit
///|
// AstView trait — implement for every typed view type in your language package.
pub using @core {trait AstView}
```

**Step 5: Run tests**

```bash
cd loom && moon test
```

**Step 6: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/core/lib.mbt loom/src/loom.mbt loom/src/core/pkg.generated.mbti loom/src/pkg.generated.mbti
git commit -m "feat(loom/core): add AstView trait; export from loom root"
```

---

## Task 4: Create typed view types in examples/lambda

**Files:**
- Create: `examples/lambda/src/views.mbt`
- Modify: `examples/lambda/src/moon.pkg` (add `dowdiness/loom` if not already aliased at root)

**Step 1: Write failing tests first**

Create `examples/lambda/src/views_test.mbt`:

```moonbit
///|
// Tests for typed SyntaxNode view types.

///|
test "LambdaExprView::cast returns Some for LambdaExpr nodes" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  // SourceFile wraps LambdaExpr; find the LambdaExpr child
  let lambda_child = syn.children()[0]
  inspect(LambdaExprView::cast(lambda_child) is Some(_), content="true")
}

///|
test "LambdaExprView::cast returns None for non-lambda nodes" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let int_child = syn.children()[0]
  inspect(LambdaExprView::cast(int_child) is None, content="true")
}

///|
test "LambdaExprView::param returns bound name" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = LambdaExprView::cast(syn.children()[0]).unwrap()
  inspect(view.param(), content="x")
}

///|
test "LambdaExprView::body returns Some for well-formed lambda" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = LambdaExprView::cast(syn.children()[0]).unwrap()
  inspect(view.body() is Some(_), content="true")
}

///|
test "IntLiteralView::value returns parsed integer" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = IntLiteralView::cast(syn.children()[0]).unwrap()
  inspect(view.value(), content="Some(42)")
}

///|
test "VarRefView::name returns identifier text" {
  let (cst, _) = parse_cst_recover("myVar") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = VarRefView::cast(syn.children()[0]).unwrap()
  inspect(view.name(), content="myVar")
}

///|
test "AppExprView::cast returns Some for application" {
  let (cst, _) = parse_cst_recover("f x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = AppExprView::cast(syn.children()[0]).unwrap()
  inspect(view.func() is Some(_), content="true")
  inspect(view.arg() is Some(_), content="true")
}

///|
test "LetExprView::name returns binding name" {
  let (cst, _) = parse_cst_recover("let x = 1 in x") catch {
    _ => abort("lex error")
  }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = LetExprView::cast(syn.children()[0]).unwrap()
  inspect(view.name(), content="x")
}

///|
test "SyntaxNode::to_json produces valid JSON string" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let j = syn.to_json()
  let s = j.to_string()
  inspect(s.contains("\"kind\""), content="true")
}

///|
test "LambdaExprView::to_json includes param and body keys" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let view = LambdaExprView::cast(syn.children()[0]).unwrap()
  let s = view.to_json().to_string()
  inspect(s.contains("\"param\""), content="true")
  inspect(s.contains("\"body\""), content="true")
}
```

**Step 2: Run tests to verify they fail**

```bash
cd examples/lambda && moon test -p dowdiness/lambda 2>&1 | head -20
```

**Step 3: Create `views.mbt`**

Create `examples/lambda/src/views.mbt`:

```moonbit
///|
// Typed SyntaxNode view types for the lambda calculus grammar.
//
// Each view wraps a SyntaxNode and exposes named, typed accessors.
// Use ViewType::cast(n) to narrow a SyntaxNode to a specific view;
// cast returns None when the node's kind doesn't match.
//
// Pattern:
//   let syn = parser.parse()    // SyntaxNode
//   let source = syn.children()[0]
//   match LambdaExprView::cast(source) {
//     Some(v) => println(v.param())
//     None    => ...
//   }

///|
pub struct LambdaExprView {
  node : @seam.SyntaxNode
}

///|
pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.LambdaExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for LambdaExprView with syntax_node(self) {
  self.node
}

///|
/// The bound parameter name (e.g. "x" in λx. body).
pub fn LambdaExprView::param(self : LambdaExprView) -> String {
  self.node
    .find_token(@syntax.IdentToken.to_raw())
    .map(t => t.text())
    .unwrap_or("")
}

///|
/// The body expression (first interior-node child, skipping tokens).
pub fn LambdaExprView::body(self : LambdaExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub impl ToJson for LambdaExprView with to_json(self) -> Json {
  {
    "kind": "LambdaExpr",
    "param": self.param(),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "body": match self.body() {
      Some(b) => b.to_json()
      None => Json::Null
    },
  }
}

// ─── AppExpr ─────────────────────────────────────────────────────────────────

///|
pub struct AppExprView {
  node : @seam.SyntaxNode
}

///|
pub fn AppExprView::cast(n : @seam.SyntaxNode) -> AppExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.AppExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for AppExprView with syntax_node(self) {
  self.node
}

///|
/// The function being applied (first interior-node child).
pub fn AppExprView::func(self : AppExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
/// The argument (second interior-node child).
pub fn AppExprView::arg(self : AppExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
pub impl ToJson for AppExprView with to_json(self) -> Json {
  {
    "kind": "AppExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "func": match self.func() {
      Some(n) => n.to_json()
      None => Json::Null
    },
    "arg": match self.arg() {
      Some(n) => n.to_json()
      None => Json::Null
    },
  }
}

// ─── BinaryExpr ──────────────────────────────────────────────────────────────

///|
pub struct BinaryExprView {
  node : @seam.SyntaxNode
}

///|
pub fn BinaryExprView::cast(n : @seam.SyntaxNode) -> BinaryExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.BinaryExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for BinaryExprView with syntax_node(self) {
  self.node
}

///|
pub fn BinaryExprView::lhs(self : BinaryExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub fn BinaryExprView::rhs(self : BinaryExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
/// The operator kind: Plus or Minus, from the first operator token found.
pub fn BinaryExprView::op(self : BinaryExprView) -> @ast.Bop? {
  for elem in self.node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(t) =>
        if t.kind() == @syntax.PlusToken.to_raw() {
          return Some(@ast.Bop::Plus)
        } else if t.kind() == @syntax.MinusToken.to_raw() {
          return Some(@ast.Bop::Minus)
        }
      _ => ()
    }
  }
  None
}

///|
pub impl ToJson for BinaryExprView with to_json(self) -> Json {
  {
    "kind": "BinaryExpr",
    "op": match self.op() {
      Some(Plus) => "+"
      Some(Minus) => "-"
      None => "?"
    },
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "lhs": match self.lhs() {
      Some(n) => n.to_json()
      None => Json::Null
    },
    "rhs": match self.rhs() {
      Some(n) => n.to_json()
      None => Json::Null
    },
  }
}

// ─── IfExpr ──────────────────────────────────────────────────────────────────

///|
pub struct IfExprView {
  node : @seam.SyntaxNode
}

///|
pub fn IfExprView::cast(n : @seam.SyntaxNode) -> IfExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.IfExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for IfExprView with syntax_node(self) {
  self.node
}

///|
pub fn IfExprView::condition(self : IfExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub fn IfExprView::then_branch(self : IfExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
pub fn IfExprView::else_branch(self : IfExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(2)
}

///|
pub impl ToJson for IfExprView with to_json(self) -> Json {
  {
    "kind": "IfExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "condition": match self.condition() {
      Some(n) => n.to_json()
      None => Json::Null
    },
    "then": match self.then_branch() {
      Some(n) => n.to_json()
      None => Json::Null
    },
    "else": match self.else_branch() {
      Some(n) => n.to_json()
      None => Json::Null
    },
  }
}

// ─── LetExpr ─────────────────────────────────────────────────────────────────

///|
pub struct LetExprView {
  node : @seam.SyntaxNode
}

///|
pub fn LetExprView::cast(n : @seam.SyntaxNode) -> LetExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.LetExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for LetExprView with syntax_node(self) {
  self.node
}

///|
/// The binding name (first IdentToken in the node).
pub fn LetExprView::name(self : LetExprView) -> String {
  self.node
    .find_token(@syntax.IdentToken.to_raw())
    .map(t => t.text())
    .unwrap_or("")
}

///|
/// The init expression (first interior-node child).
pub fn LetExprView::init(self : LetExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
/// The body expression (second interior-node child).
pub fn LetExprView::body(self : LetExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
pub impl ToJson for LetExprView with to_json(self) -> Json {
  {
    "kind": "LetExpr",
    "name": self.name(),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "init": match self.init() {
      Some(n) => n.to_json()
      None => Json::Null
    },
    "body": match self.body() {
      Some(n) => n.to_json()
      None => Json::Null
    },
  }
}

// ─── ParenExpr ───────────────────────────────────────────────────────────────

///|
pub struct ParenExprView {
  node : @seam.SyntaxNode
}

///|
pub fn ParenExprView::cast(n : @seam.SyntaxNode) -> ParenExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.ParenExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for ParenExprView with syntax_node(self) {
  self.node
}

///|
pub fn ParenExprView::inner(self : ParenExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub impl ToJson for ParenExprView with to_json(self) -> Json {
  {
    "kind": "ParenExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "inner": match self.inner() {
      Some(n) => n.to_json()
      None => Json::Null
    },
  }
}

// ─── IntLiteral ──────────────────────────────────────────────────────────────

///|
pub struct IntLiteralView {
  node : @seam.SyntaxNode
}

///|
pub fn IntLiteralView::cast(n : @seam.SyntaxNode) -> IntLiteralView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.IntLiteral {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for IntLiteralView with syntax_node(self) {
  self.node
}

///|
/// Parse and return the integer value. Returns None if the token text is not
/// a valid integer (should not happen in a well-formed tree).
pub fn IntLiteralView::value(self : IntLiteralView) -> Int? {
  self.node
    .find_token(@syntax.IntToken.to_raw())
    .map(t => @strconv.parse_int(t.text()) catch { _ => return None })
}

///|
pub impl ToJson for IntLiteralView with to_json(self) -> Json {
  {
    "kind": "IntLiteral",
    "value": match self.value() {
      Some(v) => (v : Int)
      None => 0
    },
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
  }
}

// ─── VarRef ──────────────────────────────────────────────────────────────────

///|
pub struct VarRefView {
  node : @seam.SyntaxNode
}

///|
pub fn VarRefView::cast(n : @seam.SyntaxNode) -> VarRefView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.VarRef {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @loom.AstView for VarRefView with syntax_node(self) {
  self.node
}

///|
pub fn VarRefView::name(self : VarRefView) -> String {
  self.node
    .find_token(@syntax.IdentToken.to_raw())
    .map(t => t.text())
    .unwrap_or("")
}

///|
pub impl ToJson for VarRefView with to_json(self) -> Json {
  {
    "kind": "VarRef",
    "name": self.name(),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
  }
}
```

**Step 4: Verify `moon.pkg` has `dowdiness/loom` and `dowdiness/seam` imports**

Check `examples/lambda/src/moon.pkg`. It should already have these since `grammar.mbt` uses `@loom.Grammar`. If `@seam` isn't explicitly imported but is re-exported through `@loom`, it may still work. Run `moon check` to find out:

```bash
cd examples/lambda && moon check 2>&1 | head -30
```

If you see "unresolved import" for `@seam`, add `"dowdiness/seam" @seam` to the import block in `examples/lambda/src/moon.pkg`.

**Step 5: Run view tests**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f views_test.mbt
```
Expected: all pass.

**Step 6: Run full lambda test suite**

```bash
cd examples/lambda && moon test
```
Expected: all 293+ tests pass (views are additive at this point).

**Step 7: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/views.mbt examples/lambda/src/views_test.mbt examples/lambda/src/moon.pkg examples/lambda/src/pkg.generated.mbti
git commit -m "feat(lambda): add typed SyntaxNode view types (LambdaExprView, AppExprView, etc.)"
```

---

## Task 5: Add `syntax_node_to_term` using views

**Files:**
- Modify: `examples/lambda/src/cst_convert.mbt` (add function; will be deleted in Task 8)

**Step 1: Write failing test**

Add to `examples/lambda/src/views_test.mbt`:

```moonbit
///|
test "syntax_node_to_term: integer" {
  let (cst, _) = parse_cst_recover("42") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(syn)
  inspect(term, content="Int(42)")
}

///|
test "syntax_node_to_term: lambda" {
  let (cst, _) = parse_cst_recover("λx.x") catch { _ => abort("lex error") }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(syn)
  inspect(term, content="Lam(\"x\", Var(\"x\"))")
}

///|
test "syntax_node_to_term: let binding" {
  let (cst, _) = parse_cst_recover("let x = 1 in x") catch {
    _ => abort("lex error")
  }
  let syn = @seam.SyntaxNode::from_cst(cst)
  let term = syntax_node_to_term(syn)
  inspect(term, content="Let(\"x\", Int(1), Var(\"x\"))")
}
```

**Step 2: Run tests to confirm failure**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f views_test.mbt 2>&1 | head -10
```

**Step 3: Add `syntax_node_to_term` to `cst_convert.mbt`**

Append to `examples/lambda/src/cst_convert.mbt`:

```moonbit
///|
/// Convert a SyntaxNode to a Term using typed view types.
/// Replaces the old AstNode-based path: SyntaxNode → AstNode → Term.
/// SourceFile wraps the actual expression in a single child; this function
/// unwraps it automatically.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  // SourceFile is the top-level wrapper; descend to the actual expression.
  let node = match @syntax.SyntaxKind::from_raw(root.kind()) {
    @syntax.SourceFile =>
      match root.nth_child(0) {
        Some(child) => child
        None => return @ast.Term::Var("<empty>")
      }
    _ => root
  }
  view_to_term(node)
}

///|
fn view_to_term(node : @seam.SyntaxNode) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral =>
      match IntLiteralView::cast(node) {
        Some(v) => @ast.Term::Int(v.value().or(0))
        None => @ast.Term::Var("<error>")
      }
    @syntax.VarRef =>
      match VarRefView::cast(node) {
        Some(v) => @ast.Term::Var(v.name())
        None => @ast.Term::Var("<error>")
      }
    @syntax.LambdaExpr =>
      match LambdaExprView::cast(node) {
        Some(v) => {
          let body = match v.body() {
            Some(b) => view_to_term(b)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Lam(v.param(), body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.AppExpr =>
      match AppExprView::cast(node) {
        Some(v) => {
          let func = match v.func() {
            Some(f) => view_to_term(f)
            None => @ast.Term::Var("<error>")
          }
          // AppExpr can have multiple arguments; fold left
          let children = node.children()
          if children.length() >= 2 {
            let mut result = view_to_term(children[0])
            for i = 1; i < children.length(); i = i + 1 {
              result = @ast.Term::App(result, view_to_term(children[i]))
            }
            result
          } else {
            func
          }
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.BinaryExpr =>
      match BinaryExprView::cast(node) {
        Some(v) => {
          let lhs = match v.lhs() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let rhs = match v.rhs() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let op = v.op().or(@ast.Bop::Plus)
          @ast.Term::Bop(op, lhs, rhs)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.IfExpr =>
      match IfExprView::cast(node) {
        Some(v) => {
          let cond = match v.condition() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let then_ = match v.then_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let else_ = match v.else_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::If(cond, then_, else_)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.LetExpr =>
      match LetExprView::cast(node) {
        Some(v) => {
          let init = match v.init() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let body = match v.body() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Let(v.name(), init, body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.ParenExpr =>
      match ParenExprView::cast(node) {
        Some(v) => match v.inner() {
          Some(inner) => view_to_term(inner)
          None => @ast.Term::Var("<error>")
        }
        None => @ast.Term::Var("<error>")
      }
    _ => @ast.Term::Var("<error: " + node.kind().to_string() + ">")
  }
}
```

**Step 4: Run tests**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f views_test.mbt
```

**Step 5: Run full test suite**

```bash
cd examples/lambda && moon test
```

**Step 6: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/cst_convert.mbt examples/lambda/src/views_test.mbt examples/lambda/src/pkg.generated.mbti
git commit -m "feat(lambda): add syntax_node_to_term via typed views"
```

---

## Task 6: Rewire `lambda_grammar` to use `SyntaxNode` as `Ast`

**Files:**
- Modify: `examples/lambda/src/grammar.mbt`
- Modify: `examples/lambda/src/lambda.mbt`

**Orientation:** `grammar.mbt` defines `lambda_grammar : Grammar[Token, SyntaxKind, AstNode]`. We change the `Ast` type to `@seam.SyntaxNode`. The `to_ast` callback becomes identity (returns the `SyntaxNode` as-is). The `on_lex_error` returns an error `SyntaxNode`.

**Step 1: Update `grammar.mbt`**

Replace the entire file content:

```moonbit
///|
/// Lambda calculus grammar description.
///
/// This is the complete integration surface — a single value that
/// bridge factories consume to produce ImperativeParser or ReactiveParser.
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @seam.SyntaxNode,
] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  // Identity: the SyntaxNode IS the Ast. Callers use typed views to navigate.
  to_ast=fn(s) { s },
  // On lex error: create a minimal error SyntaxNode.
  on_lex_error=fn(_msg) {
    let cst = @seam.CstNode::new(
      @syntax.ErrorNode.to_raw(),
      [],
    )
    @seam.SyntaxNode::from_cst(cst)
  },
)
```

**Step 2: Update `lambda.mbt` public API facade**

In `examples/lambda/src/lambda.mbt`, update the public exports. The file becomes:

```moonbit
///|
// Public API facade for dowdiness/lambda.

///|
// AST types — Term and Bop remain for evaluation; AstNode is removed.
pub using @ast {type Term, type Bop, type VarName}

///|
// Typed view types — primary tree navigation API.
// Import `dowdiness/lambda` and use these to navigate parse results.
pub using @seam {type SyntaxNode, type SyntaxToken, type SyntaxElement}

///|
// Edit primitive — apply incremental updates to the parser
pub using @core {type Edit}

///|
// Incremental engine — the primary type for incremental parsing
pub using @incremental {type ImperativeParser}

///|
/// Create a lambda calculus ImperativeParser, pre-configured with the lambda
/// grammar. The grammar is baked in — pass only the initial source string.
/// The parser returns SyntaxNode; use typed view types to navigate the tree.
pub fn new_imperative_parser(
  source : String,
) -> @incremental.ImperativeParser[@seam.SyntaxNode] {
  @loom.new_imperative_parser(source, lambda_grammar)
}
```

**Step 3: Run `moon check` to see compile errors**

```bash
cd examples/lambda && moon check 2>&1 | head -40
```

Note down every error — these are the tests/files that still reference `AstNode`. Work through them in Task 7.

**Step 4: Commit what compiles so far**

```bash
cd examples/lambda && moon fmt
git add examples/lambda/src/grammar.mbt examples/lambda/src/lambda.mbt examples/lambda/src/pkg.generated.mbti
git commit -m "refactor(lambda): change Grammar Ast type from AstNode to SyntaxNode"
```

---

## Task 7: Update all tests and callsites that used `AstNode`

**Files (scan with `moon check` output from Task 6):**
Likely: `imperative_parser_test.mbt`, `reactive_parser_test.mbt`, `parser_test.mbt`, `parse_tree_test.mbt`, `cst_tree_test.mbt`, benchmarks.

**Orientation:** Tests previously did:
```moonbit
let tree = parser.parse()     // → AstNode
inspect(@ast.print_ast_node(tree), content="(λx. x)")
match tree.kind { @ast.AstKind::Lam("x") => () }
```

After the change, `parser.parse()` returns `SyntaxNode`. Update tests to use:
- Views for structural checks: `LambdaExprView::cast(tree.children()[0]).unwrap().param()`
- `syntax_node_to_term` for semantic checks (Term's `Show` = `"Lam(\"x\", Var(\"x\"))"`)
- `SyntaxNode.to_json()` or view `.to_json()` for serialization checks

**Step 1: Work through each failing file**

For each file with errors, apply this pattern:

*Old (AstNode):*
```moonbit
let tree = parser.parse()
inspect(@ast.print_ast_node(tree), content="(λx. x)")
```

*New (SyntaxNode via views):*
```moonbit
let tree = parser.parse()
let term = syntax_node_to_term(tree)
inspect(@ast.print_term(term), content="(λx. x)")
```

For match on `AstKind`:
```moonbit
// Old:
match db.term().kind { @ast.AstKind::Lam("x") => () ... }

// New:
match LambdaExprView::cast(db.term().children()[0]) {
  Some(v) => assert_eq(v.param(), "x")
  None => abort("expected LambdaExpr")
}
```

For `ReactiveParser`, `db.term()` now returns `SyntaxNode`. The `inspect(db.term(), content=...)` snapshot tests need regeneration: run `moon test --update` after fixing compile errors.

**Step 2: Fix `reactive_parser_test.mbt`**

This test heavily uses `@ast.AstKind`. Rewrite each test. Key pattern:

```moonbit
// Old: inspect db.term() as AstNode
inspect(
  db.term(),
  content=(#|{kind: Bop(Plus), start: 0, end: 5, ...}),
)

// New: use syntax_node_to_term then inspect Term
let term = syntax_node_to_term(db.term())
inspect(term, content="Bop(Plus, Int(1), Int(2))")
```

For the parity test (ReactiveParser vs direct parse), update to compare `syntax_node_to_term` outputs:
```moonbit
let direct_term = syntax_node_to_term(parse_cst_recover(source).0)
let reactive_term = syntax_node_to_term(db.term())
assert_eq(direct_term, reactive_term)
```

Note: `parse_cst_to_ast_node` no longer exists. Replace with `parse_cst_recover` + `syntax_node_to_term`.

**Step 3: Run tests and update snapshots**

```bash
cd examples/lambda && moon test 2>&1 | head -50
```

If only snapshot mismatches remain:
```bash
cd examples/lambda && moon test --update
```

Verify the updated snapshots look correct (check `git diff`).

**Step 4: Run full suite clean**

```bash
cd examples/lambda && moon test
```
Expected: all tests pass.

**Step 5: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/
git commit -m "refactor(lambda): update all tests to use SyntaxNode and typed views"
```

---

## Task 8: Delete `AstNode`/`AstKind` from `ast/ast.mbt` and delete `cst_convert.mbt`

**Orientation:** `AstNode` and `AstKind` should have no remaining references after Task 7. Verify, then delete.

**Step 1: Confirm no remaining references**

```bash
grep -rn "AstNode\|AstKind\|print_ast_node\|parse_cst_to_ast_node\|cst_to_ast\|syntax_node_to_ast_node" \
  examples/lambda/src/ | grep -v "_build" | grep -v "cst_convert.mbt"
```
Expected: no output (all references cleared in Task 7).

**Step 2: Shrink `ast/ast.mbt`**

Delete everything in `examples/lambda/src/ast/ast.mbt` except `Term`, `Bop`, `VarName`, `print_term`, and `node_to_term` is already gone. The file should become:

```moonbit
// Semantic AST types for Lambda Calculus.
// AstNode was removed — use typed SyntaxNode view types instead.

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson)

///|
pub(all) enum Term {
  Int(Int)
  Var(VarName)
  Lam(VarName, Term)
  App(Term, Term)
  Bop(Bop, Term, Term)
  If(Term, Term, Term)
  Let(VarName, Term, Term)
} derive(Show, Eq)

///|
pub fn print_term(term : Term) -> String {
  fn go(t : Term) -> String {
    match t {
      Int(i) => i.to_string()
      Var(x) => x
      Lam(x, t) => "(λ" + x + ". " + go(t) + ")"
      App(t1, t2) => "(" + go(t1) + " " + go(t2) + ")"
      Bop(Plus, t1, t2) => "(" + go(t1) + " + " + go(t2) + ")"
      Bop(Minus, t1, t2) => "(" + go(t1) + " - " + go(t2) + ")"
      If(t1, t2, t3) => "if " + go(t1) + " then " + go(t2) + " else " + go(t3)
      Let(x, init, body) => "let " + x + " = " + go(init) + " in " + go(body)
    }
  }
  go(term)
}
```

**Step 3: Delete `cst_convert.mbt`** (the old conversion; `syntax_node_to_term` and `view_to_term` moved in Task 5 to a new location)

Wait — in Task 5 we *appended* to `cst_convert.mbt`. Now delete the old content and keep only `syntax_node_to_term` + `view_to_term`. The easiest path: rename `cst_convert.mbt` to `term_convert.mbt` and remove all AstNode functions.

```bash
git mv examples/lambda/src/cst_convert.mbt examples/lambda/src/term_convert.mbt
```

Edit `term_convert.mbt` to remove all functions referencing `AstNode`:
- Delete: `convert_source_file_children`, `convert_syntax_node`, `syntax_node_to_ast_node`, `cst_to_ast_node`, `cst_to_term`, `parse_cst_to_ast_node`
- Keep: `syntax_node_to_term`, `view_to_term`

**Step 4: Run `moon check`**

```bash
cd examples/lambda && moon check 2>&1 | head -20
```
Expected: no errors.

**Step 5: Run full test suite**

```bash
cd examples/lambda && moon test
```
Expected: all tests pass.

**Step 6: Commit**

```bash
cd examples/lambda && moon info && moon fmt
git add examples/lambda/src/ast/ast.mbt examples/lambda/src/term_convert.mbt examples/lambda/src/pkg.generated.mbti
git rm examples/lambda/src/cst_convert.mbt
git commit -m "refactor(lambda): delete AstNode/AstKind and cst_convert; keep Term and view-based term_convert"
```

---

## Task 9: Add memoization correctness test for `Memo[SyntaxNode]`

**Files:**
- Modify: `examples/lambda/src/reactive_parser_test.mbt`

**Goal:** Verify that a whitespace-only edit does not trigger AST recomputation — the reactive memo should skip `to_ast` because the interned `CstNode` is unchanged, and `SyntaxNode.Eq` returns true.

**Step 1: Write the test**

Add to `examples/lambda/src/reactive_parser_test.mbt`:

```moonbit
///|
/// A whitespace-only edit shifts positions but leaves the interned CstNode
/// unchanged. SyntaxNode::Eq is structure-only (CstNode equality, ignoring
/// offset), so Memo[SyntaxNode] correctly skips recomputation.
/// We verify this indirectly: the SyntaxNode returned before and after the
/// whitespace-only edit must be equal (by our Eq impl).
test "ReactiveParser: whitespace-only edit preserves SyntaxNode Eq" {
  let db = @loom.new_reactive_parser("λx.x", lambda_grammar)
  let t1 = db.term()
  db.set_source(" λx.x") // prepend space — shifts all positions
  let t2 = db.term()
  // SyntaxNode::Eq ignores offset; same CstNode structure = equal
  assert_eq(t1 == t2, true)
}
```

**Step 2: Run the test**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f reactive_parser_test.mbt
```
Expected: pass.

**Step 3: Commit**

```bash
git add examples/lambda/src/reactive_parser_test.mbt
git commit -m "test(lambda): verify Memo[SyntaxNode] skips recomputation on whitespace-only edits"
```

---

## Task 10: Final verification across all packages

**Step 1: Run loom full suite**

```bash
cd loom && moon test
```

**Step 2: Run seam full suite**

```bash
cd seam && moon test
```

**Step 3: Run lambda full suite with count**

```bash
cd examples/lambda && moon test 2>&1 | tail -5
```
Expected output line: something like `test result: ok. 293 passed; 0 failed`

**Step 4: Run incr suite (should be unaffected)**

```bash
cd incr && moon test
```

**Step 5: Run docs check**

```bash
bash check-docs.sh
```

**Step 6: Final commit if any formatting drift**

```bash
cd seam && moon info && moon fmt
cd loom && moon info && moon fmt
cd examples/lambda && moon info && moon fmt
git add seam/ loom/ examples/lambda/
git commit -m "chore: regenerate .mbti interfaces and format after typed views migration"
```

---

## Task 11: Update docs

**Files:**
- Modify: `docs/plans/2026-03-03-typed-syntax-node-views-design.md` — add `**Status:** Complete`
- Move plan to archive: `git mv docs/plans/2026-03-03-typed-syntax-node-views-design.md docs/archive/completed-phases/`
- Modify: `docs/README.md` — move entry from Active Plans → Archive
- Modify: `ROADMAP.md` — mark Typed SyntaxNode Views as ✅ Complete
- Modify: `examples/lambda/ROADMAP.md` — mark Typed SyntaxNode Views as ✅ Complete

**Step 1: Update design doc status**

In `docs/plans/2026-03-03-typed-syntax-node-views-design.md`, change the Status line to:
```
**Status:** Complete
```

**Step 2: Archive the plan**

```bash
git mv docs/plans/2026-03-03-typed-syntax-node-views-design.md \
        docs/archive/completed-phases/2026-03-03-typed-syntax-node-views-design.md
```

**Step 3: Update `docs/README.md`**

Move the plan entry from "Active Plans" to "Archive":
```markdown
## Archive (Historical / Completed)

- [archive/completed-phases/2026-03-03-typed-syntax-node-views-design.md](archive/completed-phases/2026-03-03-typed-syntax-node-views-design.md) — typed views design (rust-analyzer model, AstNode removed)
- ...
```
Remove the "Active Plans" section (or leave it empty if no other plans exist).

**Step 4: Update ROADMAP.md**

Find the "Typed SyntaxNode Views" entry and change:
```
| Typed SyntaxNode Views | Future — Confidence: High |
```
to:
```
| Typed SyntaxNode Views | ✅ Complete (2026-03-03) |
```
And add a Completed entry in the Completed Work section.

**Step 5: Verify docs check**

```bash
bash check-docs.sh
```

**Step 6: Commit**

```bash
git add docs/ ROADMAP.md examples/lambda/ROADMAP.md
git commit -m "docs: archive typed SyntaxNode views plan; mark complete in ROADMAP"
```

---

## Quick Reference

**Run tests for one package:**
```bash
cd seam && moon test
cd loom && moon test
cd examples/lambda && moon test
```

**Run a single test file:**
```bash
cd examples/lambda && moon test -p dowdiness/lambda -f reactive_parser_test.mbt
```

**Check interfaces after changes:**
```bash
moon info && moon fmt
```

**MoonBit pattern: `Option.or(default)`**
```moonbit
self.value().or(0)          // Int? → Int with default 0
```

**MoonBit pattern: match on kind**
```moonbit
match @syntax.SyntaxKind::from_raw(node.kind()) {
  @syntax.LambdaExpr => ...
  _ => ...
}
```

**MoonBit pattern: `Array[Json]` literal**
In ToJson impls, build children with:
```moonbit
let children_json : Array[Json] = []
children_json.push(...)
```

**When in doubt:** `moon check` first, fix compile errors before running tests.
