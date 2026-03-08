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
/// Precedence: prefix_lexer (step-based) > error_token (resilient) > plain.
fn[T] create_buffer(
  source : String,
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  eof_token : T,
  error_token : T?,
  prefix_lexer? : @core.PrefixLexer[T]? = None,
) -> @core.TokenBuffer[T] raise @core.LexError {
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
      @core.TokenBuffer::new_resilient(
        source,
        tokenize_fn=tokenize,
        eof_token~,
        error_token=err_tok,
      )
    (None, None) =>
      @core.TokenBuffer::new(source, tokenize_fn=tokenize, eof_token~)
  }
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
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let error_token = grammar.error_token
  let prefix_lexer = grammar.prefix_lexer
  let to_ast = grammar.to_ast
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[T]]] = Ref::new([])
  let lang = @incremental.ImperativeLanguage::new(
    full_parse=source => {
      let buffer = create_buffer(
        source,
        tokenize,
        spec.eof_token,
        error_token,
        prefix_lexer~,
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
      @incremental.ParseOutcome::Tree(syntax, 0)
    },
    incremental_parse=(source, old_syntax, edit) => {
      // Ensure buffer is up to date (updated or newly created).
      match token_buf.val {
        Some(buffer) => {
          let _ = buffer.update(edit, source) catch {
            @core.LexError(msg) => {
              let rebuilt = create_buffer(
                source,
                tokenize,
                spec.eof_token,
                error_token,
                prefix_lexer~,
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
              [] // dummy: value discarded by let _
            }
          }
        }
        None => {
          let buffer = create_buffer(
            source,
            tokenize,
            spec.eof_token,
            error_token,
            prefix_lexer~,
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
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          edit.start,
          edit.old_end(),
          buffer.token_count(),
          fn(i) { buffer.get_token(i) },
          fn(i) { buffer.get_start(i) },
          spec,
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
    to_ast~,
    on_lex_error=grammar.on_lex_error,
    get_diagnostics=fn() { last_diags.val.map(@core.format_diagnostic) },
  )
  @incremental.ImperativeParser::new(source, lang)
}

///|
/// Create a ReactiveParser from a Grammar.
///
/// Builds a three-memo pipeline:
///   Signal[String] → Memo[TokenStage[T]] → Memo[CstStage] → Memo[Ast]
///
/// TokenStage identity includes both tokens and source text so CST parsing
/// always reflects current source bytes.
pub fn[T : @seam.IsTrivia + Eq, K : @seam.ToRawKind, Ast : Eq] new_reactive_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ReactiveParser[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let error_token = grammar.error_token
  let prefix_lexer = grammar.prefix_lexer
  let to_ast = grammar.to_ast
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, source, label="source_text")
  // Token memo — token sequence + source text.
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
      ) catch {
        @core.LexError(msg) =>
          return {
            tokens: [],
            source: s,
            is_lex_error: true,
            lex_error_message: "Tokenization error: " + msg,
          }
      }
      {
        tokens: buffer.get_tokens(),
        source: s,
        is_lex_error: false,
        lex_error_message: "",
      }
    },
    label="tokens",
  )
  // CST memo — parses from token stage.
  // Depends ONLY on token_memo (not source_text directly).
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
      let source = stage.source
      let starts = @core.build_starts(tokens)
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
        to_ast(syntax)
      }
    },
    label="term",
  )
  @pipeline.ReactiveParser::from_parts(source_text, cst_memo, term_memo)
}
