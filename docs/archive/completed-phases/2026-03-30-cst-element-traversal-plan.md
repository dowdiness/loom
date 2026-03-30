# CstElement Traversal Methods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port 7 closure methods + Finder trait from cst-transform research module to seam's `CstElement`, giving downstream parsers a standard traversal toolkit.

**Architecture:** Add a single new file `seam/cst_traverse.mbt` with all traversal methods and `Finder` trait. Tests in `seam/cst_traverse_wbtest.mbt` (whitebox — consistent with seam convention). Each method is a mechanical translation from `cst-transform/src/green_node.mbt`, replacing `GreenNode::Leaf/Branch` with `CstElement::Token/Node`.

**Tech Stack:** MoonBit, seam module (`dowdiness/seam`)

---

## File Structure

| File | Action | Content |
|------|--------|---------|
| `seam/cst_traverse.mbt` | Create | `transform`, `fold`, `transform_fold`, `each`, `iter`, `map`, `Finder` trait, `find` |
| `seam/cst_traverse_wbtest.mbt` | Create | Whitebox tests for all 7 methods + `find` |

## Test Tree Convention

All tests use this tree structure with explicit `RawKind` values:

```
SourceFile(RawKind(20))
├── Token(RawKind(9), "foo")
├── Token(RawKind(11), " ")
├── BinaryExpr(RawKind(21))
│   ├── Token(RawKind(10), "1")
│   ├── Token(RawKind(12), "+")
│   └── Token(RawKind(10), "2")
└── Token(RawKind(13), "")
```

Helper function in test file:

```moonbit
fn make_test_tree() -> CstElement {
  let foo = CstToken::new(RawKind(9), "foo")
  let ws = CstToken::new(RawKind(11), " ")
  let one = CstToken::new(RawKind(10), "1")
  let plus = CstToken::new(RawKind(12), "+")
  let two = CstToken::new(RawKind(10), "2")
  let eof = CstToken::new(RawKind(13), "")
  let bin_expr = CstNode::new(RawKind(21), [
    CstElement::Token(one),
    CstElement::Token(plus),
    CstElement::Token(two),
  ])
  let root = CstNode::new(RawKind(20), [
    CstElement::Token(foo),
    CstElement::Token(ws),
    CstElement::Node(bin_expr),
    CstElement::Token(eof),
  ])
  CstElement::Node(root)
}
```

---

### Task 1: `transform` and `fold`

**Files:**
- Create: `seam/cst_traverse.mbt`
- Create: `seam/cst_traverse_wbtest.mbt`

- [ ] **Step 1: Write failing tests for `transform` and `fold`**

Create `seam/cst_traverse_wbtest.mbt` with the test helper and two tests:

```moonbit
///|
fn make_test_tree() -> CstElement {
  let foo = CstToken::new(RawKind(9), "foo")
  let ws = CstToken::new(RawKind(11), " ")
  let one = CstToken::new(RawKind(10), "1")
  let plus = CstToken::new(RawKind(12), "+")
  let two = CstToken::new(RawKind(10), "2")
  let eof = CstToken::new(RawKind(13), "")
  let bin_expr = CstNode::new(RawKind(21), [
    CstElement::Token(one),
    CstElement::Token(plus),
    CstElement::Token(two),
  ])
  let root = CstNode::new(RawKind(20), [
    CstElement::Token(foo),
    CstElement::Token(ws),
    CstElement::Node(bin_expr),
    CstElement::Token(eof),
  ])
  CstElement::Node(root)
}

///|
test "transform: reconstruct source text" {
  let tree = make_test_tree()
  let result = tree.transform(
    fn(token) { token.text },
    fn(_kind, children) {
      let mut s = ""
      for child in children {
        s = s + child
      }
      s
    },
  )
  inspect!(result, content="foo 1+2")
}

///|
test "transform: count nodes" {
  let tree = make_test_tree()
  let result = tree.transform(
    fn(_token) { 1 },
    fn(_kind, children) {
      let mut sum = 1
      for child in children {
        sum = sum + child
      }
      sum
    },
  )
  // 2 branch nodes + 6 leaf tokens = 8
  inspect!(result, content="8")
}

///|
test "transform: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let result = elem.transform(fn(t) { t.text }, fn(_k, _c) { "" })
  inspect!(result, content="x")
}

///|
test "fold: sum text lengths" {
  let tree = make_test_tree()
  let result = tree.fold(
    fn(token) { token.text.length() },
    fn(a, b) { a + b },
    0,
  )
  // "foo" + " " + "1" + "+" + "2" + "" = 7
  inspect!(result, content="7")
}

///|
test "fold: count tokens only" {
  let tree = make_test_tree()
  let result = tree.fold(fn(_token) { 1 }, fn(a, b) { a + b }, 0)
  // 6 leaf tokens
  inspect!(result, content="6")
}

///|
test "fold: single token" {
  let tok = CstToken::new(RawKind(10), "42")
  let elem = CstElement::Token(tok)
  let result = elem.fold(fn(t) { t.text.length() }, fn(a, b) { a + b }, 0)
  inspect!(result, content="2")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt 2>&1 | head -20`
Expected: compilation errors — `transform` and `fold` not defined on `CstElement`

- [ ] **Step 3: Implement `transform` and `fold`**

Create `seam/cst_traverse.mbt`:

```moonbit
// cst_traverse.mbt — Closure-based traversal methods for CstElement.
//
// Ported from cst-transform/ research module. See cst-transform/REPORT.md
// for performance characteristics.

///|
/// Bottom-up structure-preserving transformation.
///
/// Leaves are mapped by `on_token`; interior nodes by `on_node` which
/// receives the node's kind and an `Array[R]` of already-transformed children.
pub fn[R] CstElement::transform(
  self : CstElement,
  on_token : (CstToken) -> R,
  on_node : (RawKind, Array[R]) -> R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) => {
      let results = Array::new(capacity=node.children.length())
      for child in node.children {
        results.push(child.transform(on_token, on_node))
      }
      on_node(node.kind, results)
    }
  }
}

///|
/// Monoid catamorphism — folds leaf results with `combine` without
/// allocating an intermediate `Array[R]`.
///
/// **Warning:** `empty` is shared by reference. Use only value-type
/// accumulators (Int, String). For Array collection, use `transform` instead.
pub fn[R] CstElement::fold(
  self : CstElement,
  on_token : (CstToken) -> R,
  combine : (R, R) -> R,
  empty : R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) =>
      for child in node.children; acc = empty {
        continue combine(acc, child.fold(on_token, combine, empty))
      } nobreak {
        acc
      }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt`
Expected: all 6 tests pass

- [ ] **Step 5: Commit**

```bash
git add seam/cst_traverse.mbt seam/cst_traverse_wbtest.mbt
git commit -m "feat(seam): add CstElement::transform and CstElement::fold"
```

---

### Task 2: `transform_fold` and `each`

**Files:**
- Modify: `seam/cst_traverse.mbt`
- Modify: `seam/cst_traverse_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Append to `seam/cst_traverse_wbtest.mbt`:

```moonbit
///|
test "transform_fold: node count" {
  let tree = make_test_tree()
  let result = tree.transform_fold(
    fn(_token) { 1 },
    fn(_kind) { 1 },
    fn(_kind, acc, child) { acc + child },
  )
  // 2 branch nodes + 6 tokens = 8
  inspect!(result, content="8")
}

///|
test "transform_fold: single token" {
  let tok = CstToken::new(RawKind(10), "7")
  let elem = CstElement::Token(tok)
  let result = elem.transform_fold(
    fn(t) { t.text.length() },
    fn(_kind) { 0 },
    fn(_kind, acc, child) { acc + child },
  )
  inspect!(result, content="1")
}

///|
test "each: visits all nodes and can terminate early" {
  let tree = make_test_tree()
  let mut count = 0
  let completed = tree.each(fn(_elem) {
    count = count + 1
    true
  })
  inspect!(completed, content="true")
  // 2 branch nodes + 6 tokens = 8
  inspect!(count, content="8")
}

///|
test "each: early termination" {
  let tree = make_test_tree()
  let mut count = 0
  let completed = tree.each(fn(elem) {
    count = count + 1
    // Stop at first Token with kind 10 (Number)
    match elem {
      CstElement::Token(t) => t.kind != RawKind(10)
      _ => true
    }
  })
  inspect!(completed, content="false")
  // Root(20) -> Token(9,"foo") -> Token(11," ") -> BinaryExpr(21) -> Token(10,"1") stops
  inspect!(count, content="5")
}

///|
test "each: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let mut visited = false
  let _ = elem.each(fn(_e) { visited = true; true })
  inspect!(visited, content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt 2>&1 | head -20`
Expected: compilation errors — `transform_fold` and `each` not defined

- [ ] **Step 3: Implement `transform_fold` and `each`**

Append to `seam/cst_traverse.mbt`:

```moonbit
///|
/// Fused transform+fold: avoids `Array[R]` allocation.
///
/// Like `transform`, processes children bottom-up. Instead of collecting
/// into an Array, folds inline: `on_child(kind, accumulator, child_result)`.
pub fn[R] CstElement::transform_fold(
  self : CstElement,
  on_token : (CstToken) -> R,
  init : (RawKind) -> R,
  on_child : (RawKind, R, R) -> R,
) -> R {
  match self {
    Token(token) => on_token(token)
    Node(node) =>
      for child in node.children; acc = init(node.kind) {
        continue on_child(
            node.kind,
            acc,
            child.transform_fold(on_token, init, on_child),
          )
      } nobreak {
        acc
      }
  }
}

///|
/// Callback-based depth-first pre-order traversal.
///
/// Calls `f` for every element in the tree. Returns `true` if traversal
/// completed, `false` if `f` returned `false` to request early termination.
pub fn CstElement::each(self : CstElement, f : (CstElement) -> Bool) -> Bool {
  if not(f(self)) {
    return false
  }
  match self {
    Token(_) => true
    Node(node) => {
      for child in node.children {
        if not(child.each(f)) {
          return false
        }
      }
      true
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt`
Expected: all 11 tests pass

- [ ] **Step 5: Commit**

```bash
git add seam/cst_traverse.mbt seam/cst_traverse_wbtest.mbt
git commit -m "feat(seam): add CstElement::transform_fold and CstElement::each"
```

---

### Task 3: `iter` and `map`

**Files:**
- Modify: `seam/cst_traverse.mbt`
- Modify: `seam/cst_traverse_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Append to `seam/cst_traverse_wbtest.mbt`:

```moonbit
///|
test "iter: collects all elements" {
  let tree = make_test_tree()
  let count = tree.iter().fold(init=0, fn(acc, _elem) { acc + 1 })
  // 2 branch nodes + 6 tokens = 8
  inspect!(count, content="8")
}

///|
test "iter: find_first" {
  let tree = make_test_tree()
  let found = tree.iter().find_first(fn(elem) {
    match elem {
      CstElement::Token(t) => t.kind == RawKind(12) // Plus
      _ => false
    }
  })
  inspect!(found.is_empty(), content="false")
  match found {
    Some(CstElement::Token(t)) => inspect!(t.text, content="+")
    _ => inspect!("unreachable", content="")
  }
}

///|
test "iter: empty node" {
  let node = CstNode::new(RawKind(20), [])
  let elem = CstElement::Node(node)
  let count = elem.iter().fold(init=0, fn(acc, _e) { acc + 1 })
  inspect!(count, content="1")
}

///|
test "map: identity preserves structure" {
  let tree = make_test_tree()
  let mapped = tree.map(fn(elem) { elem })
  // Reconstruct source text to verify structure
  let text = mapped.transform(
    fn(token) { token.text },
    fn(_kind, children) {
      let mut s = ""
      for child in children {
        s = s + child
      }
      s
    },
  )
  inspect!(text, content="foo 1+2")
}

///|
test "map: transform tokens" {
  let tree = make_test_tree()
  let mapped = tree.map(fn(elem) {
    match elem {
      CstElement::Token(t) =>
        if t.kind == RawKind(9) { // Ident
          CstElement::Token(CstToken::new(t.kind, "bar"))
        } else {
          elem
        }
      _ => elem
    }
  })
  let text = mapped.transform(
    fn(token) { token.text },
    fn(_kind, children) {
      let mut s = ""
      for child in children {
        s = s + child
      }
      s
    },
  )
  inspect!(text, content="bar 1+2")
}

///|
test "map: single token" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let mapped = elem.map(fn(e) {
    match e {
      CstElement::Token(t) =>
        CstElement::Token(CstToken::new(t.kind, "y"))
      _ => e
    }
  })
  match mapped {
    CstElement::Token(t) => inspect!(t.text, content="y")
    _ => inspect!("unreachable", content="")
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt 2>&1 | head -20`
Expected: compilation errors — `iter` and `map` not defined

- [ ] **Step 3: Implement `iter` and `map`**

Append to `seam/cst_traverse.mbt`:

```moonbit
///|
/// Depth-first pre-order iterator over all elements in the tree.
///
/// Uses an explicit stack. Suitable for stdlib composition
/// (`.filter`, `.find_first`, `.take`, etc.).
pub fn CstElement::iter(self : CstElement) -> Iter[CstElement] {
  let stack : Array[CstElement] = [self]
  Iter::new(fn() {
    if stack.is_empty() {
      return None
    }
    let current = stack.unsafe_pop()
    match current {
      Node(node) => {
        let mut i = node.children.length() - 1
        while i >= 0 {
          stack.push(node.children[i])
          i = i - 1
        }
      }
      Token(_) => ()
    }
    Some(current)
  })
}

///|
/// Bottom-up structure-preserving map: transforms a `CstElement` into
/// another `CstElement`.
///
/// Children are recursively mapped first, then `f` is applied to the
/// reconstructed element. For `Node` elements, a new `CstNode` is built
/// with `CstNode::new` to ensure metadata consistency.
pub fn CstElement::map(
  self : CstElement,
  f : (CstElement) -> CstElement,
) -> CstElement {
  match self {
    Token(_) => f(self)
    Node(node) => {
      let new_children = Array::new(capacity=node.children.length())
      for child in node.children {
        new_children.push(child.map(f))
      }
      f(CstElement::Node(CstNode::new(node.kind, new_children)))
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt`
Expected: all 17 tests pass

- [ ] **Step 5: Commit**

```bash
git add seam/cst_traverse.mbt seam/cst_traverse_wbtest.mbt
git commit -m "feat(seam): add CstElement::iter and CstElement::map"
```

---

### Task 4: `Finder` trait and `find`

**Files:**
- Modify: `seam/cst_traverse.mbt`
- Modify: `seam/cst_traverse_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Append to `seam/cst_traverse_wbtest.mbt`:

```moonbit
///|
struct NumberFinder { kind : RawKind }

///|
impl Finder for NumberFinder with check(self, elem) {
  match elem {
    CstElement::Token(t) => t.kind == self.kind
    _ => false
  }
}

///|
test "find: locates first number token" {
  let tree = make_test_tree()
  let found = tree.find(NumberFinder { kind: RawKind(10) })
  match found {
    Some(CstElement::Token(t)) => inspect!(t.text, content="1")
    _ => inspect!("not found", content="")
  }
}

///|
test "find: returns None when no match" {
  let tree = make_test_tree()
  let found = tree.find(NumberFinder { kind: RawKind(99) })
  inspect!(found.is_empty(), content="true")
}

///|
test "find: matches node element" {
  let tree = make_test_tree()
  let found = tree.find({ kind: RawKind(21) } : NodeKindFinder)
  match found {
    Some(CstElement::Node(n)) =>
      inspect!(n.kind == RawKind(21), content="true")
    _ => inspect!("not found", content="")
  }
}

///|
struct NodeKindFinder { kind : RawKind }

///|
impl Finder for NodeKindFinder with check(self, elem) {
  match elem {
    CstElement::Node(n) => n.kind == self.kind
    _ => false
  }
}

///|
test "find: single token match" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let found = elem.find(NumberFinder { kind: RawKind(9) })
  match found {
    Some(CstElement::Token(t)) => inspect!(t.text, content="x")
    _ => inspect!("not found", content="")
  }
}

///|
test "find: single token no match" {
  let tok = CstToken::new(RawKind(9), "x")
  let elem = CstElement::Token(tok)
  let found = elem.find(NumberFinder { kind: RawKind(10) })
  inspect!(found.is_empty(), content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt 2>&1 | head -20`
Expected: compilation errors — `Finder` trait and `find` not defined

- [ ] **Step 3: Implement `Finder` trait and `find`**

Append to `seam/cst_traverse.mbt`:

```moonbit
///|
/// Typeclass for DFS search. `check` returns true if the element matches.
/// Statically dispatched — zero closure overhead for predicates.
pub(open) trait Finder {
  check(Self, CstElement) -> Bool
}

///|
/// Statically-dispatched DFS find. Returns the first element where `check` is true.
pub fn[F : Finder] CstElement::find(self : CstElement, f : F) -> CstElement? {
  if F::check(f, self) {
    return Some(self)
  }
  match self {
    Token(_) => None
    Node(node) => {
      for child in node.children {
        match child.find(f) {
          Some(n) => return Some(n)
          None => ()
        }
      }
      None
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd seam && moon test -f cst_traverse_wbtest.mbt`
Expected: all 22 tests pass

- [ ] **Step 5: Commit**

```bash
git add seam/cst_traverse.mbt seam/cst_traverse_wbtest.mbt
git commit -m "feat(seam): add Finder trait and CstElement::find"
```

---

### Task 5: Final verification and interface update

**Files:**
- Modify: `seam/pkg.generated.mbti` (auto-generated by `moon info`)

- [ ] **Step 1: Run full seam test suite**

Run: `cd seam && moon check && moon test`
Expected: all tests pass (existing + 22 new)

- [ ] **Step 2: Update interfaces**

Run: `cd seam && moon info`
Expected: `pkg.generated.mbti` updated with new methods and `Finder` trait

- [ ] **Step 3: Verify API in `.mbti`**

Run: `cd seam && grep -E "(transform|fold|each|iter|map|find|Finder)" pkg.generated.mbti`
Expected: all 7 methods + `Finder` trait visible in the interface

- [ ] **Step 4: Format**

Run: `cd seam && moon fmt`

- [ ] **Step 5: Commit**

```bash
cd seam && git add pkg.generated.mbti cst_traverse.mbt cst_traverse_wbtest.mbt
git commit -m "chore(seam): update interfaces after CstElement traversal methods"
```
