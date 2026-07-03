# ADR: Structural AST Testing for the Grammar Emitter

**Date:** 2026-07-03
**Status:** Accepted
**Issues:** [#574](https://github.com/dowdiness/loom/issues/574), [#576](https://github.com/dowdiness/loom/issues/576), [#577](https://github.com/dowdiness/loom/issues/577), [#578](https://github.com/dowdiness/loom/issues/578)

The grammar emitter (`loomgen/emit_grammar.mbt`) was split into a two-phase
pipeline — AST construction then rendering — so that tests can assert against
the AST structure (`MbtModule`) rather than the rendered string. This ADR
records that design and its consequences.

## Context

The emitter builds MoonBit source code from a `@grammar.GrammarIr` IR. Its
only test harness before this change was rendered-string matching
(`inspect(source.contains(...), content="true")`).

**Two kinds of fragility:**

1. **Formatting coupling.** `@pretty.render_string` produces output that
   `moon fmt` disagrees with. A formatting change in the renderer, a comment
   tweak, or an import reordering breaks string-matching tests even when the
   emitter logic is correct.

2. **Implicit assertion.** `source.contains("fn parse_foo")` asserts only that
   a substring appears somewhere in the output, not that the correct function
   appears at the correct position with the correct sequence of statements.

**Test breakdown (22 tests at time of writing):**

| Category | Count | Tests | Intent |
|---|---|---|---|
| Already structural | 2 | 1–2 | Use `emit_grammar_module` + `derive(Eq)` |
| Error-message | 7 | 3, 9, 10, 12–14, 20 | Test rejection paths; correct to keep string-based |
| Fixture-parity | 3 | 15–17 | Compare against checked-in `.g.mbt` files; correct to keep string-based |
| Behavioral (convertible) | 10 | 4–8, 11, 18–19, 21–22 | Test emitter logic; `source.contains` is fragile here |

The boundary between "error-message" and "behavioral" is fuzzy at the test
level: some tests (e.g. 7, 8) mix error assertions with structural assertions
in a single test body. The counts are approximate.

## Decision

1. **Extract `emit_grammar_module` from `emit_grammar`.** The new function
   returns `Result[MbtModule, String]` — the fully-constructed MoonBit AST
   before rendering. The existing `emit_grammar` keeps its unchanged
   `Result[String, String]` signature and delegates:

   ```moonbit
   pub fn emit_grammar(...) -> Result[String, String] {
     emit_grammar_module(...).map(fn(m) {
       @pretty.render_string(m.to_layout(), width=80)
     })
   }
   ```

2. **Test structurally via `derive(Eq)` on `MbtModule`.** Tests construct the
   expected `MbtModule` literal and assert equality against the emitter's
   output. All AST types in `loomgen/mbt_ast.mbt` derive `Eq` and `Debug`.

3. **Keep `emit_grammar` signature unchanged.** Downstream consumers (the CLI
   in `main.mbt`, any third-party integration) continue to receive
   `Result[String, String]`. `emit_grammar_module(...) -> Result[MbtModule, String]`
   is also `pub` for test and tooling use; `loomgen` is `is-main: true`, so
   this imposes no API-stability obligation.

4. **Error conditions are unchanged.** `emit_grammar_module` returns the same
   `Err(String)` values as `emit_grammar`:
   - MissingRoot, MissingRef, MissingNative, AmbiguousRule from the
     `@grammar.compile` step
   - Native name collides with a generated `parse_<rule>` stub (a
     loomgen-level check — `compile` cannot see the `parse_` prefix)
   - Root rule named `"root"` produces `"parse_root"` which collides with the
     generated entry point
   No new error paths were introduced.
5. **Fixture regeneration requires `moon fmt` post-processing.** The
   `--regenerate-fixtures` flag regenerates `.g.mbt` fixture files from the
   current emitter output. Because `@pretty.render_string` output diverges
   from `moon fmt`, every regeneration must be followed by
   `moon fmt loomgen/fixtures/`. CI enforces formatting via `moon fmt --check`
   in the `check-loomgen` job.

## Rejected Alternatives

- **String-only testing (status quo ante).** Rejected because
  `source.contains` tests fail on formatting changes and assert only substring
  presence, not structural correctness. This was the only option before the
  split.

- **Golden-file testing against fixtures only.** Rejected because fixture
  files render through the same `@pretty.render_string` pipeline, so they
  share the formatting-coupling problem. Fixture tests (15–17) are still
  useful as a parity check against checked-in reference output, but they are
  not sufficient for behavioral coverage.

- **Snapshot testing.** A snapshot would couple to the rendered string shape,
  inheriting both formatting fragility and implicit assertion. No snapshot
  infrastructure exists in the MoonBit test framework at this version, so this
  would require building custom tooling.

## Consequences

**Positive:**

- Structural `derive(Eq)` assertions are invariant under formatting changes,
  comment placement, and import reordering. Only semantic changes break the
  test.
- A failed assertion produces a precise mismatch — the differing field of
  `MbtFnDecl` or `MbtExpr` — rather than a "substring not found" message.
- `MbtModule` and the AST types are available for other `loomgen/` code
  generators (token impls, step lexer, syntax kind) that might adopt the same
  two-phase pipeline.

**Negative:**

- `loomgen/mbt_ast.mbt` depends on the `@pretty` rendering API via
  `impl @pretty.Pretty for MbtModule`. A breaking change to the `@pretty`
  trait requires updating the pretty-printer impls in `mbt_ast.mbt`.
- Adding a new AST variant requires `derive(Eq)` on the new variant. This is
  enforced by existing structural tests.
- `--regenerate-fixtures` output must be post-processed with `moon fmt`. A
  developer who regenerates fixtures and forgets to format will hit a CI
  failure in `moon fmt --check`. Mitigation: documented in the flag's `about`
  text and in agent setup guides.

**Neutral:**

- `emit_grammar_module` duplicates the parameter list of `emit_grammar` (six
  parameters plus one optional). A parameter change to one requires a change
  to both.
- Making `emit_grammar_module` and all `Mbt*` types `pub` carries no
  immediate cost — `loomgen` is `is-main: true` with no external consumers.
  If `loomgen` later becomes a library, these types become part of the public
  surface and would need stability guarantees.
- `@pretty.render_string` output style (`width=80`) matches `moon fmt`'s
  default line width, but the two formatters are not equivalent. The root
  cause of the divergence is not investigated here.

## Non-goals

- This is not a general-purpose MoonBit AST. `MbtModule` covers only the
  subset of MoonBit used by the grammar emitter. Other code generators in
  `loomgen/` may adopt it, but the shape is driven by
  `emit_compiled_expr`'s output.
- The CLI interface is unchanged. The `--regenerate-fixtures` flag already
  existed; its help text now includes the `moon fmt` step.
- Converting all remaining `source.contains` tests to structural assertions is
  not required by this decision. Error-message tests and fixture-parity tests
  will remain string-based.
- The `@pretty` rendering pipeline is unchanged. The disagreement between
  `@pretty.render_string` and `moon fmt` is a known limitation, not addressed
  here.

## Follow-up

- Convert the remaining behavioral tests (Choice predicates, Seq/RepeatWhile,
  diagnostics/consume, error-node wrap, Native lowering, RepeatTopLoop,
  PrattApp/PrattBinary, find_first, OneOf-in-RepeatWhile) to structural
  assertions incrementally, as time allows or when a fragility signal appears.
- Consider whether `MbtModule` should become a shared internal type across all
  `loomgen/` code generators, not just the grammar emitter.
