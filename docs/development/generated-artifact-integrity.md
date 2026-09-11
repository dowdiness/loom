# Generated artifact integrity

Repository regeneration checks must treat each generated output and its provenance as one explicit artifact set.

## Contract

Each set lists repository-relative paths explicitly and includes:

- the pinned source and version used by the generator;
- an integrity hash when the upstream source has a published or recorded hash;
- the upstream license when source data is vendored;
- the generator itself;
- every committed generated output;
- a generated header identifying the generator where the output format supports comments;
- hermetic tests or regeneration that require no network access; and
- deletion detection as well as content-drift detection.

After regeneration, run `scripts/check-generated-artifacts.sh` with every path in the set. The helper rejects missing paths, untracked paths, modified paths, and tracked files deleted from the index and recreated as untracked files. Do not use unresolved globs or repository-wide implicit scans.

Temporary comparison outputs are not committed artifacts. Compare them directly with their explicit committed fixture using `diff`; use the helper for generators that update committed paths in place.
