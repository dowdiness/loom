# Grammar compiled capabilities migration

**Date:** 2026-07-20
**Status:** Accepted
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

The rule root remains slot zero. Remaining rule names, native names, and guard names are sorted before slot assignment. The explicit `compile` call receives `native_names`, `guard_names`, and `native_rule_refs` declarations alongside `GrammarIr`; it assigns deterministic slots and records the ordered names for binding. Each native dependency target set is sorted by resolved `RuleSlot` before storage. The convenience `interpret` path derives those declarations from its factory and guard maps.

### Compiled predicates

Add a public compiled predicate snapshot representation. It is not the authored grammar construction type; callers may inspect snapshots but only compiler-owned `CompiledGrammar` storage is executable:

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

`CompiledExpr::Ref` becomes `RefSlot(RuleSlot)`. `CompiledExpr::Native` becomes `NativeSlot(NativeSlot)`. Native dependency metadata becomes an array indexed by `NativeSlot`, whose entries contain resolved `RuleSlot` targets sorted by slot order. The compiler still verifies that each target exists and is a top-level `Choice`.

`CompiledGrammar` owns its storage behind private fields. To preserve the existing lambda spike's custom residue interpreter, public snapshot/query accessors expose `names_snapshot()`, `slot_for_name(name) -> RuleSlot?`, `root_slot()`, and `rule_snapshot(slot)`. `names_snapshot` returns a fresh name array; `slot_for_name` returns an opaque slot without exposing its integer representation; `rule_snapshot` copies every compiler-owned nested array in the expression tree. Generic `T` and `K` payload values are not cloned because the grammar package cannot assume a clone operation; their ownership/immutability remains the authored token and syntax-kind contract. No accessor aliases compiler-owned storage, so mutating snapshot arrays cannot change slot mappings or executable behavior.

The compiled grammar contains:

- rule names and compiled rule bodies;
- root `RuleSlot`;
- native names and guard names in deterministic slot order;
- slot-based native dispatch metadata.

`CompiledExpr`, `CompiledAlt`, and `CompiledPred` remain public snapshot representations for analyzer/spike consumers. Their values cannot be passed back into `bind`; only the compiler-owned `CompiledGrammar` storage is executable. This preserves the external probe without exposing mutable compiled arrays.

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

The fields shown above are conceptual; the public `ExecutableGrammar` value is also opaque, and its arrays/brands cannot be mutated or extracted by callers.
The explicit execution method is `ExecutableGrammar::parse_root(self) -> ParseRoot`. It is the only public bridge from an opaque compiled/bound grammar to a parser root; it executes the root rule against each supplied parser context.

`bind` performs the only registry-to-array conversion. Both `bind` and `interpret` accept native factories, so every native caller uses the same setup-time capability acquisition path. For an explicitly compiled grammar, missing or unexpected handlers raise `GrammarBindError` before a parser context is touched. The convenience `interpret` path derives its compile-time native/guard name declarations from the factory and guard maps it receives, then delegates to `bind`; an empty factory map is the normal no-native case. The interpreter receives only `ExecutableGrammar`; it indexes arrays by slots and never performs `Map.get` or fallback validation.

`interpret` remains as a convenience API that compiles and binds. `interpret_compiled` is removed rather than retained as an unsafe bypass.

### Native capabilities

Replace the native callback's arbitrary `(RuleName) -> Bool` gate with opaque, setup-time capabilities:

```text
NativeCapabilityBrand {
  // private token : Ref[Unit], allocated fresh per ExecutableGrammar and NativeSlot
  // compare token identity with physical_equal; never structural Eq or slot-derived Int
}

RuleCapability[T, K] {
  // private (NativeCapabilityBrand, RuleSlot) representation
}

NativeCapabilities[T, K] {
  pairs : Array[(RuleName, RuleCapability[T, K])]
}

NativeCapabilities::require(
  self : NativeCapabilities[T, K],
  name : RuleName,
) -> RuleCapability[T, K] raise GrammarBindError

NativeFactory[T, K] =
  (NativeCapabilities[T, K]) -> NativeRule[T, K] raise GrammarBindError

NativeRule[T, K] =
  (ParserContext[T, K], NativeDispatcher[T, K]) -> Unit

NativeDispatcher[T, K] {
  try_rule :
    (ParserContext[T, K], RuleCapability[T, K]) -> Bool
}
```

For each native slot in each binding, `bind` creates one fresh opaque `NativeCapabilityBrand`. It creates named capability pairs for exactly that native's compiled, allowed target slots, all carrying the native's brand, and passes them to its factory. The factory selects capabilities by name during setup and captures only the opaque capability values it needs; positional coupling is not part of the contract. It cannot create an arbitrary rule capability, and the returned runtime callback does not capture a registry, builder, or name-lookup closure.

At native execution time, the interpreter constructs a dispatcher containing the current native's brand and the current executable grammar. `try_rule` verifies both the native brand and allowed-target invariant, then executes the rule encoded by the capability. A capability from another executable binding or another native in the same binding is a programmer defect: the dispatcher calls `fail` before dispatch, never emits a parser diagnostic, and never interprets the foreign numeric slot against the current grammar. A valid capability whose `Choice` predicate does not match returns `false`. The dispatcher does not accept `RuleSlot` directly, so an arbitrary slot cannot be introduced at the native call site.

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
7. Migrate `examples/lambda/spike` from direct `CompiledGrammar` field access to defensive snapshots and `RuleSlot` accessors. Keep its intentional `ManualNewlineAppExpr` and crippled-reuse behavior spike-local; it no longer depends on `interpret_compiled`.
8. Migrate `examples/html/html_grammar_ir.mbt` to per-parse capability factories. `close_boundary` is captured as a `RuleCapability`; `cst_parser.mbt` no longer accepts `(String) -> Bool`.
9. Regenerate `loom/grammar/pkg.generated.mbti` and update all affected generated/API fixtures.
10. Remove `check_pred_guards`, `NativeRef(RuleName)`, name-keyed dispatch metadata, `interpret_compiled`, and runtime mismatch diagnostics.

## Error boundaries

`compile` has the signature `GrammarIr × native_names × guard_names × native_rule_refs -> CompiledGrammar raise GrammarCompileError`. The declaration arguments are part of the compile boundary and are not inferred from mutable runtime handler registries.

`bind` has the signature `CompiledGrammar × Map[RuleName, NativeFactory] × Map[RuleName, HostGuard] -> ExecutableGrammar raise GrammarBindError`. It raises for a handler registry that does not match an explicitly compiled grammar, or when a native factory propagates a failed capability selection. Capability pairs are constructed from compiler-owned dispatch metadata; a native factory can select only a declared opaque capability and cannot create or receive an arbitrary slot.

`GrammarBuildError` is the named combined error:

```text
GrammarBuildError =
  Compile(GrammarCompileError)
  Bind(GrammarBindError)
```

`interpret` has the signature `GrammarIr × Map[RuleName, NativeFactory] × Map[RuleName, HostGuard] × native_rule_refs -> ParseRoot raise GrammarBuildError`; it derives `native_names` and `guard_names` from those maps, calls `compile`, then calls `bind` with the same factory/guard maps. It wraps compile failures as `Compile` and bind/factory failures as `Bind`. Parser recovery diagnostics remain parser-context output and are not used for grammar construction failures.

The explicit execution path is `compile -> bind -> ExecutableGrammar::parse_root`. `bind` returns the opaque executable value; it does not itself start parsing.

## Tests and acceptance

### Compiler

- Guard, native, and rule slots are deterministic.
- Every authored `HostGuard` lowers to `HostGuardSlot`.
- Every native dependency lowers to resolved rule slots.
- Missing/ambiguous names still fail during compilation.
- Non-Choice native targets fail during compilation.

### Interpreter

- The evaluator is tested independently for every predicate field: `Choice.starts`; `RepeatTopLevel.starts`; `RepeatTopLevel.delim`; `PrattApp.starts`; `PrattBinary.skip`; `RepeatWhile.pred`; `WrapIfNext.pred`; `ErrorUntil.stop`; `DiagnoseIf.pred`; `ExpectSkip.skip`; `ConsumeGated.skip`; `ConsumeGated.look`; `RequireSep.stop`; `RequireSep.alt`; and `ErrorNodeUntil.stop`.
- Every listed field has both a direct `HostGuard` case and a `Not(HostGuard(...))` case.
- `HostGuard` is never silently treated as a token-only predicate.
- Explicit `bind` rejects missing and unexpected handlers before parsing.
- A native factory calling `NativeCapabilities::require` with an undeclared target raises `GrammarBindError` before parsing.
- Native factories receive only declared target capabilities.
- A dispatcher rejects a foreign-binding or cross-native capability with `fail`, while a valid nonmatching Choice capability returns `false`.
- Binding-brand tests use distinct fresh `Ref[Unit]` identities and verify that capabilities from different bindings and different native slots are rejected.
- Snapshot-array mutation tests prove that modifying `names_snapshot()` or `rule_snapshot()` results cannot alter later binding or execution; the test does not claim to clone arbitrary generic `T`/`K` payload internals.
- The lambda spike migrates name resolution from `compiled.names.search(name)` to `slot_for_name(name)` and passes the returned opaque slots through its probe environment.
- Native capability calls preserve the old successful and failing Choice behavior without runtime registry diagnostics.

### Equivalence and HTML

- Existing grammar property tests preserve CST and diagnostic equivalence between convenience `interpret` and explicit `compile -> bind -> parse_root` construction.
- HTML raw-text, void-element, nesting, close-boundary, bounded recovery, and parse-state isolation tests remain green.
- Generated `.mbti` files match the checked-in public API.
- No hand-written HTML membership helper remains.

## Consequences

This is an intentional public API break in `dowdiness/loom/grammar`. Compiled IR becomes safer to execute and easier to analyze, while authored grammar construction remains unchanged. Native implementations change from runtime string dispatch to a one-time capability acquisition step. The compiled grammar can be reused across parser contexts; executable bindings remain parse-local when callbacks capture parser-local state such as the HTML tag stack.

The capability factory adds setup ceremony to native integrations, but it makes invalid native dependencies fail before parsing and removes a class of runtime fallback bugs. A later generated API may make capability acquisition named and type-specific without changing this boundary.
