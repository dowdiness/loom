# Changelog

Notable user-facing changes to Loom and its sibling modules.

## Unreleased

### Removed

- **Breaking diagnostic API cleanup:** removed `DiagnosticSource`,
  `DiagnosticSourceFile`, the callback-holder `SourceProvider`, and the
  `Diagnostic::lexer_error*` parser convenience methods. Loom now exposes
  `lexer_diagnostic` / `lexer_diagnostic_at` as parser-owned adapters.

- **Breaking `@core` API removal:** `ParserContext::lex_mode()` and
  `ParserContext::set_lex_mode(Int)` are removed. Persistent lexer-decided modes
  should use `ModeLexer`/`ModeRelexFactory`; explicit parser-directed goals
  should use `GoalTokenSource`. The unused private checkpoint state was
  also removed.

### Changed

- **Markdown high-level Block projection:** `parse` and `parse_markdown` now
  share the source-bound `parse_document` → `MarkdownSemanticRead` →
  `markdown_semantic_read_to_block` seam. `parse_cst`, `markdown_fold_node`, and
  the `Parser[Block]` editor path remain compatibility surfaces; the retained
  direct source-aware fold is now a parity/benchmark oracle.

- **Breaking CST metadata ownership boundary:** `CstNode` fields are private,
  public construction copies children, and every node retains an immutable
  `CstMetadataPolicy`. Reconstruction and event builders require a policy and
  reject mixed metadata domains with catchable `Failure`; parser facades
  propagate that failure. Use `CstNode::new_unclassified` or
  `CstMetadataPolicy::unclassified()` for language-agnostic trees. `CstFold`
  now keys its cache by `CstNode`, `tree_diff` verifies structural equality,
  and the private numeric node hash is no longer a persistent identifier.
  Root reconstruction uses `CstNode::with_replaced_root` to validate the
  replacement domain without exposing policy state.

- **Breaking mode-relex ownership boundary:** mode-aware token buffers are now
  constructed with `TokenBuffer::new_from_mode_relex` and a retained
  `ModeRelexFactory`. Custom relex callbacks receive opaque `OldTokenStarts`
  instead of a mutable offset array and return validated `ModeRelexResult`
  values. Invalid partial output discards the session and retries through a
  fresh factory session without partially committing parser-visible state.

- **Breaking diagnostic naming:** `Diagnostic` construction/access now uses
  `origin` and `DiagnosticOrigin`; rendering receives any `SourceResolver`, and
  coherent rendering inputs use `SourceSnapshot`.

- `examples/markdown` adds
  `experimental_markdown_ir_canonical_format_checked`, which formats a
  semantic `MarkdownIR::Document` through a finite, deterministic candidate
  search and accepts output only after `parse_cst` plus diagnostic-aware
  MarkdownIR lowering reproduces the same position- and surface-independent
  document semantics. It returns structured failures for non-document roots,
  opaque recovery/unsupported nodes, unrepresentable input, and exhausted
  search limits. The existing string-returning formatter delegates to this
  checked path for semantic documents while preserving its legacy unchecked
  behavior for subtree and opaque compatibility inputs.

- **Breaking `examples/markdown` token/CST shape change:** CommonMark emphasis
  is now resolved by a private parser-owned delimiter-run pass for `*` and `_`,
  including Unicode-aware flanking and unmatched/partial runs. Inline lexing
  emits one `Token::Star` per unescaped `*` (and no longer emits
  `Token::StarStar` for inline `**`) and adds `Token::Underscore`. Matched
  emphasis boundaries are emitted as `EmphasisDelimiterToken`; unmatched,
  escaped, and unused marker portions are ordinary `TextToken`s rather than
  recovery errors. `UnderscoreToken` and `EmphasisDelimiterToken` use append-only
  raw kinds 39 and 40; existing variants and raw IDs remain available. CST/role
  consumers should identify editable emphasis boundaries by token kind, not by
  marker spelling.

- **Breaking `examples/markdown` CST API:** `SyntaxKind::HeadingMarkerToken`
  has been split into `AtxHeadingMarkerToken` and
  `SetextHeadingUnderlineToken`. Consumers that match the old variant or query
  `direct_token_of_kind(HeadingMarkerToken.to_raw())` must query the
  form-specific kind: use `AtxHeadingMarkerToken` for `#` prefixes and
  `SetextHeadingUnderlineToken` for `=`/`-` underline lines.
  `Token::HeadingMarker(Int)`, `HeadingNode`, and
  `MarkdownRole::HeadingMarker` are unchanged.

- `examples/markdown`: improved CommonMark tab handling for list and
  blockquote indentation, including tab-expanded nested list markers and
  container-relative indented code blocks.

- **`dowdiness/loom/core` — `@core` package surface reduction (Stage A1):**
  `ProjectionIdentityBaseline`, `ProjectionIdentityTracker`, `ProjectionLeaf`,
  `StableProjectionLeaf`, `ProjectionStringIdAllocator`, and the four
  `realign_projection_*` functions are removed from the `@core` package's
  public `.mbti`. They are now in the new `dowdiness/loom/projection` package
  and continue to be re-exported unchanged by the `dowdiness/loom` facade.
  **No change required for code that imports via `@loom.*`** — the facade
  surface is identical. Direct `@core.ProjectionIdentity*` importers must
  switch to `@loom.*` or `@projection.*`.

- `dowdiness/seam`: hardened source-span/reuse APIs before stabilization.
  `CstToken::is_source_backed` is the stable token-provenance predicate;
  `CstToken::unsafe_backing_source`,
  `EventBuffer::push_parser_reuse_node_rebased*`, and
  `EventBuffer::push_parser_synthetic_zero_width_token` carry explicit
  unstable, parser-owned naming. The older `CstToken::source`,
  `EventBuffer::push_reuse_node_at*`, and
  `EventBuffer::push_synthetic_zero_width_token` names are deprecated
  compatibility aliases.

### Added

- **`dowdiness/diagnostic`:** new parser-independent module for validated UTF-16
  offsets/ranges, structured diagnostics, source-qualified labels, line
  indexing, deterministic plain rendering, and atomic single-source fixes. The
  open `SourceResolver`, `TextDisplay`, and `ToDiagnostic` traits support
  external source stores, presentation policy, and application-defined errors
  without a Loom dependency. Loom's `LexError` is the first production
  `ToDiagnostic` implementation. The default plain renderer remains
  code-unit-compatible and the production module remains MoonBit-core-only.

- **`dowdiness/diagnostic_moji`:** new opt-in adapter that renders structured
  diagnostics with `dowdiness/moji` display cells for Unicode marker alignment,
  deterministic four-column tab expansion, combined display units, and visible
  markers for non-empty zero-width spans.

- **`dowdiness/diagnostic_pretty`:** new opt-in adapter that converts structured
  diagnostics into width-aware `dowdiness/pretty` layouts with typed severity,
  code, source, gutter, label, and note annotations. Unicode display-cell
  measurement, configurable tabs, and East Asian Ambiguous-width policy come
  from `dowdiness/moji`; ANSI, HTML, themes, and terminal detection remain
  separate consumers.

- **`dowdiness/moji`:** added grapheme-aware terminal display measurement.
  `display_width` and `display_units` combine moji's UTF-16 grapheme boundaries
  with UAX #11 widths, explicit East Asian Ambiguous policy, absolute tab-stop
  expansion, zero-width units, and non-additive ligature grouping. Width-table
  Unicode versioning is exposed independently from segmentation data.

- **`dowdiness/loomgen` — M16 EBNF subset: `~` (Emit), `!` (EmitOr), `@until` (ErrorUntil):**
  Postfix `Token~` lowers to `Expr::Emit(token, kind)` — silently skip if absent.
  Postfix `Token!` lowers to `Expr::EmitOr(token, kind, msg)` — emit diagnostic + placeholder if absent.
  `@until(Token)` / `@until(T1 | T2)` lowers to `Expr::ErrorUntil(Pred::IsToken/OneOf, msg)` — consume until synchronization point.
  All three syntaxes available in `#loom.rule` annotations and `.loomgrammar` files.
  Golden fixture + parity test added under `fixtures/rule_emit_fixture.*`.

- **`dowdiness/loomgen` — default lex patterns for `#loom.ident`, `#loom.literal`, `#loom.trivia` (#635, #641):**
  Token variants annotated with `#loom.ident`, `#loom.literal`, or `#loom.trivia` no
  longer require an explicit `#loom.pattern("...")` annotation. The generated lexer
  uses sensible defaults: `[a-zA-Z_][a-zA-Z0-9_]*` for identifiers,
  `[0-9]+(\.[0-9]+)?` for literals, and `[ \t\r\n]+` for trivia. Explicit
  `#loom.pattern` still overrides with a custom regex. `#loom.custom_lex` variants
  are unaffected (no default pattern emitted).


### Fixed

- **`dowdiness/loom/core` — bounded long-lived `CstFold` cache retention
  ([#782](https://github.com/dowdiness/loom/issues/782)):** the memoized CST→AST
  fold now compacts its private cache every 64 folds, retaining entries
  reachable from the current CST and releasing deleted historical subtrees.
  Structural collision verification and descendant warming remain unchanged.

- **`examples/html` — infinite loop on a stray close tag; native `moon test` no longer hangs (#646):**
  `parse_html_root`'s fallthrough recovery called `skip_until(is_sync_point)`,
  which consumes nothing when the current token is already a sync point. A
  mismatched close tag (e.g. `<div></span>`) leaves a `CloseTag` — itself a sync
  point — at the root, so the recovery loop spun forever at the same position
  (observed as a 100% CPU `tcc @…html.blackbox_test.rspfile` spin under
  `--target native`, and identically under `moonrun` on `wasm-gc`). Switched to
  `skip_until_progress`, which guarantees forward progress by consuming one error
  token when already at a sync point.

- **`dowdiness/loom/grammar` — `@until` no longer emits spurious diagnostic when already at sync point (#636):**
  `ErrorUntil(stop, msg)` now guards `ctx.error(msg)` behind
  `if !stop.matches(ctx.peek())` — when the current token already satisfies the
  stop predicate (e.g. `@until(RBrace)` with `peek = RBrace`), no diagnostic is
  emitted and `skip_until` is skipped. Fix applied to both the interpreter and
  the compiled emission path.

- **`dowdiness/loom/core` — `ParserContext::expect` and `expect_adjacent` no longer emit "emit_token: unexpected EOF" diagnostic:**
  Both functions now skip `emit_token` when at EOF — EOF has no source text to
  emit as a CST token, so attempting to do so produced a spurious diagnostic on
  every well-formed parse that uses `Expect(EOF, ...)` (e.g. every grammar with
  a trailing `EOF` in its root rule). The diagnostic was harmless but added
  noise, obscuring real recovery diagnostics.

### Added

- `dowdiness/loom`: added `ParserContext` grammar-author helpers:
  `emit_current_token`, `current_token_text`, `current_token_range`, and
  `too_many_errors`.
- `dowdiness/loom`: added `ParserContext` node-introspection helpers:
  `current_node_kind()` (returns `K?` — the kind of the most recently opened
  node), `peek_index(n)` (trivia-inclusive token-buffer access), and
  `finish_nodes_until(kind)` (auto-close nodes above a target kind, used for
  HTML-style optional closing tags).
- `dowdiness/loom`: added `finish_nodes_until_inclusive(kind)` —
  like `finish_nodes_until` but also closes the matching node.
  Eliminates the two-step pattern
  (`if ctx.finish_nodes_until(K) { ctx.finish_node() }`).

- **`dowdiness/loom/projection`** — new package containing the stable
  semantic projection-identity subsystem extracted from `loom/core` (Stage A1).
  Depends on `loom/core` data types and `text_change`; the engine
  (`loom/core` parser, `loom/incremental`, `loom/pipeline`) is structurally
  prohibited from depending on it. All projection-identity symbols remain
  accessible via the `dowdiness/loom` facade unchanged.

- `dowdiness/loom`: added `SyntaxGrammar`, `SyntaxParser`,
  `SyntaxSnapshot`, and `new_syntax_parser` for reactive CST/diagnostics
  consumers that do not have an AST fold or whose AST is not naturally `Eq`.
- `dowdiness/loom`: added stable semantic projection identity helpers
  (`ProjectionIdentityBaseline`, `ProjectionIdentityTracker`, `ProjectionLeaf`,
  `StableProjectionLeaf`, `ProjectionStringIdAllocator`,
  `realign_projection_identities`, and `realign_projection_items`) for
  preserving domain IDs across editor edits and malformed-input recovery.
- `dowdiness/seam`: added projection-friendly direct CST query helpers on
  `SyntaxNode`: `direct_token_of_kind`, `direct_tokens_of_kind`, and
  `direct_children_of_kind`. These make direct argument-shape validation more
  obvious for library users and help avoid accidentally accepting nested tokens
  during semantic projection.
- `dowdiness/seam`: added `CstNode::direct_elements_iter` for lazy direct
  visible-child traversal with transparent `RepeatGroup` flattening.
- `dowdiness/seam`: added `SyntaxNode::direct_elements_iter` for lazy
  positioned direct-child traversal as `SyntaxElement`s, reusing the same
  transparent `RepeatGroup` flattening semantics.
