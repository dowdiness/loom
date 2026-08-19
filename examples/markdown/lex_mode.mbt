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
