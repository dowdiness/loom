# Grammar Compiled Capabilities Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unresolved runtime grammar names and split predicate evaluation with deterministic compiled slots, pre-parse executable binding, and per-native opaque capabilities while preserving authored grammar IR and HTML/lambda behavior.

**Architecture:** `compile` receives authored `GrammarIr` plus explicit native/guard/dependency declarations and lowers every reference to deterministic opaque slots. `CompiledGrammar` owns its arrays privately but exposes defensive snapshots and `slot_for_name` for the lambda spike. `bind` converts host registries into an opaque `ExecutableGrammar`; runtime evaluates only compiled predicates and per-native capabilities, never name-keyed fallback paths.

**Tech Stack:** MoonBit 0.10.0+84519ca0a; `dowdiness/loom/grammar`; `@core.ParserContext`; `@seam` traits; MoonBit generated `.mbti` interfaces; existing loom grammar, HTML parser, and lambda spike tests.

## Global Constraints

- Preserve authored `GrammarIr`, `Expr`, `Alt`, and `Pred` construction APIs; the intentional break is in compiled/runtime APIs and native registration.
- `compile` receives `native_names`, `guard_names`, and `native_rule_refs`; do not infer explicit compilation declarations from mutable runtime registries.
- Slot assignment is deterministic: root rule slot `0`, remaining rule names sorted; native and guard names independently sorted.
- `CompiledGrammar` fields and executable storage are private. Public snapshots copy compiler-owned arrays; generic `T`/`K` payloads are not cloned.
- `NativeCapabilityBrand` is a fresh `Ref[Unit]` per executable binding and native slot; compare identity with `physical_equal`, never structural equality or a slot-derived integer.
- A foreign or cross-native capability is a programmer defect and calls `fail` before dispatch. A valid nonmatching `Choice` capability returns `false` without a parser diagnostic.
- Every edited MoonBit file receives `moon check` before the next edit; use `moon ide` for diagnostics/type information while changing APIs.
- Use one file per edit call, `rtk`-prefixed commands, and existing package test targets. Do not run formatters until the final formatting task.
- No compatibility shim for `interpret_compiled`, `NativeRef(String)`, raw compiled fields, or runtime registry fallback.

---

## Task 1: Lower authored predicates and names into compiled slots

**Files:**
- Modify: `loom/grammar/compile.mbt`
- Test: `loom/grammar/compile_test.mbt`
- Generated later: `loom/grammar/pkg.generated.mbti`

**Interfaces:**
- Consumes: existing `GrammarIr[T,K]`, `Expr[T,K]`, `Pred[T]`, declaration arguments to `compile`.
- Produces: public opaque slot value types, public compiled snapshot enums, private compiled storage, deterministic lowering used by Tasks 2–4.

### Steps

- [ ] **1. Add failing compiler tests for deterministic and resolved lowering.**

  Add tests that compile a grammar with:
  - two non-root rules whose names sort differently from insertion order;
  - two native names and two guard names in reverse insertion order;
  - nested `Not(All(HostGuard(...), IsToken(...)))` predicates;
  - one native dependency target set supplied in reverse order, targeting multiple top-level `Choice` rules.

  Assert through the planned public methods that:
  - root is `RuleSlot` zero semantically;
  - `slot_for_name` returns stable slots;
  - native/guard snapshot order is sorted;
  - nested guards lower to `HostGuardSlot` in the compiled snapshot;
  - dispatch snapshots contain `RuleSlot` targets in resolved slot order, independent of declaration insertion order.

  Add negative tests for missing guard, missing native, missing dispatch target, and non-`Choice` dispatch target. Run:

  ```bash
  rtk moon test --target native loom/grammar/compile_test.mbt
  ```

  Expected: FAIL because slot types, compiled predicate variants, and snapshot/query methods do not exist yet.

- [ ] **2. Define opaque slot wrappers and compiled predicate representation.**

  In `compile.mbt`, add public wrapper types with private fields and package-private constructors/accessors:

  ```moonbit
  pub struct RuleSlot(Int)
  pub struct NativeSlot(Int)
  pub struct GuardSlot(Int)
  ```

  Add public `CompiledPred[T]` as the snapshot representation:

  ```moonbit
  pub enum CompiledPred[T] {
    Any
    IsToken(T)
    OneOf(Array[T])
    Not(CompiledPred[T])
    All(CompiledPred[T], CompiledPred[T])
    HostGuardSlot(GuardSlot)
  }
  ```

  Keep constructors/accessors for slot integers private. Public callers can pattern-match compiled snapshots and pass slot values back to query methods, but cannot construct slots.

- [ ] **3. Replace validation-only predicate checking with lowering.**

  Implement private:

  ```moonbit
  fn[T] lower_pred(
    pred : Pred[T],
    guard_slot_of : Map[RuleName, GuardSlot],
  ) -> CompiledPred[T] raise GrammarCompileError
  ```

  Map every authored predicate recursively. `HostGuard(name)` resolves to `HostGuardSlot`; missing names raise `MissingHostGuard`. Delete `check_pred_guards`; no compiled expression receives a raw `Pred`.

- [ ] **4. Lower rules, natives, and dependency metadata.**

  Keep the existing explicit `compile` declaration parameters. Sort each declaration set before creating slot maps. Change compiled variants as follows:

  ```text
  RefSlot(Int)         -> RefSlot(RuleSlot)
  NativeRef(RuleName)  -> NativeSlot(NativeSlot)
  Pred fields          -> CompiledPred fields
  ```

  Resolve every `native_rule_refs` target to `RuleSlot`, retain the top-level `Choice` check, sort each resolved target array by `RuleSlot`, and store slot-based dispatch arrays. Make `CompiledGrammar` storage private.

  Add defensive public query methods:

  ```text
  names_snapshot() -> Array[RuleName]
  slot_for_name(RuleName) -> RuleSlot?
  root_slot() -> RuleSlot
  rule_snapshot(RuleSlot) -> CompiledExpr[T,K]
  native_names_snapshot() -> Array[RuleName]
  guard_names_snapshot() -> Array[RuleName]
  native_dispatch_snapshot(NativeSlot) -> Array[RuleSlot]
  ```

  `rule_snapshot` copies compiler-owned nested arrays. Do not claim to clone arbitrary `T` or `K` payload internals.

- [ ] **5. Run the compiler package check and update generated interface only after it is type-correct.**

  Run:

  ```bash
  rtk moon check --target native loom/grammar
  ```

Expected: `loom/grammar` cannot be considered green until the interpreter is migrated. Do not commit this intermediate representation change. The public compiled-IR clean break is intentionally atomic with Task 2 runtime migration and downstream caller updates; do not add compatibility variants to make an intermediate commit compile.

## Task 2: Build executable binding and one predicate evaluator

**Files:**
- Modify: `loom/grammar/interpreter.mbt`
- Test: `loom/grammar/interpreter_test.mbt`
- Test: `loom/grammar/grammar_ir_properties_wbtest.mbt`

**Interfaces:**
- Consumes: slot-based `CompiledGrammar`, `CompiledExpr`, `CompiledPred`, and explicit declaration metadata from Task 1.
- Produces: `GrammarBindError`, `GrammarBuildError`, `NativeFactory`, `NativeCapabilities`, `RuleCapability`, `NativeDispatcher`, `ExecutableGrammar`, `bind`, and `ExecutableGrammar::parse_root`.

### Steps

- [ ] **1. Add failing binding and capability tests before changing runtime code.**

  Add tests for:
  - missing and unexpected native/guard handlers in explicit `compile -> bind`;
  - `NativeCapabilities::require` on an undeclared target;
  - a valid target returning `false` when its `Choice` predicate does not match;
  - matching target dispatch returning `true` and emitting the expected subtree;
  - foreign-binding capability rejection;
  - cross-native capability rejection;
  - factory error propagation before a parser context is touched.

  Run:

  ```bash
  rtk moon test --target native loom/grammar/interpreter_test.mbt
  ```

  Expected: FAIL against the removed/old APIs and missing binding types.

- [ ] **2. Define concrete error and capability types.**

  Add:

  ```moonbit
  pub suberror GrammarBindError {
    MissingNative(String)
    UnexpectedNative(String)
    MissingGuard(String)
    UnexpectedGuard(String)
    CapabilityRejected(String)
  }

  pub suberror GrammarBuildError {
    Compile(GrammarCompileError)
    Bind(GrammarBindError)
  }
  ```

  Define `NativeCapabilityBrand` with a private fresh `Ref[Unit]`. Define `RuleCapability[T,K]` with private `(NativeCapabilityBrand, RuleSlot)` storage. Define `NativeCapabilities[T,K]` as named capability pairs and make `require(name)` raise `GrammarBindError` when the name is absent.

- [ ] **3. Define the new native API and executable bundle.**

  Use these signatures:

  ```moonbit
  pub type NativeRule[T, K] =
    (@core.ParserContext[T, K], NativeDispatcher[T, K]) -> Unit

  pub type NativeFactory[T, K] =
    (NativeCapabilities[T, K]) -> NativeRule[T, K] raise GrammarBindError

  pub fn[T, K] bind(
    compiled : CompiledGrammar[T, K],
    natives? : Map[RuleName, NativeFactory[T, K]] = Map([]),
    guards? : Map[RuleName, HostGuard[T, K]] = Map([]),
  ) -> ExecutableGrammar[T, K] raise GrammarBindError
  ```

  Make `ExecutableGrammar` opaque with private compiled grammar, native/guard arrays, native dispatch arrays, and per-native brands. Add:

  ```moonbit
  pub fn[T, K] ExecutableGrammar::parse_root(
    self : Self[T, K],
  ) -> (@core.ParserContext[T, K]) -> Unit
  ```

  This is the only public bridge from bound grammar to execution. `interpret_compiled` is deleted.

- [ ] **4. Implement `bind` before runtime execution.**

  In deterministic slot order:
  - compare explicit compiled native/guard names with supplied registry keys;
  - raise missing/unexpected errors before creating a parser root;
  - allocate a fresh `Ref[Unit]` brand for each `NativeSlot`;
  - construct named `(RuleName, RuleCapability)` pairs from compiler-owned dispatch metadata;
  - invoke each factory and propagate `GrammarBindError`;
  - store returned native callbacks and guard handlers in slot arrays.

  No factory receives an arbitrary `RuleSlot`, registry map, or runtime lookup closure.

- [ ] **5. Implement `NativeDispatcher::try_rule`.**

  The dispatcher receives the current executable grammar, current native brand, native dispatch metadata, native/guard arrays, and parser context at call time. It must:
  - compare brand identity with `physical_equal`;
  - call `fail` on foreign or cross-native capability;
  - verify the capability slot is in the current native's allowed target set;
  - execute only a compiled `Choice` target;
  - use the unified compiled predicate evaluator;
  - return `false` only for a valid target whose `Choice` arms do not match.

  No capability mismatch emits parser diagnostics.

- [ ] **6. Implement `eval_compiled_pred` and rewrite every runtime branch.**

  Add one private evaluator:

  ```moonbit
  fn[T : Eq, K] eval_compiled_pred(
    pred : CompiledPred[T],
    token : T,
    ctx : @core.ParserContext[T, K],
    guards : Array[HostGuard[T, K]],
  ) -> Bool
  ```

  `HostGuardSlot` indexes the guard array directly. Replace all `Pred::matches` and `pred_matches_ctx` calls in these exact fields:

  ```text
  Choice.starts
  RepeatTopLevel.starts / delim
  PrattApp.starts
  PrattBinary.skip
  RepeatWhile.pred
  WrapIfNext.pred
  ErrorUntil.stop
  DiagnoseIf.pred
  ExpectSkip.skip
  ConsumeGated.skip / look
  RequireSep.stop / alt
  ErrorNodeUntil.stop
  ```

  Change `run_expr` to accept only `ExecutableGrammar` and use private direct compiled-rule access internally; do not call defensive `rule_snapshot` on the hot path.

- [ ] **7. Rewrite `interpret` and migrate native tests.**

  `interpret` accepts the same native factory registry as `bind`:

  ```moonbit
  pub fn[T, K] interpret(
    ir : GrammarIr[T, K],
    natives? : Map[RuleName, NativeFactory[T, K]] = Map([]),
    guards? : Map[RuleName, HostGuard[T, K]] = Map([]),
    native_rule_refs? : Map[RuleName, Set[RuleName]] = Map([]),
  ) -> (@core.ParserContext[T, K]) -> Unit raise GrammarBuildError
  ```

  It derives `native_names` and `guard_names` from the factory/guard map keys, calls `compile`, then passes the same factories and guards to `bind`. Callers with no native use an empty factory map. There is no `NativeRule` registry convenience path and no legacy `(RuleName) -> Bool` adapter; all native callers acquire capabilities during factory setup.

  Update native tests that need dispatch to explicit factories or the same factory registry through `interpret`. Remove tests for runtime missing-registry diagnostics and replace them with bind-time `GrammarBindError` tests.

- [ ] **8. Run focused grammar checks.**

  Run:

  ```bash
  rtk moon check --target native loom/grammar
  rtk moon test --target native loom/grammar/interpreter_test.mbt
  rtk moon test --target native loom/grammar/compile_test.mbt
  ```

  Expected: grammar package tests pass. Do not commit yet; downstream HTML and lambda consumers still need the same clean-break API migration.

## Task 3: Migrate property tests and lambda spike consumer

**Files:**
- Modify: `loom/grammar/grammar_ir_properties_wbtest.mbt`
- Modify: `examples/lambda/spike/probe_interpreter.mbt`
- Modify: `examples/lambda/spike/lambda_ir.mbt`
- Regenerate: `examples/lambda/spike/pkg.generated.mbti` if present

**Interfaces:**
- Consumes: explicit `compile -> bind -> parse_root`; public compiled snapshots and `slot_for_name` from Task 1.
- Produces: property-test equivalence and a compiling lambda spike without direct compiled-storage access or `interpret_compiled`.

### Steps

- [ ] **1. Migrate grammar property equivalence paths.**

  Replace each `interpret_compiled(compile(ir))` construction with:

  ```text
  compiled = compile(ir, native_names=Set::Set([]), guard_names=Set::Set([]), native_rule_refs=Map([]))
  executable = bind(compiled, natives=Map([]), guards=Map([]))
  parse_root = executable.parse_root()
  ```

  Preserve the existing CST and diagnostic comparisons against convenience `interpret`. These generated properties use token-only predicates and no native factories.

- [ ] **2. Migrate lambda slot/name access.**

  Replace `compiled.names.search(name)` with `compiled.slot_for_name(name)`, preserving the existing abort message for an impossible missing grammar rule. Replace `compiled.rule(slot)` with `compiled.rule_snapshot(slot)`, and use `RuleSlot` values throughout `ProbeEnv`.

  Match `RefSlot(RuleSlot)` and `NativeSlot(NativeSlot)` without destructuring private fields. Keep `ManualNewlineAppExpr` and crippled reuse behavior spike-local.

- [ ] **3. Add spike-local compiled predicate matching.**

  The spike cannot call the grammar package's private runtime evaluator. Add a local token-only matcher over public `CompiledPred` snapshots for `Any`, `IsToken`, `OneOf`, `Not`, and `All`; on `HostGuardSlot(_)`, call `fail` because the lambda spike supplies no host guards. This keeps the custom probe separate from production runtime dispatch.

- [ ] **4. Run lambda and property checks.**

  ```bash
  rtk moon check --target native examples/lambda/spike
  rtk moon test --target native examples/lambda/spike
  rtk moon test --target native loom/grammar/grammar_ir_properties_wbtest.mbt
  ```

  Expected: lambda spike oracle/smoke tests and grammar property tests pass with unchanged CST behavior.

- [ ] **5. Leave the external consumer migration staged for the atomic cutover.**

  Do not commit yet. The workspace is intentionally in a clean-break transition until HTML and generated interfaces are migrated; the final implementation commit is created in Task 5 after all affected packages pass.

## Task 4: Migrate HTML to per-parse capability factories

**Files:**
- Modify: `examples/html/html_grammar_ir.mbt`
- Modify: `examples/html/cst_parser.mbt`
- Test: `examples/html/parser_test.mbt`
- Test: `examples/html/html_spec.mbt`
- Regenerate: `examples/html/pkg.generated.mbti`

**Interfaces:**
- Consumes: `bind`, `NativeFactory`, `NativeCapabilities::require`, `RuleCapability`, `NativeDispatcher`, and `ExecutableGrammar::parse_root`.
- Produces: parse-local tag-stack ownership with no string-based native dispatch.

### Steps

- [ ] **1. Add a failing HTML binding test.**

  Add a focused test that constructs a compiled HTML grammar, binds a factory that selects `close_boundary`, parses a close tag, and verifies the target Choice gate is reached. Add a negative bind test where the factory requests an undeclared target and assert `GrammarBindError` before parsing.

- [ ] **2. Convert `html_grammar_ir.mbt` to explicit binding.**

  Keep the authored `html_grammar_ir` and compile-time declarations. In `make_html_parse_root`, create the parse-local `tag_stack`, guard map, and a native factory. The factory selects `close_boundary` once with `caps.require("close_boundary")`, then returns a native callback that captures only that capability and invokes `dispatcher.try_rule(ctx, close_boundary_cap)`.

  Bind the compiled grammar with the factory/guard maps and execute `exec.parse_root()(ctx)`. A static HTML binding failure is a construction defect and uses the existing abort boundary; it must not become parser recovery output.

- [ ] **3. Remove the string callback from the HTML parser.**

  Change `parse_html_root`, `parse_element`, `parse_content`, and `finish_element` so their close-boundary dependency is a no-argument callback `try_close_boundary : () -> Bool` created by the native factory. The factory captures `close_boundary_cap`; its runtime callback builds `() => dispatcher.try_rule(ctx, close_boundary_cap)` and passes that closure through the recursive parser helpers. Replace every `try_parse_rule("close_boundary")` call with `try_close_boundary()`. Preserve the existing tag-stack unwind, raw-text, void-element, depth, and error-limit behavior.

- [ ] **4. Run HTML behavior checks.**

  ```bash
  rtk moon check --target native examples/html
  rtk moon test --target native examples/html
  ```

  Expected: all existing HTML lexer/parser/spec tests pass, including raw-text, void tags, nested mismatches, bounded recovery, and parse-state isolation.

- [ ] **5. Leave the HTML migration staged for the atomic cutover.**

  Do not commit yet. Run the focused checks, then continue to generated interface regeneration and the workspace verification in Task 5.

## Task 5: Regenerate interfaces, remove stale paths, and verify the workspace

**Files:**
- Regenerate: `loom/grammar/pkg.generated.mbti`
- Regenerate: `examples/html/pkg.generated.mbti`
- Regenerate: `examples/lambda/spike/pkg.generated.mbti` when the package emits one
- Modify only if stale references remain: all files found by searches below
- Test: all focused grammar, HTML, and lambda targets

**Interfaces:**
- Consumes: completed source migrations from Tasks 1–4.
- Produces: generated interfaces matching the accepted public API and a stale-helper-free workspace.

### Steps

- [ ] **1. Search for removed APIs and old predicate paths.**

  Run:

  ```bash
  rtk proxy git grep -n -E 'interpret_compiled|NativeRef|check_pred_guards|pred_matches_ctx|try_parse_rule|\.matches\(' -- '*.mbt' '*.mbti'
  ```

  Expected: no production/runtime matches for removed APIs; remaining `.matches` calls are authored `Pred` or spike-local token-only matching and are reviewed individually.

- [ ] **2. Regenerate generated interfaces.**

  From each package's existing workflow, run `moon info` through the package/module workflow, then inspect the generated interfaces. Confirm:
  - no public mutable `CompiledGrammar` fields;
  - `RuleSlot`, `NativeSlot`, `GuardSlot`, `CompiledPred`, `ExecutableGrammar`, `GrammarBindError`, `GrammarBuildError`, `NativeCapabilities`, `NativeDispatcher`, and `NativeFactory` signatures match the spec;
  - `parse_root` exists on `ExecutableGrammar`;
  - `interpret_compiled` and `NativeRef` are absent.

- [ ] **3. Run all affected package and workspace checks.**

  ```bash
  rtk moon check --target native loom/grammar
  rtk moon test --target native loom/grammar
  rtk moon check --target native examples/html
  rtk moon test --target native examples/html
  rtk moon check --target native examples/lambda/spike
  rtk moon test --target native examples/lambda/spike
  rtk moon check
  ```

  Expected: every command exits successfully after source and generated interfaces are both present. Do not report green from a pipeline or wrapper; capture each command's own exit status.

- [ ] **4. Run formatting and diff hygiene once.**

  ```bash
  rtk moon fmt loom/grammar examples/html examples/lambda
  rtk proxy git diff --check
  rtk proxy git status --short
  ```

  Expected: formatter changes are limited to touched MoonBit files, `git diff --check` is clean, and any remaining worktree changes are explicitly attributed before completion.

- [ ] **5. Commit the complete clean-break cutover atomically.**

  Stage all changed source, tests, and generated interfaces from Tasks 1–4. Commit only after all affected package checks pass:

  ```bash
  rtk proxy git add loom/grammar examples/html examples/lambda/spike
  rtk proxy git commit -m "refactor(grammar): migrate compiled capability execution"
  ```

  Tasks 1–4 do not create partial commits. This prevents a source commit with stale `.mbti` files or a downstream commit that depends on unstaged core changes.

## Final Acceptance Checklist

- [ ] `GrammarIr -> compile` lowers every rule/native/guard/predicate reference to deterministic slots.
- [ ] No raw `Pred::HostGuard`, `NativeRef(String)`, or name-keyed compiled dispatch remains.
- [ ] Compiled storage cannot be mutated through public fields or snapshot aliasing.
- [ ] `compile -> bind -> ExecutableGrammar::parse_root` is the only explicit compiled execution path.
- [ ] `interpret` has the named `GrammarBuildError` contract and uses the new native callback type.
- [ ] Native factories select named opaque capabilities during bind; runtime callbacks capture capability values only.
- [ ] Native brands are fresh per binding/native and identity-checked with `physical_equal`.
- [ ] Invalid capabilities call `fail`; valid Choice non-match returns `false` without parser diagnostics.
- [ ] Every predicate field listed in the accepted spec has direct and negated HostGuard coverage.
- [ ] HTML and lambda spike callers are migrated; no stale helper/API search result remains.
- [ ] Focused package tests, workspace check, formatter, and diff hygiene all pass.
