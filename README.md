# Loom

A generic incremental parser framework for MoonBit — edit-aware lexing,
a lossless green tree (CST), subtree reuse, error recovery, and a
reactive pipeline. Any grammar plugs in via a single
`Grammar[T, K, Ast]` value.

**New here?** Start with the [`dowdiness/loom` package README](loom/)
for the API and a Quick Start, then browse the [docs index](docs/README.md).

## Modules

Core framework (stable):

| Module | Path | Purpose |
|--------|------|---------|
| [`dowdiness/loom`](loom/) | `loom/` | Parser framework: incremental parsing, CST building, grammar composition |
| [`dowdiness/seam`](seam/) | `seam/` | Language-agnostic CST infrastructure (`CstNode` / `SyntaxNode`) |
| [`dowdiness/incr`](incr/) | `incr/` | Salsa-inspired reactive inputs / derived cells |

Sibling modules (see each module's README for scope and status):

| Module | Path | Purpose |
|--------|------|---------|
| [`dowdiness/pretty`](pretty/) | `pretty/` | Wadler-Lindig pretty-printer (generic `Layout[A]`, annotations) — used by `examples/json` |
| [`dowdiness/egraph`](egraph/) | `egraph/` | Equality graph for equality saturation |
| [`dowdiness/egglog`](egglog/) | `egglog/` | Relational e-graph engine (Datalog + equality saturation) |
| [`dowdiness/text_change`](text-change/) | `text-change/` | Pure contiguous text-change utilities (migrated from canopy 2026-05, #147) |
| [`dowdiness/moji`](moji/) | `moji/` | UAX #29 grapheme cluster + word boundary segmentation, UTF-16 indexed (migrated from canopy 2026-05, #147) |

## Examples

| Example | Path | Purpose |
|---------|------|---------|
| [Lambda Calculus](examples/lambda/) | `examples/lambda/` | Reference grammar — typed `SyntaxNode` views, error recovery, CRDT exploration |
| [JSON](examples/json/) | `examples/json/` | Step-based `prefix_lexer` + `block_reparse_spec` — exercises every `Grammar::new` option |
| [Markdown](examples/markdown/) | `examples/markdown/` | Mode-aware lexing via `ModeLexer` — line-start / inline / fenced code contexts |
| [MoonBit](examples/moonbit/) | `examples/moonbit/` | Skeleton official MoonBit lexer adapter + coarse Loom CST grammar |
| [Graph DSL](examples/graph-dsl/) | `examples/graph-dsl/` | Source-map/token-role graph authoring example with graph-operation lowering |

## Quick Start

Monorepo — every module is an independent MoonBit package, so run
`moon` from the module directory:

```bash
git clone https://github.com/dowdiness/loom.git
cd loom
(cd loom && moon test)                    # framework
(cd examples/lambda && moon test)         # lambda example
(cd examples/lambda && moon bench --release)
```

Multi-module development workflow: [docs/development/managing-modules.md](docs/development/managing-modules.md).

## Documentation

- [docs/README.md](docs/README.md) — navigation index (start here, architecture, API, archive)
- [ROADMAP.md](ROADMAP.md) — phase status and future work
- [CHANGELOG.md](CHANGELOG.md) — user-facing changes
