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
