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
  let to_ast = grammar.to_ast
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[T]]] = Ref::new([])
  let lang = @incremental.ImperativeLanguage::new(
    full_parse=source => {
      try {
        let buffer = @core.TokenBuffer::new(
          source,
          tokenize_fn=tokenize,
          eof_token=spec.eof_token,
        )
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
      } catch {
        @core.LexError(msg) => {
          token_buf.val = None
          last_diags.val = []
          @incremental.ParseOutcome::LexError("Tokenization error: " + msg)
        }
      }
    },
    incremental_parse=(source, old_syntax, edit) => {
      let tokens = match token_buf.val {
        Some(buffer) =>
          buffer.update(edit, source) catch {
            @core.LexError(msg) => {
              token_buf.val = None
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
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
      let damaged_range = @core.Range::new(edit.start, edit.new_end())
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,
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
  let to_ast = grammar.to_ast
  let lang : @pipeline.Language[Ast] = @pipeline.Language::from_closures(
    parse_source=fn(s) {
      try tokenize(s) catch {
        @core.LexError(msg) => {
          // cst is never read when is_lex_error=true (ReactiveParser routes to
          // on_lex_error); use a cheap error-kind placeholder instead of
          // running parse_tokens_indexed on empty input.
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
    },
    to_ast~,
    on_lex_error=grammar.on_lex_error,
  )
  @pipeline.ReactiveParser::new(source, lang)
}
