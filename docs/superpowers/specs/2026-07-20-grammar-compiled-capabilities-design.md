# Grammar compiled capabilities migration

**Date:** 2026-07-20
**Status:** Proposed
**Issue:** #607 follow-up

## Context

`loom/grammar` currently validates `HostGuard(String)` and native dispatch names during `compile`, but stores unresolved names in `CompiledExpr` and `CompiledGrammar`. Runtime evaluation therefore has multiple predicate paths: `Choice` uses context-aware dispatch while several other expression nodes call `Pred::matches`, where `HostGuard` is not evaluated. `interpret_compiled` also accepts handler registries that can disagree with the registry used during compilation and reports missing entries during parsing.

This violates the `Parse, don't validate.` boundary. The `GrammarIr -> CompiledGrammar` transition must produce a representation that contains only resolved references and can be executed without name lookup or fallback validation.

The approved migration policy is a clean break. Existing callers, tests, and generated interfaces move together; compatibility shims are not retained.

## Goals

- Make every compiled predicate context-aware by construction.
- Resolve rules, natives, guards, and native dispatch targets to deterministic slots during compilation.
- Bind host handlers before parsing and represent native dispatch as capabilities, not an arbitrary rule-name callback.
- Remove runtime registry mismatch diagnostics and `None => false` fallbacks.
- Preserve the existing authored `GrammarIr`, `Expr`, and `Pred` surface except for the intentional native registration API change.
- Preserve HTML parse-local tag-stack ownership and behavior.

## Non-goals

- No change to the authored grammar syntax.
- No new code-emitter backend.
- No enforcement of HostGuard purity by the type system; purity remains a documented callback contract.
- No optimization of classifier string allocation.
- No generated per-native record types in this migration. The generic capability set is sufficient; a generated ergonomic layer can be added later without changing compiled IR semantics.

## Decision

Introduce three opaque slot wrappers:

```text
RuleSlot
NativeSlot
GuardSlot
```

The rule root remains slot zero. Remaining rule names, native names, and guard names are sorted before slot assignment. Slot assignment is deterministic and recorded in the compiled grammar's name arrays for binding and diagnostics setup only.

### Compiled predicates

Add an internal/public compiled predicate representation:

```text
CompiledPred[T] =
  Any
  IsToken(T)
  OneOf(Array[T])
  Not(CompiledPred[T])
  All(CompiledPred[T], CompiledPred[T])
  HostGuardSlot(GuardSlot)
```

`lower_pred` converts every authored `Pred` to `CompiledPred`. A missing guard raises `MissingHostGuard`; no unresolved `HostGuard(String)` enters a compiled expression. Every predicate-bearing field in `CompiledExpr` and `CompiledAlt` uses `CompiledPred`.

### Compiled grammar

`CompiledExpr::Ref` becomes `RefSlot(RuleSlot)`. `CompiledExpr::Native` becomes `NativeSlot(NativeSlot)`. Native dependency metadata becomes an array indexed by `NativeSlot`, whose entries contain resolved `RuleSlot` targets. The compiler still verifies that each target exists and is a top-level `Choice`.

`CompiledGrammar` contains:

- rule names and compiled rule bodies;
- root `RuleSlot`;
- native names and guard names in deterministic slot order;
- slot-based native dispatch metadata.

It does not contain name-keyed runtime dispatch metadata.

### Executable binding

Add a separate `ExecutableGrammar` built from a compiled grammar and host registries:

```text
ExecutableGrammar[T, K] {
  grammar : CompiledGrammar[T, K]
  natives : Array[NativeRule[T, K]]
  guards : Array[HostGuard[T, K]]
  native_capability_brands : Array[NativeCapabilityBrand]
}
```

`bind` performs the only registry-to-array conversion. Missing or unexpected handlers raise `GrammarBindError` before a parser context is touched. The interpreter receives only `ExecutableGrammar`; it indexes arrays by slots and never performs `Map.get` or fallback validation.

`interpret` remains as a convenience API that compiles and binds. `interpret_compiled` is removed rather than retained as an unsafe bypass.

### Native capabilities

Replace the native callback's arbitrary `(RuleName) -> Bool` gate with opaque, setup-time capabilities:

```text
NativeCapabilityBrand {
  // private identity token created once per ExecutableGrammar and NativeSlot
}

RuleCapability[T, K] {
  // private (NativeCapabilityBrand, RuleSlot) representation
}

NativeCapabilities[T, K] =
  Array[(RuleName, RuleCapability[T, K])]

NativeFactory[T, K] =
  (NativeCapabilities[T, K]) -> NativeRule[T, K]

NativeRule[T, K] =
  (ParserContext[T, K], NativeDispatcher[T, K]) -> Unit

NativeDispatcher[T, K] {
  try_rule :
    (ParserContext[T, K], RuleCapability[T, K]) -> Bool
}
```

For each native slot in each binding, `bind` creates one fresh opaque `NativeCapabilityBrand`. It creates named capability pairs for exactly that native's compiled, allowed target slots, all carrying the native's brand, and passes them to its factory. The factory selects capabilities by name during setup and captures only the opaque capability values it needs; positional coupling is not part of the contract. It cannot create an arbitrary rule capability, and the returned runtime callback does not capture a registry, builder, or name-lookup closure.

At native execution time, the interpreter constructs a dispatcher containing the current native's brand and the current executable grammar. `try_rule` verifies both the native brand and allowed-target invariant, then executes the rule encoded by the capability. A capability from another executable binding or another native in the same binding is a programmer defect and fails before dispatch; it is never interpreted against the current grammar's numeric slot. The dispatcher does not accept `RuleSlot` directly, so an arbitrary slot cannot be introduced at the native call site.

A target that fails to compile or bind is a build error. A target whose `Choice` predicate does not match returns `false` as normal parser semantics; it is not a registry failure.

The generic capability array is intentionally minimal. A later generated API may expose named capability fields for ergonomics without changing the compiled representation or runtime boundary.

### Runtime predicate evaluation

All predicate-bearing expression nodes call one evaluator over `CompiledPred`. `HostGuardSlot(slot)` directly invokes `guards[slot]`. There is no `None => false` branch. The evaluator is used by `Choice`, `RepeatWhile`, `ErrorUntil`, `RepeatTopLevel`, `WrapIfNext`, Pratt expressions, diagnostic/skip expressions, separator expressions, and error-node expressions.

## Migration sequence

1. Add opaque slot wrappers and deterministic slot tables in `loom/grammar/compile.mbt`.
2. Add `CompiledPred` and replace `check_pred_guards` with `lower_pred`.
3. Lower every `Ref`, `Native`, predicate field, and native dependency edge.
4. Add `GrammarBindError`, `RuleCapability`, `NativeCapabilities`, `NativeFactory`, and `ExecutableGrammar` in `loom/grammar/interpreter.mbt`.
5. Replace all runtime registry maps with bound arrays and replace every predicate call with the single compiled evaluator.
6. Migrate interpreter tests and property tests from `interpret_compiled` to `compile -> bind -> parse_root`.
7. Migrate `examples/html/html_grammar_ir.mbt` to per-parse capability factories. `close_boundary` is captured as a `RuleCapability`; `cst_parser.mbt` no longer accepts `(String) -> Bool`.
8. Regenerate `loom/grammar/pkg.generated.mbti` and update all affected generated/API fixtures.
9. Remove `check_pred_guards`, `NativeRef(RuleName)`, name-keyed dispatch metadata, `interpret_compiled`, and runtime mismatch diagnostics.

## Error boundaries

`compile` continues to raise `GrammarCompileError` for malformed authored IR and unresolved compile-time names.

`bind` raises `GrammarBindError` for a handler registry that does not match the compiled grammar. Capability pairs are constructed from compiler-owned dispatch metadata; a native factory can select only a declared opaque capability and cannot create or receive an arbitrary slot.

`interpret` exposes a combined build error containing compile or bind failure because callers normally handle those failures at the same construction boundary. Parser recovery diagnostics remain parser-context output and are not used for grammar construction failures.

## Tests and acceptance

### Compiler

- Guard, native, and rule slots are deterministic.
- Every authored `HostGuard` lowers to `HostGuardSlot`.
- Every native dependency lowers to resolved rule slots.
- Missing/ambiguous names still fail during compilation.
- Non-Choice native targets fail during compilation.

### Interpreter

- Context-aware guard behavior is covered in every predicate-bearing runtime family, including `Not(HostGuard(...))`.
- `HostGuard` is never silently treated as a token-only predicate.
- `bind` rejects missing and unexpected handlers before parsing.
- Native factories receive only declared target capabilities.
- Native capability calls preserve the old successful and failing Choice behavior without runtime registry diagnostics.

### Equivalence and HTML

- Existing grammar property tests preserve CST and diagnostic equivalence between convenience `interpret` and explicit `compile -> bind -> parse_root` construction.
- HTML raw-text, void-element, nesting, close-boundary, bounded recovery, and parse-state isolation tests remain green.
- Generated `.mbti` files match the checked-in public API.
- No hand-written HTML membership helper remains.

## Consequences

This is an intentional public API break in `dowdiness/loom/grammar`. Compiled IR becomes safer to execute and easier to analyze, while authored grammar construction remains unchanged. Native implementations change from runtime string dispatch to a one-time capability acquisition step. The compiled grammar can be reused across parser contexts; executable bindings remain parse-local when callbacks capture parser-local state such as the HTML tag stack.

The capability factory adds setup ceremony to native integrations, but it makes invalid native dependencies fail before parsing and removes a class of runtime fallback bugs. A later generated API may make capability acquisition named and type-specific without changing this boundary.
