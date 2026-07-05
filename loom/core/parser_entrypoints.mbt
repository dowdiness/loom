// Generic parser infrastructure — parse/build-tree entry points

// ─── parse_with ───────────────────────────────────────────────────────────────

///|
/// Parse a source string using the given language spec and grammar function.
/// Returns the immutable CST and any parse diagnostics.
///
/// tokenize — converts source to a flat token array (including trivia tokens)
/// grammar  — the entry-point parse function; calls ctx methods to build the tree
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] parse_with(
  source : String,
  spec : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, DiagnosticSet) {
  let tokens = tokenize(source)
  let ctx = ParserContext::new(tokens, source, spec)
  grammar(ctx)
  ctx.flush_trivia()
  // node_stack intentionally NOT modified here — terminal auto-close before tree build.
  // If a future caller reads node_stack after this loop, must pop it.
  while ctx.open_nodes > 0 {
    ctx.error("unclosed node (auto-closed)")
    ctx.open_nodes = ctx.open_nodes - 1
    ctx.events.push(@seam.FinishNode)
  }
  let tree = ctx.events.build_tree(
    spec.root_kind.to_raw(),
    trivia_kinds=Some(spec.trivia_kinds_raw()),
    error_kind=Some(spec.error_kind.to_raw()),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  ) catch {
    e => {
      ctx.error("internal: malformed event stream: " + @debug.to_string(e))
      make_error_tree(spec)
    }
  }
  (tree, ctx.diagnostics)
}

///|
fn[T, K : @seam.ToRawKind] make_error_tree(
  spec : LanguageSpec[T, K],
) -> @seam.CstNode {
  let err_raw = spec.error_kind.to_raw()
  let error_child = @seam.CstNode::new(err_raw, [], error_kind=Some(err_raw))
  @seam.CstNode::new(
    spec.root_kind.to_raw(),
    [@seam.CstElement::Node(error_child)],
    trivia_kinds=Some(spec.trivia_kinds_raw()),
    error_kind=Some(err_raw),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  )
}

///|
/// Build the CST from an event buffer using spec metadata for root and trivia kinds.
///
/// The generic parser intentionally uses the non-interned builder so tokens keep
/// zero-copy source spans. Parser-owned reuse events rebase reused token spans
/// onto the current source buffer, avoiding process-global interners and old
/// source-buffer retention.
///
/// Source-span rebasing necessarily constructs fresh CST nodes, so generic
/// parser clients must not rely on stable physical identity for unchanged
/// subtrees across parses. Use structural equality or projection/domain
/// identity for downstream change detection.
fn[T, K : @seam.ToRawKind] build_tree_generic(
  buf : @seam.EventBuffer,
  spec : LanguageSpec[T, K],
) -> @seam.CstNode raise @seam.EventStreamError {
  buf.build_tree(
    spec.root_kind.to_raw(),
    trivia_kinds=Some(spec.trivia_kinds_raw()),
    error_kind=Some(spec.error_kind.to_raw()),
    incomplete_kind=Some(spec.incomplete_kind.to_raw()),
  )
}

///|
/// Generic incremental parse driver. Replaces the lambda-specific
/// `run_parse` / `run_parse_incremental` pair in `src/parser/`.
///
/// Accepts indexed token accessors (avoids O(n) Array[TokenInfo[T]] allocation
/// when the caller already has tokens in a language-specific layout).
/// Uses `spec.parse_root` as the grammar entry point.
///
/// Returns `(CstNode, diagnostics, reuse_count)`.
/// reuse_count is 0 for non-incremental calls (cursor=None).
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind] parse_tokens_indexed(
  source : String,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  spec : LanguageSpec[T, K],
  cursor? : ReuseCursor[T, K]? = None,
  prev_diagnostics? : DiagnosticSet? = None,
) -> (@seam.CstNode, DiagnosticSet, Int) {
  let ctx = ParserContext::new_indexed(
    token_count, get_token, get_start, get_end, source, spec,
  )
  match cursor {
    Some(c) => {
      ctx.set_reuse_cursor(c)
      match prev_diagnostics {
        Some(prev) => ctx.set_reuse_diagnostics(prev)
        None => ()
      }
    }
    None => ()
  }
  (spec.parse_root)(ctx)
  ctx.flush_trivia()
  // node_stack intentionally NOT modified here — terminal auto-close before tree build.
  // If a future caller reads node_stack after this loop, must pop it.
  while ctx.open_nodes > 0 {
    ctx.error("unclosed node (auto-closed)")
    ctx.open_nodes = ctx.open_nodes - 1
    ctx.events.push(@seam.FinishNode)
  }
  let tree = build_tree_generic(ctx.events, spec) catch {
    e => {
      ctx.error("internal: malformed event stream: " + @debug.to_string(e))
      make_error_tree(spec)
    }
  }
  (tree, ctx.diagnostics, ctx.reuse_count)
}
