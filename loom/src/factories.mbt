// Bridge factories — build Parser from a Grammar.
//
// These encapsulate all infrastructure wiring: TokenBuffer lifecycle,
// ReuseCursor construction, parse_tokens_indexed calls, diagnostic
// construction. The grammar author provides spec, lex, and to_ast;
// the factories handle the rest.
//
// ImperativeLanguage[Ast] is constructed internally for type erasure —
// grammar authors never see it.

///|
/// Create a fresh TokenBuffer.
/// The grammar owns lexing and returns a total `LexResult`; the factory only
/// chooses whether TokenBuffer may use range relex for incremental edits.
fn[T] create_buffer(
  source : String,
  lex : (String) -> @core.LexResult[T],
  eof_token : T,
  incremental_relex_enabled? : Bool = true,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> @core.TokenBuffer[T] {
  if !incremental_relex_enabled {
    return @core.TokenBuffer::new_from_lex(
      source,
      lex_fn=lex,
      eof_token~,
      incremental_relex_enabled=false,
    )
  }
  match mode_relex {
    Some(state) => {
      ignore((state.tokenize)(source))
      @core.TokenBuffer::new_from_lex(
        source,
        lex_fn=lex,
        eof_token~,
        incremental_relex_enabled~,
        mode_relex=Some(state),
      )
    }
    None =>
      @core.TokenBuffer::new_from_lex(
        source,
        lex_fn=lex,
        eof_token~,
        incremental_relex_enabled~,
      )
  }
}

///|
/// Build an `ImperativeLanguage[Ast]` from a `Grammar[T, K, Ast]`.
///
/// Each call allocates fresh per-session state (TokenBuffer ref, last
/// diagnostics, old-token cache) inside the closures. Shared by both
/// `new_imperative_parser` and `new_parser` — the only divergence downstream
/// is which engine (`ImperativeParser` vs. `Parser`) wraps the result.
fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind, Ast] build_imperative_language(
  grammar : Grammar[T, K, Ast],
) -> @incremental.ImperativeLanguage[Ast] {
  let spec = grammar.spec
  let lex = grammar.lex
  let incremental_relex_enabled = grammar.incremental_relex_enabled
  let mode_relex = grammar.mode_relex
  let cst_fold = @core.CstFold::new(grammar.fold_node)
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref(None)
  let last_parse_diags : Ref[@core.DiagnosticSet] = Ref(
    @core.DiagnosticSet::empty(),
  )
  // Persistent old-token cache: survives across edits so collect_old_tokens
  // only runs once (on first incremental parse). Subsequent edits reuse the
  // cached flat token array via ensure_old_tokens → immediate cache hit.
  // Reset to empty on full_parse (new tree, old cache invalid).
  let old_token_cache : Ref[@core.OldTokenCache] = Ref(
    @core.OldTokenCache::empty(),
  )
  @incremental.ImperativeLanguage::new(
    full_parse=source => {
      let buffer = create_buffer(
        source,
        lex,
        spec.eof_token,
        incremental_relex_enabled~,
        mode_relex~,
      )
      token_buf.val = Some(buffer)
      let (cst, diagnostics, _) = @core.parse_tokens_indexed(
        source,
        buffer.token_count(),
        fn(i) { buffer.get_token(i) },
        fn(i) { buffer.get_start(i) },
        fn(i) { buffer.get_end(i) },
        spec,
      )
      let lex_diagnostics = buffer.get_diagnostics()
      let all_diagnostics = lex_diagnostics.copy()
      all_diagnostics.extend(diagnostics)
      last_parse_diags.val = diagnostics
      let syntax = @seam.SyntaxNode::from_cst(cst)
      old_token_cache.val = @core.OldTokenCache::empty() // new tree — old cache invalid
      (syntax, all_diagnostics, 0)
    },
    incremental_parse=(source, old_syntax, edit) => {
      // Block reparse pre-check: attempt narrow subtree reparse before
      // updating the TokenBuffer. If the edit is strictly interior to a
      // reparseable block and the re-lexed tokens are balanced, we can
      // splice the reparsed subtree without a full incremental parse.
      match grammar.block_reparse_spec {
        Some(block_spec) =>
          match
            @core.reparse_block(
              old_syntax,
              source,
              edit,
              lex,
              spec,
              block_spec,
              last_parse_diags.val,
            ) {
            Some((new_cst, new_diagnostics)) => {
              let buffer = create_buffer(
                source,
                lex,
                spec.eof_token,
                incremental_relex_enabled~,
                mode_relex~,
              )
              let lex_diagnostics = buffer.get_diagnostics()
              let all_diagnostics = lex_diagnostics.copy()
              all_diagnostics.extend(new_diagnostics)
              last_parse_diags.val = new_diagnostics
              token_buf.val = Some(buffer)
              return (@seam.SyntaxNode::from_cst(new_cst), all_diagnostics, 1)
            }
            None => () // Fall through to normal incremental
          }
        None => ()
      }
      // Ensure buffer is up to date (updated or newly created).
      match token_buf.val {
        Some(buffer) =>
          buffer.update(edit, source) catch {
            @core.LexError(_) => {
              let rebuilt = create_buffer(
                source,
                lex,
                spec.eof_token,
                incremental_relex_enabled~,
                mode_relex~,
              )
              token_buf.val = Some(rebuilt)
            }
          }
        None => {
          let buffer = create_buffer(
            source,
            lex,
            spec.eof_token,
            incremental_relex_enabled~,
            mode_relex~,
          )
          token_buf.val = Some(buffer)
        }
      }
      // Buffer is always Some after the match above.
      let buffer = token_buf.val.unwrap()
      // Patch the persistent old-token cache: remove tokens in the old damage
      // range and accumulate offset delta for post-damage lookups.
      old_token_cache.val.apply_source_edit(edit)
      let cursor = Some(
        @core.ReuseCursor::new_with_edit(
          old_syntax.cst_node(),
          edit,
          buffer.token_count(),
          fn(i) { buffer.get_token(i) },
          fn(i) { buffer.get_start(i) },
          fn(i) { buffer.get_view(i) },
          spec,
          reuse_size_threshold=spec.reuse_size_threshold,
          old_token_cache=old_token_cache.val,
          allow_left_adjacent_reuse=edit.old_len > 0 && edit.new_len == 0,
        ),
      )
      let (new_cst, diagnostics, reuse_count) = @core.parse_tokens_indexed(
        source,
        buffer.token_count(),
        fn(i) { buffer.get_token(i) },
        fn(i) { buffer.get_start(i) },
        fn(i) { buffer.get_end(i) },
        spec,
        cursor~,
        prev_diagnostics=Some(last_parse_diags.val),
      )
      let lex_diagnostics = buffer.get_diagnostics()
      let all_diagnostics = lex_diagnostics.copy()
      all_diagnostics.extend(diagnostics)
      last_parse_diags.val = diagnostics
      let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
      (new_syntax, all_diagnostics, reuse_count)
    },
    to_ast=fn(syntax) { cst_fold.fold(syntax) },
    get_fold_stats=Some(fn() { cst_fold.get_stats() }),
  )
}

///|
/// Create an ImperativeParser from a Grammar.
///
/// Each call creates fresh internal state (TokenBuffer, diagnostics).
/// CST tokens produced by the parser are source spans; unchanged subtrees are
/// shared through incremental `ReuseNode` splicing rather than process-global
/// token/node interners.
pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind, Ast] new_imperative_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @incremental.ImperativeParser[Ast] {
  @incremental.ImperativeParser::new(source, build_imperative_language(grammar))
}

///|
/// Create a unified `Parser[Ast]` from a Grammar.
///
/// Wraps the same imperative engine as `new_imperative_parser` but publishes
/// derived state (source, syntax tree, AST, diagnostics) as read-only
/// `@incr.Derived` views — see `Parser` in `loom/src/pipeline/` for the
/// reactive surface.
///
/// Pass `runtime~` to join an existing reactive graph (useful when downstream
/// derived cells need to share the same `Runtime` as the parser). Omitting it
/// creates a fresh runtime owned by the returned parser.
pub fn[T : Eq + @seam.IsTrivia + @seam.ToRawKind, K : @seam.ToRawKind, Ast : Eq] new_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
  runtime? : @incr.Runtime,
) -> @pipeline.Parser[Ast] {
  @pipeline.Parser::new(source, build_imperative_language(grammar), runtime?)
}
