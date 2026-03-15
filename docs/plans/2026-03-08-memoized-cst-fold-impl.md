# Memoized CST Fold — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `CstFold[Ast]` — a framework-owned memoized catamorphism over CstNode that makes CST → AST conversion incremental.

**Architecture:** CstFold walks the CST top-down, checks a hash-keyed cache before calling the user's algebra, and verifies that all node-children were visited. It replaces `Grammar.to_ast` with `Grammar.fold_node` (an algebra that receives a framework-provided `recurse` function). The cache persists across incremental parses inside both `ReactiveParser` and `ImperativeParser`.

**Tech Stack:** MoonBit, loom framework (`loom/src/core/`, `loom/src/pipeline/`, `loom/src/`), seam (`seam/`), incr (`incr/`), lambda example (`examples/lambda/src/`)

---

### Task 1: CstFold core struct and fold algorithm

**Files:**
- Create: `loom/src/core/cst_fold.mbt`

**Step 1: Write FoldStats and CstFold structs**

```moonbit
///|
pub struct FoldStats {
  mut reused : Int
  mut recomputed : Int
  mut unvisited : Int
} derive(Show)

///|
pub fn FoldStats::zero() -> FoldStats {
  { reused: 0, recomputed: 0, unvisited: 0 }
}

///|
/// Memoized catamorphism over CstNode.
///
/// The algebra receives a SyntaxNode and a framework-provided `recurse` function.
/// The framework handles the tree walk, hash-keyed caching, and child-visit
/// verification. The language author provides only per-node interpretation.
///
/// Cache key: CstNode.hash (structural content hash, position-independent).
/// Traversal: top-down with cache check first — unchanged subtrees are O(1).
pub struct CstFold[Ast] {
  algebra : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  mut cache : Map[Int, Ast]
  mut stats : FoldStats
}

///|
pub fn CstFold::new[Ast](
  algebra : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
) -> CstFold[Ast] {
  { algebra, cache: {}, stats: FoldStats::zero() }
}
```

**Step 2: Write the fold and fold_node methods**

```moonbit
///|
/// Run the memoized fold over a syntax tree.
/// Swaps in a fresh cache (old cache used for lookups), resets stats.
pub fn CstFold::fold[Ast](
  self : CstFold[Ast],
  root : @seam.SyntaxNode,
) -> Ast {
  let old_cache = self.cache
  self.cache = {}
  self.stats = FoldStats::zero()
  self.fold_node(root, old_cache)
}

///|
/// Internal recursive fold with old-cache lookup.
fn CstFold::fold_node[Ast](
  self : CstFold[Ast],
  node : @seam.SyntaxNode,
  old_cache : Map[Int, Ast],
) -> Ast {
  let hash = node.cst_node().hash
  // Check old cache (from previous fold invocation)
  match old_cache.get(hash) {
    Some(cached) => {
      self.cache[hash] = cached
      self.stats.reused = self.stats.reused + 1
      return cached
    }
    None => ()
  }
  // Check new cache (structural duplicate within same tree)
  match self.cache.get(hash) {
    Some(cached) => {
      self.stats.reused = self.stats.reused + 1
      return cached
    }
    None => ()
  }
  // Cache miss — call algebra with tracked recurse function
  let visited : Map[Int, Unit] = {}
  let recurse = fn(child : @seam.SyntaxNode) -> Ast {
    visited[child.start()] = ()
    self.fold_node(child, old_cache)
  }
  let result = (self.algebra)(node, recurse)
  self.cache[hash] = result
  self.stats.recomputed = self.stats.recomputed + 1
  // Verification: warm cache for unvisited node-children
  for child in node.children() {
    if not(visited.contains(child.start())) {
      self.stats.unvisited = self.stats.unvisited + 1
      let _ = self.fold_node(child, old_cache)
    }
  }
  result
}

///|
pub fn CstFold::get_stats[Ast](self : CstFold[Ast]) -> FoldStats {
  self.stats
}
```

**Step 3: Verify it compiles**

Run: `cd loom && moon check`
Expected: PASS (no type errors)

**Step 4: Commit**

```bash
git add loom/src/core/cst_fold.mbt
git commit -m "feat(core): add CstFold memoized catamorphism struct"
```

---

### Task 2: CstFold unit tests

**Files:**
- Create: `loom/src/core/cst_fold_wbtest.mbt`

**Step 1: Write tests for basic fold, cache reuse, and verification**

The tests construct CstNodes manually using `@seam.CstNode::new` and `@seam.CstToken::new`, then fold them with a trivial algebra (returns kind integer as String).

```moonbit
///|
/// Helper: create a leaf token element.
fn tok(kind_val : Int, text : String) -> @seam.CstElement {
  @seam.CstElement::Token(@seam.CstToken::new(@seam.RawKind(kind_val), text))
}

///|
/// Helper: create a node element.
fn nd(kind_val : Int, children : Array[@seam.CstElement]) -> @seam.CstElement {
  @seam.CstElement::Node(@seam.CstNode::new(@seam.RawKind(kind_val), children))
}

///|
/// Trivial algebra: returns "kind:<n>" for leaves, "kind:<n>(<child1>,<child2>,...)" for nodes.
fn test_algebra(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> String,
) -> String {
  let @seam.RawKind(k) = node.kind()
  let child_strs = node.children().map(recurse)
  if child_strs.length() == 0 {
    "kind:" + k.to_string()
  } else {
    "kind:" + k.to_string() + "(" + child_strs.join(",") + ")"
  }
}

///|
test "CstFold: basic fold produces correct result" {
  //   Root(10)
  //   ├── Token(1, "x")
  //   └── Child(20)
  //       └── Token(2, "y")
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [tok(1, "x"), child])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let result = fold.fold(syntax)
  inspect(result, content="kind:10(kind:20)")
}

///|
test "CstFold: second fold reuses cache for unchanged tree" {
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [tok(1, "x"), child])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(syntax)
  // Second fold on same tree — should be all cache hits
  let result2 = fold.fold(syntax)
  inspect(result2, content="kind:10(kind:20)")
  let stats = fold.get_stats()
  // Root + child = 2 reused, 0 recomputed
  inspect(stats.reused, content="2")
  inspect(stats.recomputed, content="0")
}

///|
test "CstFold: incremental fold reuses unchanged subtrees" {
  // Original:  Root(10) -> [Token("a"), Child(20) -> [Token("y")]]
  let child = @seam.CstNode::new(@seam.RawKind(20), [tok(2, "y")])
  let root = @seam.CstNode::new(
    @seam.RawKind(10),
    [tok(1, "a"), @seam.CstElement::Node(child)],
  )
  let fold : CstFold[String] = CstFold::new(test_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(root))
  // Modified: Root(10) -> [Token("b"), Child(20) -> [Token("y")]]
  // Child(20) is structurally identical (same hash) — should be reused.
  let new_root = @seam.CstNode::new(
    @seam.RawKind(10),
    [tok(1, "b"), @seam.CstElement::Node(child)],
  )
  let result = fold.fold(@seam.SyntaxNode::from_cst(new_root))
  inspect(result, content="kind:10(kind:20)")
  let stats = fold.get_stats()
  // Child(20) reused from cache, Root(10) recomputed
  inspect(stats.reused, content="1")
  inspect(stats.recomputed, content="1")
}

///|
test "CstFold: unvisited children are cache-warmed" {
  // Algebra that skips child nodes intentionally
  let skip_algebra = fn(
    node : @seam.SyntaxNode,
    _recurse : (@seam.SyntaxNode) -> String,
  ) -> String {
    let @seam.RawKind(k) = node.kind()
    "leaf:" + k.to_string() // Never calls recurse
  }
  let child = nd(20, [tok(2, "y")])
  let root = @seam.CstNode::new(@seam.RawKind(10), [tok(1, "x"), child])
  let fold : CstFold[String] = CstFold::new(skip_algebra)
  let _ = fold.fold(@seam.SyntaxNode::from_cst(root))
  let stats = fold.get_stats()
  // Root recomputed, child unvisited but cache-warmed
  inspect(stats.recomputed, content="2")
  inspect(stats.unvisited, content="1")
}
```

**Step 2: Run tests**

Run: `cd loom && moon test -p dowdiness/loom/core -f cst_fold_wbtest.mbt`
Expected: all 4 tests PASS

**Step 3: Commit**

```bash
git add loom/src/core/cst_fold_wbtest.mbt
git commit -m "test(core): add CstFold unit tests"
```

---

### Task 3: Grammar interface change — `to_ast` → `fold_node`

**Files:**
- Modify: `loom/src/grammar.mbt`

**Step 1: Replace `to_ast` with `fold_node` in Grammar struct**

Change the `to_ast` field to `fold_node`:

```moonbit
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  fold_node : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast
  on_lex_error : (String) -> Ast
  error_token : T?
  prefix_lexer : @core.PrefixLexer[T]?
}
```

Update `Grammar::new` to match:

```moonbit
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  fold_node~ : (@seam.SyntaxNode, (@seam.SyntaxNode) -> Ast) -> Ast,
  on_lex_error~ : (String) -> Ast,
  error_token? : T? = None,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
) -> Grammar[T, K, Ast] {
  { spec, tokenize, fold_node, on_lex_error, error_token, prefix_lexer }
}
```

**Step 2: Check that it compiles (expect downstream errors)**

Run: `cd loom && moon check`
Expected: FAIL — downstream code still references `grammar.to_ast` and `to_ast~`

**Step 3: Commit (WIP)**

```bash
git add loom/src/grammar.mbt
git commit -m "refactor(grammar): replace to_ast with fold_node algebra"
```

---

### Task 4: Wire CstFold into factories

**Files:**
- Modify: `loom/src/factories.mbt`

**Step 1: Update `new_reactive_parser` factory**

Create a `CstFold` from the grammar's `fold_node` and pass a closure that calls `cst_fold.fold(syntax)` as `to_ast` to `Language::from_closures`:

In `new_reactive_parser`, replace:
```moonbit
  let to_ast = grammar.to_ast
```
with:
```moonbit
  let cst_fold = @core.CstFold::new(grammar.fold_node)
```

And in the `Language::from_closures` call, replace:
```moonbit
    to_ast~,
```
with:
```moonbit
    to_ast=fn(syntax) { cst_fold.fold(syntax) },
```

**Step 2: Update `new_imperative_parser` factory**

Similarly, create a `CstFold` and wire it. Replace:
```moonbit
  let to_ast = grammar.to_ast
```
with:
```moonbit
  let cst_fold = @core.CstFold::new(grammar.fold_node)
```

And in the `ImperativeLanguage::new` call, replace:
```moonbit
    to_ast~,
```
with:
```moonbit
    to_ast=fn(syntax) { cst_fold.fold(syntax) },
```

**Step 3: Check that loom compiles**

Run: `cd loom && moon check`
Expected: PASS for loom module (lambda example will still fail)

**Step 4: Commit**

```bash
git add loom/src/factories.mbt
git commit -m "feat(factories): wire CstFold into both parser factories"
```

---

### Task 5: Re-export CstFold and FoldStats

**Files:**
- Modify: `loom/src/loom.mbt`

**Step 1: Add re-exports**

Add to the existing `pub using @core` block:

```moonbit
pub using @core {
  type CstFold,
  type FoldStats,
}
```

**Step 2: Update interfaces**

Run: `cd loom && moon info`

**Step 3: Commit**

```bash
git add loom/src/loom.mbt
git commit -m "feat(loom): re-export CstFold and FoldStats"
```

---

### Task 6: Create lambda algebra

**Files:**
- Modify: `examples/lambda/src/term_convert.mbt`

**Step 1: Create `lambda_fold_node` algebra from existing `view_to_term`**

Add a new public function that wraps the existing logic with a `recurse` parameter:

```moonbit
///|
/// Algebra for CstFold: per-node conversion with framework-managed recursion.
/// Replaces manual `view_to_term` recursion with the framework-provided `recurse`.
pub fn lambda_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> @ast.Term {
  // SourceFile unwrapping
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.SourceFile =>
      return match node.nth_child(0) {
        Some(child) => recurse(child)
        None => @ast.Term::Error("empty SourceFile")
      }
    _ => ()
  }
  fold_node_inner(node, recurse)
}
```

Then create `fold_node_inner` which is `view_to_term` with `recurse` replacing self-calls:

```moonbit
///|
fn fold_node_inner(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral => {
      let v = IntLiteralView::{ node, }
      @ast.Term::Int(v.value().unwrap_or(0))
    }
    @syntax.VarRef => {
      let v = VarRefView::{ node, }
      @ast.Term::Var(v.name())
    }
    @syntax.LambdaExpr => {
      let v = LambdaExprView::{ node, }
      let body = match v.body() {
        Some(b) => recurse(b)
        None => @ast.Term::Error("missing lambda body")
      }
      @ast.Term::Lam(v.param(), body)
    }
    @syntax.AppExpr => {
      let v = AppExprView::{ node, }
      match v.func() {
        None => @ast.Term::Error("missing function in application")
        Some(func_node) => {
          let mut result = recurse(func_node)
          for arg in v.args() {
            result = @ast.Term::App(result, recurse(arg))
          }
          result
        }
      }
    }
    @syntax.BinaryExpr => {
      let ops : Array[@ast.Bop] = []
      let children : Array[@seam.SyntaxNode] = []
      for elem in node.all_children() {
        match elem {
          @seam.SyntaxElement::Token(t) =>
            if t.kind() == @syntax.PlusToken.to_raw() {
              ops.push(@ast.Bop::Plus)
            } else if t.kind() == @syntax.MinusToken.to_raw() {
              ops.push(@ast.Bop::Minus)
            }
          @seam.SyntaxElement::Node(child) => children.push(child)
        }
      }
      if children.length() >= 2 {
        let mut result = recurse(children[0])
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() {
            ops[i - 1]
          } else {
            @ast.Bop::Plus
          }
          result = @ast.Term::Bop(op, result, recurse(children[i]))
        }
        result
      } else if children.length() == 1 {
        recurse(children[0])
      } else {
        @ast.Term::Error("empty BinaryExpr")
      }
    }
    @syntax.IfExpr => {
      let v = IfExprView::{ node, }
      let cond = match v.condition() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing if condition")
      }
      let then_ = match v.then_branch() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing then branch")
      }
      let else_ = match v.else_branch() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing else branch")
      }
      @ast.Term::If(cond, then_, else_)
    }
    @syntax.LetExpr => {
      let v = LetExprView::{ node, }
      let init = match v.init() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing let binding value")
      }
      let body = match v.body() {
        Some(n) => recurse(n)
        None => @ast.Term::Error("missing let body")
      }
      @ast.Term::Let(v.name(), init, body)
    }
    @syntax.ParenExpr => {
      let v = ParenExprView::{ node, }
      match v.inner() {
        Some(inner) => recurse(inner)
        None => @ast.Term::Error("empty parentheses")
      }
    }
    @syntax.ErrorNode => @ast.Term::Error("ErrorNode")
    _ =>
      @ast.Term::Error(
        "unknown node kind: " +
        @syntax.SyntaxKind::from_raw(node.kind()).to_string(),
      )
  }
}
```

Keep the old `syntax_node_to_term` and `view_to_term` functions for now — they will be removed after tests pass with the new algebra.

**Step 2: Verify it compiles**

Run: `cd loom && moon check`
Expected: PASS (new functions coexist with old ones)

**Step 3: Commit**

```bash
git add examples/lambda/src/term_convert.mbt
git commit -m "feat(lambda): add lambda_fold_node algebra for CstFold"
```

---

### Task 7: Create source-file algebra

**Files:**
- Modify: `examples/lambda/src/term_convert.mbt`

**Step 1: Create `source_file_fold_node` algebra from existing `syntax_node_to_source_file_term`**

```moonbit
///|
/// Algebra for source-file grammar: handles LetDef* Expression? sequences.
/// Right-folds definitions into nested Let terms.
pub fn source_file_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> @ast.Term,
) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.SourceFile => {
      let defs : Array[(@ast.VarName, @ast.Term)] = []
      let mut final_term : @ast.Term = @ast.Term::Unit
      for child in node.children() {
        match @syntax.SyntaxKind::from_raw(child.kind()) {
          @syntax.LetDef => {
            let v = LetDefView::{ node: child }
            let init = match v.init() {
              Some(expr_node) => recurse(expr_node)
              None => @ast.Term::Error("missing LetDef init")
            }
            defs.push((v.name(), init))
          }
          _ =>
            if final_term == @ast.Term::Unit {
              final_term = recurse(child)
            }
        }
      }
      let mut result = final_term
      for i = defs.length() - 1; i >= 0; i = i - 1 {
        let (name, init) = defs[i]
        result = @ast.Term::Let(name, init, result)
      }
      result
    }
    _ => fold_node_inner(node, recurse)
  }
}
```

**Step 2: Commit**

```bash
git add examples/lambda/src/term_convert.mbt
git commit -m "feat(lambda): add source_file_fold_node algebra"
```

---

### Task 8: Migrate lambda grammars to use `fold_node`

**Files:**
- Modify: `examples/lambda/src/grammar.mbt`

**Step 1: Change Grammar type from `SyntaxNode` to `@ast.Term` and use algebras**

```moonbit
///|
pub let lambda_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.Term,
] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  fold_node=lambda_fold_node,
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer)),
)

///|
pub let source_file_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.Term,
] = @loom.Grammar::new(
  spec=source_file_spec,
  tokenize=@lexer.tokenize_layout,
  fold_node=source_file_fold_node,
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(
    @core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer_layout),
  ),
)
```

**Step 2: Check for compile errors**

Run: `cd loom && moon check`
Expected: FAIL — downstream tests reference `db.term()` as `SyntaxNode`, need to update

Note the errors carefully — they tell you which test files need updating.

**Step 3: Commit (WIP)**

```bash
git add examples/lambda/src/grammar.mbt
git commit -m "feat(lambda): migrate grammars to fold_node with Term as Ast"
```

---

### Task 9: Update lambda tests

**Files:**
- Modify: `examples/lambda/src/reactive_parser_test.mbt`
- Modify: `examples/lambda/src/imperative_parser_test.mbt`
- Possibly modify: other test files that use `syntax_node_to_term(db.term())`

**Step 1: Update reactive parser tests**

The key change: `db.term()` now returns `@ast.Term` directly, not `SyntaxNode`. Remove all `syntax_node_to_term(db.term())` calls and replace with just `db.term()`.

For tests that accessed SyntaxNode properties (like `.kind()`), use `db.cst()` to get the CstStage and construct a SyntaxNode from it:
```moonbit
let syntax = @seam.SyntaxNode::from_cst(db.cst().cst)
```

**Step 2: Update imperative parser tests**

Same pattern: `parser.parse()` now returns `Term` directly.

**Step 3: Find and fix all remaining compile errors**

Run: `cd loom && moon check`
Fix each error file by file. The pattern is always the same: replace `syntax_node_to_term(x)` with just `x` where `x` is from `.term()` or `.parse()`.

**Step 4: Run all tests**

Run: `cd loom/examples/lambda && moon test`
Expected: all tests PASS

**Step 5: Commit**

```bash
git add examples/lambda/src/
git commit -m "fix(lambda): update tests for Term-typed Grammar"
```

---

### Task 10: Remove old `syntax_node_to_term` and `view_to_term`

**Files:**
- Modify: `examples/lambda/src/term_convert.mbt`

**Step 1: Remove the old functions**

Delete `syntax_node_to_term`, `view_to_term`, and `syntax_node_to_source_file_term`. They are now replaced by `lambda_fold_node`, `fold_node_inner`, and `source_file_fold_node`.

**Step 2: Search for remaining references**

Run: `grep -r "syntax_node_to_term\|view_to_term\|syntax_node_to_source_file_term" examples/lambda/` to find any remaining callers. Update or remove them.

Note: `parse()` in the lambda example may call `syntax_node_to_term` — check and update.

**Step 3: Run all tests**

Run: `cd loom/examples/lambda && moon test`
Expected: all tests PASS

**Step 4: Commit**

```bash
git add examples/lambda/src/
git commit -m "refactor(lambda): remove old manual-recursion term_convert functions"
```

---

### Task 11: Update generic pipeline tests

**Files:**
- Modify: `loom/src/pipeline/reactive_parser_test.mbt`
- Modify: `loom/src/factories_wbtest.mbt`

**Step 1: Update TestLang to use `fold_node`**

In `reactive_parser_test.mbt`, the `test_lang()` function creates a `Language::from_closures` with `to_ast`. Since `Language::from_closures` is internal and hasn't changed (only Grammar changed), this should still compile. Verify.

If `Language::from` needs updating (it takes `to_ast~`), wrap the existing to_ast in an algebra:
```moonbit
fold_node=fn(n, _recurse) {
  let toks = n.tokens()
  if toks.length() > 0 { toks[0].text() } else { "" }
},
```

**Step 2: Run loom tests**

Run: `cd loom && moon test`
Expected: all 88 tests PASS

**Step 3: Commit**

```bash
git add loom/src/
git commit -m "fix(loom): update generic pipeline tests for fold_node"
```

---

### Task 12: Update interfaces and format

**Files:**
- All `.mbti` files

**Step 1: Regenerate interfaces and format**

Run: `cd loom && moon info && moon fmt`

**Step 2: Review API changes**

Run: `git diff *.mbti` — verify:
- `Grammar` now has `fold_node` instead of `to_ast`
- `CstFold` and `FoldStats` are exported from core and loom root
- Lambda grammar types changed from `SyntaxNode` to `Term`

**Step 3: Run all tests across all modules**

```bash
cd loom && moon test               # loom framework
cd examples/lambda && moon test    # lambda example
cd seam && moon test               # seam
cd incr && moon test               # incr
```

Expected: all tests PASS

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: update mbti interfaces and format"
```

---

### Task 13: Add CstFold integration test with incremental parsing

**Files:**
- Modify: `examples/lambda/src/imperative_parser_test.mbt`

**Step 1: Add test verifying fold cache reuse after incremental edit**

```moonbit
///|
test "ImperativeParser: CstFold cache reuses unchanged subtrees after edit" {
  // Parse "1 + 2" then edit to "1 + 3"
  // The "1" subtree is structurally unchanged — CstFold should reuse it.
  let parser = @loom.new_imperative_parser("1 + 2", lambda_grammar)
  let t1 = parser.parse()
  inspect(@ast.print_term(t1), content="(1 + 2)")
  // Edit: replace "2" with "3" (position 4, delete 1 char, insert 1 char)
  let edit = @core.Edit::new(start=4, old_len=1, new_len=1)
  let t2 = parser.edit(edit, "1 + 3")
  inspect(@ast.print_term(t2), content="(1 + 3)")
}
```

**Step 2: Run test**

Run: `cd loom/examples/lambda && moon test -f imperative_parser_test.mbt`
Expected: PASS

**Step 3: Commit**

```bash
git add examples/lambda/src/imperative_parser_test.mbt
git commit -m "test(lambda): add CstFold incremental reuse integration test"
```

---

### Task 14: Fold cache benchmarks

**Goal:** Measure the fold cache hit rate and wall-time improvement. The
existing let-chain benchmarks measure lex + parse but NOT the fold stage.
This task adds benchmarks that isolate fold cost.

**Files:**
- Create: `examples/lambda/src/benchmarks/fold_benchmark.mbt`

**Step 1: Add fold-specific benchmarks**

Three benchmark categories:

**A. FoldStats verification (cache hit rate):**

Not a benchmark test — a regular test that inspects `FoldStats` after
incremental edits. Proves the cache works.

```moonbit
test "CstFold stats: 80-let incremental edit reuses most subtrees" {
  let source = make_let_chain(80, "0")
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Edit last literal: "0" → "1"
  let edited = make_let_chain_edited(80)
  let edit = @core.Edit::new(...)
  let _ = parser.edit(edit, edited)
  // Inspect fold stats — expect ~79 reused, ~2 recomputed (root + edited LetDef)
  let stats = parser.get_fold_stats()  // needs accessor added
  inspect(stats.reused >= 78, content="true")
  inspect(stats.recomputed <= 3, content="true")
}
```

Note: `ImperativeParser::get_fold_stats()` must be added as a public accessor.
This requires `ImperativeParser` to store the `CstFold` and expose its stats.

**B. Fold-only wall time (initial vs incremental):**

Measures the to_ast / fold stage in isolation — not the full lex+parse+fold
pipeline. Uses `ImperativeParser::parse()` and `ImperativeParser::edit()` which
now internally call `CstFold::fold`, then reads fold stats.

```moonbit
test "fold benchmark: 80 lets - initial fold" (b : @bench.T) {
  b.bench(fn() {
    let parser = @loom.new_imperative_parser(source, lambda_grammar)
    let result = parser.parse()
    b.keep(result)
  })
}

test "fold benchmark: 80 lets - incremental fold after single edit" (b : @bench.T) {
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  b.bench(fn() {
    let result = parser.edit(edit, edited)
    b.keep(result)
  })
}
```

Compare "initial fold" (all cache misses) vs "incremental fold" (most cache
hits). The difference is the fold cache benefit.

**C. Scaling: fold cost as a function of tree size**

```moonbit
test "fold benchmark: 80 lets - fold stage" (b : @bench.T) { ... }
test "fold benchmark: 320 lets - fold stage" (b : @bench.T) { ... }
test "fold benchmark: 1000 lets - fold stage" (b : @bench.T) { ... }
```

Expected: initial fold scales O(n). Incremental fold scales O(depth) ≈ O(1)
for flat LetDef structures (only root + edited node recomputed).

**Step 2: Add `get_fold_stats` accessor to ImperativeParser**

In `loom/src/incremental/imperative_parser.mbt` (or wherever `ImperativeParser`
is defined), expose the fold stats:

```moonbit
pub fn[Ast] ImperativeParser::get_fold_stats(self) -> @core.FoldStats? {
  // Return stats from the internal CstFold if it exists
}
```

This requires `ImperativeLanguage` or the factory closure to expose the
`CstFold` instance. Design options:

1. Store `CstFold` as a field on `ImperativeParser` (simplest)
2. Store a `get_fold_stats` closure captured from the factory (no struct change)

Option 2 is less invasive — add a `get_fold_stats? : (() -> @core.FoldStats)?`
field to `ImperativeLanguage` or `ImperativeParser`.

**Step 3: Run benchmarks**

```bash
cd examples/lambda && moon bench --release -f benchmarks/fold_benchmark.mbt
```

**Step 4: Record results in `docs/performance/benchmark_history.md`**

Add a dated entry with:
- Fold cache hit rate (from FoldStats)
- Initial fold vs incremental fold wall time
- Scaling curve (80 / 320 / 1000 lets)
- Comparison: full pipeline with fold cache vs without

**Step 5: Commit**

```bash
git add examples/lambda/src/benchmarks/fold_benchmark.mbt
git add loom/src/  # if ImperativeParser accessor was added
git add docs/performance/benchmark_history.md
git commit -m "bench(lambda): add CstFold cache hit rate and wall time benchmarks"
```

---

### Task 15: Final verification and cleanup

**Step 1: Run all tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
moon test                                   # loom framework
cd examples/lambda && moon test             # lambda (311+ tests)
cd ../../seam && moon test                  # seam
cd ../incr && moon test                     # incr
```

**Step 2: Run full benchmark suite**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom/examples/lambda
moon bench --release
```

Verify:
- No regression in existing lex/parse benchmarks
- Fold benchmarks show expected cache hit rates
- Scaling is O(depth) for incremental, O(n) for initial

**Step 3: Update `docs/performance/incremental-overhead.md`**

Add a section noting the fold cache eliminates the O(tree size) fold
bottleneck documented in the "Damage Information Cliff" section.

**Step 4: Check docs**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/loom
bash check-docs.sh
```

**Step 5: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: final cleanup for memoized CST fold"
```
