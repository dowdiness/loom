# Keyed query retention and semantic history

**Date:** 2026-09-12  
**Status:** Research recommendation; no keyed-query API or retention policy accepted  
**Aligned with production:** 2026-09-15

## Production boundary

Loom's production semantic API is `Parser::attach_semantic`. Each
`SemanticAnalysis[M, R]` owns one explicit analysis lifetime and one coherent
last-good publication: the accepted model, its parser snapshot, and pending
`SemanticChange`. The JSON settings integration uses this aggregate boundary.
It does not expose a keyed query cache or an eviction policy.

This note applies only if a future Loom integration adds keyed semantic queries,
for example on top of `dowdiness/incr_query`. It does not change
`SemanticAnalysis`, introduce that dependency, or authorize a production API.
See the [semantic publication ADR](../decisions/2026-09-12-semantic-publication-ownership.md)
and [attachment guide](../api/last-good-semantic-attachment.md) for the current
contract.

## Question

How can a future keyed semantic query bound recomputable memo storage without
conflating cache residency with semantic liveness, last-good history, or domain
identity?

## Recommendation

Separate **recomputable query results** from **history-bearing semantic state**
before selecting a retention policy.

- A snapshot-determined query computes a current outcome from a key and tracked
  inputs. Evicting its memo may discard acceleration evidence only; an uncached
  evaluation must remain observably equivalent.
- A history-bearing attachment owns its accepted value, identity baseline, and
  pending transition for its explicit lifetime. These values are semantic state,
  not a cache.
- Ordinary query authors should not choose a capacity. If a deployment needs a
  resource limit, the session owner may supply a cache budget while allocation
  and eviction remain runtime implementation details.
- LRU is one candidate policy, not a domain concept or a proven optimum. Capacity,
  admission, scheduling, and accounting require workload evidence.
- A bounded memo map does not by itself bound caller-retained views, dependency
  recipes, semantic history, or values whose size varies by key.

Do not add public `forget`, `retain_all`, mandatory per-query capacities, or an
eviction-algorithm enum to Loom's semantic interface on this evidence.

## Last-good counterexample

Assume a proposed keyed attachment promises an independent last-good value for
every previously accepted key, with memo capacity one:

1. Reading `a` accepts `17`.
2. Reading `b` accepts `23` and evicts `a`.
3. After an edit, reading `a` rejects.

The promised answer is `LastGood(17, rejection)`. A memo-only implementation can
return only `Unavailable(rejection)` after eviction. Moving `17` to another map
preserves behavior, but that map is history-bearing state and may grow with the
number of previously accepted keys.

For arbitrary independent values, these three promises cannot all hold without
another durable information source or a bounded key domain:

- arbitrary distinct keys over an unbounded session;
- last-good answers for every previously accepted key;
- a fixed bound on all retained information.

The correct cut is reconstructibility: discardable acceleration belongs in the
query runtime; non-reconstructible history belongs to an explicit semantic
lifetime.

## Keep three ownership questions separate

- **Semantic liveness:** whether a key belongs to the current or deliberately
  retained semantic model.
- **Cache retention:** whether a recomputable memo remains warm.
- **Identity continuity:** whether recomputation denotes the same domain entity.

Language membership and runtime residency answer different questions. A program
may contain millions of symbols while only a small working set is queried.
Recently deleted entries may stay cached within budget without re-entering the
semantic model. Eviction must not alter domain identity; if it does, identity
was tied incorrectly to memo incarnation.

## Evidence and precedents

The accepted Incr Query kernel stores a memo value, forward trace, stamps, and
memo identity. Its private `Query::drop_memo_evidence` operation demonstrates
that a surviving view can rematerialize snapshot-determined work after complete
memo proof loss. It does not prove that history-dependent last-good state may be
discarded:

- [Incr Query kernel contract](https://github.com/dowdiness/incr/blob/main/docs/design/specs/2026-08-13-incr-query-kernel-contract.md)
- [Incr Query lifetime and transaction contract](https://github.com/dowdiness/incr/blob/main/docs/design/specs/2026-08-13-incr-query-lifetime-and-transactions.md)
- [K1.5 validation record](https://github.com/dowdiness/incr/blob/main/incr_query/kernel/evidence/k1-5-validation.md)

Salsa supports opt-in query-local LRU and performs eviction at a safe revision
boundary. It retains keys and dependency metadata, so its policy is evidence for
automatic cache management rather than a complete memory bound or semantic
history deletion:

- [Salsa cache eviction](https://salsa-rs.github.io/salsa/tuning.html)
- [Salsa eviction policy](https://github.com/salsa-rs/salsa/blob/master/src/function/eviction.rs)
- [rust-analyzer LRU configuration](https://rust-analyzer.github.io/book/configuration#lru.capacity)

Nominal Adapton separates strong memo ownership, weak back-edges, reachability,
and explicit flushing. Its mechanism differs from Incr Query, but reinforces
that garbage-collector reachability and incremental restorability are not the
same correctness boundary:

- [Incremental Computation with Names, Appendix A](https://www.cs.tufts.edu/~jfoster/papers/nominal-adapton.pdf)

## Required evidence before adoption

A production retention policy needs all of the following:

1. Differential fresh-evaluation equivalence over randomized read, edit, evict,
   rejection, and cycle sequences.
2. Surviving-view rematerialization after eviction on native, JavaScript, and
   wasm-gc targets.
3. Ownership probes distinguishing memo-owned values, returned aliases,
   view-captured keys, and downstream dependency recipes.
4. A long-lived language-tooling workload showing memo count convergence under
   unique-key churn.
5. Policy measurements against a no-eviction baseline, including hit-heavy
   reads, scans, nested queries, and transient peak memory.
6. An explicit statement of which information is bounded. An idle memo-entry
   limit is not a hard bound on process memory or semantic history.

## Result

The durable conclusion is the separation of semantic history, reconstructible
query results, and deployment resource ownership. Production
`SemanticAnalysis` remains the current last-good publication boundary. A future
keyed-query design should use current-result queries plus explicitly owned
history-bearing lifetimes, and should change that contract only through a
separate accepted decision.

**No ADR needed:** this note preserves an open design constraint and required
evidence; it accepts no Loom API, dependency, cache policy, or implementation.
