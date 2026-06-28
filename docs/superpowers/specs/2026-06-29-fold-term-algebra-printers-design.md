# Design: Migrate lambda printers onto the `interpret` fold

**Date:** 2026-06-29
**Status:** Approved (pending spec review)
**Scope:** `examples/lambda/ast/` — `pretty_traits.mbt`, `sym.mbt`, `sym_test.mbt`
**Branch:** `migrate-consumers-onto-interpret`

## Problem

`examples/lambda/ast/sym.mbt` defines a Finally-Tagless algebra (`TermSym` trait)
and a catamorphism driver `interpret[T : TermSym](Term) -> T` (renamed from
`replay` in PR #536). It is meant to be the single source of truth for Term's
recursive structure: any interpretation is a `TermSym` instance, and `interpret`
drives the recursion once.

Two production printers in `pretty_traits.mbt` **bypass** `interpret` and
hand-recurse over `Term` instead:

1. `term_to_source_with_prec` (string printer, backs `to_source` / `print_term`)
   — a full hand-recursion with its own precedence logic.
2. `term_to_pretty_layout_with_context` (layout printer, backs `to_layout` /
   `@pretty.pretty_print`) — a *partial* hand-recursion: it already delegates 9
   of 12 constructors to the existing `PrettyLayout : TermSym` impl, and only
   hand-writes `Lam`, `LetDef`, and `Module`.

This duplicates the recursion `interpret` exists to own. The goal is to delete
the hand-recursion and drive both printers through `interpret`.

## Why the printers hand-recurse today

`interpret` is a bottom-up catamorphism: when `lam(x, body)` runs, `body` is
*already folded* into an opaque `Self`. The hand-recursions do three things that
appear to need un-folded shape or top-down context:

- **Precedence parens** — thread a `ctx_prec` downward to decide wrapping.
- **Lambda collapsing** — `collect_lambda_params` peeks through `Lam(a, Lam(b, …))`
  to print `(a, b) =>` instead of `(a) => (b) =>`.
- **`let`-of-lambda → `fn` sugar** — `def_to_source`/`def_to_layout` peek whether
  a def's init is a lambda to print `fn name(p) { … }`.
- **Module top-level vs nested** — thread a `top_level : Bool` to print the
  program flat at top level and braced `{ … }` when nested.

## Key realizations

The apparent obstacles dissolve under analysis:

1. **Precedence is already compositional.** The existing `PrettyLayout` impl
   parenthesizes bottom-up: each node reports its own `prec` field, and the
   *parent* calls `wrap_if_needed(child, ctx)` to wrap a child whose `prec` is
   lower than the position requires. No top-down threading is needed — this is a
   pure catamorphism today.

2. **Module bracing can be made uniform.** `{ defs }` and bare `defs` parse to
   the *same* `Module` at top level, and nested braced modules round-trip
   (`parse("{ { 1 } }") == Module([], Module([], Int(1)))`, verified by the
   existing `parse nested blocks` test). So **always-bracing** every Module drops
   the top-down `top_level` flag while staying round-trip-safe. This is the one
   change that turns `mod` into a foldable method.

3. **Lambda-collapse and `fn`-sugar are purely cosmetic.** `(a) => (b) => …` and
   `let f = (x) => …` both parse back to the same Term as their sugared forms.
   Dropping them is snapshot churn, not a correctness change. (User decision:
   cosmetic regression is acceptable in exchange for a clean fold.)

Net effect: both printers become **pure catamorphisms over `interpret`**, and the
migration is dominated by deletion.

## Design

### Component 1 — Layout printer (`PrettyLayout`)

The `PrettyLayout : TermSym` impl already exists and is complete. Changes:

- **Edit `PrettyLayout::mod`** to always emit braces (`module_to_block_layout`
  shape) instead of the current always-flat shape. This is required for
  round-trip safety of nested modules.
- **Rewire `to_layout`**: replace `term_to_pretty_layout(self)` with
  `(interpret(self) : PrettyLayout).layout`.
- **Delete** the hand-recursion and its sugar-only helpers:
  `term_to_pretty_layout`, `term_to_pretty_layout_in_expr`,
  `term_to_pretty_layout_with_context`, `collect_lambda_params`, `def_to_layout`,
  `module_contents_to_layout`, `module_to_block_layout`,
  `function_body_to_layout`, `lambda_body_to_layout`, and the string-sugar
  helpers `module_contents_to_source`, `module_to_block_source`,
  `expression_to_source`, `function_body_to_source`, `lambda_body_to_source`,
  `def_to_source`, `params_to_source`.
- **Keep**: `wrap_if_needed`, the tagger helpers
  (`kw`/`ident`/`num`/`op_text`/`punc`/`err_text`/`tagged`), and the `prec_*`
  constants — all still used by the `TermSym` impls.
- **Delete-what-becomes-unused**: do not enumerate every helper's fate by hand.
  Some helpers (e.g. `params_to_layout`, `params_to_source`) have *no* caller once
  the hand-recursion and `def_to_*` are removed — the `PrettyLayout::lam` impl
  renders a single param via `ident(x)` directly and never calls
  `params_to_layout`. Remove the hand-recursion first, then let `moon check
  --deny-warn` flag remaining dead helpers and delete each one it names.

### Component 2 — String printer (`SourceText`)

Named `SourceText`, **not** `Source`, to avoid colliding with the `@pretty.Source`
trait that `Term` already implements.

- **Add** `struct SourceText { repr : String; prec : Int }` and a
  `SourceText : TermSym` impl in `pretty_traits.mbt`, mirroring `PrettyLayout`'s
  precedence discipline. Introduce a `wrap_source(child : SourceText, ctx : Int)
  -> String` helper analogous to `wrap_if_needed`. `SourceText::mod` always-braces,
  matching Component 1.
- **Rewire** `term_to_source` (and thus `print_term` and the `@pretty.Source for
  Term` impl) to `(interpret(self) : SourceText).repr`.
- **Delete** `term_to_source_with_prec` (and the string-sugar helpers listed
  above, shared with Component 1's deletion list).

### Component 3 — Retire `Pretty`

`Pretty` (`sym.mbt`, `{ repr : String }`, fully-parenthesized) is a test-only
demo interpretation referenced solely by `sym_test.mbt`. With `SourceText` as the
real string interpretation it is a redundant near-duplicate.

- **Delete** the `Pretty` struct and its `TermSym` impls from `sym.mbt`.
- **Repoint** the 4 `sym_test.mbt` cases that read `(interpret(t) : Pretty).repr`
  to `(interpret(t) : SourceText).repr`; update expected strings to the
  minimal-paren forms `SourceText` produces.
- **Fix** the stale comment at `pretty_traits.mbt:3` ("Delegates to the existing
  Pretty TermSym interpretation") — `to_source` delegates to `SourceText`.

Cross-package note: `interpret`, `Pretty`, and `PrettyLayout` are referenced as
`@ast.*` from blackbox tests. Bare-constructor sugar does not cross package
boundaries, so `sym_test.mbt` ascribes the result type (`(@ast.interpret(t) :
@ast.SourceText).repr`) rather than constructing `SourceText` directly — same
pattern the existing `Pretty` tests use.

The pretty-printer *feature* (width-aware, syntax-highlighted layout via
`@pretty.pretty_print`) is `PrettyLayout` and is unaffected by this deletion.

## Error handling

`interpret` is total: `unbound`, `error_term`, and `hole` are first-class
`TermSym` methods with existing impls (`<unbound: x>`, `<error: msg>`, `_`). No
partial matches, no new failure modes. `SourceText` and the edited `PrettyLayout`
keep these impls byte-for-byte.

## Output changes (accepted)

Relative to today's output:

- Curried lambdas print uncollapsed: `(a) => (b) => …` (was `(a, b) => …`).
- `let`-bound lambdas print as `let f = (x) => …` (was `fn f(x) { … }`).
- Every `Module` is braced, including the whole-program top level: `{ let a = 1
  a }` (was flat at top level).
- Minimal-paren placement is preserved by `SourceText` (not fully parenthesized).

All of the above re-parse to the original Term (round-trip-safe).

## Testing

1. **Positive control (required).** Add a round-trip assertion for a
   block-bodied lambda whose body is a nested `Module`, e.g.
   `(x) => { let a = 1; a }`. The existing `@qc` property
   `parse(pretty_print(term)) == term` *discards* every non-top-level Module via
   `has_non_roundtrippable`, so the nested-module path this migration changes is
   currently an untested null. This case calibrates the detector against exactly
   the behavior we are changing.
2. **Full snapshot suite.** Run `moon test`; triage every changed snapshot into
   "different but still parses" (accept via `moon test --update`) vs. "no longer
   parses" (must fix before proceeding). Do not blanket-update.
3. **Round-trip property stays green.** Confirm the `@qc` property still passes
   after the change.
4. Standard gates: `moon check`, `moon info && moon fmt`, inspect `git diff
   *.mbti` for unintended API surface changes (the `Pretty` deletion and `SourceText`
   addition are intentional `.mbti` changes).

## Blast radius

- `examples/lambda/ast/pretty_traits.mbt` — rewrite (add `SourceText`, rewire two
  trait impls, delete hand-recursion).
- `examples/lambda/ast/sym.mbt` — edit `PrettyLayout::mod` brace policy, delete
  `Pretty` + impls.
- `examples/lambda/ast/sym_test.mbt` — repoint `Pretty` → `SourceText`, update
  expected strings.
- Snapshot tests across the lambda example that assert printed output
  (`print_term` / `to_source` / `pretty_print`) — update accepted churn.

Estimated net ~150 lines deleted.

## Non-goals

- Migrating the heavier env-threading consumers (`resolve`, `eval`, `infer`).
  Those are separate sessions; `eval` in particular is a data-model change
  (`VClosure` would hold a function rather than a `Term`). They remain standing
  DRY targets after this change.
- Introducing a paramorphism / attribute-grammar driver. Not needed once the
  sugar is dropped and Module bracing is made uniform.
- **Source-faithful sugared printing** (`fn f(x) { … }`, collapsed multi-param
  lambdas, source block/expr distinction) is deliberately *not* recovered here.
  That fidelity is *surface* information and already lives losslessly in the CST
  (`FnKeyword`, `LambdaExpr`, `ParamList`, `BlockExpr` are distinct
  `SyntaxKind`s); `Term` is the desugared semantic core and intentionally drops
  it. If faithful sugared output is wanted later, it is a **CST-printer**
  responsibility — not a paramorphism over `Term` (which would only re-derive,
  lossily, what the CST already holds). This mirrors loom's existing two-layer
  split (CST = source truth, semantic IR = meaning), e.g. markdown's
  `CST`/`MarkdownIR`.
