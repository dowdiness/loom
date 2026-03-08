///|
/// Language-agnostic Salsa-style incremental pipeline.
///
/// Two construction paths:
///
/// 1. `ReactiveParser::new(source, lang)` — two-memo pipeline:
///    Signal[String] → Memo[CstStage] → Memo[Ast]
///    `Language::parse_source` combines lex + parse in one step.
///
/// 2. `ReactiveParser::from_parts(signal, source_memo, cst_memo, term_memo)`:
///    Signal[String] → Memo[TokenStage[T]] → Memo[CstStage] → Memo[Ast]
///    Expert constructor used by `new_reactive_parser`. It validates that the
///    supplied cells form one coherent runtime graph.
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
/// Validates that all cells share a runtime and that the dependency chain is:
///   source_text → source_memo → cst_memo → term_memo
/// If `source_memo` and `cst_memo` are the same memo, the validated shape is:
///   source_text → cst_memo → term_memo
/// Validation is eager: the memos are computed once so their dependency edges
/// are established before the parser is returned.
pub fn[Stage : Eq, Ast : Eq] ReactiveParser::from_parts(
  source_text : @incr.Signal[String],
  source_memo : @incr.Memo[Stage],
  cst_memo : @incr.Memo[CstStage],
  term_memo : @incr.Memo[Ast],
) -> ReactiveParser[Ast] {
  let source_id = source_text.id()
  let source_memo_id = source_memo.id()
  let cst_id = cst_memo.id()
  let term_id = term_memo.id()
  if source_memo_id.runtime_id != source_id.runtime_id ||
    cst_id.runtime_id != source_id.runtime_id ||
    term_id.runtime_id != source_id.runtime_id {
    abort(
      "ReactiveParser::from_parts: source_text, source_memo, cst_memo, and term_memo must belong to the same runtime",
    )
  }
  ignore(source_memo.get())
  if not(source_memo.dependencies().contains(source_id)) {
    abort(
      "ReactiveParser::from_parts: source_memo must depend on source_text",
    )
  }
  ignore(cst_memo.get())
  if source_memo_id != cst_id &&
    not(cst_memo.dependencies().contains(source_memo_id)) {
    abort(
      "ReactiveParser::from_parts: cst_memo must depend on source_memo",
    )
  }
  ignore(term_memo.get())
  if not(term_memo.dependencies().contains(cst_id)) {
    abort(
      "ReactiveParser::from_parts: term_memo must depend on cst_memo",
    )
  }
  { source_text, cst_memo, term_memo }
}
