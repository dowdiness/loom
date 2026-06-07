///|
/// Coarse CST kind space for the MoonBit parser skeleton.
///
/// The token kinds intentionally group many official token kinds together. The
/// CST still preserves source text for every token; later milestones can split
/// these into the full MoonBit syntax-kind table as grammar rules are ported.
pub(all) enum MoonbitSyntaxKind {
  // Token kinds
  TriviaToken
  SemicolonToken
  IdentifierToken
  LiteralToken
  AttributeToken
  DelimiterToken
  KeywordOrOperatorToken
  ErrorToken
  IncompleteToken
  EofToken
  // Node kinds
  SourceFileNode
  SourceItemNode
  LetItemNode
  FunctionItemNode
  StructItemNode
  EnumItemNode
  TypeItemNode
} derive(Eq, Debug)

///|
pub impl Show for MoonbitSyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @seam.ToRawKind for MoonbitSyntaxKind with fn to_raw(self) {
  RawKind(
    match self {
      TriviaToken => 0
      SemicolonToken => 1
      IdentifierToken => 2
      LiteralToken => 3
      AttributeToken => 4
      DelimiterToken => 5
      KeywordOrOperatorToken => 6
      ErrorToken => 7
      IncompleteToken => 8
      EofToken => 9
      SourceFileNode => 10
      SourceItemNode => 11
      LetItemNode => 12
      FunctionItemNode => 13
      StructItemNode => 14
      EnumItemNode => 15
      TypeItemNode => 16
    },
  )
}

///|
pub impl @seam.FromRawKind for MoonbitSyntaxKind with fn from_raw(raw) {
  match raw.0 {
    0 => TriviaToken
    1 => SemicolonToken
    2 => IdentifierToken
    3 => LiteralToken
    4 => AttributeToken
    5 => DelimiterToken
    6 => KeywordOrOperatorToken
    7 => ErrorToken
    8 => IncompleteToken
    9 => EofToken
    10 => SourceFileNode
    11 => SourceItemNode
    12 => LetItemNode
    13 => FunctionItemNode
    14 => StructItemNode
    15 => EnumItemNode
    16 => TypeItemNode
    _ => ErrorToken
  }
}
