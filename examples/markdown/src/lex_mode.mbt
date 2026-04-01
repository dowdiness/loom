///|
pub(all) enum MarkdownLexMode {
  LineStart
  Inline
  CodeBlock(Int)
} derive(Eq, Show)
