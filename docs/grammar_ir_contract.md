# Grammar IR Alternation Contract: Strict LL(1) Choice

**Status:** Active contract
**Date:** 2026-07-04
**Issue:** [#540](https://github.com/dowdiness/loom/issues/540) (item 3)
**Documents:** [design spec](superpowers/specs/2026-06-21-loomgen-ir-contract-design.md),
[implementation plan](superpowers/plans/2026-06-22-loomgen-ir-contract.md)

---

## 1. Purpose

This document records the **deliberate** alternation semantics of the `#loom.rule` /
`--grammar-ir` EBNF subset. The choice was validated (not inherited) against the
subset's scope — **reasonably completable within ≤10 short productions** — and
the decision to reject overlapping FIRST sets is a freedom the subset can afford
that a full grammar language (e.g. monogram's ordered-choice) cannot.

The contract covers the `#loom.rule` annotation and `.loomgrammar` file paths,
both of which emit `@grammar.GrammarIr` values via
`loomgen/emit_grammar_ir.mbt`.

---

## 2. Core Principle

**Every `Choice` alternative must have a clean, disjoint FIRST set.** Overlapping
FIRST sets are rejected at generation time, never compiled or interpreted. The
generated `GrammarIr` is guaranteed to have no FIRST/FIRST conflicts: a consumer
at the other side of the contract (`@grammar.interpret`, or a future code
emitter) can dispatch any `Choice` by a single-token peek without a tiebreaker.

The interpreter's `Choice` dispatch at runtime simply walks `Alt[]` in declaration
order and runs the first whose `starts` matches (see
[`interpreter.mbt`](../loom/grammar/interpreter.mbt), `run_expr`, the
`Choice(alts)` arm). It **never** sees a conflict because the build gate already
enforced one.

---

## 3. Produced `Expr` Nodes

The `#loom.rule` annotation subset lowers to exactly six `@grammar.Expr` variants
([`emit_grammar_ir.mbt`](../loomgen/emit_grammar_ir.mbt), function `lower`):

| EBNF form | Generated `Expr` node | Semantics |
|---|---|---|
| `A B C` (space-separated) | `Seq([A, B, C])` | Sequential composition |
| `A \| B` | `Choice([Alt{starts: FIRST(A), body: A}, Alt{starts: FIRST(B), body: B}])` + auto-synthesized `Any→Fail` fallback | First-match ordered, guaranteed disjoint FIRST sets |
| `X?` | `Choice([Alt{starts: FIRST(X), body: X}])` — single-alt, no fallback | Optional. Matches nothing when absent (no error) |
| `X*` | `RepeatWhile(FIRST(X), X)` | Zero-or-more, gated on FIRST |
| `X+` | `Seq([X, RepeatWhile(FIRST(X), X)])` | One-or-more |
| `Name` (terminal) | `Expect(token, kind)` | Consume-and-check a single token |
| `Name` (term rule) | `Ref("Name")` | Delegate to another rule by name |

**Node wrapping.** Every non-Pratt rule body is emitted inside a
`Node(<kind>, <body>)` — the kind comes from the term variant's
`#loom.node`/`#loom.leaf`/`#loom.root` role, which is the CST kind generated
into `SyntaxKind`. Pratt productions (`@prefix …`) emit `PrattApp` or
`PrattBinary` directly with the node kind inside the combinator (optional
`@app` override); they are **not** wrapped in an outer `Node`.

| Pratt form | Generated `Expr` node | Semantics |
|---|---|---|
| `@prefix Rule` | `PrattApp("Rule", kind, FIRST(Rule))` | Left-associative application |
| `@prefix Rule @prec[Op,…] [@skip(Tok)]` | `PrattBinary("Rule", kind, [(Op,kind),…], skip?)` | Left-associative infix operators |

`FIRST` for Pratt productions delegates through the `@prefix` rule (so upstream
`Ref` chains inherit the prefix chain's FIRST set). `leading_refs` records the
prefix rule for left-recursion detection. Nullable prefixes are rejected in
`check_pratt_nullable_prefix` before lowering.

**The `Fail` node** never appears in source `#loom.rule` text. It is auto-synthesized
as the trailing `Any→Fail` fallback on required `Choice` nodes so a required
alternation that matches no branch emits a diagnostic + placeholder instead of
silently passing through.

### How other `Expr` nodes are unreachable from `#loom.rule`

The remaining `Expr` variants are **out of subset** — they cannot be produced
by any `#loom.rule` annotation or `.loomgrammar` production. Fragments bound
through `@fragment` references (see §5) reach the generated IR for these:

`Emit`, `RepeatTopLevel`, `WrapIfNext`,
`EmitError`, `ErrorUntil`, `EmitOr`, `DiagnoseIf`, `ExpectSkip`,
`ConsumeGated`, `RequireSep`, `ErrorNodeUntil`

`Native(RuleName)` has its own escape hatch
(`Frag` nodes skip `Native` in the FIRST-set and lowering passes) and
is not fragment‑bound.  `ManualNewlineAppExpr` is interpreter‑only residue that
cannot be authored in any notation path.

These fragment‑bound variants are proven necessary by real usage in loom's own
reference grammar (`examples/lambda/spike/lambda_grammar_ir.mbt`, cited in
[#540 comment](https://github.com/dowdiness/loom/issues/540#issuecomment-4857593443)).
They are not theoretical — but they are also not expressible in the notation
subset.

---

## 4. FIRST-Set Computation and Conflict Rejection

### 4.1 What is computed

`loomgen/emit_grammar_ir.mbt` computes FIRST sets on the **EBNF** `RuleAst`
before lowering to `GrammarIr`:

- **`nullable(ast)`** — whether the construct derives the empty string. A
terminal and a fragment are never nullable; a rule is nullable iff its body is.
A nullable cycle returns `false` conservatively (the cycle is caught separately
by the left-recursion check).
- **`first_set(ast)`** — the set of token names that can begin `ast`. Unions
left-to-right through nullable prefixes of `Seq`, stopping at the first
non-nullable element. A rule cycle inside a FIRST query raises a left-recursion
error.
- **`leading_refs(ast)`** — rule-name edges in leading position, used for eager
left-recursion detection (catches cycles in `Seq`/`Node` position where
`first_set` would never be consulted).
- **`first_names_ordered(ast)`** — the FIRST set as a declaration-order array,
raising on empty set (a nullable construct cannot gate a `Choice` or `Repeat`).

### 4.2 When rejection fires

In `lower_choice` (`emit_grammar_ir.mbt`), every token from every
branch's `first_names_ordered` is checked against all previously accumulated
branch tokens:

```text
if expected.contains(n):
  raise RuleLowerError(
    "ambiguous alternation: token '" + n +
    "' begins more than one alternative; " +
    "the #loom.rule subset requires alternatives " +
    "with disjoint FIRST sets — factor the common prefix " +
    "into a shared rule (e.g. rewrite `(A B | A C)` as " +
    "`A (B | C)`), or move the pattern into a " +
    "hand-authored @fragment"
  )
```

One token shared between two branches → the entire grammar generation fails
closed. There is no ordered-choice fallback, no precedence tiebreaker, no
"first match wins" escape valve.

### 4.3 What is also rejected at generation time

- **Left-recursive rules.** Checked both eagerly (3-color DFS over leading-ref
graph in `check_left_recursion`) and on demand (cycle detection inside
`first_set`).
- **`@fragment` references.** Emit a mangled `Ref("__loom_frag__<name>")` at
the call site; FIRST-set computation treats fragments as opaque (empty set),
so fragments in gate positions (`Choice`, `RepeatWhile`) trigger an
empty-FIRST-set error. See §5.
- **Ruleless term references.** A `Name` referring to a `#loom.term` variant
with no `#loom.rule` and no `.loomgrammar` production is rejected.
- **Unknown symbols.** A `Name` that is neither a token nor a term variant is
rejected.
- **Empty FIRST sets.** A construct with no reachable leading token (e.g. a
bare `@fragment` alternative) cannot gate a `Choice` or `RepeatWhile`.
- **Nullable alternatives in a required alternation.** An alternative that can
derive the empty string (e.g. `A?` in `(A? | B)`) has a non-empty FIRST set
but makes the alternation ε-derivable, while the emitted required `Choice`
appends an `Any → Fail` fallback — the ε case would silently become a runtime
error. Deciding ε needs FOLLOW sets, which the subset does not compute, so
generation fails closed. Rewrite as `(A | B)?`.

### 4.4 For the interpreter: no runtime overlap check

The interpreter's `Choice` dispatch
([`interpreter.mbt`](../loom/grammar/interpreter.mbt)) is a simple first-match
keeps the hot path tight.

---

## 5. `@fragment` Escape Hatch

`@fragment` references are the **intended escape hatch** for non-LL(1) patterns
and out-of-subset `Expr` nodes (Pratt, delimited repeats, gated skips, etc.).
A fragment reference `@name` in a `#loom.rule` annotation or `.loomgrammar`
file names a hand-authored `pub let name : Expr[T, K]` value that the caller
supplies at grammar compilation time.

### 5.1 Current status: fragment binding via `fragments~` parameter

As of PR #615 (2026-07-03), `@fragment` references emit a mangled
`Ref("__loom_frag__<name>")` and the generated function takes a `fragments~`
parameter (`Map[String, @grammar.Expr[Token, SyntaxKind]] = Map([])`) that binds
hand-authored `Expr` bodies at the call site. The merge loop inserts fragment
bodies into the rules map before `@grammar.compile` resolves them.

The old rejection gate `check_no_fragments` was removed — the fail-closed
behavior is now `@grammar.compile` raising `MissingRef` when a caller provides
no `fragments~` entry matching a fragment reference. A missing fragment is a
compile error (caught by `@grammar.compile`), never a runtime anomaly.

Fragment references opaque to FIRST-set computation: `first_set` returns the
empty set for `Frag(name)`, so a fragment in a `Choice` alternation or
`RepeatWhile` body position triggers an empty-FIRST-set error. This is the
correct conservative behavior — a fragment's FIRST set is not known at emit
time. Fragment references in trailing position (after a non-nullable `Seq`
prefix) never require FIRST-set computation and work without restriction.

### 5.2 Implementation: `fragments~` parameter (option 2 from the design)

The binding follows option 2 from the original design ([#540 item 4](https://github.com/dowdiness/loom/issues/540)):
the generated `GrammarIr` factory (now a `pub fn`) takes a `fragments~` parameter
(`Map[String, @grammar.Expr[Token, SyntaxKind]] = Map([])`), and the emitter
inserts a `for frag, body in fragments { rules.set(frag, body) }` merge loop
before constructing the `GrammarIr` value. `@grammar.compile` resolves the
mangled `Ref("__loom_frag__<name>")` against the merged map; a missing binding
raises `MissingRef` at compile time.

The mangled `__loom_frag__` prefix avoids collision with bare variant names in
the `GrammarIr.rules` map. Fragment references use `@fragment` syntax in rule
strings (parsing to `Frag(name)` in `RuleAst`), and the emitter's `lower()`
function handles `Frag(name)` by emitting the mangled `Ref`.

Both principles from the original design are preserved: the `GrammarIr` value
remains closure-free (the fragment hand-author writes data, never closures) and
analyzable, and a missing fragment is a compile error (`MissingRef`), never a
runtime anomaly.

### 5.3 What fragments enable

13 fragment‑bound `Expr` variants (as counted in the
[#540 follow-up comment](https://github.com/dowdiness/loom/issues/540#issuecomment-4857593443))
require `@fragment` binding today — the 7 in‑subset nodes are the ones
listed in §3.  Among the fragment‑bound forms, `Emit` and `ExpectSkip` have
the highest call‑site frequency:

```
(every in‑subset variant is the 7 listed in §3)
Emit            — 13 uses (non‑diagnosing token consume inside a gated arm)
ExpectSkip      —  4 uses (gated skip then require)
EmitOr          —  2 uses
EmitError       —  2 uses
WrapIfNext      —  1 use
RequireSep      —  1 use
RepeatTopLevel  —  1 use
PrattBinary     —  1 use
PrattApp        —  1 use
ErrorUntil      —  1 use
ErrorNodeUntil  —  1 use
DiagnoseIf      —  1 use
ConsumeGated    —  1 use
```

`Native(RuleName)` (added in [#541](https://github.com/dowdiness/loom/issues/541))
is a separate escape‑hatch and is not fragment‑bound.
`ManualNewlineAppExpr` is interpreter‑only residue with no reified form in
either path.

With fragment binding implemented, a language author can drop out of the LL(1)
subset for specific rules by hand-authoring `Expr` values that use any of these
nodes — including overlapping FIRST sets, which the hand-written `Alt` predicates
control directly without going through the FIRST-set gate.

---

## 6. Why Strict LL(1) (Decision Record)

This contract is a **deliberate design decision** — not an inherited side effect
of an implementation detail. Its basis is recorded in
[#540 item 3](https://github.com/dowdiness/loom/issues/540):

> Make this a conscious call and document it: keep strict LL(1) disjointness
> (current behavior) and state it as the subset's contract.
>
> For the "≤10 short productions" scope strict LL(1) is defensible, but it
> should be a decided contract, not an inherited side effect.

### 6.1 What the subset's size buys us

The `#loom.rule` annotation subset targets grammars that fit comfortably within
a variant annotation string — typically 1–10 productions, each ≤15 tokens of
EBNF. At this scale:

- **Grammar-wide FIRST-set analysis is cheap.** The `nullable`/`first_set`/`leading_refs`
  triple pass over a 10-rule grammar runs in microseconds and never enters a
  performance-critical path.
- **Disjoint FIRST sets are achievable without heroics.** At ≤10 productions,
  a language author can almost always restructure a FIRST/FIRST conflict (e.g.
  by factoring the common left-edge into a shared helper rule). The conflict
  diagnostic points directly at the overlapping token, and the fix is local.
- **No ordered-choice need.** The overlapping token in `(A B | A C)` is always
  resolvable by introducing a factoring rule `A (B | C)`. Ordered choice would
  silently shadow the second branch's error recovery, which is worse than
  rejecting the grammar.

### 6.2 What it costs

- **`@fragment` binding is mandatory**, not optional, for any consumer that needs
  Pratt parsing, delimited repeats, gated skip, or error recovery nodes.
- **Fragment-free grammars are strictly LL(1).** A consumer whose grammar does
  not use `@fragment` can assume single-token-lookahead dispatch everywhere.
  This is a strong guarantee: the generated `GrammarIr` has zero FIRST/FIRST
  conflicts by construction.
- **Scaling beyond the subset.** A language whose grammar grows beyond the
  "≤10 short productions" scope will encounter FIRST-set constraints more
  frequently. At that point the pressure argues for either (a) more `@fragment`
  usage (the subset is a design barrier, not a mistake), or (b) moving to the
  hand-authored `GrammarIr` API directly, bypassing the annotation subset
  entirely.

### 6.3 Relationship to `@grammar.compile`

The `@grammar.compile` function (in `loom/grammar/compile.mbt`) is **agnostic**
to the LL(1) contract. It compiles any `GrammarIr` value, including one whose
`Choice` nodes have overlapping FIRST sets — those are valid (first-match
semantics, PEG-like) at the `@grammar` layer. The strict LL(1) contract is
enforced at the **generation** boundary (`loomgen emit_grammar_ir.mbt`), not
at the `@grammar` library boundary, so `@grammar` remains general while
`--grammar-ir` is strict.

---

## 7. Implications for Consumers

### 7.1 Downstream from `--grammar-ir` (the generated `GrammarIr`)

- Every `Choice` has disjoint FIRST sets. The runtime interpreter
  (`@grammar.interpret`) will never dispatch the wrong branch due to overlap.
- Every required `Choice` has a trailing `Any→Fail` fallback. An input that
  matches no branch surfaces a diagnostic + placeholder instead of silently
  passing through.
- Every optional `Choice` (from `X?`) has no fallback. Absence is silence.
- Every top-level rule has a `Node` wrapper with its CST kind. The engine's
  incremental reuse machinery keys on node kinds — so every parse gets its
  root node and every rule-body subtree gets a structural root the seam model
  can track across edits.

### 7.2 Upstream (the language author writing `#loom.rule` or `.loomgrammar`)

- `(A B | A C)` is rejected: rule grammar is LL(1) or it does not generate.
- Left recursion is rejected — rewrite cycles as `(` x `)*` repetition.
- `@fragment` references emit a mangled `Ref("__loom_frag__<name>")` — the
  caller supplies fragment bodies via the `fragments~` map parameter (see §5).
  Without a matching entry, `@grammar.compile` raises `MissingRef`.
- A nullable body cannot gate a `Choice` or `RepeatWhile`. Two distinct guards
  enforce this: a construct with an *empty* FIRST set (nothing reachable can
  begin it) is rejected outright, and a *nullable alternative* with a non-empty
  FIRST set (e.g. `A?` in a required alternation) is rejected because the
  emitted `Any → Fail` fallback would turn its ε case into a runtime error —
  rewrite `(A? | B)` as `(A | B)?`.
- `X+` / `X*` bodies with a partially-nullable inner are safe: the empty-FIRST
  guard rejects fully-nullable bodies, and a partially-nullable body always
  consumes its gating FIRST token (FIRST exists only because some derivation
  `Expect`s the gating token, which the body reaches), so `RepeatWhile` always
  progresses. The `Any→Fail` fallback cannot fire inside a repeat — the repeat
  only enters on a real FIRST match.

---

## 8. Related

- [#540 — loomgen #522 follow-ups](https://github.com/dowdiness/loom/issues/540)
  — Parent issue covering compile-regression (item 1), interpret parity (item 2),
  alternation semantics (this document, item 3), `@fragment` binding (item 4),
  and documentation gaps (items 5-6).
- [#541 — `Native(RuleName)` IR escape-hatch node](https://github.com/dowdiness/loom/issues/541)
  — Context-sensitive production escape (HTML tag matching, hand-authored parse
  functions), sharing the same compile-time validation discipline as fragment
  binding.
- [Design spec: minimal grammar-IR contract](superpowers/specs/2026-06-21-loomgen-ir-contract-design.md)
  — The full design, including predicate reification (`Pred[T]`), escape-hatch
  policy, and the decision to reify-to-data rather than admit `Opaque` closures.
- [Implementation plan: loomgen IR contract](superpowers/plans/2026-06-22-loomgen-ir-contract.md)
  — Execution tasks for the reified `[T,K]` grammar IR.
- `loomgen/emit_grammar_ir.mbt` — The `lower_choice` function where the
  disjoint-FIRST check lives.
- `loom/grammar/interpreter.mbt` — The `Choice(alts)` arm in `run_expr` where
  the first-match peek-and-run dispatch executes.
- `loom/grammar/compile.mbt` — Grammar compilation (rule interning, ref
  resolution), independent of the LL(1) contract.
