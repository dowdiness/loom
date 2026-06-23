///|
pub(all) enum MarkdownLexMode {
  LineStart
  BlockQuoteLineStart
  Inline
  CodeBlock(Int)
  HtmlBlockRaw
  HtmlBlockUntil(String)
  HtmlBlockEndLine
} derive(Eq, Debug)
