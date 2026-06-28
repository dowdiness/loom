# Grammar IR Emitter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first mode-agnostic `GrammarIr` source emitter so loomgen can generate a `parse_root` MoonBit parser backend equivalent to `@grammar.interpret` for the existing IR subset.

**Architecture:** Keep `@grammar.interpret` as the reference semantics. Add a focused `loomgen/emit_grammar.mbt` backend that walks `@grammar.GrammarIr[T,K]` and emits top-level mutually recursive `parse_<rule>` functions plus `parse_root`. Golden tests check source shape; semantic parity tests compare emitted parsers against `@grammar.interpret` on the same grammar and inputs.

**Tech Stack:** MoonBit; `dowdiness/loom/grammar`; `loomgen`; existing `ParserContext` grammar-author API.

## Global Constraints

- Work in the existing loom checkout; scope git commands with `git -C loom ...`.
- Shell commands use `rtk`.
- Use TDD: write failing tests before production code.
- `@grammar.interpret` is the semantic oracle; goldens alone are insufficient.
- `SwitchLexMode` is out of scope for this implementation because current `ParserContext` has no `lex_mode` / `set_lex_mode` API.
- Unsupported IR nodes must fail loudly at emit time, not generate partial parser code.
- Verify with `rtk moon check loomgen --target native`; add narrower `moon test` commands as tests land.

---

## File Structure

- Create `loomgen/emit_grammar.mbt`: emitter API, naming/sanitization, predicate lowering, expression lowering, and source assembly.
- Create `loomgen/emit_grammar_test.mbt`: unit/golden tests for emitted source and unsupported-node errors.
- Create or extend a grammar parity fixture package only if MoonBit cannot compile emitted source in-place from a test. Prefer a small checked-in fixture over dynamic evaluation.
- Modify `loomgen/moon.pkg`: import `dowdiness/loom/grammar` for tests and/or main package if the emitter type references `@grammar` directly.
- Modify `loomgen/main.mbt` only after the emitter core and tests pass; the first wiring may expose a narrow flag only if the input representation is real.
- Modify `docs/README.md`: index this active plan because a Markdown file is added.

## Task 1: Establish Emitter API and First Golden

**Files:**
- Create: `loomgen/emit_grammar.mbt`
- Create: `loomgen/emit_grammar_test.mbt`
- Modify: `loomgen/moon.pkg` if needed for `@grammar` imports

**Interfaces:**
- Produce `emit_grammar(...) -> Result[String, String]` or a small config-struct equivalent.
- Inputs must include token/kind rendering callbacks because MoonBit enum values cannot be reflected into source names.
- Output must include `pub fn parse_root(ctx : <core>.ParserContext[<Token>, <SyntaxKind>]) -> Unit` and one private `parse_<rule>` function per rule.

- [ ] Write a failing golden test for a one-rule grammar: `source = Node(Root, Emit(Int, IntToken))`.
- [ ] Run the targeted loomgen test; verify it fails because `emit_grammar` is missing.
- [ ] Implement the minimum emitter for `Node`, `Emit`, root function, rule function, and function-name derivation.
- [ ] Re-run the targeted test; verify it passes.

## Task 2: Deterministic Rule Ordering and Ref Lowering

**Files:**
- Modify: `loomgen/emit_grammar.mbt`
- Modify: `loomgen/emit_grammar_test.mbt`

**Interfaces:**
- Rule order mirrors `@grammar.compile`: root first, then other rule names sorted.
- `Ref("name")` lowers to `parse_<sanitized_name>(ctx)`.
- Missing refs are reported before emission using `@grammar.compile` or equivalent validation.

- [ ] Add a failing golden where `source` references `expr` and another rule sorts after/before it.
- [ ] Assert emitted function order and direct call shape.
- [ ] Add a failing error test for unresolved `Ref`.
- [ ] Implement deterministic ordering and `Ref` lowering.
- [ ] Re-run targeted loomgen tests.

## Task 3: Predicate Lowering

**Files:**
- Modify: `loomgen/emit_grammar.mbt`
- Modify: `loomgen/emit_grammar_test.mbt`

**Interfaces:**
- `Pred::Any` emits `true` in predicate position.
- `Pred::IsToken(t)` emits equality against the rendered token.
- `Pred::OneOf(tokens)` emits a match or equivalent branch that is deterministic and readable.
- `Pred::Not(inner)` emits a negated predicate without changing semantics.

- [ ] Add failing source-shape tests for `Choice` using `Any`, `IsToken`, `OneOf`, and `Not`.
- [ ] Implement predicate lowering as helper expressions or local helper functions.
- [ ] Re-run targeted loomgen tests.

## Task 4: Core Expression Coverage

**Files:**
- Modify: `loomgen/emit_grammar.mbt`
- Modify: `loomgen/emit_grammar_test.mbt`

**Interfaces:**
- Lower these nodes by mirroring `loom/grammar/interpreter.mbt`: `Expect`, `Seq`, `Choice`, `RepeatWhile`, `EmitError`, `ErrorUntil`, `Fail`, `EmitOr`, `DiagnoseIf`, `ExpectSkip`, `ConsumeGated`, `RequireSep`, `ErrorNodeUntil`, `WrapIfNext`.
- Generated code must use current `ParserContext` methods only.

- [ ] Add failing golden tests in small groups, not one giant fixture.
- [ ] Implement each group with the same branch order and diagnostic behavior as the interpreter.
- [ ] Re-run targeted loomgen tests after each group.

## Task 5: Pratt and Reuse-Sensitive Nodes

**Files:**
- Modify: `loomgen/emit_grammar.mbt`
- Modify: `loomgen/emit_grammar_test.mbt`

**Interfaces:**
- `RepeatTopLevel`, `PrattApp`, and `PrattBinary` must be copied semantically from `@grammar.interpreter`.
- Preserve reuse calls: `try_reuse_repeat_group` and `try_reuse_current_node`.
- Preserve gated soft-skip behavior in `PrattBinary`.

- [ ] Add failing goldens for `RepeatTopLevel`, `PrattApp`, and `PrattBinary`.
- [ ] Implement the lowering directly from interpreter semantics.
- [ ] Re-run targeted loomgen tests.

## Task 6: Unsupported Node Errors

**Files:**
- Modify: `loomgen/emit_grammar.mbt`
- Modify: `loomgen/emit_grammar_test.mbt`

**Interfaces:**
- `ManualNewlineAppExpr` returns an emitter error.
- `SwitchLexMode` is not added in this phase. If a placeholder type appears later, it must return an emitter error until the runtime contract exists.

- [ ] Add a failing test that `ManualNewlineAppExpr` returns a clear error mentioning the unsupported residue.
- [ ] Implement unsupported-node detection.
- [ ] Re-run targeted loomgen tests.

## Task 7: Semantic Parity Harness

**Files:**
- Create or modify: smallest practical parity fixture under `loomgen/` or a dedicated fixture package
- Modify: `loomgen/emit_grammar_test.mbt` if parity can stay in-package

**Interfaces:**
- For each parity fixture, parse the same source/tokens with `@grammar.interpret(ir)` and emitted `parse_root`.
- Compare CST and diagnostics.
- Include at least one incremental/reuse-sensitive fixture for `RepeatTopLevel` or Pratt once emitted code is compilable in a fixture package.

- [ ] Add a failing parity test for the simplest emitted parser.
- [ ] Add fixture glue so emitted code is compiled by MoonBit, not string-interpreted.
- [ ] Compare emitted parser output against interpreter output.
- [ ] Extend parity to one reuse-sensitive fixture.
- [ ] Re-run targeted parity tests.

## Task 8: CLI Wiring Decision

**Files:**
- Modify: `loomgen/main.mbt` only if there is a real input format.
- Modify: `loomgen/README.md` if a user-facing flag is added.

**Interfaces:**
- Do not implement `--grammar <file.mbt>` as if loomgen can evaluate arbitrary MoonBit values.
- Accept only a representation the program can actually parse/load.
- If no real input format exists yet, leave CLI wiring out and document emitter as a library/internal backend.

- [ ] Decide whether a usable grammar input representation exists after Tasks 1-7.
- [ ] If yes, add a failing CLI test and wire the flag.
- [ ] If no, add a short README note that CLI grammar loading is deferred.
- [ ] Re-run loomgen checks.

## Task 9: Final Verification and Docs

**Files:**
- Modify: `docs/README.md`
- Modify: `loomgen/README.md` only if user-facing behavior changed

**Interfaces:**
- `docs/README.md` indexes this plan.
- Final response states whether an ADR is required; for an active implementation plan, no closure ADR is created yet.

- [ ] Run `rtk moon check loomgen --target native` with runner exit captured directly.
- [ ] Run targeted tests added in this plan.
- [ ] Run `rtk moon fmt`.
- [ ] Review generated/source diffs.
- [ ] State verification evidence and the ADR/no-ADR status.
