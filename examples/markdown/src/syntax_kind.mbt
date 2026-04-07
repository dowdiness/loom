///|
pub(all) enum SyntaxKind {
  // Token kinds
  HeadingMarkerToken
  ListMarkerToken
  CodeFenceOpenToken
  CodeFenceCloseToken
  BlankLineToken
  StarToken
  StarStarToken
  BacktickToken
  LeftBracketToken
  RightBracketToken
  LeftParenToken
  RightParenToken
  TextToken
  CodeTextToken
  NewlineToken
  ErrorToken
  EofToken
  // Node kinds
  DocumentNode
  HeadingNode
  ParagraphNode
  UnorderedListNode
  ListItemNode
  CodeBlockNode
  BoldNode
  ItalicNode
  InlineCodeNode
  LinkNode
  ErrorNode
} derive(Debug, Eq)

///|
pub impl Show for SyntaxKind with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    HeadingMarkerToken
    | ListMarkerToken
    | CodeFenceOpenToken
    | CodeFenceCloseToken
    | BlankLineToken
    | StarToken
    | StarStarToken
    | BacktickToken
    | LeftBracketToken
    | RightBracketToken
    | LeftParenToken
    | RightParenToken
    | TextToken
    | CodeTextToken
    | NewlineToken
    | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with to_raw(self) {
  @seam.RawKind(
    match self {
      HeadingMarkerToken => 0
      ListMarkerToken => 1
      CodeFenceOpenToken => 2
      CodeFenceCloseToken => 3
      BlankLineToken => 4
      StarToken => 5
      StarStarToken => 6
      BacktickToken => 7
      LeftBracketToken => 8
      RightBracketToken => 9
      LeftParenToken => 10
      RightParenToken => 11
      TextToken => 12
      CodeTextToken => 13
      NewlineToken => 14
      ErrorToken => 15
      EofToken => 16
      DocumentNode => 17
      HeadingNode => 18
      ParagraphNode => 19
      UnorderedListNode => 20
      ListItemNode => 21
      CodeBlockNode => 22
      BoldNode => 23
      ItalicNode => 24
      InlineCodeNode => 25
      LinkNode => 26
      ErrorNode => 27
    },
  )
}

///|
pub impl @seam.FromRawKind for SyntaxKind with from_raw(raw) {
  match raw.0 {
    0 => HeadingMarkerToken
    1 => ListMarkerToken
    2 => CodeFenceOpenToken
    3 => CodeFenceCloseToken
    4 => BlankLineToken
    5 => StarToken
    6 => StarStarToken
    7 => BacktickToken
    8 => LeftBracketToken
    9 => RightBracketToken
    10 => LeftParenToken
    11 => RightParenToken
    12 => TextToken
    13 => CodeTextToken
    14 => NewlineToken
    15 => ErrorToken
    16 => EofToken
    17 => DocumentNode
    18 => HeadingNode
    19 => ParagraphNode
    20 => UnorderedListNode
    21 => ListItemNode
    22 => CodeBlockNode
    23 => BoldNode
    24 => ItalicNode
    25 => InlineCodeNode
    26 => LinkNode
    27 => ErrorNode
    _ => ErrorNode
  }
}
