# Markdown event attribution evidence (#872)

**Status:** Complete point-in-time investigation for issue
[#872](https://github.com/dowdiness/loom/issues/872). Code and current benchmarks
remain authoritative.

This document preserves the investigation results; it does not define ongoing
policy. See
[markdown-full-parse-contract.md](markdown-full-parse-contract.md) for the active
performance contract.

The PR originally recorded this bounded Markdown residual grammar and event
attribution investigation in a comment-only MoonBit file. This Markdown record
keeps the exact measurements without retaining temporary parser APIs or
production instrumentation.

## Environment

| Key | Value |
|---|---|
| Base commit | `a3161f25` |
| Stage benchmark commit | `6e0a9312` |
| Deterministic category commit | `8ea482e3` |
| Nested read-phase commit | `60c85470` |
| Payload lower-bound commit | `1db3453b` |
| moon | `0.1.20260713` |
| moonc | `v0.10.4+2cc641edf` |
| Node | `v24.14.1` |

Every wall-time row is 10 samples. Mean ± sample standard deviation is shown.
Raw outputs were captured under `/tmp/loom-872-*.txt` during the investigation.

## Commands

```bash
# Stage isolation benchmarks
moon bench --release --target wasm-gc -p dowdiness/markdown \
  -f event_attribution_benchmark_wbtest.mbt
moon bench --release --target js -p dowdiness/markdown \
  -f event_attribution_benchmark_wbtest.mbt

# Inline analysis and delimiter controls
moon bench --release --target {wasm-gc,js} -p dowdiness/markdown \
  -f inline_analysis_performance_wbtest.mbt
moon bench --release --target {wasm-gc,js} -p dowdiness/markdown \
  -f delimiter_performance_wbtest.mbt

# Retained-memory GC probe
NODE_OPTIONS=--expose-gc moon test --target js -p dowdiness/markdown \
  -f 'retained-memory*'
```

## Stage Isolation

> **Rule:** Event generation and warm green construction are independent
> measurements. They **must not be added** to estimate end-to-end latency. The
> production CST and diagnostics were the oracle for every split row.

### Representative Scale 64 — Pretokenized / Events / Warm Green

**wasm-gc:**

| Corpus | Pretokenized | Events | Warm Green |
|---|---:|---:|---:|
| paragraph | 667.14±16.01 µs | 690.27±7.74 µs | 28.84±0.41 µs |
| mixed | 2.27±0.08 ms | 2.29±0.02 ms | 0.099±0.001 ms |
| delimiter-heavy | 3.86±0.05 ms | 4.02±0.05 ms | 0.158±0.003 ms |
| recovery-heavy | 1.44±0.02 ms | 1.59±0.07 ms | 0.054±0.001 ms |
| HTML | 43.17±0.89 µs | 34.03±0.30 µs | 14.09±0.16 µs |
| fenced code | 51.28±0.47 µs | 38.54±0.77 µs | 20.27±0.21 µs |
| nested container | 757.42±20.73 µs | 716.39±9.97 µs | 33.19±0.49 µs |

**JavaScript:**

| Corpus | Pretokenized | Events | Warm Green |
|---|---:|---:|---:|
| paragraph | 828.56±30.83 µs | 895.76±31.12 µs | 54.21±10.80 µs |
| mixed | 3.51±0.19 ms | 3.12±0.04 ms | 0.141±0.001 ms |
| delimiter-heavy | 5.50±0.07 ms | 5.48±0.11 ms | 0.217±0.002 ms |
| recovery-heavy | 2.17±0.02 ms | 2.07±0.01 ms | 0.079±0.001 ms |
| HTML | 75.99±0.69 µs | 55.95±0.61 µs | 22.33±0.20 µs |
| fenced code | 87.33±0.77 µs | 63.08±2.45 µs | 28.95±0.60 µs |
| nested container | 2.39±0.07 ms | 2.23±0.04 ms | 0.055±0.003 ms |

### Stress Scale 256 — Events / Warm Green

| Corpus | Events (wasm-gc) | Warm Green (wasm-gc) | Events (JS) | Warm Green (JS) |
|---|---:|---:|---:|---:|
| paragraph | 2.97±0.05 ms | 0.127±0.003 ms | 4.10±0.08 ms | 0.191±0.002 ms |
| mixed | 11.01±0.44 ms | 0.461±0.012 ms | 14.18±0.46 ms | 0.605±0.014 ms |
| delimiter-heavy | 20.98±0.45 ms | 0.836±0.038 ms | 25.91±1.24 ms | 0.973±0.021 ms |
| recovery-heavy | 7.29±0.44 ms | 0.261±0.006 ms | 8.76±0.29 ms | 0.341±0.008 ms |
| HTML | 145.95±1.71 µs | 61.80±0.71 µs | 224.00±5.99 µs | 99.32±3.65 µs |
| fenced code | 157.45±1.37 µs | 89.40±1.22 µs | 261.88±12.42 µs | 120.53±2.26 µs |
| nested container | 10.89±0.20 ms | 0.160±0.005 ms | 32.24±0.40 ms | 0.229±0.002 ms |

**Stack-overflow caveat.** A later isolated production parse reproduced stack
overflow for the nested depth-8, 256-line corpus on both wasm-gc and JavaScript.
The successful JS 32.24 ms benchmark row is therefore **not a reliability
guarantee**.

Issue [#875](https://github.com/dowdiness/loom/issues/875) owns the correctness
boundary and bounded-stack fix. Issue
[#883](https://github.com/dowdiness/loom/issues/883) owns the bounded
delimiter-plan cost-reduction prototype.

## Deterministic Work, Scale 64

Format: source units; tokens; token/start/end reads; max reads at one token
index; retained parse events; payload copies/units.

| Corpus | Source (units) | Tokens | Token reads | Start reads | End reads | Max reads | Retained events | Payload copies | Payload units |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| paragraph | 6,537 | 837 | 27,113 | 8,073 | 8,008 | 41 | 1,222 | 321 | 6,021 |
| mixed | 10,240 | 2,753 | 81,986 | 22,400 | 22,016 | 76 | 4,032 | 1,024 | 7,872 |
| delimiter-heavy | 8,320 | 4,673 | 152,864 | 51,455 | 51,454 | 41 | 6,658 | 1,791 | 5,439 |
| recovery-heavy | 3,392 | 1,025 | 32,578 | 8,320 | 8,256 | 46 | 1,408 | 448 | 2,816 |
| HTML | 3,328 | 449 | 2,882 | 576 | 512 | 11 | 576 | 192 | 3,072 |
| fenced code | 2,560 | 577 | 3,522 | 640 | 576 | 10 | 704 | 256 | 1,856 |
| nested container | 1,718 | 641 | 13,166 | 2,623 | 2,110 | 1,364 | 1,666 | 64 | 630 |

### Block Format

Dispatch / root-paragraph / quote-paragraph / list-paragraph / setext:

| Corpus | Dispatch | Root ¶ | Quote ¶ | List ¶ | Setext |
|---|---:|---:|---:|---:|---:|
| paragraph | 130 | 128 | 0 | 0 | 128 |
| mixed | 448 | 256 | 0 | 256 | 512 |
| delimiter-heavy | 1 | 2 | 0 | 0 | 2 |
| recovery-heavy | 128 | 256 | 0 | 0 | 256 |
| HTML | 128 | 0 | 0 | 0 | 0 |
| fenced code | 64 | 0 | 0 | 0 | 0 |
| nested container | 1 | 0 | 128 | 0 | 128 |

### Inline Format

Containers / analysis tokens / code openers / code successors / link candidates
/ delimiter runs / opener checks / plan events:

| Corpus | Containers | Analysis tokens | Code openers | Code successors | Link candidates | Delimiter runs | Opener checks | Plan events |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| paragraph | 129 | 1,409 | 0 | 0 | 0 | 512 | 256 | 512 |
| mixed | 448 | 3,392 | 256 | 128 | 128 | 512 | 256 | 512 |
| delimiter-heavy | 2 | 9,342 | 256 | 254 | 128 | 3,200 | 2,112 | 3,840 |
| recovery-heavy | 128 | 1,792 | 0 | 0 | 0 | 0 | 0 | 0 |
| nested container | 128 | 128 | 0 | 0 | 0 | 0 | 0 | 0 |

### Nested Container Read Depth

The nested max read is at EOF token index 640: 1,355 ordinary reads. Lookahead
phase peaks were only 12 paragraph and 18 inline reads at one index. Getter
access is O(1); the generic `ParserContext` cache remains rejected because the
prior controlled prototype slowed wasm-gc by about 20% and JS by about 65%.

## Category Microbenchmarks

### Block and Container Decisions

4,096 pure block/container decisions:

| Target | Time |
|---|---:|
| wasm-gc | 38.34±0.36 µs |
| JavaScript | 51.89±2.74 µs |

The pure core is negligible.

4,096 root paragraph continuation observations:

| Target | Time |
|---|---:|
| wasm-gc | 748.40±168.37 µs |
| JavaScript | 458.85±13.10 µs |

At observed corpus call counts, this is not a primary bottleneck.

### Inline Analysis at 2,048 Motifs

| Operation | wasm-gc | JavaScript |
|---|---:|---:|
| code-span index | 0.503±0.006 ms | 0.729±0.045 ms |
| link index | 2.81±0.07 ms | 3.95±0.05 ms |
| delimiter plan | 6.15±0.22 ms | 6.23±0.24 ms |
| complete pipeline | 10.24±0.31 ms | 11.29±0.57 ms |

### Matched-Length Full-Parse Delimiter Controls

| Scale | Corpus | wasm-gc heavy | wasm-gc plain | JS heavy | JS plain |
|---|---|---:|---:|---:|---:|
| 64 motifs | delimiter | 4.48±0.10 ms | 0.307±0.016 ms | 6.36±0.37 ms | 0.281±0.004 ms |
| 256 motifs | delimiter | 26.16±1.05 ms | 1.15±0.02 ms | 34.21±4.71 ms | 1.06±0.08 ms |

Resolver operation counts remain linear; the measured cost ranks delimiter
planning first and link indexing second, but the evidence is adversarial and
does not yet justify a production optimization without representative-corpus
control measurements for a concrete candidate.

## Payload Materialization

Handwritten lexer payload/source ratios at scale 64:

| Corpus | Ratio |
|---|---:|
| paragraph | 92% |
| mixed | 77% |
| HTML | 92% |
| fenced code | 73% |

Backtick tokens carry no handwritten payload; fenced info strings copied by
generated payload lexer code remain a negative control for handwritten copy
elimination.

### Copy-Elision Lower Bound at 500 Groups

Copied → elided:

| Corpus | wasm-gc copied | wasm-gc elided | JS copied | JS elided |
|---|---:|---:|---:|---:|
| paragraph | 1.58 ms | 1.42 ms | 1.63 ms | 1.52 ms |
| mixed | 3.82 ms | 3.57 ms | 5.98 ms | 5.90 ms |
| fenced control | 0.522 ms | 0.490 ms | 1.00 ms | 1.00 ms |
| HTML | 0.676 ms | 0.604 ms | 1.06 ms | 1.04 ms |

JS benefits outside paragraph are noise-sized. A 1,000-distinct-edit explicit
GC probe stayed under the 32 MiB leak bound and previously observed roughly
522 KiB final heap growth, but it does not define public snapshot ownership.

## Decisions

| Action | Target | Rationale |
|---|---|---|
| **ADOPT/TRACK** | [#875](https://github.com/dowdiness/loom/issues/875) bounded recursion across repeated nested blockquote lines | Correctness boundary for nested-container stack overflow |
| **PROTOTYPE FURTHER** | Delimiter plan and link index | Only after a concrete change wins on mixed/README controls on both deployment targets |
| **DEFER** | Text/HtmlText span-backed payloads | Until ownership, incremental equality, and retained-source semantics are explicit and both targets win |
| **REJECT** | Generic `ParserContext` getter cache | Prior controlled prototype slowed wasm-gc ~20% and JS ~65% |
| **REJECT** | Generic Loom core changes | Out of scope for Markdown-attributed optimization |
| **REJECT** | Second event tape | No evidence of benefit |
| **REJECT** | EventBuffer/green arena redesign | No evidence of benefit |
| **REJECT** | Pure block-decision optimization | Measured at negligible cost |
| **REJECT** | Whole-document LineFacts | No evidence of benefit |
| **REJECT** | TokenBuffer update optimization | No evidence of benefit |

## Related Issues

- **#872** — Markdown residual grammar/event attribution investigation (this document)
- **#875** — Bounded recursion across repeated nested blockquote lines (correctness boundary)
- **#883** — Bounded delimiter-plan cost-reduction prototype

Decision record:

- No ADR needed: this file records a bounded performance investigation and does
  not change architecture or public contracts.
