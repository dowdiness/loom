# Benchmark Inventory Reconciliation Improvements

**Date:** 2026-07-13  
**Status:** Approved design  
**Related PR:** [#713](https://github.com/dowdiness/loom/pull/713)  
**Related issue:** [#712](https://github.com/dowdiness/loom/issues/712)

## Goal

Complete the evidence boundary identified during review of PR #713 without
changing benchmark detector semantics. The final real run reported five gated
rows, while the ADR contains matched trials for the six initial candidates.
Two rows newly observed in the final run require the same matched-trial
classification method before the reconciliation is considered complete.

## Scope

### Candidate evidence

Run three interleaved current-vs-baseline trials for:

- `ui-static-probe: tree 1023 static Derived + 512 eager leaves`
- `realistic: 160 defs - incremental (edit tail)`

Use the same conditions as the existing ADR table:

- current checkout: `fix/712-bench-inventory`
- baseline origin: `6e17167`
- baseline worktree: `/home/antisatori/worktrees/loom/test/644-benchmark-baseline`
- Moon: `0.1.20260703 (6fbf8c3)`
- paired current/baseline trials, three repetitions per candidate

Record current values, baseline-origin values, and the paired ratio range in
`docs/decisions/2026-07-13-benchmark-inventory-reconciliation.md`. Alternate
the paired execution order as current→baseline, baseline→current,
current→baseline. Classify a candidate as a confirmed regression only if all
three paired current-over-baseline ratios exceed 1.15. Otherwise classify it as
measurement variance or non-reproduced, while still reporting the full ratio
range. Do not change implementation, baseline values, or detector policy solely
from a non-reproduced result.

### Guard readability cleanup

Preserve the existing `--update` behavior and contract:

- keep the `count` assignment and the successful baseline-save message unchanged
  — they are part of the user-visible `--update` output contract;
- rename/reorder `validate_update_inventory` inputs to
  `current_data baseline_data`;
- keep the current-data-first and baseline-data-second awk input order;
- retain existing self-tests for missing-name rejection and unchanged baseline.

Task 1 scope is limited to `validate_update_inventory` argument/data-flow
clarification. No output contract changes.

No new detector behavior is introduced.

### Documentation

Update the ADR candidate table and evidence prose so the two newly measured
rows are explicitly covered. The documentation must distinguish the six
initial candidates from rows that appeared in the later final run.

Update `docs/README.md` for this design specification, as required whenever a
Markdown file is added.

## Verification contract

Run and record results for:

```text
bash scripts/bench-check-selftest.sh
bash bench-check.sh --validate
bash -n bench-check.sh
bash -n scripts/bench-check-selftest.sh
moon check
bash check-docs.sh
bash bench-check.sh
```

The final real run must retain `MISSING: 0` and `NEW: 0`. A nonzero exit is
acceptable only when the detector reports actual gated regressions; its exact
counts and row names must be recorded.

## Non-goals

- No baseline refresh with `--update`.
- No silent conversion of regressions to informational rows.
- No implementation optimization based on noisy benchmark output.
- No restoration of the retired `event-graph-walker` workspace.
