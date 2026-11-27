///|
#derive(Eq, Debug)
pub(all) enum MarkdownLexMode {
  LineStart
  BlockQuoteLineStart
  Inline
  CodeBlock(Int32, Char)
  QuotedCodeBlock(Int32, Char)
  HtmlBlockRaw
  HtmlBlockUntil(String)
  HtmlBlockEndLine
}

///|
pub extend MarkdownLexMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MarkdownLexMode with Eq::{equal, not_equal}

///|
/// Inline and quote-continuation tokens depend on the whole physical line:
/// same-line list prefixes decide whether a later `*`, `>`, fence, or HTML
/// opening starts a nested block. Incremental re-lexing therefore restarts and
/// converges only at modes that do not read their line's surroundings.
fn markdown_lex_mode_is_resumable(mode : MarkdownLexMode) -> Bool {
  match mode {
    Inline | BlockQuoteLineStart => false
    _ => true
  }
}
