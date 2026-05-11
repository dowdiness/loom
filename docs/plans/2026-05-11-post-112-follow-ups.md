# Post-112 Follow-Ups

**Status:** Active

## Context

PR #112 merged the line-index and recoverable lexer-error-message work. The
merged API keeps loom's canonical coordinate system as UTF-16 code-unit offsets
and derives line/column positions at presentation boundaries.

The PR also made JSON and Lambda use `error_token_from_message` for recoverable
step-lexer errors, fixed eager error-callback construction in factories, and
fixed JSON invalid-string recovery so consumed invalid escapes do not swallow
the following token.

## Recommended Next Work

1. Parser-level structured diagnostics.

   `Parser::diagnostics()` and `ImperativeParser::diagnostics()` still expose
   `Array[String]`. Add a design for retaining structured diagnostics at the
   parser boundary before adding convenience methods such as
   `diagnostics_with_line_col()` or `line_index()`.

2. Incremental `LineIndex` only if profiling justifies it.

   `LineIndex::new(source)` is simple and rebuilds from source text. Keep that
   path until an editor workload shows line-index construction in profiles.
   Then consider `LineIndex::apply_edit(old_source, new_source, edit)`.

3. Legacy resilient lexer Unicode cleanup.

   `TokenBuffer::new_resilient` is deprecated, but its fallback path still emits
   a one-code-unit error token and advances with `pos + 1` when no lexable prefix
   exists. Switch that fallback to `next_char_offset(source, pos)` and add a
   regression in `loom/src/core/token_buffer_resilient_wbtest.mbt`.

4. Document the `error_token_from_message` contract.

   The factory path now only uses `error_token_from_message` in recoverable mode,
   when an `error_token` fallback is also present. Public API docs should say
   that message-preserving recovery requires both options; without
   `error_token`, step lexing remains strict and raises `LexError`.

## Verification For Follow-Up PRs

Run the usual loom checks:

```bash
rtk moon fmt
rtk moon check
rtk moon test
rtk moon info
rtk git diff --check
```

For example-level lexer changes, also run tests from the touched example module,
for example:

```bash
cd examples/json
rtk moon test
```
