///|
pub(all) enum MarkdownLexMode {
  LineStart
  BlockQuoteLineStart
  Inline
  CodeBlock(Int)
} derive(Eq, Debug)
