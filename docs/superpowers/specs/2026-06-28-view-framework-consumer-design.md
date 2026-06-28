# Framework consumer for `#loom.view` — Stage 3 integration design

**Status:** Design / spike (not yet approved or built).
**Date:** 2026-06-28
**Addresses:** loomgen Phase 3 / #514 — how generated `*Proj` view accessor structs integrate with the reactive `Parser[Ast]` / `ImperativeParser` / `SyntaxParser` framework.
**Decision record:** This spike precedes the ADR. An ADR will be created when the design is approved and implemented.

---

## 1. Problem and scope

### 1.1 What exists

loomgen currently emits `views.g.mbt` containing `*Proj` structs for each term-enum target node that has `#loom.view` edges. These structs (e.g., `IfExprProj`, `LambdaExprProj`) wrap `@seam.SyntaxNode` and expose named accessor methods that delegate to `@seam.SyntaxNode::required_direct_child_of_kind` / `optional_direct_child_of_kind` / etc.

Generated output shape (from `views_fixture.g.mbt`):

```moonbit
pub struct IfExprProj { node : @seam.SyntaxNode }

pub fn IfExprProj::cast(n : @seam.SyntaxNode) -> IfExprProj? { ... }

pub fn IfExprProj::condition(
  self : IfExprProj,
  message? : String = "view IfExpr.condition expects exactly one IfCondition",
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.node.required_direct_child_of_kind(IfCondition.to_raw(), message=message)
}
```

The `*Proj` structs live in the `syntax/` package (alongside `syntax_kind.mbt`) — the same package that defines the `SyntaxKind` enum. They import `@seam` for `SyntaxNode` and `ProjectionShapeError`, but do **not** import `@core` (which defines the `AstView` trait, `ParserContext`, etc.).

### 1.2 What the reactive framework exposes

The framework (`/loom/pipeline/`) provides two reactive parser types:

- **`Parser[Ast]`** — generic typed parser: `.syntax_tree()` → `@incr.Derived[@seam.SyntaxNode]`, `.ast()` → `@incr.Derived[Ast]`
- **`SyntaxParser`** — syntax-only parser: `.syntax_tree()` → `@incr.Derived[@seam.SyntaxNode]`, `.diagnostics()` → `@incr.Derived[DiagnosticSet]`

Both expose their `@incr.Runtime` via `.runtime()` so downstream consumers can attach their own `@incr.Derived` cells.

### 1.3 The integration gap

The `*Proj` structs are pure CST-shape validators. They are:

- **Not reactive** — they operate on a `SyntaxNode` value, not on `@incr.Derived`
- **Not trait-bounded** — they do not implement `AstView` (because `@core` is unavailable at the syntax-package level)
- **Not wired to the parser** — there is no generated helper to go from `parser.syntax_tree()` to an `IfExprProj`

A language author currently must write all of this wiring by hand — the same work they'd do without loomgen at all. The struct generation saves typing (the accessor boilerplate) but provides no pipeline integration.

### 1.4 Scope of this spike

This spike answers:

1. Where does the framework consumer interface sit in the pipeline? (`SyntaxNode → *Proj accessor → downstream consumer`)
2. What can loomgen generate vs. what must the language author write?
3. Should `*Proj` structs implement `AstView`? If not, what should?
4. How does the reactive pipeline (`@incr.Derived`) compose with `*Proj`?

**In scope:** Pipeline map, `AstView` integration, reactive wiring pattern, generated helper surface.

**Out of scope:** Recursive typed view resolution (e.g., `body()` returning `LambdaExprView` instead of `SyntaxNode`); projectional editing integration (`TreeNode`/`Renderable` traits); `#loom.view` syntax extensions; the `@grammar` interpreter.

---

## 2. Pipeline map

```
                    Reactive pipeline (loom framework)
                    ┌────────────────────────────────────────────┐
                    │  SyntaxParser / Parser[Ast]                │
                    │    .syntax_tree() → Derived[SyntaxNode]    │
                    │    .diagnostics() → Derived[DiagnosticSet] │
                    └───────────┬────────────────────────────────┘
                                │
                   ┌────────────▼────────────┐
                   │   Language author code   │
                   │                         │
                   │  1. Read syntax root     │
                   │  2. Find target child    │
                   │  3. *Proj::cast(child)   │
                   │  4. Access typed slots   │
                   └────────────┬────────────┘
                                │
                   ┌────────────▼────────────┐
                   │  Generated (loomgen)     │
                   │  views.g.mbt             │
                   │                         │
                   │  *Proj::cast()           │
                   │  *Proj::accessor()       │
                   │    → SyntaxNode          │
                   └────────────┬────────────┘
                                │
                   ┌────────────▼────────────┐
                   │  Seam (@seam)           │
                   │                         │
                   │  SyntaxNode::            │
                   │   required_direct_       │
                   │   child_of_kind(kind)    │
                   │   → Result[SyntaxNode,   │
                   │     ProjectionShapeError]│
                   └─────────────────────────┘
```

The **framework consumer interface** sits at the language-author layer (row 2). The generated `*Proj` structs (row 3) are a consumed artifact — they provide the shape-validation vocabulary that the framework consumer uses. The interface between `*Proj` and the reactive parser is **not automated** — the language author writes the code that goes from `syntax_tree()` → `*Proj`.

---

## 3. Design decisions

### D1. `*Proj` stays in the syntax package and does NOT import `@core`

**Rationale:** The `syntax/` package already depends on `@seam` (for `SyntaxNode` / `SyntaxKind` / `ProjectionShapeError`). Adding a `@core` dependency would couple the syntax-kind package to the core parser framework. This is the wrong direction: the syntax package should be a lightweight type-definition layer, not part of the parser runtime.

The syntax package is the single natural home for `views.g.mbt` because it defines the `SyntaxKind` enum that the `*Proj` accessors reference. Moving views to a different package would require cross-package imports of variant names, defeating the purpose.

**Consequence:** `*Proj` structs do NOT implement `AstView`. The `AstView` trait is for the **grammar package** (e.g., `examples/lambda/`), which does import `@core`.

### D2. A second generated `*View` layer goes in the grammar package

For each `*Proj` struct in the syntax package, loomgen also emits a corresponding `*View` struct in the **grammar package** (wherever `spec.g.mbt` goes — the package that builds `LanguageSpec`).

The `*View` struct:

- Wraps the `*Proj` (not `SyntaxNode` directly)
- Implements `AstView` (available because the grammar package imports `@core`)
- Delegates accessor methods to the `*Proj`
- **Returns `@seam.SyntaxNode`** (same as `*Proj`) — does NOT resolve to typed views recursively

```moonbit
// Generated in grammar/views.g.mbt
pub struct IfExprView {
  proj : IfExprProj
}

pub fn IfExprView::cast(proj : IfExprProj) -> IfExprView? {
  // Validate: IfExprProj already validated the kind match
  // but we re-check for safety (the proj could be from any IfExpr-like node)
  Some({ proj })
}

pub impl @core.AstView for IfExprView with fn syntax_node(self) {
  self.proj.node
}

pub fn IfExprView::condition(
  self : IfExprView,
  message? : String = ...,
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.proj.condition(message=message)
}

pub fn IfExprView::then_branch(
  self : IfExprView,
  message? : String = ...,
) -> Result[@seam.SyntaxNode, @seam.ProjectionShapeError] {
  self.proj.then_branch(message=message)
}
```

**Rationale:** The two-tier design preserves the separation of concerns:

| Layer | Package | Imports | Responsibility |
|-------|---------|---------|----------------|
| `*Proj` | `syntax/` | `@seam` | Shape validation at the syntax-kind level |
| `*View` | `grammar/` | `@seam`, `@core`, `syntax/` | AstView integration, framework-consumer bridge |

The `*View` struct is the **framework consumer**. It is what a language author casts their `SyntaxNode` to and uses to access typed children.

**Alternative considered — single tier with conditional import:**

Instead of two structs, we could generate `AstView` impls directly on `*Proj` when `@core` is importable, and omit them otherwise. This requires loomgen to know whether the output package imports `@core` — a cross-package dependency analysis loomgen cannot perform generically. The two-tier approach avoids this analysis by letting the language author's package import choice drive the view tier they use.

**Alternative considered — merge `*View` into `*Proj` by moving `AstView` to `@seam`:**

Moving `AstView` to `@seam` (which the syntax package already imports) would let `*Proj` implement `AstView` directly. This couples the trait definition to the seam package, which is a bigger change than a second generated struct. `AstView` is conceptually a parser-framework concept, not a CST-internals concept. Rejected to avoid trait-definition churn.

### D3. Generated `*View` uses `*Proj` accessors, not direct SyntaxNode calls

Each `*View` accessor method delegates to the corresponding `*Proj` method:

```moonbit
pub fn IfExprView::condition(self) -> Result[...] { self.proj.condition() }
```

**Rationale:** The `*Proj` struct is the canonical generated artifact. The `*View` is a thin wrapper that adds `AstView` and lives in the grammar package. Wrapping (rather than duplicating) means:

- The shape-validation logic lives in only one place (`*Proj`, in the syntax package)
- A consumer using only `*Proj` (no `@core` dependency) gets full accessor functionality
- A consumer using `*View` gets the same functionality plus `AstView` integration
- Updates to `*Proj` accessor signatures automatically propagate to `*View`

### D4. Accessors return raw `SyntaxNode` (not typed nested views)

**Rationale:** Returning typed child views (e.g., `condition()` returning `IfConditionView` instead of `SyntaxNode`) requires loomgen to:

1. Determine which `#loom.node`/`#loom.view` variant a `#loom.view` target corresponds to
2. Generate the appropriate return type for each accessor
3. Handle cardinality: `optional_direct_child_of_kind` returns `SyntaxNode?`, not `IfConditionView?`

This is a cross-variant type-resolution problem — loomgen already validates that view targets reference `#loom.node`/`#loom.root` variants (in `parse_annotations.mbt`), but resolving the *type* of the target would require a lookup table from variant name to view type name. This is feasible but adds complexity before the basic integration is validated.

**Current conservative choice:** Return `@seam.SyntaxNode`. The consumer can downcast:

```moonbit
let view = IfExprView::cast(proj).unwrap()
let condition_node = view.condition().unwrap()
let condition_view = match IfConditionView::cast(condition_node) {
  Some(v) => v
  None => abort("expected IfCondition")
}
```

**Future direction:** Once the two-tier approach is deployed and validated, loomgen can optionally emit typed return types by resolving each view target's variant to its corresponding view type name. The validation in `parse_annotations.mbt` already ensures all view targets are `#loom.node` or `#loom.root` variants — the only missing piece is the type-name lookup.

### D5. Reactive wiring is manual (language author writes `@incr.Derived[Proj?]`)

The reactive pipeline exposes `Derived[SyntaxNode]`. To get a reactive `Derived[IfExprProj]`, the language author writes:

```moonbit
let if_view = @incr.Derived::Derived(
  parser.runtime(),
  fn() {
    let root = parser.syntax_tree().read_or_abort()
    root.children().iter().find_map(child -> {
      match IfExprProj::cast(child) {
        Some(proj) => Some(IfExprView { proj })
        None => None
      }
    })
  },
  label="if_view",
)
```

**Rationale:** The selection criterion ("find the first `IfExpr` child" vs. "find the nth `IfExpr`" vs. "all `IfExpr` children") is language-specific and context-dependent. The parser does not know which node the consumer considers "the" `IfExpr`. Generating a `find_in_tree` helper is possible (it would walk `SyntaxNode::children()` filtering by kind) but trivial for the language author to write, and the generated helper would have to make assumptions about selection semantics.

**Recommendation:** Do NOT generate `find_in_tree` or `derive_*` helpers. Document the pattern (above) in the projection guide.

### D6. View name derivation: `{Target}View` is the convention

The `*View` struct name follows from the target variant name:

| Syntax variant | `*Proj` struct | `*View` struct |
|----------------|----------------|----------------|
| `IfExpr` | `IfExprProj` | `IfExprView` |
| `LambdaExpr` | `LambdaExprProj` | `LambdaExprView` |
| `SourceFile` | `SourceFileProj` | `SourceFileView` |

This matches the existing naming convention in `examples/lambda/views.mbt` (e.g., `LambdaExprView`, `AppExprView`).

---

## 4. Integration test strategy

### 4.1 Existing regression tests (keep)

- `emit_view_accessors_wbtest.mbt` — tests `*Proj` generation against `views_fixture.g.mbt` byte-lock. **Keep as is.**
- `view_fixture.mbt` / `views_fixture.g.mbt` — fixture input and expected output. **Keep.**

### 4.2 New: `*Proj` → `*View` parity test

A test that converts an `*Proj` value through `*View::cast()` and verifies accessor methods return identical results:

```moonbit
test "IfExprView accessors match IfExprProj accessors" {
  let proj = IfExprProj::cast(some_if_expr_node).unwrap()
  let view = IfExprView::cast(proj).unwrap()
  // Same accessors return same Results
  inspect(view.condition(), content=(proj.condition()))
}
```

This is a unit test inside loomgen that uses the fixture view file.

### 4.3 New: End-to-end reactive integration test

A test in the `loomgen/fixtures/grammar_parity/` namespace that demonstrates the full pipeline:

1. Parse source using `ImperativeParser` with the emitted grammar
2. Extract `SyntaxNode` from result
3. Cast to `*View` via generated accessors
4. Verify accessor results match expected CST shape

This is a **demonstration** test, not a regression gate. It proves the integration works end-to-end with a real parser.

---

## 5. Implementation plan

### 5.1 Phase A (this PR): Wire `AstView` on `*Proj` via `@seam`

The simplest step that unblocks all downstream integration: **move the `AstView` trait definition to `@seam`** (from `@core`).

This is safe because:

- `@seam` is already imported by every package that has `SyntaxNode` values
- `AstView` is a one-method marker trait with no `@core` dependencies
- The `@core` re-export (`loom/loom.mbt:104` — `pub using @core {trait AstView}`) stays in place for backward compatibility
- The `@core` import of `AstView` just re-exports the seam definition (MoonBit `using` re-exports the same trait)

After this change, loomgen generates `AstView` impls directly on `*Proj` structs, eliminating the need for the two-tier `*View` layer entirely.

**Consequences of this decision:**

| Concern | Resolution |
|---------|------------|
| Syntax/ package gains AstView dependency | AstView moves to @seam, which syntax/ already imports |
| Existing `@core` consumers break? | No — `loom.mbt` re-exports `trait AstView` from core, which now comes from seam |
| Backward compat with existing views | Lambda views already implement AstView in the grammar package — that impl stays; no conflict |

### 5.2 Phase B (deferred): View finder helpers

After Phase A is validated, consider adding a generated static helper:

```moonbit
pub fn IfExprProj::find_in_syntax_tree(n : @seam.SyntaxNode) -> Array[IfExprProj]
```

This walks `n.descendants()` (or `n.children()`) collecting nodes whose kind matches. However, this is deferred because:

- `SyntaxNode` does not have a `descendants()` method (only `children()` recursion, which allocates per call)
- The selection semantics (first match vs. all matches vs. filtered) are language-specific
- The language author can write the trivial one-line helper faster than they can find the generated one

### 5.3 Phase C (future): Typed view returns

After the basic integration is stable, loomgen can resolve view target variant names to their `*View` type names and generate accessors returning `ViewType?` instead of `@seam.SyntaxNode`. This requires:

- A map from variant name to view type name in the generated output
- Conditional wrapping logic: `required_direct_child_of_kind(node, kind)` → `TargetView::cast(node)`
- Handling the cardinality wrapper: `Result[SyntaxNode, Error]` becomes `Result[TargetView?, Error]` or `Result[TargetView, Error]`

This is deliberately deferred — the typed returns add complexity before the basic integration is proven.

---

## 6. Phases summary

| Phase | Change | Delivers | Depends on |
|-------|--------|----------|------------|
| **A** | Move `AstView` to `@seam`; generate AstView impl on `*Proj` | Single-tier `*Proj` with full AstView integration; no two-tier `*View` needed | This spike approval |
| **B** | `find_in_syntax_tree` helpers on `*Proj` | Convenience for finding target nodes in parsed trees | Phase A, consumer demand |
| **C** | Typed view returns from accessor methods | End-to-end typed access without manual downcast | Phase A, view target resolution |

---

## 7. Risks and open questions

1. **`AstView` trait location change:** Moving the trait definition from `@core` to `@seam` is a source-level change to the `loom/` package. Is there any consumer that imports `@core` specifically for `AstView` and does NOT import `@seam`? (Expected answer: no — `AstView::syntax_node` returns `@seam.SyntaxNode`, so the consumer must already import `@seam`.)

2. **`AstView` doc comment drift:** The trait currently lives in `parser_ast_view.mbt` with a doc comment about the grammar-package usage pattern. If moved to `@seam`, the doc should be updated to describe the generated `*Proj` pattern instead.

3. **MoonBit trait re-export semantics:** Does `pub using @seam {trait AstView}` in `loom.mbt` correctly re-export the trait under `@core`'s namespace, or does MoonBit `using` create a new name binding? Verified: MoonBit `using` creates an alias in the importing module's namespace — so `pub using @core {trait AstView}` in `loom/loom.mbt` brings the seam-defined trait into the `@core` namespace. Backward-compatible.

4. **Concrete timeline for Phase C typed returns:** Phase A ships the *minimum* framework consumer integration. Phase C should only be pursued when a concrete language package shows that the manual downcast (D4) is a measurable friction point. The existing lambda example's hand-written views already provide typed returns — the loomgen-generated views are catching up to the hand-written convention, not replacing it.
