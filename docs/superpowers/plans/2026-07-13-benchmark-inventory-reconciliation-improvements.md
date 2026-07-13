# Benchmark Inventory Reconciliation Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the two remaining benchmark candidate classifications and clarify the `validate_update_inventory` argument/data-flow without changing output contracts.

**Architecture:** Keep benchmark detection and inventory validation in `bench-check.sh`. Keep measured candidate evidence in the existing inventory reconciliation ADR. Use paired, alternating current/baseline trials before assigning a regression classification.

**Tech Stack:** Bash, POSIX `awk`, MoonBit `moon bench --release`, checked-in TSV baseline, Markdown ADRs.

## Global Constraints

- Do not run `bench-check.sh --update`.
- Do not modify baseline measurements or detector policy based on non-reproduced variance.
- Use baseline origin `6e17167` and Moon `0.1.20260703 (6fbf8c3)` for candidate comparisons.
- Run paired trial order `current→baseline`, `baseline→current`, `current→baseline` for each candidate.
- Confirm a regression only when all three paired current-over-baseline ratios exceed `1.15`.
- Preserve `MISSING: 0` and `NEW: 0` in the final detector run.
- Prefix shell commands with `rtk`.
- Leave `/home/antisatori/worktrees/loom/test/644-benchmark-baseline` untouched.

---

### Task 1: Clean up inventory update guard

**Files:**
- Modify: `bench-check.sh:90-102` (`validate_update_inventory`)
- Modify: `bench-check.sh:201-211` (`--update` validation path)
- Test: `scripts/bench-check-selftest.sh` existing missing-inventory and unchanged-baseline cases

**Interfaces:**
- Consumes: current TSV and baseline TSV strings passed to `validate_update_inventory`.
- Produces: identical exit status and diagnostic behavior for rejected inventory updates.

- [ ] **Step 1: Record the pre-change contract**

Run:

```bash
rtk bash scripts/bench-check-selftest.sh
rtk bash bench-check.sh --validate
```

Expected: `SELFTEST PASS` and `Baseline and detector policy are valid`.

- [ ] **Step 2: Make guard argument order match data flow**

Change the function signature and call site to use current data first:

```bash
validate_update_inventory() {
  local current_data="$1" baseline_data="$2"
  awk -F '\t' '
    NR == FNR {
      current[$1] = 1
      next
    }
    !($1 in current) {
      printf "update: benchmark missing from current run: %s\n", $1 > "/dev/stderr"
      bad = 1
    }
    END { exit bad }
  ' <(printf '%s\n' "$current_data") <(printf '%s\n' "$baseline_data")
}
```

Update the call from:

```bash
validate_update_inventory "$(<"$BASELINE")" "$parsed"
```

to:

```bash
validate_update_inventory "$parsed" "$(<"$BASELINE")"
```

- [ ] **Step 3: Verify the existing behavioral contract**

Run:

```bash
rtk bash scripts/bench-check-selftest.sh
rtk bash -n bench-check.sh
rtk moon check
```

Expected: `SELFTEST PASS`, successful Bash syntax validation, and `Finished. moon: no work to do`.

- [ ] **Step 4: Commit the cleanup**

```bash
rtk git add bench-check.sh
rtk git commit -m "ci: clarify benchmark inventory update guard"
```

---

### Task 2: Measure the two final-run candidates

**Files:**
- Read: `incr/incr/tests/bench_test.mbt` and relevant benchmark package files to identify exact test indices.
- Read: `/home/antisatori/worktrees/loom/test/644-benchmark-baseline/incr/incr/tests/bench_test.mbt` and relevant baseline package files.
- Modify: none during measurement.

**Interfaces:**
- Consumes: exact benchmark test indices for the two named candidates.
- Produces: six paired measurements per candidate (three current, three baseline-origin), with ratio ranges.

- [ ] **Step 1: Resolve exact benchmark selectors**

Use the built-in repository grep tool to identify the test declarations and
line/index selectors in `incr`, `loom`, `seam`, and `examples`. Do not use a
shell grep command for content search.

Inspect the containing benchmark files and verify the exact package and index before running any measurement.

- [ ] **Step 2: Verify toolchain and worktree identity**

Run:

```bash
rtk git status --short --branch
rtk git -C /home/antisatori/worktrees/loom/test/644-benchmark-baseline status --short --branch
rtk moon version --all
rtk git -C /home/antisatori/worktrees/loom/test/644-benchmark-baseline rev-parse HEAD
rtk git -C /home/antisatori/worktrees/loom/test/644-benchmark-baseline show -s --format='%H %s' 6e17167
```

Expected: both worktrees are clean, Moon is
`0.1.20260703 (6fbf8c3)`, and the baseline worktree commit is `6e17167`.

- [ ] **Step 3: Run candidate 1 with alternating paired order**

Run the exact current and baseline benchmark selectors in this order:

```text
current candidate 1
baseline candidate 1
baseline candidate 1
current candidate 1
current candidate 1
baseline candidate 1
```

Record each raw mean in nanoseconds. Use the same package, test file, release mode, and selector for both worktrees.

- [ ] **Step 4: Run candidate 2 with alternating paired order**

Run the exact current and baseline benchmark selectors in this order:

```text
current candidate 2
baseline candidate 2
baseline candidate 2
current candidate 2
current candidate 2
baseline candidate 2
```

Record each raw mean in nanoseconds.

- [ ] **Step 5: Compute classifications before editing the ADR**

For each candidate, compute three paired ratios as `current_mean / baseline_mean` using the corresponding trial positions. Confirmed regression requires all three ratios to exceed `1.15`; otherwise classify as measurement variance or non-reproduced. Preserve the complete values and ratio range regardless of classification.

- [ ] **Step 6: Commit no measurement-only changes**

Do not commit generated benchmark artifacts or baseline updates. Keep the measurement record ready for Task 3.

---

### Task 3: Update ADR evidence and PR metadata

**Files:**
- Modify: `docs/decisions/2026-07-13-benchmark-inventory-reconciliation.md:50-67`
- Modify: `docs/README.md` only if the ADR link or description changes
- Modify: PR #713 description/comment through GitHub CLI after local commit

**Interfaces:**
- Consumes: Task 2 raw means and ratio classifications.
- Produces: an ADR table covering both final-run candidates and a concise PR evidence update.

- [ ] **Step 1: Add both candidate rows to the ADR table**

Add one row for each candidate with this exact information:

```text
Benchmark | Current trials | Baseline-origin trials | Ratio range | Classification
```

Use the measured values, not rounded values that could change the threshold decision. State that all three paired ratios were checked against `1.15`.

- [ ] **Step 2: Update evidence prose**

Replace the sentence claiming only the initial candidates were covered with prose that distinguishes:

- the six initial candidates from the first reconciled run;
- the two additional candidates observed in the final run;
- the shared classification rule;
- the fact that no baseline value, detector policy, or implementation change follows from non-reproduced results.

- [ ] **Step 3: Validate documentation**

Run:

```bash
rtk bash check-docs.sh
rtk moon check
```

Expected: `All checks passed.` and `Finished. moon: no work to do`.

- [ ] **Step 4: Commit ADR evidence**

```bash
rtk git add docs/decisions/2026-07-13-benchmark-inventory-reconciliation.md
rtk git commit -m "docs: classify final benchmark candidates"
```

- [ ] **Step 5: Update PR #713 evidence**

After local verification, update the PR body or add a comment with the two measured rows, their ratio ranges, and the final detector result. Do not claim all final rows are resolved unless both new rows are explicitly classified.

---

### Task 4: Run final verification and publish

**Files:**
- Read-only verification of all changed files.

**Interfaces:**
- Consumes: Tasks 1–3 commits.
- Produces: verified branch and updated PR #713.

- [ ] **Step 1: Run focused validation**

```bash
rtk bash scripts/bench-check-selftest.sh
rtk bash bench-check.sh --validate
rtk bash -n bench-check.sh
rtk bash -n scripts/bench-check-selftest.sh
rtk moon check
rtk bash check-docs.sh
```

Expected: all commands pass.

- [ ] **Step 2: Run the real detector comparison**

```bash
rtk proxy bash bench-check.sh
```

Record the command’s own exit status and output. Require `MISSING: 0` and `NEW: 0`. A nonzero status is expected only when gated regressions remain; record their exact names and counts.

- [ ] **Step 3: Confirm branch and diff state**

```bash
rtk git status --short --branch
rtk git log --oneline -5
rtk gh pr checks 713
```

Expected: clean branch, pushed commits, and all PR checks passing after CI completes.

- [ ] **Step 4: Commit and push any final evidence update**

```bash
rtk git push
```

Do not merge PR #713 without a separate explicit confirmation.
