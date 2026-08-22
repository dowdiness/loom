# Agent Instructions

@/home/antisatori/.codex/RTK.md

## Documentation Workflow

Before completing, deleting, or archiving a plan document, follow
`docs/development/agent-docs-protocol.md`.

In particular:

- create or update an ADR for major plan closures
- add an explicit `No ADR needed:` note for mechanical plan archival
- update `docs/README.md` whenever Markdown files are added, moved, or removed
- mention the ADR/no-ADR decision in the final response

## Cursor Cloud specific instructions

MoonBit monorepo defined by `moon.work` (no root `moon.mod.json`). Toolchain
`moon`/`moonc` (pinned `0.10.4+2cc641edf` via CI) lives in `~/.moon/bin`, which
the installer adds to `PATH` in `~/.bashrc`. Non-login shells may not source it —
use `export PATH="$HOME/.moon/bin:$PATH"` (or the full `~/.moon/bin/moon` path)
if `moon` is not found.

- `incr`, `egraph`, `egglog` are git submodules and workspace members. The
  workspace will not build until they are checked out. The startup update script
  runs `git submodule update --init --recursive`.
- `moon check` / `moon test` from **any** member directory (or the repo root)
  cover the entire workspace, not just that directory.
- `moon check` emits many pre-existing deprecation/ambiguous-brace warnings
  (~183). These are expected — only `0 errors` matters.
- Some example members (`html`, `css`, `graph-dsl`, `moonbit`, `jsx`,
  `loomgen`) are exercised with `--target native` in CI. A plain root
  `moon test` (default target) passes all of them; use `--target native` only
  when reproducing a specific CI job.
- `loomgen` is the one primary runnable app (`fn main`, a codegen CLI). Build
  with `moon build loomgen --target native`, then `moon run loomgen --target
  native -- ...` (see `.github/workflows/ci.yml` `check-loomgen` for concrete
  invocations). Everything else is a library validated via `moon test`.
- No long-running service/daemon exists; "running" the product means the test
  suite, benchmarks (`cd examples/lambda && moon bench --release`), or `loomgen`.
- Standard commands (build/test/lint/fmt/bench, per-package scoping) are in
  `CLAUDE.md` and `README.md`; repo checks are `check-deps.sh`, `check-docs.sh`,
  `bench-check.sh`.
