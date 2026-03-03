# CRDT Exploration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Connect the incremental parser to a CRDT text model and prove two peers applying the same logical edits converge to identical parse trees.

**Architecture:** Three sequential phases — (1) generic `tree_diff` in `loom/src/core/` using `CstNode.hash` as O(1) skip key, (2) simulated two-peer convergence test in `examples/lambda/`, (3) event-graph-walker integration demo. `TextDelta` and `to_edits` are already done (`loom/src/core/delta.mbt`).

**Tech Stack:** MoonBit, `moon test`, `moon check`, `moon info`

---

### Task 1: Green tree diff (`loom/src/core/diff.mbt`)

**Files:**
- Create: `loom/src/core/diff.mbt`
- Create: `loom/src/core/diff_test.mbt`

**Step 1: Write failing tests in `loom/src/core/diff_test.mbt`**

```moonbit
///|
test "tree_diff: identical trees return empty" {
  let (tree, _) = @core.parse_with(
    "λx. x",
    lambda_spec(),
    tokenize,
    parse_root,
  )
  let result = tree_diff(tree, tree)
  inspect(result.length(), content="0")
}

///|
test "tree_diff: token change returns one Edit" {
  let (old_tree, _) = @core.parse_with("x", lambda_spec(), tokenize, parse_root)
  let (new_tree, _) = @core.parse_with("y", lambda_spec(), tokenize, parse_root)
  let result = tree_diff(old_tree, new_tree)
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}

///|
test "tree_diff: insertion widens parent node" {
  let (old_tree, _) = @core.parse_with(
    "λx. x",
    lambda_spec(),
    tokenize,
    parse_root,
  )
  let (new_tree, _) = @core.parse_with(
    "λx. x + 1",
    lambda_spec(),
    tokenize,
    parse_root,
  )
  let result = tree_diff(old_tree, new_tree)
  // At least one Edit covering the changed region
  inspect(result.length() > 0, content="true")
}
```

Note: `lambda_spec()`, `tokenize`, and `parse_root` are the lambda grammar helpers already
used in `loom/src/core/lib_wbtest.mbt`. Copy that pattern — look at how `lib_wbtest.mbt`
sets up a `LanguageSpec` for lambda expressions; you need the same minimal setup here.
Actually, `diff_test.mbt` is a **blackbox** test file (not `_wbtest.mbt`), so it can only
access public API. Use the public `parse_with` from `@core` and build a minimal test spec,
or check if `examples/lambda` has a re-export. Simpler: look at how `edit_test.mbt` works
in the same package — it tests `Edit` using only primitives. For `diff_test.mbt` you can
use two `@seam.CstNode` instances created manually with `@seam.CstToken::new` and
`@seam.CstNode::new`. See below in Step 3 for test corrections.

**Step 1 (revised): Write failing tests in `loom/src/core/diff_test.mbt`**

```moonbit
///|
// Helpers — build minimal CstNode trees for testing.
fn leaf(kind : Int, text : String) -> @seam.CstNode {
  let tok = @seam.CstToken::new(@seam.RawKind(kind), text)
  @seam.CstNode::new(@seam.RawKind(kind), [@seam.CstElement::Token(tok)])
}

///|
test "tree_diff: identical nodes — empty result" {
  let node = leaf(1, "x")
  let result = tree_diff(node, node)
  inspect(result.length(), content="0")
}

///|
test "tree_diff: same-kind same-count — leaf text change produces one Edit" {
  let old = leaf(1, "x")
  let new = leaf(1, "y")
  let result = tree_diff(old, new)
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}

///|
test "tree_diff: kind mismatch — whole-node Edit" {
  let old = leaf(1, "x")
  let new = leaf(2, "x")
  let result = tree_diff(old, new)
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}

///|
test "tree_diff: unchanged left child, changed right child" {
  // Build: Node(kind=10, [Node(kind=1,"a"), Node(kind=1,"b")])
  // vs     Node(kind=10, [Node(kind=1,"a"), Node(kind=1,"z")])
  let a = leaf(1, "a")
  let b_old = leaf(1, "b")
  let b_new = leaf(1, "z")
  let old_root = @seam.CstNode::new(@seam.RawKind(10), [
    @seam.CstElement::Node(a),
    @seam.CstElement::Node(b_old),
  ])
  let new_root = @seam.CstNode::new(@seam.RawKind(10), [
    @seam.CstElement::Node(a),
    @seam.CstElement::Node(b_new),
  ])
  let result = tree_diff(old_root, new_root)
  // Only the second child changed, starting at offset 1 (after "a")
  inspect(result.length(), content="1")
  inspect(result[0].start, content="1")
  inspect(result[0].old_len, content="1")
  inspect(result[0].new_len, content="1")
}
```

**Step 2: Run to verify tests fail**

```bash
cd loom && moon test -p dowdiness/loom/core -f diff_test.mbt 2>&1 | head -20
```

Expected: compilation error — `tree_diff` not defined.

**Step 3: Implement `loom/src/core/diff.mbt`**

```moonbit
///|
/// Walk two CST trees simultaneously, appending Edit records for changed regions.
/// Uses CstNode.hash as an O(1) skip key: equal hashes mean structurally
/// identical subtrees, skipping the subtree without recursion.
fn diff_nodes(
  old : @seam.CstNode,
  new : @seam.CstNode,
  old_pos : Int,
  result : Array[Edit],
) -> Unit {
  // O(1) skip: same hash means structurally identical
  if old.hash == new.hash {
    return
  }
  // Kind or child-count mismatch: emit one Edit for the whole pair
  if old.kind != new.kind || old.children.length() != new.children.length() {
    result.push(Edit::new(old_pos, old.text_len, new.text_len))
    return
  }
  // Same kind and child count: walk children pairwise
  let mut pos = old_pos
  for i = 0; i < old.children.length(); i = i + 1 {
    let old_child = old.children[i]
    let new_child = new.children[i]
    match (old_child, new_child) {
      (@seam.CstElement::Node(o), @seam.CstElement::Node(n)) =>
        diff_nodes(o, n, pos, result)
      (@seam.CstElement::Token(o), @seam.CstElement::Token(n)) =>
        if o != n {
          result.push(Edit::new(pos, o.text_len(), n.text_len()))
        }
      _ =>
        // Node vs Token mismatch: emit one Edit
        result.push(Edit::new(pos, old_child.text_len(), new_child.text_len()))
    }
    pos = pos + old_child.text_len()
  }
}

///|
/// Compute the minimal set of Edit records describing what changed between
/// two parse trees. Uses CstNode.hash as an O(1) skip so unchanged subtrees
/// are detected without recursion.
///
/// Positions are in the old document. An empty Array means both trees are
/// structurally identical. The returned Edits can be fed directly back into
/// ImperativeParser.edit() to re-sync the parser after a merge.
pub fn tree_diff(old : @seam.CstNode, new : @seam.CstNode) -> Array[Edit] {
  let result : Array[Edit] = []
  diff_nodes(old, new, 0, result)
  result
}
```

**Step 4: Run tests to verify they pass**

```bash
cd loom && moon test -p dowdiness/loom/core -f diff_test.mbt 2>&1
```

Expected: all 4 diff tests pass.

**Step 5: Run full loom suite**

```bash
cd loom && moon test 2>&1 | tail -5
```

Expected: all existing tests pass + 4 new.

**Step 6: Commit**

```bash
cd loom
git add src/core/diff.mbt src/core/diff_test.mbt
git commit -m "feat(loom): add tree_diff using CstNode.hash as O(1) skip key"
```

---

### Task 2: `text_to_delta` helper

**Files:**
- Modify: `loom/src/core/delta.mbt` (append new function)
- Modify: `loom/src/core/delta_test.mbt` (append new tests)

**Step 1: Append failing tests to `loom/src/core/delta_test.mbt`**

```moonbit
///|
test "text_to_delta: identical strings — Retain only" {
  let result = text_to_delta("abc", "abc")
  // Retain(3), no delete/insert
  inspect(result.length(), content="1")
  match result[0] {
    TextDelta::Retain(3) => ()
    other => abort("expected Retain(3), got: " + other.to_string())
  }
}

///|
test "text_to_delta: pure insert in middle" {
  // "abc" → "abXc": insert "X" at position 2
  let result = text_to_delta("abc", "abXc")
  inspect(result.length(), content="2")
  inspect(result[0], content="Retain(2)")
  inspect(result[1], content="Insert(\"X\")")
}

///|
test "text_to_delta: pure delete in middle" {
  // "abXc" → "abc": delete "X" at position 2
  let result = text_to_delta("abXc", "abc")
  inspect(result.length(), content="2")
  inspect(result[0], content="Retain(2)")
  inspect(result[1], content="Delete(1)")
}

///|
test "text_to_delta: replace middle" {
  // "hello" → "world": nothing in common
  let result = text_to_delta("hello", "world")
  inspect(result.length(), content="2")
  inspect(result[0], content="Delete(5)")
  inspect(result[1], content="Insert(\"world\")")
}

///|
test "text_to_delta: insert at start" {
  // "" → "hi": pure insert
  let result = text_to_delta("", "hi")
  inspect(result.length(), content="1")
  inspect(result[0], content="Insert(\"hi\")")
}

///|
test "text_to_delta: round-trip with to_edits" {
  // text_to_delta → to_edits should produce one Edit for a simple replacement
  let delta = text_to_delta("λx. x", "λx. x + 1")
  let edits = to_edits(delta)
  inspect(edits.length(), content="1")
  inspect(edits[0].start, content="5")
  inspect(edits[0].old_len, content="0")
  inspect(edits[0].new_len, content="4")
}
```

**Step 2: Run to verify tests fail**

```bash
cd loom && moon test -p dowdiness/loom/core -f delta_test.mbt 2>&1 | grep "FAILED\|error" | head -10
```

Expected: `text_to_delta` not defined.

**Step 3: Append `text_to_delta` to `loom/src/core/delta.mbt`**

```moonbit
///|
/// Convert a (old, new) string pair into a minimal TextDelta sequence.
///
/// Finds the longest common prefix and suffix, then emits:
///   [Retain(prefix), Delete(old_mid_len), Insert(new_mid)]
///
/// Handles any single contiguous change (the common CRDT case after merge).
/// For identical strings, returns [Retain(n)] — to_edits converts this to [].
pub fn text_to_delta(old : String, new : String) -> Array[TextDelta] {
  let old_len = old.length()
  let new_len = new.length()
  // Find common prefix length
  let mut prefix = 0
  while prefix < old_len && prefix < new_len && old[prefix] == new[prefix] {
    prefix += 1
  }
  // Find common suffix length (don't overlap with prefix region)
  let mut suffix = 0
  while suffix < old_len - prefix &&
        suffix < new_len - prefix &&
        old[old_len - 1 - suffix] == new[new_len - 1 - suffix] {
    suffix += 1
  }
  let old_mid_len = old_len - prefix - suffix
  let new_mid = (new[prefix:new_len - suffix] catch { _ => "" }).to_string()
  let result : Array[TextDelta] = []
  if prefix > 0 {
    result.push(TextDelta::Retain(prefix))
  }
  if old_mid_len > 0 {
    result.push(TextDelta::Delete(old_mid_len))
  }
  if new_mid.length() > 0 {
    result.push(TextDelta::Insert(new_mid))
  }
  result
}
```

**Step 4: Run tests**

```bash
cd loom && moon test -p dowdiness/loom/core -f delta_test.mbt 2>&1
```

Expected: all delta tests pass (existing 8 + new 6 = 14).

**Step 5: Run full loom suite**

```bash
cd loom && moon test 2>&1 | tail -5
```

**Step 6: Commit**

```bash
cd loom
git add src/core/delta.mbt src/core/delta_test.mbt
git commit -m "feat(loom): add text_to_delta(old, new) string-pair helper"
```

---

### Task 3: Regenerate loom interfaces

**Step 1: Regenerate and format**

```bash
cd loom && moon info && moon fmt
```

**Step 2: Verify**

```bash
cd loom && moon check 2>&1
```

Expected: clean.

**Step 3: Check diff**

```bash
git diff loom/src/core/pkg.generated.mbti
```

Expected: `tree_diff` and `text_to_delta` appear in the interface.

**Step 4: Commit**

```bash
cd loom
git add src/core/pkg.generated.mbti
git commit -m "chore(loom): regenerate interfaces (tree_diff, text_to_delta)"
```

---

### Task 4: Simulated two-peer convergence test

**Files:**
- Create: `examples/lambda/src/crdt_peer_test.mbt`

**Step 1: Write failing test in `examples/lambda/src/crdt_peer_test.mbt`**

```moonbit
// Simulated two-peer CRDT convergence test.
// Each peer has a String (the text) and an ImperativeParser.
// We manually apply TextDelta sequences to both peers and assert convergence.

///|
struct Peer {
  mut text : String
  parser : @incremental.ImperativeParser[@seam.SyntaxNode]
}

///|
fn Peer::new(source : String) -> Peer {
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  { text: source, parser }
}

///|
/// Apply a TextDelta to a String, producing the new text.
fn build_new_text(source : String, delta : Array[@core.TextDelta]) -> String {
  let buf = StringBuilder::new()
  let mut cursor = 0
  for d in delta {
    match d {
      @core.TextDelta::Retain(n) => {
        buf.write_string((source[cursor:cursor + n] catch { _ => "" }).to_string())
        cursor += n
      }
      @core.TextDelta::Delete(n) => cursor += n
      @core.TextDelta::Insert(s) => buf.write_string(s)
    }
  }
  buf.write_string((source[cursor:] catch { _ => "" }).to_string())
  buf.to_string()
}

///|
/// Apply a TextDelta to a peer: update text and drive the incremental parser.
///
/// Applies each Edit from to_edits() sequentially. For each edit, the inserted
/// content is extracted from the final new_text — this works because edits
/// from to_edits() are in sequential-application order, so edit.start in the
/// intermediate source corresponds to the same offset in new_text.
fn apply_peer_delta(peer : Peer, delta : Array[@core.TextDelta]) -> Unit {
  let new_text = build_new_text(peer.text, delta)
  let edits = @core.to_edits(delta)
  let mut current = peer.text
  for edit in edits {
    let inserted = (new_text[edit.start:edit.start + edit.new_len] catch {
      _ => ""
    }).to_string()
    current = (current[0:edit.start] catch { _ => "" }).to_string() +
      inserted +
      (current[edit.start + edit.old_len:] catch { _ => "" }).to_string()
    let _ = peer.parser.edit(edit, current)
  }
  peer.text = new_text
}

///|
test "two peers converge after sequential sync" {
  // Both peers start empty
  let peer_a = Peer::new("")
  let peer_b = Peer::new("")
  // Peer A types "λx. x"
  let delta_a = [@core.TextDelta::Insert("λx. x")]
  apply_peer_delta(peer_a, delta_a)
  // Peer B receives A's edit
  apply_peer_delta(peer_b, delta_a)
  // Both should have same text
  inspect(peer_a.text == peer_b.text, content="true")
  // Both should have same CST
  let tree_a = peer_a.parser.get_tree().unwrap()
  let tree_b = peer_b.parser.get_tree().unwrap()
  inspect(tree_a.cst_node() == tree_b.cst_node(), content="true")
}

///|
test "two peers converge after two rounds of sync" {
  let peer_a = Peer::new("")
  let peer_b = Peer::new("")
  // Round 1: A types initial expression, B gets it
  let delta1 = [@core.TextDelta::Insert("42")]
  apply_peer_delta(peer_a, delta1)
  apply_peer_delta(peer_b, delta1)
  // Round 2: A extends, B gets it
  let delta2 = [
    @core.TextDelta::Retain(2),
    @core.TextDelta::Insert(" + 1"),
  ]
  apply_peer_delta(peer_a, delta2)
  apply_peer_delta(peer_b, delta2)
  // Both converge
  inspect(peer_a.text, content="42 + 1")
  inspect(peer_b.text, content="42 + 1")
  let tree_a = peer_a.parser.get_tree().unwrap()
  let tree_b = peer_b.parser.get_tree().unwrap()
  inspect(tree_a.cst_node() == tree_b.cst_node(), content="true")
}

///|
test "tree_diff confirms incremental parse matches full reparse after sync" {
  // After applying a delta, the incremental parse and a fresh full parse
  // should produce identical CstNodes — tree_diff returns empty.
  let peer = Peer::new("42")
  let delta = [@core.TextDelta::Retain(2), @core.TextDelta::Insert(" + 1")]
  apply_peer_delta(peer, delta)
  // Full reparse of final text
  let (fresh_cst, _) = @core.parse_with(
    peer.text,
    lambda_spec(),
    tokenize_lambda,
    parse_lambda_root,
  )
  let incremental_cst = peer.parser.get_tree().unwrap().cst_node()
  let diffs = @core.tree_diff(incremental_cst, fresh_cst)
  inspect(diffs.length(), content="0")
}
```

Note: The third test uses `lambda_spec()`, `tokenize_lambda`, and `parse_lambda_root`
which are exposed by the lambda grammar. Check `examples/lambda/src/grammar.mbt` and
`cst_parser.mbt` to find the correct public names. If they aren't public, use
`peer_a.text == peer_b.text` and `tree_a.cst_node() == tree_b.cst_node()` as the
convergence check (the first two tests already do this), and drop the third test.

**Step 2: Run to verify tests compile or fail**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f crdt_peer_test.mbt 2>&1 | head -30
```

Fix any compilation errors (missing imports, wrong function names) before continuing.
Check `examples/lambda/src/moon.pkg` to ensure `@core`, `@loom`, `@incremental`, and
`@seam` are already imported (they are — see the existing `moon.pkg`).

**Step 3: Run all lambda tests to verify no regressions**

```bash
cd examples/lambda && moon test 2>&1 | tail -5
```

Expected: all existing tests pass + new peer tests.

**Step 4: Commit**

```bash
cd examples/lambda
git add src/crdt_peer_test.mbt
git commit -m "test(lambda): add simulated two-peer CRDT convergence test"
```

---

### Task 5: event-graph-walker integration demo

**Files:**
- Modify: `examples/lambda/moon.mod.json` (add dependency)
- Modify: `examples/lambda/src/moon.pkg` (add import for test)
- Create: `examples/lambda/src/crdt_egw_test.mbt`

**Step 1: Add event-graph-walker to `examples/lambda/moon.mod.json`**

The current deps section is:
```json
"deps": {
  "dowdiness/loom": { "path": "../../loom" },
  "dowdiness/seam": { "path": "../../seam" },
  "moonbitlang/quickcheck": "0.9.10"
}
```

Add:
```json
"deps": {
  "dowdiness/loom": { "path": "../../loom" },
  "dowdiness/seam": { "path": "../../seam" },
  "dowdiness/event-graph-walker": { "path": "../../../event-graph-walker" },
  "moonbitlang/quickcheck": "0.9.10"
}
```

**Step 2: Add the egw import to `examples/lambda/src/moon.pkg`** (in the `for "test"` block)

Open `examples/lambda/src/moon.pkg` and add to the existing test import block:
```
"dowdiness/event-graph-walker/text" @egw,
```

If there is no `for "test"` block, add one:
```
import {
  ...existing imports...
} for "test" {
  "dowdiness/event-graph-walker/text" @egw,
}
```

Check `moon.pkg` first — the structure may differ. The import should be scoped to `"test"` only so the EGW dependency doesn't affect production builds.

**Step 3: Install the dependency**

```bash
cd examples/lambda && moon update 2>&1
```

Expected: dependency resolved or already available via path.

**Step 4: Write the integration demo in `examples/lambda/src/crdt_egw_test.mbt`**

```moonbit
// event-graph-walker integration demo.
// EgwPeer wraps a TextDoc (real CRDT) + ImperativeParser.
// bridge_sync() converts a SyncMessage to TextDelta via text_to_delta,
// then drives the incremental parser incrementally.

///|
struct EgwPeer {
  doc : @egw.TextDoc
  parser : @incremental.ImperativeParser[@seam.SyntaxNode]
}

///|
fn EgwPeer::new(agent_id : String) -> EgwPeer {
  let doc = @egw.TextDoc::new(agent_id)
  let parser = @loom.new_imperative_parser("", lambda_grammar)
  let _ = parser.parse()
  { doc, parser }
}

///|
/// Snapshot text, apply a SyncMessage, then drive the incremental parser
/// with the resulting TextDelta.
fn EgwPeer::bridge_sync(self : EgwPeer, message : @egw.SyncMessage) -> Unit {
  let old_text = self.doc.text()
  try {
    self.doc.sync().apply(message)
  } catch {
    _ => return // skip on error in demo
  }
  let new_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let delta = @core.text_to_delta(old_text, new_text)
  let new_text_final = new_text
  let edits = @core.to_edits(delta)
  let mut current = old_text
  for edit in edits {
    let inserted = (new_text_final[edit.start:edit.start + edit.new_len] catch {
      _ => ""
    }).to_string()
    current = (current[0:edit.start] catch { _ => "" }).to_string() +
      inserted +
      (current[edit.start + edit.old_len:] catch { _ => "" }).to_string()
    let _ = self.parser.edit(edit, current)
  }
}

///|
test "egw two peers converge: same text and parse tree after sync" {
  let peer_a = EgwPeer::new("a")
  let peer_b = EgwPeer::new("b")
  // Peer A inserts a lambda expression
  try {
    let _ = peer_a.doc.insert(@egw.Pos::at(0), "λx. x")
  } catch {
    _ => abort("peer_a insert failed")
  }
  // Peer B inserts " + 1" — but B hasn't synced yet, so B's doc is still ""
  // B inserts first, then we sync A→B and B→A
  try {
    let _ = peer_b.doc.insert(@egw.Pos::at(0), " + 1")
  } catch {
    _ => abort("peer_b insert failed")
  }
  // Export each peer's ops
  let msg_a = try {
    peer_a.doc.sync().export_all()
  } catch {
    _ => abort("export_all failed for a")
  }
  let msg_b = try {
    peer_b.doc.sync().export_all()
  } catch {
    _ => abort("export_all failed for b")
  }
  // Apply cross-sync
  peer_a.bridge_sync(msg_b)
  peer_b.bridge_sync(msg_a)
  // Both peers should have the same text (order determined by eg-walker merge)
  inspect(peer_a.doc.text() == peer_b.doc.text(), content="true")
  // Both parse trees should match
  let tree_a = peer_a.parser.get_tree().unwrap()
  let tree_b = peer_b.parser.get_tree().unwrap()
  inspect(tree_a.cst_node() == tree_b.cst_node(), content="true")
}
```

**Step 5: Run tests**

```bash
cd examples/lambda && moon test -p dowdiness/lambda -f crdt_egw_test.mbt 2>&1 | head -30
```

Fix any compilation errors. Common issues:
- `@egw.Pos::at(0)` — check actual constructor name in `pkg.generated.mbti`
- `@egw.SyncMessage` vs `@egw.text.SyncMessage` — check the alias used in `moon.pkg`
- `try { ... } catch { _ => }` — MoonBit error handling syntax

**Step 6: Run full lambda suite**

```bash
cd examples/lambda && moon test 2>&1 | tail -10
```

Expected: all tests pass including the new egw test.

**Step 7: Commit**

```bash
cd examples/lambda
git add moon.mod.json src/moon.pkg src/crdt_egw_test.mbt
git commit -m "test(lambda): add event-graph-walker integration demo with bridge_sync"
```

---

### Task 6: Update ROADMAP and archive design

**Step 1: Update `examples/lambda/ROADMAP.md`**

In the CRDT Exploration section, update the status line from `Research phase` to
`Complete (2026-03-03)` and mark all three "What to Build" checklist items done.

**Step 2: Mark design doc complete and archive**

In `docs/plans/2026-03-03-crdt-exploration-design.md`, change the Status line from
`Approved` to `Complete`.

Then move it:
```bash
cd loom && git mv docs/plans/2026-03-03-crdt-exploration-design.md docs/archive/completed-phases/
```

**Step 3: Update `docs/README.md`**

Remove the entry from Active Plans and add to Archive:
```markdown
## Active Plans

(empty)
```

In the archive section, the `archive/completed-phases/` link already covers it generically.

**Step 4: Validate docs**

```bash
cd loom && bash check-docs.sh 2>&1
```

Expected: all checks pass.

**Step 5: Final commit**

```bash
cd loom
git add docs/ examples/lambda/ROADMAP.md
git commit -m "docs: mark CRDT exploration complete, archive design doc"
```
