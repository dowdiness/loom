# `dowdiness/cst-transform`

Research sandbox for CST traversal primitives.

**Status:** not a stable framework module. The production traits
(`Folder`, `TransformFolder`, `Finder`) have already been ported into
[`seam/cst_traverse.mbt`](../seam/) — new consumers should use `seam`,
not this package. This package retains two experimental traversal shapes
(`transform_cps`, `transform_view`) that [ROADMAP](../ROADMAP.md) item
#62 flags for deletion.

## What's in here

- `GreenNode` — standalone toy tree for benchmarking traversal styles
  without a dependency on `seam`.
- `Folder`, `TransformFolder`, `Finder`, `MutVisitor`, `Walker` traits —
  the full matrix of static-dispatch traversal shapes.
- `transform`, `fold`, `transform_fold`, `map`, `each`, `iter`,
  `find` — closure-based methods on `GreenNode`.
- `transform_cps`, `transform_view` — experimental shapes pending
  deletion (ROADMAP #62).
- `NodeCount`, `IdentFinder`, `CstMeta`, `MutMeta` — benchmarking
  newtypes demonstrating the single-element-tuple-struct unboxing
  pattern.

Full signatures: [`src/pkg.generated.mbti`](src/pkg.generated.mbti).

## Why this exists

The package isolates traversal-shape experiments from production so
benchmarks can compare trait / closure / CPS / view variants without
pulling in the full CST pipeline. Findings are captured in
[`REPORT.md`](REPORT.md) — the relevant sections are:

- Single-element tuple-struct newtypes (`NodeCount(Int)`) compile to
  hand-written performance; multi-field structs do not.
- Allocation dominates dispatch: heap allocation per node is 3–4× more
  expensive than indirect calls.
- Mutable visitors win for multi-property metadata in a single pass.

The production traversal surface in `seam/cst_traverse.mbt` was derived
from these findings.

## Relation to `seam`

| Shape | Here (research) | In `seam` (production) |
|-------|-----------------|------------------------|
| `Folder` trait | ✅ | ✅ ported 2026-03-30 |
| `TransformFolder` trait | ✅ | ✅ |
| `Finder` trait | ✅ | ✅ |
| `MutVisitor` / `Walker` | ✅ | MutVisitor deferred — see ROADMAP #59 |
| `transform_cps`, `transform_view` | ✅ | Deliberately not ported (ROADMAP #62) |

If you need a traversal primitive on a real CST, reach for
[`seam/cst_traverse.mbt`](../seam/). This package is only useful for
reproducing the benchmarks in `REPORT.md` or prototyping new traversal
shapes.

## Running

```bash
cd cst-transform
moon check && moon test
moon bench --release   # reproduces REPORT.md numbers
```
