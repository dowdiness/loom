///|
/// Language-agnostic Salsa-style incremental pipeline.
///
/// Two construction paths:
///
/// 1. `ReactiveParser::new(source, lang)` — two-memo pipeline:
///    Signal[String] → Memo[CstStage] → Memo[Ast]
///    `Language::parse_source` combines lex + parse in one step.
///
/// 2. `ReactiveParser::from_parts(signal, cst_memo, term_memo)` — three-memo:
///    Signal[String] → Memo[TokenStage[T]] → Memo[CstStage] → Memo[Ast]
///    Built by `new_reactive_parser` factory. The TokenStage memo enables
///    early cutoff when position-independent tokens are unchanged.
///
/// Lex-error routing: `CstStage::is_lex_error` is set explicitly by the
/// `Parseable` implementation, so `term_memo` dispatches to `on_lex_error`
/// without fragile heuristics.
///
/// **Lifetime:** one ReactiveParser per document editing session.
pub struct ReactiveParser[Ast] {
  priv source_text : @incr.Signal[String]
  priv cst_memo : @incr.Memo[CstStage]
  priv term_memo : @incr.Memo[Ast]
}

///|
/// Ast : Eq is required to call Memo::new (backdating needs structural equality).
pub fn[Ast : Eq] ReactiveParser::new(
  initial_source : String,
  lang : Language[Ast],
) -> ReactiveParser[Ast] {
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
pub fn[Ast] ReactiveParser::get_source(self : ReactiveParser[Ast]) -> String {
  self.source_text.get()
}

///|
/// Update the source text, invalidating the cst and term memos.
/// If the new source equals the current source (String::Eq), Signal::set
/// is a no-op and no recomputation occurs.
pub fn[Ast] ReactiveParser::set_source(
  self : ReactiveParser[Ast],
  source : String,
) -> Unit {
  self.source_text.set(source)
}

///|
/// Return the current CstStage (parse result + normalized diagnostics).
/// Triggers memo evaluation if the source has changed since last call.
pub fn[Ast] ReactiveParser::cst(self : ReactiveParser[Ast]) -> CstStage {
  self.cst_memo.get()
}

///|
/// Return normalized parse diagnostic strings.
/// On tokenization error this contains the tokenization message.
/// On parse error this contains position-annotated error strings.
pub fn[Ast] ReactiveParser::diagnostics(
  self : ReactiveParser[Ast],
) -> Array[String] {
  self.cst_memo.get().diagnostics.copy()
}

///|
/// Return the AST for the current source.
/// Backed by term_memo: on a warm call (no source change) the Runtime skips
/// recomputation and returns the cached Ast immediately.
pub fn[Ast : Eq] ReactiveParser::term(self : ReactiveParser[Ast]) -> Ast {
  self.term_memo.get()
}

///|
/// Construct a ReactiveParser from pre-built memos.
/// Used by factories that build the three-memo chain (token → cst → term)
/// externally for token-stage early cutoff.
pub fn[Ast] ReactiveParser::from_parts(
  source_text : @incr.Signal[String],
  cst_memo : @incr.Memo[CstStage],
  term_memo : @incr.Memo[Ast],
) -> ReactiveParser[Ast] {
  { source_text, cst_memo, term_memo }
}
