///|
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  ListItem(Array[Inline])
  CodeBlock(String, String)
  Error(String)
} derive(Show, Eq, Debug)

///|
pub(all) enum Inline {
  Text(String)
  Bold(Array[Inline])
  Italic(Array[Inline])
  InlineCode(String)
  Link(Array[Inline], String)
  Error(String)
} derive(Show, Eq, Debug)
