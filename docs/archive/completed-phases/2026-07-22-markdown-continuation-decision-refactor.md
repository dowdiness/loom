# Markdown Continuation Decision Refactor Implementation Plan

**Status:** Complete

**Completion note:** Implemented in commits `8df3581..4f43ef6`, with final private-visibility cleanup in `c4f2688` and speculative/actual continuation characterization coverage in `a1e231e`. The focused continuation, inline, and parser tests pass; `moon test --target native examples/markdown` reports `Total tests: 339, passed: 339, failed: 0`; the Markdown package check returns to the 57-warning baseline with zero errors; documentation and diff checks pass.

**Decision record:**

- No ADR needed: this implements the documented Markdown-local continuation design without changing public APIs, parser ownership, or architectural scope.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Markdown's boolean continuation callback with typed decision/consumption handlers while preserving CST output, speculative rollback, incremental behavior, and all existing continuation semantics.

**Architecture:** The Markdown block parser remains the owner of continuation policy. Continuing policies construct an owner-specific `ContinuationHandler[T]`; the inline driver evaluates its decision and passes the typed action to the matching consumer. Always-line-bound parsing uses a separate non-generic entry point, so no fake stop action or generic stop handler exists. A private boolean bridge may remain inside the inline scanner solely to thread continuation through nested inline parsers; no block-parser call site constructs that bridge directly.

**Tech Stack:** MoonBit 0.10.0+; `@core.ParserContext`; Markdown `InlineParsePolicy`; existing CST event/checkpoint infrastructure; `moon check`, targeted `moon test`, `moon fmt`, generated `.mbti` inspection, and `check-docs.sh`.

## Global Constraints

- Preserve all existing Markdown behavior, CST event order, diagnostics, source fidelity, incremental reuse, and block-boundary decisions.
- Use `ContinuationDecision[T] { Continue(T); Stop }` and owner-specific action types exactly as defined in the approved design spec.
- Keep `ContinuationHandler[T]` for continuing policies only:
  `decide : () -> ContinuationDecision[T]` and `consume : (T) -> Unit`.
- Use `parse_indexed_inline_container_without_continuation` for always-line-bound policies; do not introduce `StopOnly[T]`, `Unit` actions, empty action enums, or fake payloads.
- Keep `ParserContext`, `token_at`, `goal_source`, parser-session callbacks, generated grammar interfaces, delimiter-frontier integration, invalidation, and benchmark baselines unchanged.
- Decision functions must not directly call `emit_token`, `start_node`, `finish_node`, or `bump_error`; CST effects remain in `consume` functions or existing block-parser operations outside the decision.
- Preserve existing `ctx.lookahead` usage inside observation-only Markdown helpers and preserve the current speculative delimiter-index pass followed by the actual parse pass.
- Keep owner-specific `decide_*` and `consume_*` pairing local to the owner; do not expose a generic factory that permits cross-policy pairing.
- Direct purity tests may inspect only existing public observations: `current_token_range`, `current_node_kind`, `lex_mode`, and the controlled event-mark delta. Do not add core introspection for private diagnostics or reuse fields.
- `ParserContext::mark()` returns the pre-push event length and appends exactly one tombstone. A decision with no net event mutation must satisfy `after_mark == before_mark + 1`.
- Every edited MoonBit file receives `rtk moon check examples/markdown` before the next MoonBit edit. Use `moon ide` diagnostics/type information while changing symbols; do not hand-edit generated `.mbti` files.
- Use `rtk` for all shell commands. Run formatters only in the final verification task.
- No compatibility shim for the old `() -> Bool` call-site API. The private scanner bridge is an implementation detail, not a public or block-parser continuation contract.

## File Map

- Modify: `examples/markdown/inline_parser.mbt`
  - Define the generic continuation decision/handler shape.
  - Refactor the inline container driver and thread a handler-derived continuation bridge through nested inline parsing.
  - Add the non-generic no-continuation driver for line-bound containers.
- Modify: `examples/markdown/cst_parser.mbt`
  - Define Markdown owner-specific action enums.
  - Extract decision and consumption functions from root, block quote, setext, list-item, and list-item-setext callbacks.
  - Construct typed handlers at every continuing call site and route headings through the no-continuation driver.
- Create: `examples/markdown/continuation_wbtest.mbt`
  - Focused white-box tests for decision variants, public-state purity, controlled event-mark deltas, action re-evaluation, and driver integration.
- Modify: `docs/README.md`
  - Add the new implementation-plan link beside the related Markdown continuation design spec.
- Inspect only after implementation: `examples/markdown/pkg.generated.mbti`
  - Confirm the private refactor did not unintentionally change the generated public interface.

---

## Task 1: Define typed continuation interfaces and owner action types

**Files:**
- Modify: `examples/markdown/inline_parser.mbt:68-73`
- Modify: `examples/markdown/cst_parser.mbt` near the continuation helpers and owner call sites
- Test: `examples/markdown/continuation_wbtest.mbt` created in Task 2

**Interfaces:**
- Produces `ContinuationDecision[T]`, `ContinuationHandler[T]`, and the owner-specific action enums consumed by Tasks 2–6.
- Does not change parser behavior or any call site yet.

### Steps

- [x] **1. Add the private generic decision and handler declarations.**

  Place the declarations near `parse_indexed_inline_container` in `inline_parser.mbt`:

  ```moonbit
priv enum ContinuationDecision[T] {
    Continue(T)
    Stop
  }

priv struct ContinuationHandler[T] {
    decide : () -> ContinuationDecision[T]
    consume : (T) -> Unit
  }
  ```

  Keep both types private to the Markdown package. Do not add a stop-only variant to either type.

- [x] **2. Add all owner-specific action enums in `cst_parser.mbt`.**

  Add the exact variants from the approved design:

  ```moonbit
priv enum RootContinuationKind {
    NoPrefix
    ThematicBreakPrefix
    ListMarkerPrefix
  }

priv enum ContinuationPrefixKind {
    NoPrefix
    ThematicBreakPrefix
    ListMarkerPrefix
  }

priv enum BlockQuoteContinuationKind {
    MarkerAndPrefix(ContinuationPrefixKind)
    PrefixOnly(ContinuationPrefixKind)
  }

priv enum BlockQuoteHeadingContinuationKind {
    MarkerAndPrefix(ContinuationPrefixKind)
  }

priv enum SetextContinuationKind {
    NoPrefix
    OrderedMarkerAsText
  }

priv enum ListItemContinuationKind {
    NoPrefix
    IndentationPrefix
    OrderedMarkerAsText
  }

priv enum ListItemSetextContinuationKind {
    NoPrefix
    IndentationPrefix
    OrderedMarkerAsText
  }
  ```

  Keep the enums package-private. Do not add `derive(Eq)` solely for the refactor; tests can match each expected variant and payload directly.

- [x] **3. Check the type-only change before any behavioral edit.**

  Run:

  ```bash
  rtk moon check examples/markdown
  ```

  Expected: the Markdown package checks successfully with no errors and no warning
  delta from the pre-task baseline. Mark all package-internal continuation types as
  `priv`; MoonBit permits cross-file use within the package. Do not suppress warnings
  with fake uses or leave package-internal declarations unqualified.

---

## Task 2: Extract root and setext decisions/consumers with focused tests

**Files:**
- Modify: `examples/markdown/cst_parser.mbt:141-180,277-303`
- Create: `examples/markdown/continuation_wbtest.mbt`

**Interfaces:**
- Produces:
  - `decide_root_paragraph_continuation(ctx) -> ContinuationDecision[RootContinuationKind]`
  - `consume_root_continuation(ctx, kind : RootContinuationKind) -> Unit`
  - `decide_setext_continuation(ctx) -> ContinuationDecision[SetextContinuationKind]`
  - `consume_setext_continuation(ctx, kind : SetextContinuationKind) -> Unit`
- Preserves the existing root paragraph and root setext call-site behavior until Task 6 migrates the driver calls.

### Steps

- [x] **1. Create the focused continuation test fixture helper.**

  In `continuation_wbtest.mbt`, add a package-local context constructor using the existing Markdown tokenizer and spec:

  ```moonbit
  fn continuation_context(
    source : String,
  ) -> @core.ParserContext[Token, SyntaxKind] {
    let tokens = tokenize(source) catch {
      _ => abort("continuation test tokenization failed")
    }
    @core.ParserContext::new(tokens, source, markdown_spec)
  }
  ```

  Test sources should begin at a newline when exercising a continuation decision, for example `"\nbar\n"`, so the context is at the same observation point used by the inline driver.

- [x] **2. Extract root paragraph decision logic without effects.**

  Replace the boolean decision/effect mixture in `consume_root_paragraph_inline_continuation` with a decision that preserves the current predicates and returns an action:

  ```moonbit
  fn decide_root_paragraph_continuation(
    ctx : @core.ParserContext[Token, SyntaxKind],
  ) -> ContinuationDecision[RootContinuationKind] {
    let next = ctx.peek_nth(1)
    if next_prefix_requires_root_block_dispatch(ctx) ||
      (
        !next_token_after_newline_is_lone_list_marker(ctx) &&
        (
          token_breaks_paragraph_after_newline(next) ||
          next is Newline ||
          next is EOF
        )
      ) {
      Stop
    } else {
      match next {
        Indentation(_) if ctx.peek_nth(2) is ThematicBreak =>
          Continue(ThematicBreakPrefix)
        ListMarker | OrderedListMarker(_) => Continue(ListMarkerPrefix)
        _ => Continue(NoPrefix)
      }
    }
  }
  ```

  The decision may retain existing `ctx.lookahead` calls in observation helpers, but it must not emit tokens or start/finish nodes.

- [x] **3. Extract root paragraph consumption.**

  Implement `consume_root_continuation` so it emits exactly the events previously emitted by the `else` branch, based only on the typed action:

  ```moonbit
  fn consume_root_continuation(
    ctx : @core.ParserContext[Token, SyntaxKind],
    kind : RootContinuationKind,
  ) -> Unit {
    ctx.emit_token(NewlineToken)
    match kind {
      ThematicBreakPrefix => {
        ctx.emit_token(TextToken)
        ctx.emit_token(TextToken)
      }
      ListMarkerPrefix => ctx.emit_token(TextToken)
      NoPrefix => ()
    }
  }
  ```

- [x] **4. Extract the root setext lambda into named decision and consumer functions.**

  Preserve the current newline guard, underline lookahead, block-boundary checks, and ordered-marker-as-text behavior:

  ```moonbit
  fn decide_setext_continuation(
    ctx : @core.ParserContext[Token, SyntaxKind],
  ) -> ContinuationDecision[SetextContinuationKind] {
    guard ctx.peek() is Newline else { return Stop }
    if setext_underline_depth_after_newline(
      ctx,
      allow_list_marker=true,
      min_indent=0,
    ) is Some(_) {
      Stop
    } else {
      let next = ctx.peek_nth(1)
      if token_breaks_paragraph_after_newline(next) ||
        next is Newline ||
        next is EOF {
        Stop
      } else if next is OrderedListMarker(_) {
        Continue(OrderedMarkerAsText)
      } else {
        Continue(NoPrefix)
      }
    }
  }

  fn consume_setext_continuation(
    ctx : @core.ParserContext[Token, SyntaxKind],
    kind : SetextContinuationKind,
  ) -> Unit {
    ctx.emit_token(NewlineToken)
    match kind {
      OrderedMarkerAsText => ctx.emit_token(TextToken)
      NoPrefix => ()
    }
  }
  ```

  Verify the exact token used for the ordered-marker branch against the current lambda before implementing; the action must describe the token at the post-newline cursor position, not `peek_nth(1)` after the cursor has moved.

- [x] **5. Add root/setext direct decision tests before migrating callers.**

  Add tests that invoke the named decisions directly and match every action:

  ```moonbit
  test "continuation decisions: root variants" {
    match decide_root_paragraph_continuation(continuation_context("\nbar\n")) {
      Continue(NoPrefix) => ()
      _ => abort("expected root NoPrefix")
    }
    match decide_root_paragraph_continuation(continuation_context("\n    ---\n")) {
      Continue(ThematicBreakPrefix) => ()
      _ => abort("expected root ThematicBreakPrefix")
    }
    match decide_root_paragraph_continuation(continuation_context("\n-\n")) {
      Continue(ListMarkerPrefix) => ()
      _ => abort("expected root ListMarkerPrefix")
    }
  }

  test "continuation decisions: root interruption cases stop" {
    match decide_root_paragraph_continuation(continuation_context("\n---\n")) {
      Stop => ()
      _ => abort("expected bare thematic break to stop")
    }
    match decide_root_paragraph_continuation(continuation_context("\n- item\n")) {
      Stop => ()
      _ => abort("expected list item to stop")
    }
  }
  ```

  Add setext tests for `NoPrefix`, `OrderedMarkerAsText`, and `Stop`, plus direct purity assertions. For every direct test:

  ```moonbit
  let before_range = ctx.current_token_range()
  let before_node = ctx.current_node_kind()
  let before_mode = ctx.lex_mode()
  let before_mark = ctx.mark()
  let _ = decision(ctx)
  let after_mark = ctx.mark()
  inspect(ctx.current_token_range(), content=before_range)
  inspect(ctx.current_node_kind(), content=before_node)
  inspect(ctx.lex_mode(), content=before_mode)
  inspect(after_mark, content=before_mark + 1)
  ```

  Use a test-specific `decision` binding when the decision returns different owner types. The test must not wrap the decision in an outer `lookahead`.

- [x] **6. Run focused tests and package check.**

  Run:

  ```bash
  rtk moon test --target native examples/markdown/continuation_wbtest.mbt
  rtk moon check examples/markdown
  ```

  Expected: the newly extracted functions and direct tests compile; existing call sites still require the old callback until Task 6, so the driver API must not be changed in this task unless the implementation batches the dependent migration atomically.

---

## Task 3: Extract block-quote decisions and consumers

**Files:**
- Modify: `examples/markdown/cst_parser.mbt:332-405`
- Modify: `examples/markdown/continuation_wbtest.mbt`

**Interfaces:**
- Produces:
  - `decide_block_quote_paragraph_continuation(ctx) -> ContinuationDecision[BlockQuoteContinuationKind]`
  - `consume_block_quote_continuation(ctx, kind : BlockQuoteContinuationKind) -> Unit`
  - `decide_block_quote_heading_continuation(ctx) -> ContinuationDecision[BlockQuoteHeadingContinuationKind]`
  - `consume_block_quote_heading_continuation(ctx, kind : BlockQuoteHeadingContinuationKind) -> Unit`


Keep the existing boolean callbacks until Task 6 completes the driver migration; these
new functions are an additive extraction, not a compatibility API.
### Steps

- [x] **1. Name the block-quote prefix observation.**

  Add a pure helper that classifies the current post-newline token without emitting:

  ```moonbit
  fn observe_continuation_prefix(
    ctx : @core.ParserContext[Token, SyntaxKind],
    offset : Int,
  ) -> ContinuationPrefixKind {
    let next = ctx.peek_nth(offset)
    match next {
      Indentation(_) if ctx.peek_nth(offset + 1) is ThematicBreak =>
        ThematicBreakPrefix
      ListMarker | OrderedListMarker(_) => ListMarkerPrefix
      _ => NoPrefix
    }
  }
  ```

  Keep `emit_paragraph_continuation_prefix` as the shared effectful helper used by consumers. Do not inline it into only one owner.

- [x] **2. Extract block-quote paragraph decision logic.**

  Preserve both current branches:

  - `BlockQuoteMarker` plus a continuing unquoted token → `MarkerAndPrefix(prefix)`
  - non-marker continuing token → `PrefixOnly(prefix)`
  - thematic-break and block-boundary cases → `Stop`

  The decision may call `next_unquoted_line_is_thematic_break(ctx)` and other existing observation helpers. It must not emit `NewlineToken`, `BlockQuoteMarkerToken`, or prefix tokens. Use `observe_continuation_prefix(ctx, 2)` for a `BlockQuoteMarker` branch and `observe_continuation_prefix(ctx, 1)` for a `PrefixOnly` branch; block-quote setext marker continuation also observes offset `2`.

- [x] **3. Implement typed block-quote consumers.**

  `MarkerAndPrefix(prefix)` emits `NewlineToken`, `BlockQuoteMarkerToken`, then the same prefix events as `emit_paragraph_continuation_prefix`. `PrefixOnly(prefix)` emits `NewlineToken` and the prefix events only. Use the action payload to make the consumed branch explicit; do not re-run a boundary predicate in the consumer.

- [x] **4. Extract block-quote setext decision with all existing guards.**

  `decide_block_quote_heading_continuation` must include, in order:

  1. current token is `Newline`;
  2. `quoted_setext_underline_depth_after_newline(ctx)` is absent;
  3. the existing block-quote marker continuation predicate succeeds;
  4. the action payload records the prefix required by the consumer.

  Do not implement only the marker-matching portion; the setext underline guard currently lives in the surrounding lambda and must move into the decision.

- [x] **5. Add block-quote variant and purity tests.**

  Cover `MarkerAndPrefix(NoPrefix)`, `MarkerAndPrefix(ThematicBreakPrefix)`, `MarkerAndPrefix(ListMarkerPrefix)`, `PrefixOnly(NoPrefix)`, `PrefixOnly(ThematicBreakPrefix)`, `PrefixOnly(ListMarkerPrefix)`, and both stop conditions. Cover block-quote setext marker continuation and its setext-underline stop condition. Repeat the public-state and exact mark-delta assertions.

- [x] **6. Check the package.**

  Run:

  ```bash
  rtk moon check examples/markdown
  ```

  Expected: no type errors. Do not migrate inline driver callers until Task 5/6 unless the changes are kept in one atomic implementation commit.

---

## Task 4: Extract list-item and list-item-setext decisions and consumers

**Files:**
- Modify: `examples/markdown/cst_parser.mbt:1139-1266`
- Modify: `examples/markdown/continuation_wbtest.mbt`

**Interfaces:**
- Produces:
  - `decide_list_item_continuation(ctx, content_indent, allow_ordered_marker, has_paragraph_content) -> ContinuationDecision[ListItemContinuationKind]`
  - `consume_list_item_continuation(ctx, kind : ListItemContinuationKind) -> Unit`
  - `decide_list_item_setext_continuation(ctx, content_indent, allow_ordered_marker) -> ContinuationDecision[ListItemSetextContinuationKind]`
  - `consume_list_item_setext_continuation(ctx, kind : ListItemSetextContinuationKind) -> Unit`

Keep the existing boolean callbacks until Task 6 completes the driver migration; these
new functions are an additive extraction, not a compatibility API.

### Steps

- [x] **1. Preserve the `has_paragraph_content` capture in the decision input.**

  `parse_list_item_inline_content` currently captures `has_paragraph_content` before creating its callback. Move that value into `decide_list_item_continuation`; when it is false, return `Stop` before evaluating continuation boundaries. Do not recompute the value after the inline scan begins.

- [x] **2. Extract list-item action classification.**

  The decision must preserve, in order, the existing ordered-marker nested-list check, list-marker boundary check, block-dispatch check, and `token_can_continue_list_item_paragraph_after_newline` check. Classify `let next = ctx.peek_nth(1)` as:

  ```text
  Indentation(_)        -> IndentationPrefix
  OrderedListMarker(_)  -> OrderedMarkerAsText when allowed
  otherwise             -> NoPrefix
  ```

  The decision emits nothing.

- [x] **3. Extract list-item consumption.**

  `consume_list_item_continuation` emits `NewlineToken`, then emits `IndentationToken` or `TextToken` according to the typed action. The consumer must not repeat the boundary predicates.

- [x] **4. Extract list-item-setext decision and consumption.**

  Preserve `setext_underline_depth_after_newline(... allow_list_marker=false ...)`, ordered nested-list checks, list boundary checks, block-dispatch checks, and the existing ordered-marker/indentation token treatment. Return `Stop` for an underline or any existing boundary condition.

- [x] **5. Add list-item action tests.**

  Cover `NoPrefix`, `IndentationPrefix`, `OrderedMarkerAsText`, and `Stop` for both list-item and list-item-setext decisions. Include both `has_paragraph_content=false` and `true`; the false case must stop without invoking continuation boundary consumption. Repeat direct public-state and exact mark-delta assertions.

- [x] **6. Check the package.**

  Run:

  ```bash
  rtk moon check examples/markdown
  ```

---

## Task 5: Refactor the inline driver and nested continuation plumbing

Tasks 5 and 6 are one atomic API cutover. Do not commit or treat the package as
complete after Task 5 alone: its driver signature change intentionally requires the
immediate call-site migration in Task 6.

**Files:**
- Modify: `examples/markdown/inline_parser.mbt:69-325`

**Interfaces:**
- Replaces the block-parser-facing `continue_line : () -> Bool` parameter on `parse_indexed_inline_container` with `handler : ContinuationHandler[T]`.
- Produces the non-generic `parse_indexed_inline_container_without_continuation(ctx, policy)` entry point.
- Keeps the private nested-parser boolean bridge internal to `inline_parser.mbt` only.

### Steps

- [x] **1. Add the private handler-to-boolean bridge.**

  The existing nested functions (`parse_indexed_inline_code`, `parse_inline`, `parse_bold`, `parse_italic`, and `parse_link`) all need a `() -> Bool` continuation callback to preserve their local loops. Synthesize that callback only inside the driver:

  ```moonbit
  fn continuation_step[T](
    handler : ContinuationHandler[T],
  ) -> () -> Bool {
    fn() -> Bool {
      match handler.decide() {
        Continue(action) => {
          handler.consume(action)
          true
        }
        Stop => false
      }
    }
  }
  ```

  Do not expose this bridge to `cst_parser.mbt`, and do not let a block-parser call site pass a boolean callback.

- [x] **2. Route the generic active driver through the bridge.**

  Change the signature to:

  ```moonbit
  fn[T] parse_indexed_inline_container(
    ctx : @core.ParserContext[Token, SyntaxKind],
    policy : InlineParsePolicy,
    handler : ContinuationHandler[T],
  ) -> Unit
  ```

  Create one `continue_line` closure from the handler and use the same closure in both places where the current implementation calls the callback:

  - delimiter indexing inside the outer `ctx.lookahead`;
  - the actual inline parse loop.

  Preserve the existing delimiter index, token emission, and `parse_indexed_inline_code` behavior. A `Continue(action)` must consume the action in both speculative and actual passes exactly as the current callback emits tokens in both passes.

- [x] **3. Add the non-generic stop driver.**

  Implement:

  ```moonbit
  fn parse_indexed_inline_container_without_continuation(
    ctx : @core.ParserContext[Token, SyntaxKind],
    policy : InlineParsePolicy,
  ) -> Unit {
    parse_indexed_inline_container_with_continue_line(
      ctx,
      policy,
      fn() -> Bool { false },
    )
  }
  ```

  If a shared private scanner helper is needed, name it explicitly and keep it private. Its boolean callback is an internal loop mechanism, not a public continuation policy API. Do not introduce a generic stop handler or fake action.

- [x] **4. Verify nested parser boundaries.**

  Ensure a newline inside code spans, emphasis, or links calls the synthesized continuation step and therefore consumes the same typed action as the outer driver. A `Stop` must preserve existing recovery behavior, including the indexed code-span boundary abort path and unclosed emphasis/link restoration.

- [x] **5. Check the driver before caller migration.**

  Run:

  ```bash
  rtk moon check examples/markdown
  ```

  The check may report the expected old-call-site type errors after the signature
  change. Do not add a compatibility overload or commit this intermediate state;
  continue directly into Task 6 in the same atomic implementation change.

---

## Task 6: Migrate every Markdown continuation call site

**Files:**
- Modify: `examples/markdown/cst_parser.mbt:151-175,233-235,317-319,359-361,400-407,1170-1187,1249-1266`
- Modify: `examples/markdown/continuation_wbtest.mbt`

**Interfaces:**
- Consumes the typed owner decisions/consumers from Tasks 2–4 and the generic/non-generic drivers from Task 5.
- Produces a call-site-complete Markdown parser with no block-parser `() -> Bool` continuation callback construction.

### Steps

- [x] **1. Migrate root setext.**

  Replace the inline lambda at `try_parse_setext_heading` with a handler whose `decide` calls `decide_setext_continuation(ctx)` and whose `consume` calls `consume_setext_continuation(ctx, action)`. Preserve the surrounding setext underline consumption, finish-node, checkpoint, and restore logic.

- [x] **2. Migrate line-bound headings.**

  Replace the always-false callback in `parse_heading_with_prefix` with:

  ```moonbit
  parse_indexed_inline_container_without_continuation(
    ctx,
    InlineParsePolicy::line_bound(),
  )
  ```

  Preserve the following newline emission outside the inline driver.

- [x] **3. Migrate root paragraphs.**

  Construct a `ContinuationHandler[RootContinuationKind]` from `decide_root_paragraph_continuation` and `consume_root_continuation`, then pass it to `parse_indexed_inline_container`.

- [x] **4. Migrate block-quote paragraphs and block-quote setext.**

  Use `ContinuationHandler[BlockQuoteContinuationKind]` for ordinary block quotes. Use `ContinuationHandler[BlockQuoteHeadingContinuationKind]` for `try_parse_block_quote_setext_heading`; the decision must include the setext-specific underline guard from the old lambda.

- [x] **5. Migrate list-item content while preserving captured state.**

  In `parse_list_item_inline_content`, capture `has_paragraph_content` once as today. Construct a `ContinuationHandler[ListItemContinuationKind]` whose decision receives `content_indent`, `allow_ordered_marker`, and the captured boolean. The consumer receives only the action and emits the same prefix events.

- [x] **6. Migrate list-item setext.**

  Construct `ContinuationHandler[ListItemSetextContinuationKind]` with the existing `content_indent` and `allow_ordered_marker` values. Preserve the surrounding setext underline consumption and checkpoint restore.

- [x] **7. Delete the old callback implementations.**

  After every caller uses a typed handler or the non-generic stop driver, delete
  `consume_root_paragraph_inline_continuation`,
  `consume_block_quote_inline_continuation`,
  `consume_block_quote_heading_continuation`,
  `consume_list_item_inline_continuation`, and
  `consume_list_item_setext_heading_inline_continuation`.
  The root setext inline lambda is removed by its call-site migration. Do not leave
  aliases, wrappers, or unused boolean continuation APIs.

- [x] **8. Prove call-site completeness.**

  Search the Markdown package for remaining block-parser uses of the old shape:

  ```bash
  rtk grep -n "parse_indexed_inline_container|continue_line" examples/markdown/cst_parser.mbt examples/markdown/inline_parser.mbt
  ```

  Expected: `cst_parser.mbt` contains only typed handler construction or the non-generic no-continuation entry point; `inline_parser.mbt` contains the private nested boolean bridge only. No compatibility wrapper is permitted.

- [x] **9. Run focused parser tests.**

  Run:

  ```bash
  rtk moon test --target native examples/markdown/continuation_wbtest.mbt
  rtk moon test --target native examples/markdown/inline_test.mbt
  rtk moon test --target native examples/markdown/parser_test.mbt
  rtk moon check examples/markdown
  ```

  Expected: all focused tests pass, including existing multiline emphasis, code-span, heading, setext, block-quote, list-item, and source-fidelity behavior.

---

## Task 7: Full verification, generated-interface inspection, and documentation hygiene

**Files:**
- Inspect: `examples/markdown/pkg.generated.mbti`
- Modify: `docs/README.md` to add the plan link
- Inspect: `docs/superpowers/specs/2026-07-20-markdown-continuation-decision-refactor-design.md`

### Steps

- [x] **1. Run the complete Markdown package test target.**

  From the repository root, run:

  ```bash
  rtk moon test --target native examples/markdown
  ```

  Expected: all Markdown tests pass with no failures. Record the exact result in the implementation PR or completion note.

- [x] **2. Run final formatting and checks.**

  Run:

  ```bash
  rtk moon fmt
  rtk moon check examples/markdown
  rtk moon info --package examples/markdown
  ```

  `moon fmt` is the only formatter invocation. If formatting changes MoonBit files, rerun `rtk moon check examples/markdown` and the focused tests.

- [x] **3. Inspect generated interfaces.**

  Read `examples/markdown/pkg.generated.mbti` after `moon info`. Confirm the new continuation types and functions remain package-private and that no `loom/core/pkg.generated.mbti` or other core interface changes occurred. Never hand-edit generated interfaces.

- [x] **4. Update the documentation index.**

  Add an index entry next to the related Markdown continuation design in `docs/README.md`.
  The archived entry target is `archive/completed-phases/2026-07-22-markdown-continuation-decision-refactor.md`
  and its description must identify this as the completed implementation plan for the
  Markdown-local typed continuation decision/consumption refactor.

- [x] **5. Run documentation and diff checks.**

  Run:

  ```bash
  rtk proxy git diff --check
  rtk proxy bash check-docs.sh
  ```

  Expected: both commands pass; the docs index resolves the new plan link, no fossil references are introduced, and no generated-interface drift is present.

- [x] **6. Perform final independent review after implementation and before completion/PR.**

  Review the implementation diff against the approved design spec with a different model. Require exact file/line findings for:

  - typed action ownership and handler pairing;
  - generic active versus non-generic stop driver use;
  - decision-side effects and exact event-mark delta tests;
  - speculative versus actual action consistency;
  - unchanged parser behavior and package boundaries.

  Do not claim the implementation complete until focused tests, full Markdown tests, `moon check`, docs health, generated-interface inspection, and independent review all pass.

## Completion Criteria

- [x] No Markdown block-parser call site constructs the old `() -> Bool` continuation callback.
- [x] The only always-stop path is the non-generic no-continuation driver.
- [x] Every continuing owner uses its named action type and matching `ContinuationHandler[T]` consumer.
- [x] Direct decisions have no observable public parser-state mutation and satisfy the exact event-mark delta.
- [x] Speculative delimiter indexing and actual parsing preserve the existing event/diagnostic behavior.
- [x] Existing inline, incremental, source-fidelity, and Markdown block tests pass.
- [x] `examples/markdown/pkg.generated.mbti` shows no unintended public API change.
- [x] `check-docs.sh` and `git diff --check` pass.
- [x] No ADR is required for plan creation; an ADR decision is revisited only if the implementation changes the architectural scope or closes a major plan.
