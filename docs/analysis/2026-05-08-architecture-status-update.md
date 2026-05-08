# Architecture Status Update — 2026-05-08

**Status:** Point-in-time delta. Builds on [2026-04-19 architecture diagnosis](2026-04-19-architecture-diagnosis.md); does not replace it. The 2026-04-19 doc is the baseline; this file records what shipped, what changed, and one factual correction.

**Headline:** No new architectural pressure has emerged. The 2026-04-19 plan still applies, with one stage revised: **`egraph/` is a peer library, not a research module.** It must not be relocated to `experiments/`.

---

## What changed since 2026-04-19

### Shipped

| Item | Mechanism | Verified |
|------|-----------|----------|
| Stage A graphviz swap | PR #98 (commit `a1316e2`) — `antisatori/graphviz` path-dep → published `dowdiness/graphviz@0.1.0` | `loom/graphviz/` directory absent in tree |
| `check-docs.sh` doctest-regression guard | Commit `fa21a16` — warns on missing `README.mbt.md` pairing | — |
| ROADMAP #60 deferred-in-place | Commit `050cf7b` — naming-collision rationale recorded | — |

### Resolved by measurement (2026-04-19, restated for the record)

- **#58 Folder / TransformFolder traits already exist** in `seam/cst_traits.mbt:16,30`.
- **#59 MutVisitor — no measured justification.** `build_tree`-with-`ReuseNode` clocks 34.72 µs over a 50×100-token tree; `CstNode::new` is not on a hot path. ROADMAP #59's own caveat resolves negative.
- **Closures-vs-traits perf framing in `cst_traverse.mbt:37-39` is wrong** for benchmarked workloads — closures match or beat traits. The narrow "captured upvars" claim remains untested; do not justify speculative trait work with it.

### Correction to the 2026-04-19 diagnosis

**`egraph/` was mis-categorized as research-phase.** The 2026-04-19 doc proposed moving it under `experiments/` based on (a) the lambda dep being test-only and (b) "research-phase" framing in its TODO list.

That call missed two facts:

1. **`canopy/moon.mod.json` declares `dowdiness/egraph` as a path-dep** at `./loom/egraph` — the parent project commits to maintaining the package at that path. Relocation breaks the parent.
2. **`loom/egraph/examples/lambda-opt/`** is a working lambda-calculus optimizer (5 source files: `convert.mbt`, `analysis.mbt`, `lang.mbt`, `rules.mbt`, `optimize.mbt`) using equality saturation. This is production-shaped code, not a sandbox.

**Revised verdict:** treat `egraph/` like `egglog/` — peer library, top-level, with a documented contract. The earlier framing of "test-only lambda import = research module" was wrong; a path-dep from `canopy/moon.mod.json` is a stronger signal of production status than the absence of internal `@lambda` imports.

This supersedes §3 P2 and §6 Stage C lines about `egraph` in the 2026-04-19 doc. Mark those superseded; do not edit the original (immutable point-in-time convention).

---

## Current pending work (revised)

Replace the 2026-04-19 §6 Stage C plan with this:

| # | Action | Cost | Risk |
|---|--------|------|------|
| 1 | Delete `cst-transform/` per ROADMAP #62 + 3 follow-ups (`.claude/settings.json` test hook; comment refs in `seam/cst_traverse.mbt:3` and `cst_traits.mbt:7`; `alga/EXPERIMENT_REPORT.md:10`) | 1 PR | Low — zero canopy consumers (verified 2026-04-19) |
| 2 | Add `egraph/README.md` section documenting peer-library status + canopy path-dep contract (mirror `egglog`'s pattern) | docs only | Trivial |
| 3 | Add `egglog/README.md` section documenting `@incr` contract surface (`FunctionalRelation`, `Runtime`, `rt.fixpoint()`, `delta_scan()`) | docs only | Trivial |
| 4 | Delete `loom/src/loom.mbt` facade (~253 callsites in examples) | 2–3 days | Medium — wait for contiguous window |

`experiments/` directory is **not** created by this plan. No module currently warrants the label.

Stage B (#60 `CstNode::each` extraction) remains deferred per ROADMAP. Stage D (zero-copy lexing, typed-view codegen) unchanged.

---

## Recommended first bite

**Item 1: delete `cst-transform/`.** Highest payoff per hour, lowest risk, unblocks closing ROADMAP #62. Items 2 and 3 (peer-library README sections) can ride in adjacent PRs.

Item 4 (facade deletion) is the largest remaining mechanical migration; sequence it when 2–3 days are available. Defer until then.

---

## Scope

Same as 2026-04-19 §10, with one addition to the *excluded* list:

- **Relocating `egraph/`.** Confirmed peer library; relocation breaks `canopy/moon.mod.json`.

All other inclusions/exclusions stand.
