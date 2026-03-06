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
  let to_ast = grammar.to_ast
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[T]]] = Ref::new([])
  let lang = @incremental.ImperativeLanguage::new(
    full_parse=source => {
      let buffer = match error_token {
        Some(err_tok) =>
          @core.TokenBuffer::new_resilient(
            source,
            tokenize_fn=tokenize,
            eof_token=spec.eof_token,
            error_token=err_tok,
          )
        None =>
          @core.TokenBuffer::new(
            source,
            tokenize_fn=tokenize,
            eof_token=spec.eof_token,
          ) catch {
            @core.LexError(msg) => {
              token_buf.val = None
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
          }
      }
      token_buf.val = Some(buffer)
      let tokens = buffer.get_tokens()
      let (cst, diagnostics, _) = @core.parse_tokens_indexed(
        source,
        tokens.length(),
        fn(i) { tokens[i].token },
        fn(i) { tokens[i].start },
        fn(i) { tokens[i].end },
        spec,
      )
      last_diags.val = diagnostics
      let syntax = @seam.SyntaxNode::from_cst(cst)
      @incremental.ParseOutcome::Tree(syntax, 0)
    },
    incremental_parse=(source, old_syntax, edit) => {
      let tokens = match token_buf.val {
        Some(buffer) =>
          match error_token {
            Some(err_tok) =>
              buffer.update(edit, source) catch {
                @core.LexError(_) => {
                  let rebuilt = @core.TokenBuffer::new_resilient(
                    source,
                    tokenize_fn=tokenize,
                    eof_token=spec.eof_token,
                    error_token=err_tok,
                  )
                  token_buf.val = Some(rebuilt)
                  rebuilt.get_tokens()
                }
              }
            None =>
              buffer.update(edit, source) catch {
                @core.LexError(msg) => {
                  token_buf.val = None
                  last_diags.val = []
                  return @incremental.ParseOutcome::LexError(
                    "Tokenization error: " + msg,
                  )
                }
              }
          }
        None =>
          match error_token {
            Some(err_tok) => {
              let buffer = @core.TokenBuffer::new_resilient(
                source,
                tokenize_fn=tokenize,
                eof_token=spec.eof_token,
                error_token=err_tok,
              )
              token_buf.val = Some(buffer)
              buffer.get_tokens()
            }
            None =>
              try {
                let buffer = @core.TokenBuffer::new(
                  source,
                  tokenize_fn=tokenize,
                  eof_token=spec.eof_token,
                )
                token_buf.val = Some(buffer)
                buffer.get_tokens()
              } catch {
                @core.LexError(msg) => {
                  last_diags.val = []
                  return @incremental.ParseOutcome::LexError(
                    "Tokenization error: " + msg,
                  )
                }
              }
          }
      }
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          edit.start,
          edit.old_end(),
          tokens.length(),
          fn(i) { tokens[i].token },
          fn(i) { tokens[i].start },
          spec,
        ),
      )
      let (new_cst, diagnostics, reuse_count) = @core.parse_tokens_indexed(
        source,
        tokens.length(),
        fn(i) { tokens[i].token },
        fn(i) { tokens[i].start },
        fn(i) { tokens[i].end },
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
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind, Ast : Eq] new_reactive_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ReactiveParser[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let error_token = grammar.error_token
  let to_ast = grammar.to_ast
  let lang : @pipeline.Language[Ast] = @pipeline.Language::from_closures(
    parse_source=fn(s) {
      match error_token {
        Some(err_tok) => {
          let buffer = @core.TokenBuffer::new_resilient(
            s,
            tokenize_fn=tokenize,
            eof_token=spec.eof_token,
            error_token=err_tok,
          )
          let tokens = buffer.get_tokens()
          let (cst, diags, _) = @core.parse_tokens_indexed(
            s,
            tokens.length(),
            fn(i) { tokens[i].token },
            fn(i) { tokens[i].start },
            fn(i) { tokens[i].end },
            spec,
          )
          @pipeline.CstStage::{
            cst,
            diagnostics: diags.map(@core.format_diagnostic),
            is_lex_error: false,
          }
        }
        None =>
          try tokenize(s) catch {
            @core.LexError(msg) => {
              // cst is never read when is_lex_error=true (ReactiveParser routes
              // to on_lex_error); use a cheap error-kind placeholder.
              let cst = @seam.CstNode::new(spec.error_kind.to_raw(), [])
              @pipeline.CstStage::{
                cst,
                diagnostics: ["tokenization: " + msg],
                is_lex_error: true,
              }
            }
          } noraise {
            tokens => {
              let (cst, diags, _) = @core.parse_tokens_indexed(
                s,
                tokens.length(),
                fn(i) { tokens[i].token },
                fn(i) { tokens[i].start },
                fn(i) { tokens[i].end },
                spec,
              )
              @pipeline.CstStage::{
                cst,
                diagnostics: diags.map(@core.format_diagnostic),
                is_lex_error: false,
              }
            }
          }
      }
    },
    to_ast~,
    on_lex_error=grammar.on_lex_error,
  )
  @pipeline.ReactiveParser::new(source, lang)
}
