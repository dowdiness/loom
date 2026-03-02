///|
/// Language-agnostic Salsa-style incremental pipeline.
///
/// source_text : Signal[String]
///   → cst_memo  : Memo[CstStage]    (Language::parse_source combines lex + parse)
///   → term_memo : Memo[Ast]
///
/// Two memos vs the lambda-specific three-memo pipeline (Signal → TokenStage →
/// CstStage → Ast). `Language::parse_source` combines tokenize+parse internally,
/// losing the TokenStage backdating boundary. The CstStage hash-equality and
/// Ast structure-only equality boundaries remain effective.
///
/// Lex-error routing: `CstStage::is_lex_error` is set explicitly by the
/// `Parseable` implementation, so `term_memo` dispatches to `on_lex_error`
/// without fragile heuristics.
///
/// **Lifetime:** one ParserDb per document editing session.
pub struct ParserDb[Ast] {
  priv source_text : @incr.Signal[String]
  priv cst_memo : @incr.Memo[CstStage]
  priv term_memo : @incr.Memo[Ast]
}

///|
/// Ast : Eq is required to call Memo::new (backdating needs structural equality).
pub fn[Ast : Eq] ParserDb::new(
  initial_source : String,
  lang : Language[Ast],
) -> ParserDb[Ast] {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, initial_source, label="source_text")

  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { (lang.parse_source)(source_text.get()) },
    label="cst",
  )

  let term_memo = @incr.Memo::new(
    rt,
    fn() -> Ast {
      let stage = cst_memo.get()
      if stage.is_lex_error {
        // parse_source signalled a lex failure: route to on_lex_error with
        // the first diagnostic message (always present when is_lex_error = true).
        let msg = if stage.diagnostics.length() > 0 {
          stage.diagnostics[0]
        } else {
          "lex error"
        }
        (lang.on_lex_error)(msg)
      } else {
        let syntax = @seam.SyntaxNode::from_cst(stage.cst)
        (lang.to_ast)(syntax)
      }
    },
    label="term",
  )
  { source_text, cst_memo, term_memo }
}

///|
/// Return the current source text.
pub fn[Ast] ParserDb::get_source(self : ParserDb[Ast]) -> String {
  self.source_text.get()
}

///|
/// Update the source text, invalidating the cst and term memos.
/// If the new source equals the current source (String::Eq), Signal::set
/// is a no-op and no recomputation occurs.
pub fn[Ast] ParserDb::set_source(self : ParserDb[Ast], source : String) -> Unit {
  self.source_text.set(source)
}

///|
/// Return the current CstStage (parse result + normalized diagnostics).
/// Triggers memo evaluation if the source has changed since last call.
pub fn[Ast] ParserDb::cst(self : ParserDb[Ast]) -> CstStage {
  self.cst_memo.get()
}

///|
/// Return normalized parse diagnostic strings.
/// On tokenization error this contains the tokenization message.
/// On parse error this contains position-annotated error strings.
pub fn[Ast] ParserDb::diagnostics(self : ParserDb[Ast]) -> Array[String] {
  self.cst_memo.get().diagnostics.copy()
}

///|
/// Return the AST for the current source.
/// Backed by term_memo: on a warm call (no source change) the Runtime skips
/// recomputation and returns the cached Ast immediately.
pub fn[Ast : Eq] ParserDb::term(self : ParserDb[Ast]) -> Ast {
  self.term_memo.get()
}
