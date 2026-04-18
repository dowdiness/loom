// Bridge factories — build Parser from a Grammar.
//
// These encapsulate all infrastructure wiring: TokenBuffer lifecycle,
// ReuseCursor construction, parse_tokens_indexed calls, diagnostic
// formatting. The grammar author provides spec, tokenize, to_ast, and
// on_lex_error; the factories handle the rest.
//
// ImperativeLanguage[Ast] is constructed internally for type erasure —
// grammar authors never see it.

///|
/// Create a fresh TokenBuffer.
/// Precedence: mode_relex > prefix_lexer (step-based) > error_token (resilient) > plain.
fn[T] create_buffer(
  source : String,
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  eof_token : T,
  error_token : T?,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
  mode_relex? : @core.ModeRelexState[T]? = None,
) -> @core.TokenBuffer[T] raise @core.LexError {
  match mode_relex {
    Some(state) => {
      // Mode-aware path takes precedence: error_token and prefix_lexer are
      // intentionally ignored because ModeRelexState.tokenize handles all
      // tokenization (including error recovery) via the captured ModeLexer.
      let (tokens, starts) = (state.tokenize)(source)
      @core.TokenBuffer::new_with_mode_relex(
        source, tokens, starts, eof_token, state,
      )
    }
    None =>
      // Existing stateless path (unchanged)
      match (prefix_lexer, error_token) {
        (Some(lexer), Some(err_tok)) =>
          @core.TokenBuffer::new_from_steps(
            source,
            lexer,
            eof_token~,
            error_token=err_tok,
          )
        (Some(lexer), None) =>
          // Step-based without error_token: run in strict mode and surface
          // Invalid/Incomplete as LexError instead of synthesizing EOF-like tokens.
          @core.TokenBuffer::new_from_steps_strict(source, lexer, eof_token~)
        (None, Some(err_tok)) =>
          // Deprecated: legacy binary-search probing. Migrate to prefix_lexer.
          @core.TokenBuffer::new_resilient_compat(
            source,
            tokenize_fn=tokenize,
            eof_token~,
            error_token=err_tok,
          )
        (None, None) =>
          @core.TokenBuffer::new(source, tokenize_fn=tokenize, eof_token~)
      }
  }
}

///|
/// Build an `ImperativeLanguage[Ast]` from a `Grammar[T, K, Ast]`.
///
/// Each call allocates fresh per-session state (TokenBuffer ref, last
/// diagnostics, old-token cache) inside the closures. Shared by both
/// `new_imperative_parser` and `new_parser` — the only divergence downstream
/// is which engine (`ImperativeParser` vs. `Parser`) wraps the result.
fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast] build_imperative_language(
  grammar : Grammar[T, K, Ast],
) -> @incremental.ImperativeLanguage[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let error_token = grammar.error_token
  let prefix_lexer = grammar.prefix_lexer
  let mode_relex = grammar.mode_relex
  let cst_fold = @core.CstFold::new(grammar.fold_node)
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[T]]] = Ref::new([])
  // Pending lex-error message, `Some` when the most recent parse attempt
  // tripped a LexError. Surfaced by `get_diagnostics` alongside parse
  // diagnostics so consumers reading `Parser::diagnostics()` (or
  // `ImperativeParser::diagnostics()`) don't silently miss lex failures
  // when `syntax_tree()` is `None`. Cleared at the top of every
  // full_parse / incremental_parse call so the success path reports
  // only structural diagnostics.
  let lex_error_msg : Ref[String?] = Ref::new(None)
  // Persistent old-token cache: survives across edits so collect_old_tokens
  // only runs once (on first incremental parse). Subsequent edits reuse the
  // cached flat token array via ensure_old_tokens → immediate cache hit.
  // Reset to empty on full_parse (new tree, old cache invalid).
  let old_token_cache : Ref[@core.OldTokenCache] = Ref::new(
    @core.OldTokenCache::empty(),
  )
  @incremental.ImperativeLanguage::new(
    full_parse=source => {
      lex_error_msg.val = None
      let buffer = create_buffer(
        source,
        tokenize,
        spec.eof_token,
        error_token,
        prefix_lexer~,
        mode_relex~,
      ) catch {
        @core.LexError(msg) => {
          token_buf.val = None
          last_diags.val = []
          let formatted = "Tokenization error: " + msg
          lex_error_msg.val = Some(formatted)
          return @incremental.ParseOutcome::LexError(formatted)
        }
      }
      token_buf.val = Some(buffer)
      let (cst, diagnostics, _) = @core.parse_tokens_indexed(
        source,
        buffer.token_count(),
        fn(i) { buffer.get_token(i) },
        fn(i) { buffer.get_start(i) },
        fn(i) { buffer.get_end(i) },
        spec,
      )
      last_diags.val = diagnostics
      let syntax = @seam.SyntaxNode::from_cst(cst)
      old_token_cache.val = @core.OldTokenCache::empty() // new tree — old cache invalid
      @incremental.ParseOutcome::Tree(syntax, 0)
    },
    incremental_parse=(source, old_syntax, edit) => {
      lex_error_msg.val = None
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
              tokenize,
              spec,
              block_spec,
              last_diags.val,
            ) {
            Some((new_cst, new_diagnostics)) => {
              last_diags.val = new_diagnostics
              token_buf.val = None // Invalidate for next potential fallback
              return @incremental.ParseOutcome::Tree(
                @seam.SyntaxNode::from_cst(new_cst),
                1,
              )
            }
            None => () // Fall through to normal incremental
          }
        None => ()
      }
      // Ensure buffer is up to date (updated or newly created).
      match token_buf.val {
        Some(buffer) =>
          buffer.update(edit, source) catch {
            @core.LexError(msg) => {
              let rebuilt = create_buffer(
                source,
                tokenize,
                spec.eof_token,
                error_token,
                prefix_lexer~,
                mode_relex~,
              ) catch {
                @core.LexError(msg2) => {
                  token_buf.val = None
                  last_diags.val = []
                  let formatted = "Tokenization error: " + msg2
                  lex_error_msg.val = Some(formatted)
                  return @incremental.ParseOutcome::LexError(formatted)
                }
              }
              ignore(msg)
              token_buf.val = Some(rebuilt)
            }
          }
        None => {
          let buffer = create_buffer(
            source,
            tokenize,
            spec.eof_token,
            error_token,
            prefix_lexer~,
            mode_relex~,
          ) catch {
            @core.LexError(msg) => {
              last_diags.val = []
              let formatted = "Tokenization error: " + msg
              lex_error_msg.val = Some(formatted)
              return @incremental.ParseOutcome::LexError(formatted)
            }
          }
          token_buf.val = Some(buffer)
        }
      }
      // Buffer is always Some after the match above.
      let buffer = token_buf.val.unwrap()
      // Patch the persistent old-token cache: remove tokens in the old damage
      // range and accumulate offset delta for post-damage lookups.
      old_token_cache.val.apply_edit(edit.start, edit.old_end(), edit.new_end())
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          edit.start,
          edit.old_end(),
          buffer.token_count(),
          fn(i) { buffer.get_token(i) },
          fn(i) { buffer.get_start(i) },
          fn(i) { buffer.get_view(i) },
          spec,
          reuse_size_threshold=spec.reuse_size_threshold,
          old_token_cache=old_token_cache.val,
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
        prev_diagnostics=Some(last_diags.val),
      )
      last_diags.val = diagnostics
      let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
      @incremental.ParseOutcome::Tree(new_syntax, reuse_count)
    },
    to_ast=fn(syntax) { cst_fold.fold(syntax) },
    on_lex_error=grammar.on_lex_error,
    get_diagnostics=fn() {
      let formatted = last_diags.val.map(@core.format_diagnostic)
      match lex_error_msg.val {
        Some(m) => {
          formatted.push(m)
          formatted
        }
        None => formatted
      }
    },
    get_fold_stats=Some(fn() { cst_fold.get_stats() }),
  )
}

///|
/// Create an ImperativeParser from a Grammar.
///
/// Each call creates fresh internal state (TokenBuffer, diagnostics).
/// Interners (token deduplication, node deduplication) are process-global and
/// shared across all parsers — accumulated, never cleared, not parser-isolated.
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast] new_imperative_parser(
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
/// `@incr.Memo` views — see `Parser` in `loom/src/pipeline/` for the
/// reactive surface.
///
/// Pass `runtime~` to join an existing reactive graph (useful when downstream
/// memos need to share the same `Runtime` as the parser). Omitting it creates
/// a fresh runtime owned by the returned parser.
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast : Eq] new_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
  runtime? : @incr.Runtime,
) -> @pipeline.Parser[Ast] {
  @pipeline.Parser::new(source, build_imperative_language(grammar), runtime?)
}
