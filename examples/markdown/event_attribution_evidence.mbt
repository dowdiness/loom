// #872 Markdown residual grammar/event attribution evidence.
//
// This comment-only source file preserves the investigation result without
// retaining temporary parser APIs or production instrumentation. Exact probe
// implementations remain reproducible from the named commits in this branch.
//
// Environment
// -----------
// Base: a3161f25
// Stage benchmark commit: 6e0a9312
// Deterministic category commit: 8ea482e3
// Nested read-phase commit: 60c85470
// Payload lower-bound commit: 1db3453b
// moon 0.1.20260713; moonc v0.10.4+2cc641edf; Node v24.14.1.
// Every wall-time row is 10 samples. Mean ± sample standard deviation is shown.
// Raw outputs were captured under /tmp/loom-872-*.txt during the investigation.
//
// Commands
// --------
// moon bench --release --target wasm-gc -p dowdiness/markdown \
//   -f event_attribution_benchmark_wbtest.mbt
// moon bench --release --target js -p dowdiness/markdown \
//   -f event_attribution_benchmark_wbtest.mbt
// moon bench --release --target {wasm-gc,js} -p dowdiness/markdown \
//   -f inline_analysis_performance_wbtest.mbt
// moon bench --release --target {wasm-gc,js} -p dowdiness/markdown \
//   -f delimiter_performance_wbtest.mbt
// NODE_OPTIONS=--expose-gc moon test --target js -p dowdiness/markdown \
//   -f 'retained-memory*'
//
// Stage isolation
// ---------------
// Event generation and warm green construction are independent measurements.
// They must not be added to estimate end-to-end latency. The production CST and
// diagnostics were the oracle for every split row.
//
// Representative scale 64, pretokenized / events / warm green:
// corpus             wasm-gc                         JavaScript
// paragraph          667.14±16.01 / 690.27±7.74 / 28.84±0.41 us
// mixed              2.27±0.08 / 2.29±0.02 / 0.099±0.001 ms
// delimiter-heavy    3.86±0.05 / 4.02±0.05 / 0.158±0.003 ms
// recovery-heavy     1.44±0.02 / 1.59±0.07 / 0.054±0.001 ms
// HTML               43.17±0.89 / 34.03±0.30 / 14.09±0.16 us
// fenced code        51.28±0.47 / 38.54±0.77 / 20.27±0.21 us
// nested container   757.42±20.73 / 716.39±9.97 / 33.19±0.49 us
//
// paragraph          828.56±30.83 / 895.76±31.12 / 54.21±10.80 us
// mixed              3.51±0.19 / 3.12±0.04 / 0.141±0.001 ms
// delimiter-heavy    5.50±0.07 / 5.48±0.11 / 0.217±0.002 ms
// recovery-heavy     2.17±0.02 / 2.07±0.01 / 0.079±0.001 ms
// HTML               75.99±0.69 / 55.95±0.61 / 22.33±0.20 us
// fenced code        87.33±0.77 / 63.08±2.45 / 28.95±0.60 us
// nested container   2.39±0.07 / 2.23±0.04 / 0.055±0.003 ms
//
// Stress scale 256, events / warm green:
// corpus             wasm-gc                    JavaScript
// paragraph          2.97±0.05 / 0.127±0.003 ms  4.10±0.08 / 0.191±0.002 ms
// mixed              11.01±0.44 / 0.461±0.012 ms 14.18±0.46 / 0.605±0.014 ms
// delimiter-heavy    20.98±0.45 / 0.836±0.038 ms 25.91±1.24 / 0.973±0.021 ms
// recovery-heavy     7.29±0.44 / 0.261±0.006 ms  8.76±0.29 / 0.341±0.008 ms
// HTML               145.95±1.71 / 61.80±0.71 us 224.00±5.99 / 99.32±3.65 us
// fenced code        157.45±1.37 / 89.40±1.22 us 261.88±12.42 / 120.53±2.26 us
// nested container   10.89±0.20 / 0.160±0.005 ms 32.24±0.40 / 0.229±0.002 ms
//
// A later isolated production parse reproduced stack overflow for the nested
// depth-8, 256-line corpus on both wasm-gc and JavaScript. The successful JS
// 32.24 ms benchmark row is therefore not a reliability guarantee. Issue #875
// owns the correctness boundary and bounded-stack fix.
//
// Deterministic work, scale 64
// ----------------------------
// Format:
// source units; tokens; token/start/end reads; max reads at one token index;
// retained parse events; payload copies/units.
// paragraph: 6537; 837; 27113/8073/8008; 41; 1222; 321/6021
// mixed: 10240; 2753; 81986/22400/22016; 76; 4032; 1024/7872
// delimiter: 8320; 4673; 152864/51455/51454; 41; 6658; 1791/5439
// recovery: 3392; 1025; 32578/8320/8256; 46; 1408; 448/2816
// HTML: 3328; 449; 2882/576/512; 11; 576; 192/3072
// fenced: 2560; 577; 3522/640/576; 10; 704; 256/1856
// nested: 1718; 641; 13166/2623/2110; 1364; 1666; 64/630
//
// Block format is dispatch/root-paragraph/quote-paragraph/list-paragraph/setext:
// paragraph 130/128/0/0/128; mixed 448/256/0/256/512;
// delimiter 1/2/0/0/2; recovery 128/256/0/0/256;
// HTML 128/0/0/0/0; fenced 64/0/0/0/0; nested 1/0/128/0/128.
//
// Inline format is containers/analysis tokens/code openers/code successors/
// link candidates/delimiter runs/opener checks/plan events:
// paragraph 129/1409/0/0/0/512/256/512
// mixed 448/3392/256/128/128/512/256/512
// delimiter 2/9342/256/254/128/3200/2112/3840
// recovery 128/1792/0/0/0/0/0/0
// nested 128/128/0/0/0/0/0/0.
//
// The nested max read is EOF token index 640: 1,355 ordinary reads. Lookahead
// phase peaks were only 12 paragraph and 18 inline reads at one index. Getter
// access is O(1); the generic ParserContext cache remains rejected because the
// prior controlled prototype slowed wasm-gc by about 20% and JS by about 65%.
//
// Category microbenchmarks
// ------------------------
// 4,096 pure block/container decisions:
// wasm-gc 38.34±0.36 us; JS 51.89±2.74 us. The pure core is negligible.
// 4,096 root paragraph continuation observations:
// wasm-gc 748.40±168.37 us; JS 458.85±13.10 us. At observed corpus call counts,
// this is not a primary bottleneck.
//
// Inline analysis at 2,048 motifs:
//                         wasm-gc           JavaScript
// code-span index         0.503±0.006 ms    0.729±0.045 ms
// link index              2.81±0.07 ms      3.95±0.05 ms
// delimiter plan          6.15±0.22 ms      6.23±0.24 ms
// complete pipeline       10.24±0.31 ms     11.29±0.57 ms
//
// Matched-length full-parse delimiter controls:
// 64 motifs: wasm 4.48±0.10 ms heavy vs 0.307±0.016 ms plain;
//            JS 6.36±0.37 ms heavy vs 0.281±0.004 ms plain.
// 256 motifs: wasm 26.16±1.05 ms heavy vs 1.15±0.02 ms plain;
//             JS 34.21±4.71 ms heavy vs 1.06±0.08 ms plain.
// Resolver operation counts remain linear; the measured cost ranks delimiter
// planning first and link indexing second, but the evidence is adversarial and
// does not yet justify a production optimization without representative-corpus
// control measurements for a concrete candidate.
//
// Payload materialization
// -----------------------
// Handwritten lexer payload/source ratios at scale 64 were paragraph 92%, mixed
// 77%, HTML 92%, and fenced code 73%. Backtick tokens carry no handwritten
// payload; fenced info strings copied by generated payload lexer code remain a
// negative control for handwritten copy elimination.
//
// Copy-elision lower-bound at 500 groups, copied -> elided:
//                         wasm-gc           JavaScript
// paragraph               1.58 -> 1.42 ms   1.63 -> 1.52 ms
// mixed                   3.82 -> 3.57 ms   5.98 -> 5.90 ms
// fenced control          0.522 -> 0.490 ms 1.00 -> 1.00 ms
// HTML                    0.676 -> 0.604 ms 1.06 -> 1.04 ms
// JS benefits outside paragraph are noise-sized. A 1,000-distinct-edit explicit
// GC probe stayed under the 32 MiB leak bound and previously observed roughly
// 522 KiB final heap growth, but it does not define public snapshot ownership.
//
// Decisions
// ---------
// ADOPT/TRACK: #875, bounded recursion across repeated nested blockquote lines.
// PROTOTYPE FURTHER: delimiter plan and link index, only after a concrete change
// wins on mixed/README controls on both deployment targets.
// DEFER: Text/HtmlText span-backed payloads until ownership, incremental
// equality, and retained-source semantics are explicit and both targets win.
// REJECT: generic ParserContext getter cache; generic Loom core changes; a second
// event tape; EventBuffer/green arena redesign; pure block-decision optimization;
// whole-document LineFacts; TokenBuffer update optimization.
//
// No ADR needed: this file records a bounded performance investigation and does
// not change architecture or public contracts.
