# PROTOTYPE — cmark-informed inline event index

## Question

Can Loom's Markdown inline analysis bank omit ordinary text payloads and retain only syntax-bearing source ranges without losing the delimiter facts currently computed from each token?

## Run

From `examples/markdown`:

```sh
moon bench --release --target native inline_event_index_prototype_wbtest.mbt
moon bench --release --target wasm inline_event_index_prototype_wbtest.mbt
moon bench --release --target js inline_event_index_prototype_wbtest.mbt
```

The benchmark tokenizes before the timed body. It therefore measures the analysis-bank stage, not lexing or full parsing.

## Prototype

`inline_event_index_prototype_wbtest.mbt` compares:

- **current-like bank**: an owned `String` and first/last/backslash facts for every lexer token;
- **sparse bank**: only delimiter, bracket, parenthesis, backtick, and line-boundary events with source ranges;
- **sparse analysis**: source-derived neighboring-character facts using `StringView` when an event is inspected;
- **sparse code-span index**: a test-only equivalent of `build_code_span_delimiter_index` that scans omitted text as source gaps;
- **guarded sparse link index**: a source-range implementation for complete, balanced, single-line inline-target links, with explicit fallback for references, separated destinations, literal recovery, and code/link conflicts;
- **sparse delimiter plan**: the existing resolver reused unchanged, with only source-order delimiter event collection replaced;
- **parser-shell integration**: `parse_indexed_inline_container_with_continue_line` now selects the sparse source-range path and falls back to the full-token oracle for unsupported link forms;
- **source-view boundary**: `ParserContext::source_view(start~, end~)` exposes a bounded zero-copy view without exposing parser state.

Differential smoke tests cover ASCII, Unicode, escaped markers, LF, CRLF, and CR. They passed on all three targets.

## Measurements

Mean time per benchmark iteration:

| Target | Workload | Current-like bank | Sparse bank | Current-like analysis | Sparse analysis |
|---|---|---:|---:|---:|---:|
| Native | plain 250 lines | 56.9 µs | 6.4 µs | — | — |
| Native | delimiter-heavy 250 lines | 491 µs | 133 µs | 496 µs | 160 µs |
| Wasm | plain 250 lines | 133 µs | 20.7 µs | — | — |
| Wasm | delimiter-heavy 250 lines | 1.34 ms | 318 µs | 1.32 ms | 401 µs |
| JS | plain 250 lines | 82.8 µs | 6.7 µs | — | — |
| JS | delimiter-heavy 250 lines | 397 µs | 209 µs | 424 µs | 265 µs |

The code-span index phase was also measured on the delimiter-heavy 250-line source:

| Target | Existing index only | Sparse index only | Existing bank + index | Sparse bank + index |
|---|---:|---:|---:|---:|
| Native | 66.2 µs | 96.6 µs | 560 µs | 233 µs |
| Wasm | 160 µs | 380 µs | 1.57 ms | 532 µs |
| JS | 72.7 µs | 127 µs | 520 µs | 355 µs |

The sparse code-span index itself is slower because it must inspect source gaps. The combined bank-plus-index path remains faster because it avoids constructing owned text for ordinary tokens.

The guarded link-index phase was also measured on the delimiter-heavy 250-line source:

| Target | Existing link index only | Sparse link index only | Existing bank + link index | Sparse bank + link index |
|---|---:|---:|---:|---:|
| Native | 396 µs | 115 µs | 1.02 ms | 361 µs |
| Wasm | 814 µs | 248 µs | 2.33 ms | 793 µs |
| JS | 517 µs | 158 µs | 1.08 ms | 524 µs |

The guarded sparse link path matched all candidates in the supported fixtures. Unsupported reference/separated forms returned fallback instead of guessing.

The delimiter-plan phase was measured on the same delimiter-heavy 250-line source:

| Target | Existing plan only | Sparse plan only | Existing full pipeline | Sparse full pipeline |
|---|---:|---:|---:|---:|
| Native | 964 µs | 633 µs | 2.36 ms | 1.05 ms |
| Wasm | 2.21 ms | 1.79 ms | 5.31 ms | 2.69 ms |
| JS | 924 µs | 621 µs | 2.31 ms | 1.26 ms |

The resolver implementation itself was not changed; the improvement comes from avoiding owned ordinary-token text while collecting delimiter facts.

The integrated parser shell was measured against the full-token oracle on a single paragraph spanning 250 inline-heavy lines. Tokenization and CST construction are included:

| Target | Full-token shell | Sparse shell |
|---|---:|---:|
| Native | 5.63 ms | 4.07 ms |
| Wasm | 15.02 ms | 12.22 ms |
| JS | 5.57 ms | 4.33 ms |

The sparse shell produced byte-for-byte-equivalent CST structure and diagnostics in the guarded fixtures. Unsupported link forms exercised the full-token fallback.

A real dev-host browser seam probe used 250 Markdown blocks and 20 Raw `fill` edits. Two paired runs against the pre-sparse Loom commit did not show a reliable end-to-end improvement: `input_to_render_ms` was 129.1/174.3 ms (p50/p95) for sparse versus 130.8/171.6 ms for the baseline in one run, and 137.8/220.5 ms versus 131.4/174.0 ms in the second. The editor commit phase was also slower in the second run (86.1/168.1 ms versus 80.2/122.4 ms). These measurements are evidence against production adoption at this point, not evidence of a browser win.

## Verdict

**Promising, but not production evidence.** The sparse representation is materially cheaper in this isolated stage, including the cost of recovering delimiter facts from source views. The strongest result is the Wasm delimiter-heavy case, where the bank prototype is about 4x faster.

The guarded path is currently wired into the real Markdown inline parser as an experiment and is exercised by the full Markdown test suite. It supports source-range code/emphasis analysis and guarded simple inline-target links; unsupported link syntax falls back to the full-token path. Sparse-only invariant failures are also classified as fallback, and supported link candidates are checked with a linear source-order frontier.

This is not a production-adoption decision. The first real browser seam measurements show no reliable end-to-end improvement, so this path must not be upstreamed as a default optimization. Any future reconsideration still requires broader full-token-vs-sparse differential tests over CommonMark recovery and incremental edits, plus an ADR. The intentional public `ParserContext::source_view` addition is reflected in `loom/core/pkg.generated.mbti`. Full-rebuild fallback and lossless CST behavior remain mandatory.

The branch is `perf/cmark-inline-events` and the worktree is `/tmp/loom-cmark-inline-events`.
