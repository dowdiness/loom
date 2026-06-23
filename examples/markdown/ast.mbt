///|
pub(all) enum Block {
  Document(Array[Block])
  Heading(Int, Array[Inline])
  Paragraph(Array[Inline])
  UnorderedList(Array[Block])
  OrderedList(Array[Block], OrderedListMarker?)
  UnorderedListItem(Array[Inline])
  OrderedListItem(Array[Inline], OrderedListMarker?)
  CodeBlock(String, String)
  HtmlBlock(String)
  Error(String)
} derive(Eq, Debug)

///|
pub impl Show for Block with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) enum Inline {
  Text(String)
  Bold(Array[Inline])
  Italic(Array[Inline])
  InlineCode(String)
  Link(Array[Inline], String)
  Error(String)
} derive(Eq, Debug)

///|
pub impl Show for Inline with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
