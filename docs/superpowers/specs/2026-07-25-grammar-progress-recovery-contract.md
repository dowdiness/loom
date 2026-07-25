# Grammar Progress and Malformed-Input Recovery Contract

**Status:** Active contract
**Date:** 2026-07-25
**Scope:** Loom grammar execution after the compiled-capabilities migration

## Current State

This document records a contract whose core implementation is already present and tested; it is not a request to reimplement the completed compiler/interpreter migration.

Implemented evidence includes:

- conservative compile-time rejection for provable recursion and zero-progress repetition;
- parse-local rule cycle detection using `RuleSlot` and cursor position;
- runtime no-progress guards for repeating and Pratt application paths;
- Native capability dispatch sharing the same cycle protection;
- `ErrorUntil` boundary semantics and required-element diagnostics;
- real-language malformed-input tests for Lambda, CSS, and HTML;
- full Loom workspace validation via `NEW_MOON_MOD=0 moon test --frozen`
  from the repository root.

The #751–#755 implementation is complete. Ongoing work is limited to contract maintenance, future grammar coverage, and the documented host responsibility for Native callbacks that never return. The throwaway prototype and audit have been deleted after their conclusions were captured here.

## Problem Statement

Loom executes authored `GrammarIr` through a compiled and bound interpreter. Recursive rules, repeating expressions, Pratt combinators, and opaque `Native` callbacks can all participate in one execution cycle. A grammar that re-enters at the same cursor position can therefore loop indefinitely or overflow the call stack unless progress is made observable and enforceable.

Progress is also easy to confuse with recovery. Reaching a closing delimiter can be a valid synchronization boundary, but it must not silently turn a missing required construct into a successful parse. Conversely, trailing garbage before a known delimiter should produce one useful diagnostic and leave the delimiter available to its enclosing rule.

The initial probe and source-corpus audit established that:

- direct and nullable leading recursion is statically unsafe;
- a locally nullable repetition body is statically unsafe;
- safe progress frequently depends on following a `Ref` into its leading token behavior;
- `Native` progress is opaque to `compile`;
- the audited CSS, Lambda, E3, and HTML consumers contain no obvious authored zero-progress repetition;
- Lambda treats empty input as a valid empty module, so recovery policy is grammar-specific rather than universally erroring at EOF.

Without a durable contract, future grammar authors could reintroduce silent recovery, zero-progress loops, or inconsistent diagnostics while all ordinary valid-input tests continue to pass.

## Solution

Define and preserve a layered execution contract:

1. `compile` performs conservative static progress analysis and rejects cases it can prove unsafe.
2. `bind` links host capabilities without pretending that opaque `Native` callbacks are statically proven.
3. The interpreter enforces dynamic progress at recursive and repeating execution boundaries.
4. Recovery expressions have explicit diagnostic and cursor-boundary semantics.
5. Real CSS, HTML, and Lambda grammars test the public parse boundary, including diagnostic messages, source ranges, CST coverage, synchronization tokens, and language-specific recovery behavior.

The highest test seam is the public grammar parse boundary: construct a parser through `interpret` or `compile → bind → parse_root`, run it through the language's normal `LanguageSpec`/CST entry point, and assert externally observable diagnostics and tree behavior. Private stack or analyzer implementation details are not direct test contracts.

## Test Seams

The contract uses the fewest existing seams that cover the complete behavior:

1. **Build seam:** call `compile` and assert `GrammarCompileError` for statically provable unsafe grammars. This is the highest seam for compiler rejection and avoids asserting private analysis tables.
2. **Execution seam:** call `bind` followed by `ExecutableGrammar::parse_root`, or use the `interpret` convenience path, and parse through `ParserContext`. This covers cycle guards, Native capabilities, repetition, and recovery in one execution boundary.
3. **Language seam:** use each language's normal lexer and `LanguageSpec`/CST entry point. This is the highest seam for source ranges, diagnostic wording, delimiter preservation, CST coverage, and HTML tag-stack behavior.

No new test-only production seam is required. `cursor_position` is the narrow existing parser-context observation needed by the runtime contract; the rule call stack remains private.

## User Stories

1. As a grammar author, I want direct left recursion to be rejected during compilation, so that an invalid grammar cannot start parsing.
2. As a grammar author, I want nullable leading recursion to be rejected, so that indirect cycles cannot re-enter without consuming input.
3. As a grammar author, I want statically provable zero-progress repetition to be rejected, so that an empty body cannot spin forever.
4. As a grammar author, I want opaque `Native` progress to be treated conservatively, so that the compiler does not make unsound assumptions about host code.
5. As a grammar author, I want unknown recursive paths to be guarded at runtime, so that accepted but unusual hand-authored `GrammarIr` cannot loop indefinitely.
6. As a grammar author, I want recursion that consumes a token before re-entry to remain valid, so that ordinary nested and left-associative grammar shapes are not over-rejected.
7. As a grammar author, I want `Choice`, Pratt, `RepeatTopLevel`, and Native capability dispatch to share the same progress safety model, so that moving a rule behind a combinator does not remove its protection.
8. As a grammar author, I want a repeated body that returns without moving the cursor to stop with a diagnostic, so that the parser remains responsive on malformed input.
9. As a host integration author, I want a finite Native callback that returns without progress to be stopped at a repetition or recursive boundary, so that host integration cannot accidentally create an interpreter spin loop.
10. As a host integration author, I want the parser to distinguish a callback that returns without progress from a callback that never returns, so that the remaining non-returning case is documented as a host responsibility rather than hidden by parser behavior.
11. As a recovery author, I want `ErrorUntil` to remain silent when its stop token is already current, so that valid trailing recovery does not report a false error.
12. As a recovery author, I want `ErrorUntil` to leave the synchronization token unconsumed, so that the enclosing rule can emit and structure the delimiter normally.
13. As a recovery author, I want `ErrorUntil` to skip unexpected tokens through EOF without consuming EOF, so that recovery is bounded and composable.
14. As a recovery author, I want required operations such as `Expect`, `EmitOr`, `ExpectSkip`, and `Fail` to own missing-element diagnostics, so that `ErrorUntil` is not overloaded with required-value semantics.
15. As a recovery author, I want `ErrorNodeUntil` to represent an explicit unconditional error region, so that callers can request an error node when the construct failure is already known.
16. As a Lambda user, I want `(1,)` to report the missing required item at the comma while preserving a complete CST, so that editor features can continue operating on malformed source.
17. As a Lambda user, I want `{ let x = }` to report the missing initializer at the closing brace, so that a delimiter does not silently validate an incomplete binding.
18. As a Lambda user, I want empty source to remain a valid empty module, so that the generic recovery contract does not impose an incorrect language-specific EOF error.
19. As a CSS user, I want garbage before `RBrace` to produce one `expected 'RBrace'` diagnostic, so that trailing recovery is useful without duplicating errors.
20. As a CSS user, I want the diagnostic range to begin at the recovery boundary and the closing brace to remain available, so that the recovered CST preserves block structure.
21. As an HTML user, I want mismatched close tags to report the expected and actual spelling at the close-tag range, so that diagnostics point to the actionable source.
22. As an HTML user, I want unclosed nested elements to report the innermost unclosed element at EOF, so that parse-local tag-stack state is observable and useful.
23. As an HTML user, I want malformed nesting to preserve valid later siblings, so that one recovery event does not poison the rest of the document.
24. As a maintainer, I want the prototype's conclusions captured in a durable contract, so that the throwaway probe can be deleted without losing its design evidence.
25. As a maintainer, I want full workspace validation to include adversarial grammar, real-language malformed input, and generated interface checks, so that progress safety is not validated only by happy-path examples.

## Implementation Decisions

- Keep the authored `GrammarIr`, `Expr`, and `Pred` construction surfaces stable. Progress and recovery enforcement belongs at compile, bind, and interpreter boundaries rather than in a new authored grammar language.
- Treat observable parser cursor movement as the definition of progress. Diagnostics, placeholders, node creation, callback invocation, and host state mutation do not count as input progress.
- Use conservative static analysis. The compiler rejects direct or nullable leading cycles and structurally proven zero-progress repetition. It returns an unknown classification when progress depends on opaque Native behavior or non-local rule analysis that cannot be proven safely.
- Protect unknown recursive re-entry with a parse-local rule call stack. Re-entering the same `RuleSlot` at the same cursor position is an execution failure; re-entering after cursor advancement is allowed.
- Apply dynamic no-progress checks to `RepeatWhile`, `RepeatTopLevel`, and Pratt application loops. A body that returns without advancing emits a grammar-execution diagnostic, emits the normal error placeholder where appropriate, and stops the current cycle.
- Share the rule call stack between ordinary interpreter execution and `NativeDispatcher` capability calls. Native dispatch must not bypass cycle detection or reintroduce name-based execution.
- Preserve ordered `Choice` behavior for compiled hand-authored grammars while allowing static analysis to stop after a definitely-true alternative. Generated strict-LL(1) grammars continue to reject overlapping FIRST sets at generation time.
- Keep the separation `compile → bind → interpreter`. Compilation resolves grammar structure and performs static checks; binding links Native factories and HostGuards; interpretation executes only resolved slots and bound arrays.
- Define `ErrorUntil(stop, message)` as conditional trailing recovery:
  - at `stop`, emit no diagnostic and leave `stop` for the enclosing rule;
  - at EOF, emit no diagnostic and consume nothing;
  - otherwise, emit exactly one diagnostic and skip unexpected tokens through `stop` or EOF without consuming the synchronization token.
- Define required-element diagnostics separately. `Expect`, `EmitOr`, `ExpectSkip`, and `Fail` diagnose missing required constructs before trailing `ErrorUntil` recovery runs.
- Define `ErrorNodeUntil` as an explicit unconditional-error operation. It emits its diagnostic and error node, then consumes unexpected input up to but not including the synchronization token or EOF.
- Preserve parse-local HTML tag-stack ownership. The generic interpreter must not turn HTML's host-owned tag matching into global grammar state.
- Treat empty input according to each language grammar. Lambda's empty source is a valid empty module; HTML may report an unclosed or required-root condition; neither behavior is imposed globally by `ErrorUntil`.
- Keep the progress probe and audit as throwaway evidence. Their conclusions are represented by this contract, production implementation, and externally observable tests; the probe logic must not be promoted into runtime code.
- Do not add a compatibility shim or unsafe compiled-grammar execution path. The existing clean-break compiled-capabilities migration remains the execution boundary.

## Testing Decisions

- Tests must assert external behavior at the highest available seam: public grammar parse entry points, normal language lexers, `LanguageSpec`/CST construction, diagnostic messages and ranges, and preserved synchronization tokens or later siblings.
- Private `RuleCallStack` fields, slot-array layout, and analyzer helper names are implementation details. Their behavior is covered indirectly through adversarial public parses and compile errors.
- Compiler tests cover direct recursion, nullable leading recursion, recursion hidden behind `Choice`, Pratt and `RepeatTopLevel` paths, false-gated paths, and structurally empty repetition bodies.
- Interpreter tests cover unknown recursive re-entry, Native capability dispatch recursion, valid recursive re-entry after token consumption, and no-progress guards for repetition and Pratt application.
- Recovery contract tests cover `ErrorUntil` at an existing stop token, at EOF, and after garbage; required `EmitOr` at a delimiter and EOF; and explicit `ErrorNodeUntil` behavior.
- Lambda real-grammar tests cover `(1,)`, `{ let x = }`, exact diagnostic message and source offset, complete CST coverage, and valid empty-module behavior. Existing missing-body, missing-delimiter, and missing-keyword cases remain complementary prior art.
- CSS real-grammar tests use the source lexer rather than only synthetic token arrays where source ranges matter. They verify `@until(RBrace)` message, recovery range, exact diagnostic count, and preservation of the enclosing block's closing delimiter. Existing declaration and trailing-garbage acceptance tests remain the baseline for `EmitOr` and `ErrorUntil` interplay.
- HTML real-grammar tests verify exact mismatched-close diagnostics and close-tag ranges, innermost unclosed-element diagnostics at EOF, parse-local tag-stack recovery, and preservation of valid later siblings.
- Generated-interface validation remains part of acceptance. Any public `ParserContext` or grammar API change must be reflected in generated `.mbti` output without accidental trait-bound widening.
- Final validation includes affected package checks, full Loom module tests, formatting, diff checks, and a review that excludes the intentionally dirty `incr` submodule state from the feature diff.

## Acceptance Criteria

The contract is accepted when all of the following remain true:

1. **Static safety:** provable direct/nullable leading recursion and provable zero-progress repetition fail during `compile`; false-gated paths and consuming recursive paths remain valid.
2. **Dynamic safety:** an unknown cycle that re-enters a rule at the same cursor position terminates with a grammar-execution diagnostic; a recursive call after cursor advancement continues normally.
3. **Combinator coverage:** the same safety behavior holds through `Choice`, Pratt application, `RepeatTopLevel`, `RepeatWhile`, and Native capability dispatch.
4. **Recovery boundaries:** `ErrorUntil` is silent at its stop token and EOF, reports once for preceding garbage, leaves the synchronization token available, and never consumes EOF.
5. **Required diagnostics:** missing required constructs at delimiters or EOF are diagnosed by the required operation rather than being silently accepted by trailing recovery.
6. **Lambda evidence:** `(1,)` reports `Expected )` at offset 2 with a complete CST; `{ let x = }` reports `Unexpected token` at offset 10 with a complete CST; empty source remains a valid empty module.
7. **CSS evidence:** real source recovery reports exactly one `expected 'RBrace'` diagnostic at the recovery boundary and retains the enclosing block's closing delimiter.
8. **HTML evidence:** mismatched close tags report their expected/actual spelling at the close-tag range; unclosed nested elements report the innermost element at EOF; valid later siblings remain in the CST.
9. **Regression safety:** the full Loom module, affected language packages, generated interfaces, formatting, and diff checks pass without mutating the intentionally dirty `incr` state.

### Contract-to-test traceability

| Contract area | Observable evidence |
|---|---|
| Static progress | compiler rejection tests for recursion and zero-progress repetition |
| Runtime cycle guard | unknown recursion, Native dispatch recursion, and consuming recursion tests |
| Repeat/Pratt safety | no-progress guard tests for `RepeatWhile`, `RepeatTopLevel`, and `PrattApp` |
| `ErrorUntil` | stop-token, EOF, garbage, message, range, and delimiter-preservation tests |
| Lambda recovery | `(1,)`, `{ let x = }`, missing body/delimiter, and empty-module tests |
| CSS recovery | source-lexer `@until(RBrace)` message/range and valid-block tests |
| HTML recovery | mismatched-close range, unclosed-element EOF, tag-stack, and sibling-preservation tests |

## Out of Scope

- Proving that arbitrary Native code terminates or forcing a callback that never returns to yield control.
- Enforcing HostGuard purity through the MoonBit type system.
- Designing a general backtracking parser, ordered-choice recovery strategy, or new lexer model.
- Changing the authored grammar syntax or replacing `ErrorUntil` with an unconditional diagnostic operation.
- Making empty input universally erroneous across languages.
- Replacing HTML's parse-local tag stack with global mutable grammar state.
- Adding a new public recovery API when existing `ParserContext` recovery operations express the contract.
- Optimizing cursor checks before a benchmark demonstrates a measurable bottleneck.
- Publishing or closing an issue based on this draft without an explicit repository/action approval.

## Further Notes

The prototype source-corpus audit found no obvious production zero-progress repetition, but it demonstrated why a local `RepeatWhile` check is insufficient: safe progress often lives behind a `Ref`, while Native progress cannot be inferred from `GrammarIr`. The hybrid static-plus-runtime design is therefore intentional rather than a temporary compromise.

The real-language tests also exposed an important boundary: a closing delimiter can be a valid recovery synchronization point, and empty input can be valid in one grammar while malformed in another. Recovery diagnostics must therefore be attached to the required construct and language grammar, not inferred from the mere presence of `ErrorUntil` or EOF.

This document is a durable synthesis of the throwaway prototype conclusions and the implemented progress/recovery behavior. It is not a plan-closure record; no ADR is required solely for creating this draft.
