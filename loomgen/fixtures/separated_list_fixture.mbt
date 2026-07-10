/// Fixture for #604 SeparatedList {Sep} syntax.
/// Exercises one-or-more items separated by a delimiter, lowered to RepeatTopLevel.

///
#loom.token
pub(all) enum Tok {
  #loom.punct(",")
  Comma
  #loom.keyword("x")
  X
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum ListTerm {
  #loom.root
  #loom.rule("Item{Comma} Eof")
  Source
  #loom.leaf
  #loom.rule("X")
  Item
} derive(Eq, Debug)
