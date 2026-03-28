# Block Reparse Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a framework-level block reparse fast-path to loom's incremental parser — when an edit falls inside a reparseable block (`{ ... }`), re-lex and re-parse only that block, splice the result into the old tree. O(block_size + depth) independent of document size.

**Architecture:** Grammar authors provide a `BlockReparseSpec[T, K]` (3 functions: is_reparseable, get_reparser, is_balanced). The framework provides find_reparseable_ancestor, path-copy splice, and reparse_block orchestrator. Integration is a pre-check in `factories.mbt` before the existing incremental parse path.

**Tech Stack:** MoonBit, loom parser framework, seam CST library

**Design spec:** `docs/plans/2026-03-22-block-reparse-impl-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `seam/cst_node.mbt` | Modify | Add `CstNode::with_replaced_child` |
| `seam/cst_node_wbtest.mbt` | Modify | Tests for with_replaced_child |
| `loom/src/core/block_reparse.mbt` | Create | `BlockReparseSpec[T, K]` struct |
| `loom/src/block_reparse.mbt` | Create | `find_reparseable_ancestor`, `build_physical_path`, `splice_tree`, `parse_block_isolated`, `reparse_block`, diagnostic merging |
| `loom/src/grammar.mbt` | Modify | Add `block_reparse_spec` field to Grammar |
| `loom/src/factories.mbt` | Modify | Pre-check in `incremental_parse` closure |
| `examples/lambda/src/block_reparse.mbt` | Create | Lambda's is_reparseable, get_reparser, is_balanced |
| `examples/lambda/src/cst_parser.mbt` | Modify | Make `parse_block_expr` pub |
| `examples/lambda/src/grammar.mbt` | Modify | Wire BlockReparseSpec into lambda_grammar |
| `examples/lambda/src/block_reparse_test.mbt` | Create | Correctness + edge case tests |

---

## Task 1: CstNode::with_replaced_child

**Files:**
- Modify: `seam/cst_node.mbt`
- Test: `seam/cst_node_wbtest.mbt`

- [ ] **Step 1: Write test**

Add to `seam/cst_node_wbtest.mbt`:

```moonbit
///|
test "with_replaced_child replaces correctly" {
  // Build a simple tree: Root(Token("a"), Token("b"))
  let tok_a = CstToken::new(RawKind(1), "a")
  let tok_b = CstToken::new(RawKind(2), "b")
  let tok_c = CstToken::new(RawKind(3), "c")
  let root = CstNode::new(
    RawKind(100),
    [CstElement::Token(tok_a), CstElement::Token(tok_b)],
  )
  inspect(root.text_len, content="2")
  // Replace child 1 (tok_b) with tok_c
  let new_root = root.with_replaced_child(1, CstElement::Token(tok_c))
  inspect(new_root.text_len, content="2")
  inspect(new_root.kind, content="RawKind(100)")
  // Original unchanged
  inspect(root.children[1].text_len(), content="1")
}

///|
test "with_replaced_child recomputes metadata" {
  let tok_a = CstToken::new(RawKind(1), "a")
  let tok_bc = CstToken::new(RawKind(2), "bc")
  let root = CstNode::new(RawKind(100), [CstElement::Token(tok_a)])
  inspect(root.text_len, content="1")
  inspect(root.token_count, content="1")
  // Replace with longer token
  let new_root = root.with_replaced_child(0, CstElement::Token(tok_bc))
  inspect(new_root.text_len, content="2")
  inspect(new_root.token_count, content="1")
  // Hash changed
  inspect(root.hash == new_root.hash, content="false")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd seam && moon test -f cst_node_wbtest.mbt`
Expected: FAIL — `with_replaced_child` not defined

- [ ] **Step 3: Implement with_replaced_child**

Add to `seam/cst_node.mbt` after the `CstNode::new` constructor:

```moonbit
///|
/// Create a new CstNode with one child replaced. Pure function — original unchanged.
/// Delegates to CstNode::new() for correct metadata recomputation.
pub fn CstNode::with_replaced_child(
  self : CstNode,
  index : Int,
  new_child : CstElement,
  trivia_kind? : RawKind? = None,
  error_kind? : RawKind? = None,
  incomplete_kind? : RawKind? = None,
) -> CstNode {
  let new_children : Array[CstElement] = []
  for i, child in self.children {
    if i == index {
      new_children.push(new_child)
    } else {
      new_children.push(child)
    }
  }
  CstNode::new(self.kind, new_children, trivia_kind~, error_kind~, incomplete_kind~)
}
```

- [ ] **Step 4: Run tests**

Run: `cd seam && moon test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
cd seam && moon info && moon fmt
git add seam/cst_node.mbt seam/cst_node_wbtest.mbt
git add -A
git commit -m "feat(seam): add CstNode::with_replaced_child for path-copy splice"
```

---

## Task 2: BlockReparseSpec Struct

**Files:**
- Create: `loom/src/core/block_reparse.mbt`

- [ ] **Step 1: Create the struct file**

Create `loom/src/core/block_reparse.mbt`:

```moonbit
///|
/// Grammar-provided configuration for block reparse.
/// The grammar author implements three functions to enable block-level
/// incremental reparsing for their language.
pub struct BlockReparseSpec[T, K] {
  /// Returns true for node kinds that can be reparsed in isolation.
  /// Only "container" kinds with explicit delimiters (e.g., BlockExpr)
  /// should return true.
  is_reparseable : (@seam.RawKind) -> Bool
  /// Returns the parse function for a reparseable kind.
  /// Must be the same grammar function that produced the node originally.
  get_reparser : (@seam.RawKind) -> ((ParserContext[T, K]) -> Unit)?
  /// Structural integrity check on re-lexed tokens.
  /// Returns false to reject and fall through to normal incremental parse.
  /// For brace-delimited blocks: count { and }, verify equal.
  is_balanced : (Array[TokenInfo[T]]) -> Bool
}
```

- [ ] **Step 2: Run moon check**

Run: `cd loom && moon check`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/core/block_reparse.mbt
git add -A
git commit -m "feat(loom): add BlockReparseSpec struct"
```

---

## Task 3: Grammar + Factory Integration

**Files:**
- Modify: `loom/src/grammar.mbt`
- Modify: `loom/src/factories.mbt`

- [ ] **Step 1: Add block_reparse_spec field to Grammar**

In `loom/src/grammar.mbt`, add to the Grammar struct (after `prefix_lexer`):

```moonbit
  block_reparse_spec : @core.BlockReparseSpec[T, K]?
```

Update `Grammar::new()` constructor to accept the new optional parameter:

```moonbit
  block_reparse_spec? : @core.BlockReparseSpec[T, K]? = None,
```

And assign it in the constructor body.

- [ ] **Step 2: Run moon check**

Run: `cd loom && moon check`
Expected: No errors (existing callers use default None)

- [ ] **Step 3: Add re-export in loom facade**

In the loom root package (`loom/src/`), ensure `BlockReparseSpec` is accessible. Add to the `using` declarations if needed:

```moonbit
pub using @core { type BlockReparseSpec }
```

- [ ] **Step 4: Run all tests**

Run: `cd loom && moon test && cd ../seam && moon test`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/grammar.mbt loom/src/
git add -A
git commit -m "feat(loom): add block_reparse_spec to Grammar"
```

---

## Task 4: find_reparseable_ancestor + splice_tree + reparse_block

This is the core framework task. All pieces go in one new file.

**Files:**
- Create: `loom/src/block_reparse.mbt`

- [ ] **Step 1: Create the block_reparse.mbt file with find_reparseable_ancestor**

Create `loom/src/block_reparse.mbt`:

```moonbit
///|
/// Build the physical CstNode child-index path from root to a target node
/// at the given byte offset and kind. Handles RepeatGroup transparency.
fn build_physical_path(
  root : @seam.CstNode,
  target_offset : Int,
  target_end : Int,
  target_kind : @seam.RawKind,
) -> Array[Int]? {
  let path : Array[Int] = []
  let mut current = root
  let mut current_offset = 0
  // Drill down through the CstNode tree using byte offsets
  // Match on kind + start offset + end offset to avoid ambiguity
  while current.kind != target_kind ||
    current_offset != target_offset ||
    current_offset + current.text_len != target_end {
    let mut found = false
    let mut child_offset = current_offset
    for i, child in current.children {
      let child_len = child.text_len()
      if target_offset >= child_offset && target_offset < child_offset + child_len {
        path.push(i)
        match child {
          @seam.CstElement::Node(n) => {
            current = n
            current_offset = child_offset
            found = true
            break
          }
          @seam.CstElement::Token(_) => return None
        }
      }
      child_offset = child_offset + child_len
    }
    if not(found) {
      return None
    }
  }
  Some(path)
}

///|
/// Find the smallest reparseable ancestor containing the edit.
/// Returns the ancestor SyntaxNode and the physical CstNode path for splicing.
/// Returns None if no reparseable ancestor found or edit touches boundaries.
pub fn find_reparseable_ancestor(
  tree : @seam.SyntaxNode,
  edit : @core.Edit,
  is_reparseable : (@seam.RawKind) -> Bool,
) -> (@seam.SyntaxNode, Array[Int])? {
  // Find the deepest node containing edit.start
  let node = tree.find_at(edit.start)
  // Walk up looking for reparseable ancestor
  let mut current = node
  while true {
    let kind = current.kind()
    if is_reparseable(kind) {
      // Check edit is strictly interior (not touching delimiters)
      let block_start = current.start()
      let block_end = current.end()
      let edit_end = edit.start + edit.new_len
      if edit.start > block_start && edit_end < block_end + edit.delta() {
        // Build physical path from root CstNode
        let root_cst = tree.cst_node()
        let block_end = current.end()
        match build_physical_path(root_cst, block_start, block_end, kind) {
          Some(path) => return Some((current, path))
          None => return None
        }
      }
    }
    match current.parent() {
      Some(parent) => current = parent
      None => break
    }
  }
  None
}

///|
/// Path-copy splice: replace a node at the given path with a new node.
/// Walks bottom-up, creating new CstNodes at each ancestor level.
pub fn splice_tree(
  root : @seam.CstNode,
  path : Array[Int],
  new_node : @seam.CstNode,
  trivia_kind? : @seam.RawKind? = None,
  error_kind? : @seam.RawKind? = None,
  incomplete_kind? : @seam.RawKind? = None,
) -> @seam.CstNode {
  if path.is_empty() {
    return new_node
  }
  // Collect nodes along the path (root to target's parent)
  let mut current = root
  let nodes : Array[@seam.CstNode] = [root]
  for i = 0; i < path.length() - 1; i = i + 1 {
    match current.children[path[i]] {
      @seam.CstElement::Node(n) => {
        nodes.push(n)
        current = n
      }
      _ => abort("splice_tree: path leads to token, not node")
    }
  }
  // Replace bottom-up
  let mut replacement : @seam.CstElement = @seam.CstElement::Node(new_node)
  for i = path.length() - 1; i >= 0; i = i - 1 {
    let node = nodes[i]
    let new_parent = node.with_replaced_child(
      path[i], replacement, trivia_kind~, error_kind~, incomplete_kind~,
    )
    replacement = @seam.CstElement::Node(new_parent)
  }
  match replacement {
    @seam.CstElement::Node(n) => n
    _ => abort("splice_tree: unexpected token result")
  }
}
```

- [ ] **Step 2: Add parse_block_isolated function**

Continue in `loom/src/block_reparse.mbt`:

```moonbit
///|
/// Parse a block in isolation: tokenize substring, call reparse function,
/// build tree with block_kind as root, unwrap the double-wrapped result.
fn parse_block_isolated[T : Eq + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind](
  block_text : String,
  block_kind : @seam.RawKind,
  reparse_fn : (@core.ParserContext[T, K]) -> Unit,
  spec : @core.LanguageSpec[T, K],
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
) -> (@seam.CstNode, Array[@core.Diagnostic[T]])? {
  // Tokenize the block text
  let tokens = try {
    tokenize(block_text)
  } catch {
    _ => return None
  }
  // Create ParserContext (uses Array[TokenInfo] constructor)
  let ctx = @core.ParserContext::new(tokens, block_text, spec)
  // Call the reparse function (not spec.parse_root)
  reparse_fn(ctx)
  // Flush trivia and auto-close unclosed nodes
  ctx.flush_trivia()
  while ctx.open_nodes > 0 {
    ctx.open_nodes = ctx.open_nodes - 1
    ctx.events.push(@seam.FinishNode)
  }
  // Build tree with block_kind as root (no interning needed for small blocks)
  // Uses EventBuffer::build_tree which is public, unlike build_tree_generic
  let cst = ctx.events.build_tree(
    block_kind,
    trivia_kind=Some(spec.whitespace_kind.to_raw()),
    error_kind=Some(spec.error_kind.to_raw()),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  )
  // Unwrap: take first Node child (the actual BlockExpr from double-wrap)
  let mut inner : @seam.CstNode? = None
  for child in cst.children {
    match child {
      @seam.CstElement::Node(n) => {
        inner = Some(n)
        break
      }
      _ => ()
    }
  }
  match inner {
    Some(block_cst) => Some((block_cst, ctx.errors))
    None => None
  }
}
```

- [ ] **Step 3: Add reparse_block orchestrator**

Continue in `loom/src/block_reparse.mbt`:

```moonbit
///|
/// Merge diagnostics: keep old outside block, replace inside with new (offset-adjusted).
fn merge_diagnostics[T](
  old_diagnostics : Array[@core.Diagnostic[T]],
  new_diagnostics : Array[@core.Diagnostic[T]],
  block_start : Int,
  old_block_end : Int,
  delta : Int,
) -> Array[@core.Diagnostic[T]] {
  let result : Array[@core.Diagnostic[T]] = []
  // Keep diagnostics before block
  for d in old_diagnostics {
    if d.end <= block_start {
      result.push(d)
    } else if d.start >= old_block_end {
      // After block: shift by delta
      result.push(
        @core.Diagnostic::{
          message: d.message,
          start: d.start + delta,
          end: d.end + delta,
          got_token: d.got_token,
        },
      )
    }
    // Inside block: discard (replaced by new_diagnostics)
  }
  // Add new block diagnostics, offset-adjusted from local to global
  for d in new_diagnostics {
    result.push(
      @core.Diagnostic::{
        message: d.message,
        start: d.start + block_start,
        end: d.end + block_start,
        got_token: d.got_token,
      },
    )
  }
  result
}

///|
/// Attempt block reparse. Returns Some((new_cst, diagnostics)) on success,
/// None to fall through to normal incremental parse.
pub fn reparse_block[T : Eq + @seam.IsTrivia + @seam.IsEof, K : @seam.ToRawKind](
  old_syntax : @seam.SyntaxNode,
  edit : @core.Edit,
  new_source : String,
  spec : @core.BlockReparseSpec[T, K],
  language_spec : @core.LanguageSpec[T, K],
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  old_diagnostics : Array[@core.Diagnostic[T]],
) -> (@seam.CstNode, Array[@core.Diagnostic[T]])? {
  // 1. Find reparseable ancestor
  let (block_node, path) = match find_reparseable_ancestor(
    old_syntax, edit, spec.is_reparseable,
  ) {
    Some(result) => result
    None => return None
  }
  let block_kind = block_node.kind()
  // 2. Get reparse function
  let reparse_fn = match (spec.get_reparser)(block_kind) {
    Some(f) => f
    None => return None
  }
  // 3. Compute new block text range
  let block_start = block_node.start()
  let old_block_end = block_node.end()
  let new_block_end = old_block_end + edit.delta()
  let block_text = new_source.substring(start=block_start, end=new_block_end)
  // 4. Tokenize the substring
  let tokens = try {
    tokenize(block_text)
  } catch {
    _ => return None
  }
  // 5. Integrity check
  if not((spec.is_balanced)(tokens)) {
    return None
  }
  // 6. Parse the block in isolation
  let (new_block_cst, block_diagnostics) = match parse_block_isolated(
    block_text, block_kind, reparse_fn, language_spec, tokenize,
  ) {
    Some(result) => result
    None => return None
  }
  // 7. Splice into old tree
  let new_root = splice_tree(
    old_syntax.cst_node(),
    path,
    new_block_cst,
    trivia_kind=language_spec.whitespace_kind.to_raw(),
    error_kind=language_spec.error_kind.to_raw(),
    incomplete_kind=language_spec.incomplete_kind.to_raw(),
  )
  // 8. Merge diagnostics
  let merged = merge_diagnostics(
    old_diagnostics, block_diagnostics, block_start, old_block_end, edit.delta(),
  )
  Some((new_root, merged))
}
```

- [ ] **Step 4: Run moon check**

Run: `cd loom && moon check`

**Note:** This step may surface issues with:
- `ParserContext::new` visibility or parameter names
- `ctx.get_diagnostics()` method name (may be `ctx.errors` or similar)
- `build_tree_fully_interned` parameter names
- `SyntaxNode::cst_node()` accessibility (it's `priv` — may need a public accessor)

Read the actual source to resolve these. Key files:
- `loom/src/core/parser.mbt` — ParserContext fields and methods
- `seam/event.mbt` — build_tree_fully_interned signature
- `seam/syntax_node.mbt` — cst_node accessor

Fix any compilation issues, then verify with `moon check`.

- [ ] **Step 5: Run all tests**

Run: `cd loom && moon test && cd ../seam && moon test`
Expected: All existing tests PASS

- [ ] **Step 6: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/block_reparse.mbt
git add -A
git commit -m "feat(loom): add find_reparseable_ancestor, splice_tree, reparse_block"
```

---

## Task 5: Factory Integration

**Files:**
- Modify: `loom/src/factories.mbt`

- [ ] **Step 1: Add block reparse pre-check to incremental_parse closure**

In `loom/src/factories.mbt`, find the `incremental_parse` closure inside `new_imperative_parser` (around line 93). Add the block reparse pre-check **before** the TokenBuffer update logic.

The pre-check should:
1. Check if `grammar.block_reparse_spec` is `Some(block_spec)`
2. If so, call `reparse_block(old_syntax, edit, source, block_spec, grammar.spec, grammar.tokenize, last_diags.val)`
3. If it returns `Some((new_cst, new_diagnostics))`:
   - Store diagnostics: `last_diags.val = new_diagnostics`
   - Invalidate TokenBuffer: `token_buf.val = None`
   - Return `@incremental.ParseOutcome::Tree(@seam.SyntaxNode::from_cst(new_cst), 1)`
4. If it returns `None`, fall through to existing incremental parse

Key variable names from `factories.mbt`:
- `last_diags` — `Ref[Array[Diagnostic[T]]]` storing last diagnostics
- `token_buf` — `Ref[TokenBuffer[T]?]` storing the token buffer (set to `None` to invalidate)
- Return type: `@incremental.ParseOutcome` with variants `Tree(SyntaxNode, Int)` and `LexError(String)`

- [ ] **Step 2: Run all tests**

Run: `cd loom && moon test`
Expected: All tests PASS (no grammar has block_reparse_spec yet, so pre-check is never triggered)

- [ ] **Step 3: Commit**

```bash
cd loom && moon info && moon fmt
git add loom/src/factories.mbt
git add -A
git commit -m "feat(loom): add block reparse pre-check in incremental_parse"
```

---

## Task 6: Lambda BlockReparseSpec

**Files:**
- Create: `examples/lambda/src/block_reparse.mbt`
- Modify: `examples/lambda/src/cst_parser.mbt` — make `parse_block_expr` pub
- Modify: `examples/lambda/src/grammar.mbt` — wire spec

- [ ] **Step 1: Make parse_block_expr pub**

In `examples/lambda/src/cst_parser.mbt`, change `parse_block_expr` from `fn` to `pub fn`:

```moonbit
pub fn parse_block_expr(
```

- [ ] **Step 2: Create lambda block reparse spec**

Create `examples/lambda/src/block_reparse.mbt`:

```moonbit
///|
/// Lambda grammar's block reparse specification.
/// Only BlockExpr is reparseable.
pub let lambda_block_reparse_spec : @loom.BlockReparseSpec[
  @token.Token,
  @syntax.SyntaxKind,
] = {
  is_reparseable: fn(kind) {
    kind == @syntax.BlockExpr.to_raw()
  },
  get_reparser: fn(kind) {
    if kind == @syntax.BlockExpr.to_raw() {
      Some(parse_block_expr)
    } else {
      None
    }
  },
  is_balanced: fn(tokens) {
    let mut depth = 0
    for token in tokens {
      if token.token == @token.LBrace {
        depth = depth + 1
      }
      if token.token == @token.RBrace {
        depth = depth - 1
      }
      if depth < 0 {
        return false
      }
    }
    depth == 0
  },
}
```

- [ ] **Step 3: Wire into both lambda grammars**

In `examples/lambda/src/grammar.mbt`, add `block_reparse_spec` to **both** `lambda_grammar` and `lambda_grammar_no_threshold`:

```moonbit
pub let lambda_grammar : @loom.Grammar[...] = @loom.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  fold_node=lambda_fold_node,
  on_lex_error=fn(msg) { @ast.Term::Error("lex error: " + msg) },
  error_token=Some(@token.Error("")),
  prefix_lexer=Some(@core.PrefixLexer::new(lex_step=@lexer.lambda_step_lexer)),
  block_reparse_spec=Some(lambda_block_reparse_spec),
)
```

- [ ] **Step 4: Run moon check**

Run: `cd examples/lambda && moon check`
Expected: No errors

- [ ] **Step 5: Run all tests**

Run: `cd examples/lambda && moon test`
Expected: All 385 tests PASS (block reparse is now active — existing incremental tests serve as the first correctness check)

**If any incremental tests fail:** Block reparse may be producing different CSTs than full incremental. Debug by checking:
- Is the unwrap step correct? (double-wrapped tree → inner node)
- Are diagnostic offsets correct?
- Is the physical path correct? (RepeatGroup handling)

- [ ] **Step 6: Commit**

```bash
cd examples/lambda
moon info && moon fmt
git add src/block_reparse.mbt src/cst_parser.mbt src/grammar.mbt
git add -A
git commit -m "feat(lambda): add BlockReparseSpec for BlockExpr"
```

---

## Task 7: Correctness Tests

**Files:**
- Create: `examples/lambda/src/block_reparse_test.mbt`

- [ ] **Step 1: Write correctness tests**

Create `examples/lambda/src/block_reparse_test.mbt`:

```moonbit
///|
test "block reparse: edit inside block matches full reparse" {
  let source = "let x = { let a = 1; a }\nx"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Change 1 to 2 inside block
  let new_source = "let x = { let a = 2; a }\nx"
  let edit = @core.Edit::new(18, 1, 1)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // Verify block reparse was used (reuse_count == 1)
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: edit touching brace falls through" {
  let source = "let x = { 1 }\nx"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Delete the closing brace — should fall through to normal incremental
  let new_source = "let x = { 1 \nx"
  let edit = @core.Edit::new(12, 1, 0)
  let incr_term = parser.edit(edit, new_source)
  // Should still produce a term (with errors)
  let printed = @ast.print_term(incr_term)
  inspect(printed.length() > 0, content="true")
}

///|
test "block reparse: nested blocks reparses inner" {
  let source = "{ let x = { let a = 1; a }; x }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Edit inside inner block
  let new_source = "{ let x = { let a = 2; a }; x }"
  let edit = @core.Edit::new(20, 1, 1)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}

///|
test "block reparse: no block in source falls through" {
  let source = "let x = 1\nx"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  let new_source = "let x = 2\nx"
  let edit = @core.Edit::new(8, 1, 1)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // Verify block reparse was NOT used (reuse_count > 1 means normal incremental)
  inspect(parser.get_last_reuse_count() != 1, content="true")
}

///|
test "block reparse: block with errors produces correct diagnostics" {
  let source = "{ let a = 1 let b = 2; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Edit value — block has missing delimiter error
  let new_source = "{ let a = 3 let b = 2; a }"
  let edit = @core.Edit::new(10, 1, 1)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}

///|
test "block reparse: empty block after deletion" {
  let source = "{ let a = 1; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // Delete everything inside braces: "{ }"
  let new_source = "{ }"
  let edit = @core.Edit::new(2, 13, 0)
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch {
    _ => {
      // parse() raises on diagnostics, use parse_term instead
      let (term, _) = parse_term(new_source) catch { _ => abort("lex error") }
      term
    }
  }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}

///|
test "block reparse: block reparse then normal edit works" {
  // Verify TokenBuffer invalidation: block reparse then non-block edit
  let source = "{ let a = 1; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  // First edit: inside block (block reparse)
  let source2 = "{ let a = 2; a }"
  let edit1 = @core.Edit::new(10, 1, 1)
  let _ = parser.edit(edit1, source2)
  // Second edit: add text after block (falls through to normal incremental)
  let source3 = "{ let a = 2; a }\n42"
  let edit2 = @core.Edit::new(16, 0, 3)
  let incr_term = parser.edit(edit2, source3)
  let full_term = parse(source3) catch { _ => abort("parse error") }
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}
```

- [ ] **Step 2: Run tests**

Run: `cd examples/lambda && moon test -f block_reparse_test.mbt`
Expected: All PASS

If tests fail, debug the block reparse path. Common issues:
- Edit offsets wrong (count characters carefully)
- Unwrap step wrong (check CstNode structure)
- Diagnostic offset adjustment wrong
- Physical path through RepeatGroups incorrect

- [ ] **Step 3: Run full test suite**

Run: `cd examples/lambda && moon test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
cd examples/lambda
moon info && moon fmt
git add src/block_reparse_test.mbt
git add -A
git commit -m "test(lambda): add block reparse correctness tests"
```

---

## Task 8: Final Verification

- [ ] **Step 1: Run all test suites**

```bash
cd examples/lambda && moon test
cd ../../loom && moon test
cd ../seam && moon test
```
Expected: All pass

- [ ] **Step 2: Run moon check**

```bash
cd examples/lambda && moon check
cd ../../loom && moon check
cd ../seam && moon check
```
Expected: No errors

- [ ] **Step 3: Run benchmarks**

```bash
cd examples/lambda && moon bench --release
```
Expected: No significant regression on existing benchmarks

- [ ] **Step 4: Update interfaces and format**

```bash
cd examples/lambda && moon info && moon fmt
cd ../../loom && moon info && moon fmt
cd ../seam && moon info && moon fmt
```

- [ ] **Step 5: Review .mbti changes**

```bash
git diff *.mbti
```
Expected: New entries for `CstNode::with_replaced_child`, `BlockReparseSpec`, `find_reparseable_ancestor`, `splice_tree`, `reparse_block`, lambda's `lambda_block_reparse_spec`, `parse_block_expr` (now pub)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: update interfaces for block reparse"
```

---

## Dependency Graph

```
Task 1 (CstNode::with_replaced_child)
    ↓
Task 2 (BlockReparseSpec struct)
    ↓
Task 3 (Grammar + Factory field)
    ↓
Task 4 (find_reparseable_ancestor + splice_tree + reparse_block)
    ↓
Task 5 (Factory integration pre-check)
    ↓
Task 6 (Lambda BlockReparseSpec)
    ↓
Task 7 (Correctness tests)
    ↓
Task 8 (Final verification)
```

All tasks are sequential — each builds on the previous.

---

## Notes for Implementer

1. **SyntaxNode::cst_node() is public.** `pub fn SyntaxNode::cst_node(self) -> CstNode` exists at `seam/syntax_node.mbt:445`.

2. **ParserContext API.** Constructor: `ParserContext::new(tokens, source, spec)` where `tokens: Array[TokenInfo[T]]`. Diagnostics: `ctx.errors` (direct field access, type `Array[Diagnostic[T]]`). Open node count: `ctx.open_nodes` (mutable Int field). Events: `ctx.events` (type `EventBuffer`).

3. **Tree building.** Use `ctx.events.build_tree(root_kind, trivia_kind~, error_kind~, incomplete_kind~)` — the `EventBuffer::build_tree` method is public and doesn't require interners (unlike `build_tree_fully_interned`). `build_tree_generic` is private to core.

4. **String slicing.** MoonBit uses `new_source.substring(start=N, end=M)`. Check existing code for the exact pattern. Some versions use `string[start:end]` slice syntax.

5. **Diagnostic construction.** `Diagnostic` struct fields: `message`, `start`, `end`, `got_token`. Construct via struct literal: `@core.Diagnostic::{ message, start, end, got_token }`.

6. **TokenBuffer invalidation.** `token_buf` is `Ref[TokenBuffer[T]?]`. Set `token_buf.val = None` after successful block reparse. The factory already handles `None` by rebuilding from scratch.

7. **Existing incremental tests as regression guard.** The 3 incremental tests added in Task 10 of the grammar extension plan (`imperative_parser_test.mbt`) test edits inside blocks. These will exercise the block reparse path once the spec is wired in Task 6. If they break, the block reparse path has a bug.

8. **parse_block_expr visibility.** Making it `pub` exposes it from the lambda package. If this is undesirable, create a `pub fn lambda_block_reparser(kind: RawKind) -> ((ParserContext) -> Unit)?` wrapper instead.

9. **Type constraints.** The `reparse_block` function needs `T : Eq + IsTrivia + IsEof` and `K : ToRawKind`. These are the same constraints used by `parse_tokens_indexed`. If MoonBit gives constraint errors, check the exact trait bounds on the existing functions and match them.

10. **Double tokenization.** The current implementation tokenizes twice: once for `is_balanced` check, once inside `parse_block_isolated`. To optimize, pass the tokens from the balance check into the parse step. This is a straightforward optimization but not required for correctness — defer to a follow-up if needed.
