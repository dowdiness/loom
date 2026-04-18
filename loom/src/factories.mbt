// Bridge factories — build ImperativeParser or ReactiveParser from a Grammar.
//
// These encapsulate all infrastructure wiring: TokenBuffer lifecycle,
// ReuseCursor construction, parse_tokens_indexed calls, diagnostic
// formatting. The grammar author provides spec, tokenize, to_ast, and
// on_lex_error; the factories handle the rest.
//
// ImperativeLanguage[Ast] and Language[Ast] are constructed internally
// for type erasure — grammar authors never see them.

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
  // Persistent old-token cache: survives across edits so collect_old_tokens
  // only runs once (on first incremental parse). Subsequent edits reuse the
  // cached flat token array via ensure_old_tokens → immediate cache hit.
  // Reset to empty on full_parse (new tree, old cache invalid).
  let old_token_cache : Ref[@core.OldTokenCache] = Ref::new(
    @core.OldTokenCache::empty(),
  )
  @incremental.ImperativeLanguage::new(
    full_parse=source => {
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
          return @incremental.ParseOutcome::LexError(
            "Tokenization error: " + msg,
          )
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
                  return @incremental.ParseOutcome::LexError(
                    "Tokenization error: " + msg2,
                  )
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
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
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
    get_diagnostics=fn() { last_diags.val.map(@core.format_diagnostic) },
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

///|
/// Create a ReactiveParser from a Grammar.
///
/// Builds a three-memo pipeline with trivia-insensitive early cutoff:
///   Signal[String] → Memo[TokenStage[T]] → Memo[CstStage] → Memo[Ast]
///
/// TokenStage equality compares only non-trivia tokens (via `IsTrivia`).
/// Whitespace-only edits cause the token memo to backdate, skipping
/// CST and AST recomputation entirely. Content edits that change any
/// non-trivia token trigger the full pipeline.
///
/// `T : Eq + IsTrivia` is required: token-stage memoization needs
/// structural equality for non-trivia tokens at the memo boundary.
pub fn[T : @seam.IsTrivia + Eq, K : @seam.ToRawKind, Ast : Eq] new_reactive_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ReactiveParser[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let error_token = grammar.error_token
  let prefix_lexer = grammar.prefix_lexer
  let mode_relex = grammar.mode_relex
  let cst_fold = @core.CstFold::new(grammar.fold_node)
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, source, label="source_text")
  // Token memo — stores full lex output (tokens + starts + source).
  // Equality compares only tokens + error state, NOT positions or source.
  // This enables early cutoff: edits that shift positions without changing
  // token kinds/content cause the memo to backdate.
  let token_memo : @incr.Memo[@core.TokenStage[T]] = @incr.Memo::new(
    rt,
    fn() -> @core.TokenStage[T] {
      let s = source_text.get()
      let buffer = create_buffer(
        s,
        tokenize,
        spec.eof_token,
        error_token,
        prefix_lexer~,
        mode_relex~,
      ) catch {
        @core.LexError(msg) =>
          return {
            tokens: [],
            starts: [],
            source: s,
            is_lex_error: true,
            lex_error_message: "Tokenization error: " + msg,
          }
      }
      {
        tokens: buffer.get_tokens(),
        starts: buffer.get_starts(),
        source: s,
        is_lex_error: false,
        lex_error_message: "",
      }
    },
    label="tokens",
  )
  // CST memo — parses from token stage.
  // Depends ONLY on token_memo (not source_text directly).
  // When token_memo backdates (tokens unchanged despite position shift),
  // CstStage skips entirely — this is the TokenStage early cutoff.
  let cst_memo : @incr.Memo[@pipeline.CstStage] = @incr.Memo::new(
    rt,
    fn() -> @pipeline.CstStage {
      let stage = token_memo.get()
      if stage.is_lex_error {
        let cst = @seam.CstNode::new(spec.error_kind.to_raw(), [])
        return @pipeline.CstStage::{
          cst,
          diagnostics: [stage.lex_error_message],
          is_lex_error: true,
        }
      }
      let tokens = stage.tokens
      let starts = stage.starts
      let source = stage.source
      let (cst, diags, _) = @core.parse_tokens_indexed(
        source,
        tokens.length(),
        fn(i) { tokens[i].token },
        fn(i) { starts[i] },
        fn(i) { starts[i] + tokens[i].len },
        spec,
      )
      @pipeline.CstStage::{
        cst,
        diagnostics: diags.map(@core.format_diagnostic),
        is_lex_error: false,
      }
    },
    label="cst",
  )
  // Term memo — converts CST to AST.
  let term_memo : @incr.Memo[Ast] = @incr.Memo::new(
    rt,
    fn() -> Ast {
      let stage = cst_memo.get()
      if stage.is_lex_error {
        let msg = if stage.diagnostics.length() > 0 {
          stage.diagnostics[0]
        } else {
          "lex error"
        }
        (grammar.on_lex_error)(msg)
      } else {
        let syntax = @seam.SyntaxNode::from_cst(stage.cst)
        cst_fold.fold(syntax)
      }
    },
    label="term",
  )
  @pipeline.ReactiveParser::from_parts(
    rt, source_text, token_memo, cst_memo, term_memo,
  )
}
