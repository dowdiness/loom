# Native(RuleName) IR escape-hatch node — implementation plan

**Status:** Active
**Issue:** [dowdiness/loom#541](https://github.com/dowdiness/loom/issues/541)
**Design:** full spec in issue #541 body; 5 corrections from Codex design validation posted as an [issue comment](https://github.com/dowdiness/loom/issues/541#issuecomment-4852978462) (2026-07-01) and folded into the steps below.
**Plan authored by:** Codex ("Opus orchestrates, Codex plans" — plan >~50 lines across 4+ files with new invariants). Opus owns the design/invariants and executes.

## Goal

Add a `Native(RuleName)` escape-hatch node to the closure-free `@grammar` IR so context-sensitive productions (e.g. HTML tag-stack matching) can delegate to hand-written host code, without breaking `derive(Eq, Debug)` on `Expr`/`CompiledExpr`/`CompiledGrammar`, and without breaking interpreted/emitted parity.

## Corrections folded in (do not skip)

1. `interpret`/`emit_grammar` must derive `native_names` from the registry and thread it into `compile` — otherwise every grammar containing `Native(...)` fails `MissingNative`.
2. `AmbiguousRule` must be a **global namespace check** (`ir.rules.keys ∩ native_names == ∅`), run once before lowering — not only inside the `Native(...)` lowering arm.
3. Use this codebase's actual optional-arg syntax, `name? : T = default` (see `loom/factories.mbt:19`) — not `name~ : T = default`.
4. `examples/lambda/spike/probe_interpreter.mbt` has its own exhaustive `CompiledExpr` match (line ~71) that will fail to compile once `NativeRef` is added — needs its own arm.
5. Interpreted/emitted parity is not automatic for `Native` — add a native-specific `grammar_parity` fixture proving `call_rule` (interpreted) and direct `parse_<rule>(ctx)` calls (emitted) produce identical output.

## Steps

Each step should compile (`moon check`) before moving to the next. TDD: red test, then minimal implementation to green.

1. **IR shape test, then IR variant** — `loom/grammar/ir_test.mbt`, then `loom/grammar/ir.mbt`.
   Add the smallest test constructing an `Expr` containing `Native("...")`, verifying `Eq`/`Debug` still hold. Then add `Expr::Native(RuleName)` next to `Ref(RuleName)`. Tight loop: add red test, immediately add the variant, run `moon check` once both exist (a test referencing `Expr::Native` won't compile until the variant lands).

2. **Compile tests for native validation and lowering** — `loom/grammar/compile_test.mbt`.
   Red tests: `Native("missing")` with empty `native_names` raises `MissingNative`; a name that is both a native and an `ir.rules` key raises `AmbiguousRule` even with no `Native(...)` node referencing it (proves the check is global, not lowering-arm-local); a declared native lowers to `CompiledExpr::NativeRef(name)`; existing `compile(ir)` call sites still work unchanged.

3. **Minimal compile implementation** — `loom/grammar/compile.mbt`.
   Add `MissingNative(RuleName)` and `AmbiguousRule(RuleName)` to the compile error type. Add `CompiledExpr::NativeRef(RuleName)`. Add `native_names? : Set[RuleName] = Set::new()` to `compile` (labelled-optional syntax, correction 3). Before lowering rules, run the global namespace check once (correction 2): any `ir.rules` key also in `native_names` → `AmbiguousRule`. Keep `MissingRoot`-style validation ordering. Thread `native_names` into `lower`; add the `Native(name)` arm — absent from `native_names` → `MissingNative(name)`, else → `CompiledExpr::NativeRef(name)`.

4. **Probe interpreter exhaustive-match repair** — `examples/lambda/spike/probe_interpreter.mbt`.
   Add a `CompiledExpr::NativeRef` arm to the spike's exhaustive match, defensive (non-aborting) in the same spirit as the `ManualNewlineAppExpr` fallback. This is a compilation guard, not new behavior — do this **before** relying on the new `CompiledExpr` variant anywhere else, or workspace-wide `moon check` breaks.

5. **Interpreter tests for native execution** — `loom/grammar/interpreter_test.mbt`.
   Red tests: a native mid-`Seq` runs in order with its neighbors; a native re-enters the grammar via `call_rule` and produces the same subtree as an equivalent `Ref`; an empty registry at runtime for a compiled `NativeRef` emits a diagnostic and does not abort.

6. **Interpreter implementation** — `loom/grammar/interpreter.mbt`.
   Add `typealias NativeRule[T, K] = (@core.ParserContext[T, K], (RuleName) -> Unit) -> Unit`. Add `natives? : Map[RuleName, NativeRule[T, K]] = Map::new()` to `interpret`/`interpret_compiled` (correction 3 syntax). Correction 1: `interpret(ir, natives?)` must derive `native_names` from `natives.keys()` and pass it into `compile`; `interpret_compiled` captures the same registry for execution without recompiling. Thread `natives` through every `run_expr` recursive call alongside `grammar`. Add the `NativeRef(name) => match natives.get(name) { Some(f) => f(ctx, call_rule); None => <diagnostic, not abort> }` arm, where `call_rule` is `name => run_expr(ctx, grammar, natives, grammar.rule(<slot of name>))`.

7. **Emitter tests for NativeRef output** — `loomgen/emit_grammar_wbtest.mbt`.
   Red tests: `NativeRef(name)` emits literal `name(ctx)` — no `parse_` prefix, no generated stub; emitted header documents the hand-written native requirement; `MissingNative`/`AmbiguousRule` surface as emitter errors.

8. **Emitter implementation** — `loomgen/emit_grammar.mbt`.
   Add `native_names? : Set[RuleName] = Set::new()` to `emit_grammar` (correction 3 syntax), pass into `@grammar.compile` (correction 1, emitted-path half). Extend the compile-error catch for `MissingNative`/`AmbiguousRule`. Add the `NativeRef(name)` emission arm writing exactly `name(ctx)`. Ensure the rule-stub generation loop still only emits stubs for declarative `compiled.names`, never natives. Update the emitted file header comment.

9. **Native parity fixture — grammar + interpreted + emitted** — new `loomgen/fixtures/grammar_parity_native/` (parallel to `grammar_parity/` and `grammar_parity_reuse/`).
   Define shared token/kind types and an IR containing `Native(...)`. Build an interpreted parser using a native registry whose native calls `call_rule("...")`. Build (or generate, see step 10) a checked-in parser where the native is hand-written and calls sibling `parse_<rule>(ctx)` directly. This is correction 5's fixture scaffold.

10. **Native parity test + generated fixture content** — `loomgen/fixtures/grammar_parity_native/` parity wbtest + generated parser file.
    Add the parity whitebox test comparing interpreted-vs-emitted CST/diagnostics for the same input. Generate or hand-write the checked-in native parser fixture so the emitted native calls `parse_<rule>(ctx)` directly (no `call_rule` plumbing in the emitted path) while the interpreted native goes through `call_rule`. Invariant to assert: both paths agree on output despite the different re-entry mechanism.

11. **Public interface regeneration** — `loom/grammar/pkg.generated.mbti` and any other affected `.mbti`.
    Run this module's normal `moon info`/interface-check flow. Confirm the public interface shows: `Native` on `Expr`; `NativeRef` on `CompiledExpr`; the two new compile errors; updated `compile`/`interpret`/`interpret_compiled` signatures with the optional native params; `NativeRule` if public. Check `git diff *.mbti` per repo convention — this is where a stray `~` vs `?` syntax mistake or an accidentally-widened bound would show up.

12. **Final verification pass**
    Run, in order: `loom/grammar/compile_test.mbt`, `loom/grammar/interpreter_test.mbt`, `loomgen/emit_grammar_wbtest.mbt`, the new `grammar_parity_native` fixture test, then the existing `grammar_parity`/`grammar_parity_reuse` fixtures (regression — must still pass unchanged). Then `moon check` workspace-wide. If any other exhaustive `CompiledExpr` match surfaces beyond `probe_interpreter.mbt`, add a `NativeRef` arm there too before considering this done.

## Notes carried from design validation (non-blocking, keep in mind)

- Recursive natives (native A's `call_rule` reaching a rule containing `Native(A)`/`Native(B)`) are not inherently broken — same `grammar`/`natives` registry is reused via closure capture. Non-consuming recursion is a pre-existing risk class for `Ref` too; natives just make it easier to hide.
- `call_rule` is grammar-rule-only by contract — a native calling `call_rule("B")` where `B` is native-only has no slot to resolve in either path. Native-to-native delegation should go through a declarative rule wrapping `Native(B)`, or be handled directly in host code. Don't add machinery for this now; just don't let it silently no-op without a diagnostic.
- Name-based lookup (`Map`/`Set`) over slot-interning is the right first cut — natives are a rare escape hatch, not hot-path `Ref` dispatch. If this ever needs to be faster, `CompiledGrammar::slot_of(name) -> Int?` is the documented future option — do not build it preemptively.
