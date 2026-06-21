# Parser-Generation Spike Results

**Status:** Complete  
**Date:** 2026-06-21  
**Spike plan:** [superpowers/plans/2026-06-20-parser-generation-spike.md](../superpowers/plans/2026-06-20-parser-generation-spike.md)  
**Decision record:** no new ADR needed — this doc serves as the decision record (cross-reference: [analysis/2026-06-20-parser-generation-direction.md](2026-06-20-parser-generation-direction.md) §Spike gating)

---

## Verdict: GO

Safety gates all pass. Track 2 added `Seq`, `PrattBinary`, `PrattApp`, and `RepeatWhile` combinators, raising lambda E1 from 1/7 to **5/7**. E3 probe grammar (JSON-shaped, externally specified) is **5/5 declarative** with all D1 oracle tests passing. Both GO conditions from the conditional verdict are satisfied.

---

## What Was Built

Tasks 0–14 of the spike plan were executed in `examples/lambda/src/spike/`:

| File | Purpose |
|------|---------|
| `types.mbt` | `GrammarIr`, `Expr` enum, `RuleId`, `DivergenceClass` |
| `interpreter.mbt` | `interpret(ir)` → `parse_root` closure; all Expr variants |
| `lambda_ir.mbt` | `lambda_spike_ir()`, `build_b_syntax_grammar()`, `normalized_syntax_grammar()` |
| `leaves.mbt` | `project_lambda_leaves()` — deterministic CST leaf extractor |
| `oracle.mbt` | `run_oracle_fixture()`, D1/D2a/D2b/reuse-parity checks, divergence classifier |
| `fixtures.mbt` | Edit-sequence fixtures covering let-defs, Pratt, error recovery, combined |
| `measurements.mbt` | E1/E2/E3 ergonomics measurements and E3 probe plan |

**Config-normalization invariant:** Both parser A (hand-written `parse_lambda_root`) and parser B (IR-interpreted) are built through `normalized_syntax_grammar(spec, lex)` with `incremental_relex_enabled=false, block_reparse_spec=None`. Only `parse_root` differs between A and B.

---

## Safety Oracle Results

### D1: Incremental matches fresh

**PASS** — all fixtures, both A and B.

For every edit step across all fixtures (let-def, app/bop Pratt, error recovery, combined), the incremental parse result equals a fresh full parse on the same source. B's interpreted `parse_root` is incrementally correct.

### D2a: A and B parse trees are structurally identical

**PASS (structural) + REPLICATION_RESIDUAL noted.**

CST `tree_diff` is empty for all fixtures. Diagnostic structural fields (`source`, `severity`, `code`, `primary`) are equal between A and B for all fixtures.

**ReplicationResidual finding:** B's error message wording differs from A's on malformed inputs ("delete second RHS" step in the combined fixture). This is a cross-implementation wording difference, not a structural divergence. It does NOT block GO. Filed as a known deviation.

### D2b: Stable projection IDs agree

**PASS** (with honesty scoping documented).

Both trackers seeded before first `apply_edit`. Stable IDs agree across all non-malformed steps. Malformed intermediates recorded correctly; recovery resumes correctly.

**Honesty scoping (Task 9):** Under this wiring, D2b is not an independent path-dependence oracle — a D2b mismatch implies a D2a CST mismatch. D2b's independent value is: (1) hash-collision blind spot guard, (2) consumer-facing stable-ID assertion. Both are exercised by the fixtures.

### REUSE-PARITY: reuse counts match

**VACUOUS** (Task 10 finding).

`reuse_count` in `SyntaxSnapshot` tracks both repeat-group reuse (`try_reuse_repeat_group`) and engine-level node reuse (`ctx.node()` fast-path). When repeat-group reuse is disabled (crippled B), engine-level reuse compensates — yielding the same count. REUSE-PARITY is always satisfied and provides no signal for this spike.

**Implication:** The repeat-group reuse optimization is PERFORMANCE-ONLY and does not affect `reuse_count`. Throughput comparison between A and B requires benchmarking (Task 13 E3 probe), not oracle comparison.

---

## Ergonomics Results

### E1: Rule coverage ratio

**Track 1 (initial spike):** 1/7 rules declarative.  
**Track 2 (Seq + Pratt extension):** 5/7 declarative.  
**P2 fixes (tail threading + block/newline combinators):** **5 / 7 (~71%)** — unchanged, but Source is now fully generic.

| Rule | Classification | Encoding (after P2 fixes) |
|------|---------------|---------|
| Source | **Declarative** | `RepeatTopLevel(rule_id, starts_pred, tail_expr, cripple_reuse)` — all behavior in IR value; interpreter is fully generic |
| Definition | Escape hatch | `ManualDefinition` — `parse_definition_ir` dispatched via `run_expr`; complex let/fn logic not yet IR-expressible |
| Expression | **Declarative** | `Ref(Binary)` — generic dispatch |
| Binary | **Declarative** | `PrattBinary(Application, BinaryExpr, [(Plus,…),(Minus,…)])` |
| Application | **Declarative** | `PrattApp(Atom, AppExpr, atom_starts_token)` |
| Atom | **Declarative** | `Choice([…])` with `Seq` for paren/block/error arms; `ManualDefinition` and `ManualBlockDelimiterCheck` appear as sub-expressions, not rule-level escape hatches |
| ParamList | Escape hatch | `ManualParamList` — mark/start_at retroactive-wrap dance not yet IR-expressible |

### E2: Lambda-specific escape hatches

**Track 2:** Both missing combinators added. **P2 fixes: 3 sub-rule combinator gaps identified.**

| Combinator | Status | Note |
|------------|--------|------|
| `Seq(Array[Expr])` | **Added** | Enables sequential token emission + recursion chains |
| `PrattBinary` | **Added** | Infix operator table, left-associative |
| `PrattApp` | **Added** | Left-associative application |
| `RepeatWhile(pred, body)` | **Wired** (was stubbed) | While-loop over predicate |
| `EmitError(msg)` | **Added** | Diagnostic without placeholder node |

**Remaining escape hatches (3):**

| Escape hatch | Gap it fills |
|---|---|
| `ManualParamList` | Retroactive-wrap (`mark`/`start_at`) — deferred node-open not expressible with `Seq` |
| `ManualBlockDelimiterCheck` | Counted repeat with conditional diagnostic — `RepeatWhile` cannot count iterations or branch on count |
| `ManualNewlineAppExpr` | Context-sensitive `allow_newline_application` mode — `PrattApp` uses a fixed starts predicate; cannot vary newline-consumption by parse context (let-body vs trailing expression) |

Rule-level escape hatches (Definition + ParamList) and sub-rule combinator gaps (ManualBlockDelimiterCheck + ManualNewlineAppExpr) are all lambda-specific and do not affect loomgen's ability to generate parsers for grammars without these patterns.

### E3: Second-grammar reuse probe

**PASS — 5/5 rules declarative, D1 oracle passes across all test fixtures.**

Grammar specification source: **JSON (RFC 8259).** Structure was defined externally from the grammar spec, not reverse-engineered to fit the IR combinators.

Token mapping (lambda lexer, no new lexer):

| Lambda token | JSON role |
|---|---|
| `Integer` | number literal |
| `Identifier` | string-like value |
| `Hole` (`_`) | null |
| `LeftParen` / `RightParen` | `[` / `]` |
| `LBrace` / `RBrace` | `{` / `}` |
| `Comma` | `,` |
| `Eq` | `:` |

| Rule | Encoding | Declarative? |
|------|----------|-------------|
| Source | `Ref(Definition)` | ✓ |
| Value | `Choice([Integer, Identifier, Hole, Array, Object])` | ✓ |
| Array | `Node(ParenExpr, Seq([Emit((), Choice([empty, elements+RepeatWhile(Comma,…)]), Expect()])` | ✓ |
| Object | `Node(BlockExpr, Seq([Emit({), Choice([empty, members+RepeatWhile(Comma,…)]), Expect(})])` | ✓ |
| Member | `Node(LetDef, Seq([Expect(Ident), Expect(Eq), Ref(Value)]))` | ✓ |

No `PrattBinary` or `PrattApp` required — the E3 grammar verifies that `Seq + RepeatWhile + Choice + Emit + Expect` alone suffice for a separator-structured grammar.

**D1 oracle tests** (file: `src/spike/e3_oracle_wbtest.mbt`):

| Test | Fixture | Result |
|------|---------|--------|
| `e3: array literal D1 parity` | `(1, foo, 3)` → element edits → append | **PASS** |
| `e3: object literal D1 parity` | `{x = 1}` → value edit → add member | **PASS** |
| `e3: nested array-of-objects D1 parity` | `({a = 1}, {b = 2})` → inner value edit | **PASS** |

---

## Decision

### What the spike proved

1. The oracle infrastructure is correct and exercisable. D1/D2a/D2b all pass on a non-trivial grammar with error recovery, Pratt parsing, and multi-definition sources.
2. The architecture supports grammar-as-data: a `GrammarIr` → `parse_root` → loom engine pipeline is viable. The `normalized_syntax_grammar` wrapper correctly isolates the parse function as the only variable between A and B.
3. `reuse_count` is not a useful parity oracle — both repeat-group and node-level reuse increment it.
4. **Track 2:** `Seq + PrattBinary + PrattApp + RepeatWhile` raise lambda E1 from 1/7 to 5/7. E3 JSON-grammar is 5/5 declarative with D1 passing — proving the combinators generalise beyond lambda's specific structure.

### GO conditions (all satisfied after Track 2)

| Condition | Status |
|-----------|--------|
| D1 passes for B (incremental = fresh) | ✓ Pass |
| D2a passes for B (structural parity with A) | ✓ Pass |
| D2b passes for B (stable IDs agree) | ✓ Pass |
| E1 ≥ 5/7 for lambda grammar | ✓ 5/7 |
| E3 second grammar declarative | ✓ 5/5 |
| E3 D1 oracle passes | ✓ All pass |

**Loomgen can proceed to code-generation stage.**

### What does NOT need to change

- The oracle harness (D1/D2a/D2b) is reusable as-is.
- The `normalized_syntax_grammar` pattern is correct — use for all future spike grammars.
- `project_lambda_leaves` + `ProjectionIdentityTracker` seeding protocol works correctly.

### Remaining escape hatches (non-blocking)

3 lambda-specific escape hatches remain (see E2 table). All are lambda-specific patterns. They do not affect loomgen's ability to generate parsers for grammars without soft-newline rules, counted-delimiter constraints, or positional parameter lists (which covers most target use cases). They can be addressed as additional combinators during loomgen implementation.

---

## Commit history

| Commit | Task | Description |
|--------|------|-------------|
| c182f68 | 0 | Spike moon.pkg |
| (prior context) | 1–7 | Types, interpreter, leaves, oracle stubs |
| 76f5128 | 8 | Lambda IR, `build_b_syntax_grammar`, B smoke tests |
| eac37b8 | 9 | Persistent A-vs-B oracle harness |
| fd084cf | 10 | REUSE-PARITY positive control + finding |
| effa11e | 11 | Divergence classifier and stop condition |
| e940102 | 12 | E1/E2 ergonomics measurements |
| 691cfad | 13 | E3 second-grammar reuse probe plan |
| (Track 2) | 14 | Seq + PrattBinary + PrattApp + RepeatWhile + EmitError; lambda E1 5/7; E3 JSON grammar 5/5; D1 oracle PASS |
| fe75b4e | P2 | ManualNewlineAppExpr (top-level/block newline-app), ManualBlockDelimiterCheck (counted delimiter diagnostic), RepeatTopLevel rule_id threading, E3 Emit→Expect for member key; E2 hatches 1→3; 7 new tests |
| (this commit) | P2-tail | Thread tail_expr through RepeatTopLevel; Source fully generic; update results doc |
