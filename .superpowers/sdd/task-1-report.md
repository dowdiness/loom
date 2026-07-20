# Task 1 Report: Define the atomic native-dispatch contract

## Status: DONE

Intentional red baseline — tests and documentation only; compiler/interpreter implementation deferred to Tasks 2–3.

## Commit

```
32a7f203195f38523d2af107dcf3bb4dbb000be3
test(grammar): define atomic native-dispatch contract (Task 1)
```

## Changes

### `loom/grammar/interpreter_test.mbt`
- Migrated native fixtures from `_call_rule` / `call_rule` to `_try_parse_rule` / `try_parse_rule` with `(RuleName) -> Bool` semantics.
- Renamed re-entry and unknown-name tests to `try_parse_rule` wording.
- Added `try_parse_rule atomic gate skips body when HostGuard returns false`: native calls `try_parse_rule("gate_rule")` on a top-level `Choice` whose sole arm uses `HostGuard("always_false")`; asserts `false`, empty diagnostics, and zero emitted CST children.

### `loom/grammar/compile_test.mbt`
- Added `compile succeeds when dispatch target is a top-level Choice` (uses `native_rule_refs={"native": Set::Set(["choice"])})`).
- Added `compile raises MissingNativeDispatchRule for undeclared dispatch target`.
- Added `compile raises NativeDispatchTargetNotChoice for non-Choice target`.

### `loom/grammar/pred.mbt`
- Documented HostGuard purity contract for native-dispatch entry predicates via `try_parse_rule`.

## Verification

### Command 1

```bash
rtk moon check --target native loom/grammar
```

**Result:** exit code 255 (expected red baseline)

**Errors (7 total, grammar task-related):**

1. `compile_test.mbt:190` — `native_rule_refs` parameter missing on `compile`
2. `compile_test.mbt:204` — `native_rule_refs` parameter missing on `compile`
3. `compile_test.mbt:211` — `MissingNativeDispatchRule` constructor absent from `GrammarCompileError`
4. `compile_test.mbt:226` — `native_rule_refs` parameter missing on `compile`
5. `compile_test.mbt:233` — `NativeDispatchTargetNotChoice` constructor absent from `GrammarCompileError`
6. `interpreter_test.mbt:162` — `try_parse_rule("inner")` has type `Unit`, wanted `Bool`
7. `interpreter_test.mbt:351` — `try_parse_rule("gate_rule")` has type `Unit`, wanted `Bool`

Also 26 pre-existing warnings in `loom/core` and other grammar test files (unchanged).

### Command 2

```bash
rtk moon test --target native loom/grammar/interpreter_test.mbt loom/grammar/compile_test.mbt
```

**Result:** exit code 1 (compile failures prevent test execution)

Same 7 errors as above; no tests executed.

### Command 3 (post-documentation sanity)

`pred.mbt` comment change introduces no additional errors beyond the six test/API mismatches above (HostGuard doc compiles cleanly once other errors are resolved).

## Preserved unrelated work

Uncommitted HTML/loomgen changes in `examples/html/*`, `loomgen/*` were not modified.

## Concerns

None for Task 1 scope. The seven compile errors are the expected intentional red baseline until Tasks 2–3 implement `native_rule_refs`, new error variants, and `try_parse_rule : (RuleName) -> Bool`.


## Task 1 Fixture Fix (post-review)

Adjusted only the migrated native re-entry fixture in `loom/grammar/interpreter_test.mbt` to match the committed plan:
- via-native `"inner"` now uses a single-arm top-level `Expr::Choice` with `Pred::Any` and the same `Expr::Emit(...)` body.
- native callback now calls `ignore(try_parse_rule("inner"))` while preserving the existing CST equivalence assertion against the `Ref` baseline, whose `"inner"` remains `Expr::Emit(...)`.
- left the atomic false-path test and compiler/interpreter implementation unchanged.

### Focused verification after fix

#### Command

```bash
rtk moon test --target native loom/grammar/interpreter_test.mbt
```

#### Output

```text
Error: [4085]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/compile_test.mbt:190:5 ]
     │
 190 │     native_rule_refs={"native": Set::Set(["choice"])},
     │     ────────┬───────  
     │             ╰───────── This function has no parameter with label native_rule_refs~.
─────╯
Error: [4085]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/compile_test.mbt:204:7 ]
     │
 204 │       native_rule_refs={"native": Set::Set(["missing"])},
     │       ────────┬───────  
     │               ╰───────── This function has no parameter with label native_rule_refs~.
─────╯
Error: [4031]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/compile_test.mbt:211:10 ]
     │
 211 │     Some(MissingNativeDispatchRule("native", "missing")) => ()
     │          ────────────┬────────────  
     │                      ╰────────────── The type @dowdiness/loom/grammar.GrammarCompileError does not have the constructor MissingNativeDispatchRule.
─────╯
Error: [4085]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/compile_test.mbt:226:7 ]
     │
 226 │       native_rule_refs={"native": Set::Set(["emit_only"])},
     │       ────────┬───────  
     │               ╰───────── This function has no parameter with label native_rule_refs~.
─────╯
Error: [4031]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/compile_test.mbt:233:10 ]
     │
 233 │     Some(NativeDispatchTargetNotChoice("native", "emit_only")) => ()
     │          ──────────────┬──────────────  
     │                        ╰──────────────── The type @dowdiness/loom/grammar.GrammarCompileError does not have the constructor NativeDispatchTargetNotChoice.
─────╯
Error: [4014]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/interpreter_test.mbt:357:19 ]
     │
 357 │     gate_result = try_parse_rule("gate_rule")
     │                   ─────────────┬─────────────  
     │                                ╰─────────────── Expr Type Mismatch
        has type : Unit
        wanted   : Bool
─────╯
Warning: [0020]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/reuse_test.mbt:191:39 ]
     │
 191 │       if node.kind != TestToken::Word.to_raw() || node.text_len != 3 {
     │                                       ───┬──  
     │                                          ╰──── Warning (deprecated): The method `to_raw` is implicitly promoted from `impl @dowdiness/seam.ToRawKind for TestToken`. This behavior is deprecated, either use `@dowdiness/seam.ToRawKind::to_raw` instead or add a `extend TestToken with @dowdiness/seam.ToRawKind::{to_raw, ..}` declaration.
─────╯
Warning: [0020]
     ╭─[ /home/antisatori/worktrees/loom/test/644-benchmark-classification/loom/grammar/reuse_test.mbt:214:54 ]
     │
 214 │       cursor.explain_reuse_rejection(TestToken::Word.to_raw(), 0, 0),
     │                                                      ───┬──  
     │                                                         ╰──── Warning (deprecated): The method `to_raw` is implicitly promoted from `impl @dowdiness/seam.ToRawKind for TestToken`. This behavior is deprecated, either use `@dowdiness/seam.ToRawKind::to_raw` instead or add a `extend TestToken with @dowdiness/seam.ToRawKind::{to_raw, ..}` declaration.
─────╯

Command exited with code 1
```

#### Result

The native re-entry fixture no longer appears in the failure set. Remaining failures are the untouched atomic false-path `try_parse_rule("gate_rule")` contract mismatch and the pre-existing `compile_test.mbt` Task 1 red-baseline API/constructor gaps.
