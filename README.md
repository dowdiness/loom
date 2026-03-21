# Loom

A generic incremental parser framework for MoonBit.

## Modules

| Module | Path | Purpose |
|--------|------|---------|
| [`dowdiness/loom`](loom/) | `loom/` | Parser framework: incremental parsing, CST building, grammar composition |
| [`dowdiness/seam`](seam/) | `seam/` | Language-agnostic CST infrastructure |
| [`dowdiness/incr`](incr/) | `incr/` | Salsa-inspired incremental recomputation |
| [`dowdiness/egraph`](egraph/) | `egraph/` | Equality graph (e-graph) for equality saturation |
| [`dowdiness/egglog`](egglog/) | `egglog/` | Relational e-graph engine (Datalog + equality saturation) |

## Examples

| Example | Path | Purpose |
|---------|------|---------|
| [Lambda Calculus](examples/lambda/) | `examples/lambda/` | Full parser for λ-calculus with arithmetic |

## Quick Start

```bash
git clone https://github.com/dowdiness/loom.git
cd loom

(cd loom && moon test)                        # 76 tests
(cd examples/lambda && moon test)             # 293 tests
(cd examples/lambda && moon bench --release)  # benchmarks
```

## Documentation

- [docs/README.md](docs/README.md) — full navigation index
- [ROADMAP.md](ROADMAP.md) — phase status and future work
- [docs/development/managing-modules.md](docs/development/managing-modules.md) — multi-module workflow
