///|
pub(all) enum MarkdownLexMode {
  LineStart
  BlockQuoteLineStart
  Inline
  CodeBlock(Int, Char)
  QuotedCodeBlock(Int, Char)
  HtmlBlockRaw
  HtmlBlockUntil(String)
  HtmlBlockEndLine
} derive(Eq, Debug)

///|
pub extend MarkdownLexMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MarkdownLexMode with Eq::{equal, not_equal}
