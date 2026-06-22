# Minimal grammar-IR contract for loom (loomgen code-generation, stage 1)

**Status:** Design / spec (approved in brainstorm 2026-06-21; not yet planned or built).
**Date:** 2026-06-21
**Scope question answered:** What is the *minimal grammar-IR contract* that graduates the parser-generation spike's `GrammarIr`/`Expr` into a reusable loom layer, and which parser **output form** (interpret vs emit) does that contract commit to?
**Decision record:** This spec is the design record for the §4.4-step-2 "derive a minimal IR contract from the spike" deliverable in [analysis/2026-06-20-parser-generation-direction.md](../../analysis/2026-06-20-parser-generation-direction.md). It does **not** supersede that doc; it refines its step 2.

---

## 1. Problem and scope

The spike ([results](../../analysis/2026-06-20-parser-generation-spike-results.md)) returned an unconditional **GO**: a hand-authored `GrammarIr` value, interpreted into a `parse_root` closure, drives loom's incremental engine via `@core.ParserContext[T,K]` with D1/D2a/D2b parity to the hand-written lambda parser (E1 = 5/7, E3 = 5/5). The spike IR lives at `examples/lambda/src/spike/`.

That IR was built to *prove the mechanism*, not to be a contract. It is monomorphic to lambda's `@token.Token`/`@syntax.SyntaxKind`, its predicates are opaque host closures, and four of its variants (`ManualDefinition`, `ManualParamList`, `ManualBlockDelimiterCheck`, `ManualNewlineAppExpr`) are lambda-specific escape hatches. This spec designs the **minimal** promotion of that IR into a reusable, cross-language loom contract.

### 1.1 Two independent axes (do not conflate)

- **Input / spec format** — how a language author writes a grammar (annotated enum à la morm? a monogram-style builder? hand-authored IR?). **Out of scope for this contract** (deferred).
- **Output form** — what the code generator ultimately emits: a `GrammarIr` *value* consumed by a runtime interpreter, vs. specialized `parse_root` *code*. **In scope**, resolved in §6.

The contract designed here is the shared artifact that *both* output forms (and any future author-facing input format) sit on.

### 1.2 What this contract is, and is not

**Is:** the reified `[T,K]` IR types + a reified predicate type + an escape-hatch *policy* + a one-way `loom/src/grammar/` package + the graduation oracle that decides when the IR has replaced the spike's escape hatches.

**Is not:** the author-facing grammar spec format; AST/Term derivation (grammar→AST, §4.3 of the direction doc); the Layer-1 plumbing codegen (the separately-committed loomgen target); the L1-A RawKind fix (canopy#729 / loom#427, non-blocking); or *building* the analyzing-interpreter or the code-emitter (both benchmark-gated, §6).

---

## 2. How monogram solves the same problem (the existence proof)

monogram (`johnsoncodehk/monogram`, TS) parses JS/TS/HTML/YAML from **one reified grammar IR** with **zero embedded closures and zero escape hatches** (source-verified 2026-06-21):

- **`RuleExpr` is pure data.** Lookahead is *specific reified nodes* (`not` = negative lookahead, `sameLine`, `noCommentBefore`, `noMultilineFlowBefore`, `notLeftLeaf` = left-operand text guard) — never a `(token)=>bool`. Precedence lives in *separate* tables (`PrecLevel{assoc,operators}`, `LedPrec`) keyed by operator name.
- **No generic escape hatch exists.** Context-sensitivity is expressed by *growing the reified vocabulary* (many specific predicate node kinds), not by admitting a procedural valve.
- **Two backends over one analysis pass.** `analyzeGrammar` derives FIRST-sets, Pratt NUD/LED classification and binding-power tables *once*. Backend 1 = `gen-parser.ts` `createParser` (runtime, table-driven dispatch). Backend 2 = `emit-parser.ts` `emitParser(grammar): string` — re-derives the *same* analysis and emits self-contained specialized straight-line JS with the tables baked in as constants.

**Lesson taken:** reify predicates as data and refuse closures; the result is an IR that is analyzable *and* emittable, and rich enough to scale to hard languages. monogram is *not* projectional and owns its CST shape — a difference §5 turns into an explicit fork rather than copying its zero-hatch purity wholesale.

---

## 3. The contract: package, type parameters, rule namespace

- **New package `loom/src/grammar/`**, a sibling of `core/`, `projection/`, `pipeline/`. Dependency arrow: **`grammar → core` only; `core` never imports `grammar`** — the same one-way rule `projection/` follows. The engine consumes the interpreter's **output** closure `parse_root : (@core.ParserContext[T,K]) -> Unit` and stores only that in `LanguageSpec`; it never sees the IR. (Verified clean: `pkg.generated.mbti` stores `parse_root : (ParserContext[T,K]) -> Unit`; `build_b_syntax_grammar` already passes only the interpreted closure.)
- **Generalize over `[T, K]`.** `GrammarIr[T,K]`, `Expr[T,K]`, `Alt[T,K]` become generic over token type `T` and syntax-kind `K`, exactly as `ParserContext[T,K]` is. Removing the closures lets `Expr[T,K]` derive equality/debug *conditionally* (useful for tests and de-dup); the spike's `Expr` could derive nothing because of its closure fields.
- **`T : Eq` is already satisfied** — `ParserContext::at` requires it (`core/.../pkg.generated.mbti`); `expect` additionally bounds `Show + IsTrivia + IsEof + ToRawKind`. `K` is used as `ToRawKind`, **not** `Eq`/`Hash`. The reified predicate type (§4) needs only `T : Eq`.
- **Open rule namespace with hot-path interning.** Author rules as `Map[RuleName, Expr[T,K]]` (string-keyed — debuggable, matches monogram's `{type:'ref'; name}`). **But `interpret` resolves names to dense slot indices once, up front**, so per-edit `Ref` dispatch is an array index, never a hashmap lookup. (Codex-flagged: `Ref` runs on every rule entry inside the edit hot path; a raw string-map lookup there would tax incremental reparse.)

### 3.1 Spike scaffolding to drop when lifting

The spike IR carries three artifacts that exist only because it was an interpreter-only proof; the contract must drop or resolve them, not faithfully inherit them:

- **`RepeatTopLevel`'s `cripple_reuse : Bool`** (`types.mbt`) is a test-only positive control (it disables repeat-group reuse to prove the oracle's reuse check fires). It is **not** a grammar property — drop it from the contract IR; the oracle *harness* toggles reuse, not the grammar value.
- **`WrapIfNext`'s static `Int` mark** (`types.mbt`) cannot live in a static grammar value — a mark is a runtime cursor position. The reified variant is `WrapIfNext(K, Pred[T], Expr[T,K])`; the interpreter captures the mark at node entry, exactly as `PrattApp`/`PrattBinary` already call `ctx.mark()` internally.
- **`Expect`'s message `String` is currently dead** — the interpreter routes through `spike_expect` and ignores it (`let _ = msg`). The contract must either wire it (emit on the missing-token path) or drop the field; a stored-but-ignored field is a contract smell. (Resolve in the plan.)

---

## 4. Predicate reification (the architecturally-determining decision)

Replace **every** `(T) -> Bool` and `Alt.starts` closure with reified data:

```
enum Pred[T] { Any; IsToken(T); OneOf(Array[T]); Not(Pred[T]) }
fn[T : Eq] Pred::test(self : Pred[T], t : T) -> Bool
```

**This is verified for the spike slice, not hoped.** Every *declarative* (non-`Manual*`) predicate in `examples/lambda/src/spike/` is already one of these four: `token_starts_definition` = `OneOf([Fn,Let])`; `atom_starts_token` / `spike_starts_expression` / `spike_is_sync_point` = `OneOf(...)`; the atom `Alt.starts` arms = `IsToken(x)` / `Not(IsToken(EOF))` / `Any`; the newline repeats = `IsToken(Newline)`. The reification is a rewrite of values *already shaped like the target*.

**Hard rule: no `Opaque((T)->Bool)` variant.** A closure variant re-opens the un-analyzable, un-emittable hole monogram never admits. A predicate that does not fit `Pred` is recorded as an oracle *finding* (§5), not papered over with `Opaque`.

**`Pred` is an open, growable vocabulary (monogram's discipline), not a closed four-set.** Two predicate kinds in *full* lambda already fall outside the spike slice and will require new reified nodes (reserved extension points, design-principle 7 — add a variant, never a closure):

- **Bounded-scan lookahead** — `left_paren_starts_arrow_lambda` scans to the matching `)` before `=>` (`examples/lambda/src/cst_parser.mbt`). Needs a future `Scan`/`Balanced`-style reified node; cannot be `IsToken`/`OneOf`.
- **Token-text predicates** — type parsing branches on `current_token_text()` for `"Int"`/`"Unit"` (`cst_parser.mbt`). `Pred` over token *kind* `T` cannot discriminate by lexeme text; needs a future `TokenText(String)` node (or stays residue).

Both are out of the minimal-contract slice; the contract ships `{Any, IsToken, OneOf, Not}` and **documents the growth path** so they extend the vocabulary rather than forcing a closure.

**Pratt op tables stay inline.** `PrattBinary`/`PrattApp` already carry reified `Array[(T,K)]` op tables and passed the oracle. Keep inline; monogram's *separate* precedence tables are a different *choice*, not a required copy.

---

## 5. Escape-hatch policy: reify-first, residue is the result

The spike's four `Manual*` variants and the stubbed `WrapIfNext` are lambda-specific and cannot live in a `[T,K]` contract. **Policy:** reify each as a generic structural node; whatever cannot reach oracle parity is recorded as **irreducible residue** (classified by the existing `DivergenceClass`: `WrongModelStop` / `ReplicationResidual` / `NoDivergence`), never as a sanctioned closure hook. The residue **is** the §5.3 "shape loom's reuse/identity layer cannot express" signal that decides the migration bar (target i drop-in vs target ii re-baseline) **with evidence** — the first-target decision was deliberately deferred to this evidence (brainstorm choice: "reify-first, let residue decide").

### 5.1 Graduation table (falsifiable)

| Spike hatch | Reification target | Predicted outcome (Codex, source-cited) |
|---|---|---|
| `ManualParamList` | wire `WrapIfNext(K, Pred, body)` (interpreter captures the mark; drop the stub's `Int`, §3.1) | **reduces** — retroactive wrap is structural |
| `ManualDefinition` | `Node(kind, Seq[..])` + `Choice` over let/fn | **reduces**, modulo let/fn body-dispatch |
| `ManualBlockDelimiterCheck` | counted-repeat node + conditional `EmitError` (reuse the existing diagnostic node) | **reduces** — local iteration counting |
| `ManualNewlineAppExpr` | parameterized `Ref` (rule takes a mode arg) **or** an interpreter mode-stack | **predicted irreducible → residue** |

`ManualNewlineAppExpr` is the headline finding. `allow_newline_application` is **threaded through** binary/application/atom/paren/lambda recursion (`cst_parser.mbt`), not checked at a single node. A flat "mode node" is insufficient: reifying it requires either a *parameterized rule invocation* (`Ref` carrying a mode argument, propagated through the call graph) or a *dynamic mode stack* in the interpreter. Whether to pay for that, or accept it as residue that argues for target (ii), is exactly what the oracle adjudicates — not a thing to pre-decide.

### 5.2 Graduation criterion

The minimal contract "graduates" when, for each escape hatch, we either (a) reify it to a named node **and D1/D2a/D2b still pass**, or (b) record it as residue with a `DivergenceClass`. No `Opaque` is added to force (a).

### 5.3 Grow-vocabulary outcome (2026-06-22 execution)

§5.1's "reduces" predictions assumed reification with the *existing* combinators
(`Choice`/`Node`/`Seq`/`CountedRepeat`). Tracing against the now-on-disk spike
falsified that: `parse_definition_ir`/`parse_param_list_exact`/
`parse_block_delimiter_check` use **soft-newline-aware** behavior (consume soft
newlines before a required token; consume newlines before an expression gated on
a lookahead; a conditional `let (` diagnostic) that `Emit`/`Expect`/`Seq` cannot
express. Concrete: fixture `"let x =\n1"` — a plain `Seq([…,Expect(Eq),Ref(expr)])`
hits the atom `Choice`'s `ErrorUntil` on the newline (a sync point) and diverges.
The spike's own E1/E2 had already classified these three as escape hatches.

**Decision (user, 2026-06-22):** *grow the reified vocabulary* (monogram §4 — grow
the vocabulary, never a procedural valve) rather than accept residue. Each new
node reifies an **existing, tested `ParserContext` method** (loom#434–436 +
#279), so no new parser behavior is introduced — only IR surface. Codex-validated
(2 rounds, FAIL→PASS-with-fixes):

| New `Expr[T,K]` node | Reifies | Engine method |
|---|---|---|
| `Fail(String)` | `error`+placeholder fallback | `error`/`emit_error_placeholder` |
| `EmitOr(T,K,String)` | emit-token-or-diagnose (let/fn names) | `at`/`emit_token` + `Fail` |
| `DiagnoseIf(Pred,String)` | conditional diagnostic, no consume | `peek`/`error` |
| `ExpectSkip(Pred,K,T,K)` | soft-newline-aware `=`/`)`/`}` (`spike_expect`) | `expect_after_skip` |
| `ConsumeGated(Pred,K,Pred)` | soft newline before an expression | `consume_while_emit_if` |
| `RequireSep(Pred,K,Pred,Pred,String,String)` | block + top-level delimiter check (2 msgs) | `consume_while_emit` + count==0 guard |
| `ErrorNodeUntil(K,Pred,String)` | trailing-garbage `ErrorNode` (EOF-guarded) | `start_node`/`bump_error`/`finish_node` |

`SeparatedList` was considered and **dropped** — `ctx.separated_list` needs the
private `position` accessor, emits separators with raw token kind (not lambda's
`CommaToken`), and uses generic messages; the param-list comma-loop reifies
directly via `Choice`/`RepeatWhile` + `EmitOr`/`Fail`/`EmitError` instead.
`RepeatTopLevel` is **enriched** to carry delimiter handling (it must consume
delimiters after a `try_reuse_repeat_group()` hit too, else multi-definition
reuse exits the loop early). Reductions:

- `ManualParamList` → `WrapIfNext(ParamList, IsToken(LeftParen), Seq[Emit(LeftParen), <Choice/RepeatWhile comma-loop>, ExpectSkip(…,RightParen)])`
- `ManualDefinition` → `Choice[Alt(Let, Node(LetDef, Seq[Emit, EmitOr, DiagnoseIf, ExpectSkip, ConsumeGated, Ref(expr)])), Alt(Fn, Node(LetDef, Seq[Emit, EmitOr, Choice(paramlist|Fail), Choice(body|Fail)]))]`
- `ManualBlockDelimiterCheck` → `RequireSep(IsToken(Newline), NewlineToken, OneOf[RBrace,EOF], …)`
- top-level garbage → `Choice[Alt(EOF,Empty), Alt(Any, ErrorNodeUntil(ErrorNode, IsToken(EOF), …))]`

Only `ManualNewlineAppExpr` remains residue (§5.1's lone irreducible), handled by
the Task 8 evidence-gated probe. Findings #1 (`ExpectSkip` diag/EOF) and #4 (block
semicolon) are non-blockers — the spike-B already uses these exact methods and
passes 65/65 vs A; they become Task-9 watch-items only if the oracle expands
beyond the spike fixture slice.

---

## 6. Backend story: a/b/c → (c), one reified IR

- **One reified IR; the committed backend is the spike's tree-walking interpreter, re-validated.** The closures→`Pred` rewrite is a *change*; D1/D2a/D2b parity must be re-proven on the reified IR, not assumed to carry over.
- **The analyzing/table-driven interpreter *and* the code-emitter are both deferred behind one benchmark gate.** Reification *enables* both (it is the prerequisite that makes ahead-of-time analysis and code emission possible); it **pre-justifies neither**. loom is *incremental*, unlike monogram's non-incremental analyze-once, so monogram's table-driven speedup is unproven here and is explicitly **not** assumed to dissolve the emitter motivation.
- **Benchmark contract.** The deferral gate measures **incremental edit throughput** (`apply_edit` cycles), not fresh full-parse speed — fresh-parse timing would mis-rank an incremental engine. (Reinforced by the spike's REUSE-PARITY finding being *vacuous*: node-level reuse masked repeat-group differences, so throughput claims need an incremental benchmark, not an oracle count.)

This is the direction doc's §4.4-step-4 "interpret-now / emit-later, two backends over one IR, emitter deferred behind a benchmark," made concrete and shown to be real by monogram's dual backend.

---

## 7. Non-goals (keep it minimal — §4.4)

Explicitly out of scope for this contract:

1. The author-facing grammar spec format (the input axis, §1.1) — deferred.
2. AST/Term derivation (grammar → AST → plumbing, §4.3) — later stage.
3. Layer-1 plumbing codegen (views / syntax_kind / fold / print) — the separately-committed loomgen target; this contract is the IR that loomgen's annotation schema should later be designed as a *subset* of.
4. The L1-A RawKind registry fix (canopy#729 / loom#427) — non-blocking for this contract.
5. Building the analyzing-interpreter or the code-emitter — benchmark-gated (§6).
6. Block-reparse / incremental-relex parity — pinned OFF by `normalized_syntax_grammar` in the spike; a separate follow-up.

---

## 8. Open questions / risks

- **`ManualNewlineAppExpr` reification cost (§5.1).** Parameterized `Ref` vs. interpreter mode-stack vs. accept-as-residue. Decide *with* oracle evidence; do not pre-commit.
- **`Pred` vocabulary growth (§4).** Bounded-scan and token-text predicates are known future extensions. Keep `Pred` an open enum; resist the urge to add `Opaque` when they arrive.
- **`RuleName` interning correctness.** The one-time name→slot resolution must be total (every `Ref` target exists) and must run before the first parse; an unresolved `Ref` is a contract error, not a runtime no-op.
- **Re-validation, not inheritance.** Parity is a property of the *reified* IR; it must be re-measured, never inherited from the spike's closure IR.

---

## 9. Codex design review (2026-06-21)

Verdict: **sound-with-fixes**. Source-cited findings, all folded into this spec:

- (A) `Pred{Any,IsToken,OneOf,Not}` reifies every declarative spike predicate with no behavior change; the only hidden multi-token predicate (`left_paren_starts_arrow_lambda`) is outside the spike slice → §4 growth path.
- (B) `ManualNewlineAppExpr`'s mode is threaded through recursion → predicted irreducible residue; reifying needs parameterized `Ref` or a mode-stack → §5.1.
- (C) `ParserContext::at` already requires `T : Eq`; `K` is `ToRawKind` not `Eq/Hash`; removing closures enables conditional derive; token-text predicates are a second growth point → §3, §4.
- (D) Tree-walker-as-committed is the right incremental posture, but the deferral benchmark must measure incremental edit throughput → §6.
- (E) `Ref` dispatch is in the edit hot path → intern `RuleName` to dense slots in `interpret` → §3.
- (F) Boundary is clean — core stores only the `parse_root` closure, need not import grammar → §3.

---

## 10. Next step

Take this spec into the writing-plans skill to produce the implementation plan: create `loom/src/grammar/`, lift `GrammarIr`/`Expr`/`Alt` to `[T,K]`, introduce `Pred[T]` and rewrite the spike's declarative predicates, intern `RuleName`, reify the three reducible escape hatches, port the D1/D2a/D2b oracle to the reified IR, and record the residue. The plan must keep "minimal" literal (§7) and treat `ManualNewlineAppExpr` as an evidence-gated branch, not a committed build.

## 11. Related

- [analysis/2026-06-20-parser-generation-direction.md](../../analysis/2026-06-20-parser-generation-direction.md) — the spine (§4.2 ideal, §4.3 source-of-truth fork, §4.4 path, §5 oracle, §8 risks).
- [analysis/2026-06-20-parser-generation-spike-results.md](../../analysis/2026-06-20-parser-generation-spike-results.md) — the GO evidence (E1/E3, 3 residual hatches).
- [plans/2026-06-20-parser-generation-spike.md](../plans/2026-06-20-parser-generation-spike.md) — the executed spike plan.
- `examples/lambda/src/spike/{types,interpreter,lambda_ir}.mbt` — the spike IR this contract promotes.
- parent canopy `docs/design/07-loomgen-design.md` — the Layer-1 plumbing loomgen target (a future *subset* of this IR).
