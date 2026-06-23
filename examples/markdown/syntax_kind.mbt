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
  IndentedCodeTextToken
  NewlineToken
  ErrorToken
  EofToken
  OrderedListMarkerToken
  BlockQuoteMarkerToken
  ThematicBreakToken
  HtmlBlockOpenToken
  HtmlTextToken
  // Node kinds
  DocumentNode
  HeadingNode
  ParagraphNode
  UnorderedListNode
  OrderedListNode
  ListItemNode
  CodeBlockNode
  BoldNode
  ItalicNode
  InlineCodeNode
  LinkNode
  ErrorNode
  BlockQuoteNode
  ThematicBreakNode
  HtmlBlockNode
} derive(Debug, Eq)

///|
pub impl Show for SyntaxKind with fn output(self, logger) {
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
    | IndentedCodeTextToken
    | NewlineToken
    | ErrorToken
    | EofToken
    | OrderedListMarkerToken
    | BlockQuoteMarkerToken
    | ThematicBreakToken
    | HtmlBlockOpenToken
    | HtmlTextToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with fn to_raw(self) {
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
      IndentedCodeTextToken => 14
      NewlineToken => 15
      ErrorToken => 16
      EofToken => 17
      DocumentNode => 18
      HeadingNode => 19
      ParagraphNode => 20
      UnorderedListNode => 21
      ListItemNode => 22
      CodeBlockNode => 23
      BoldNode => 24
      ItalicNode => 25
      InlineCodeNode => 26
      LinkNode => 27
      ErrorNode => 28
      OrderedListMarkerToken => 29
      OrderedListNode => 30
      BlockQuoteMarkerToken => 31
      BlockQuoteNode => 32
      ThematicBreakToken => 33
      ThematicBreakNode => 34
      HtmlBlockOpenToken => 35
      HtmlTextToken => 36
      HtmlBlockNode => 37
    },
  )
}

///|
pub impl @seam.FromRawKind for SyntaxKind with fn from_raw(raw) {
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
    14 => IndentedCodeTextToken
    15 => NewlineToken
    16 => ErrorToken
    17 => EofToken
    18 => DocumentNode
    19 => HeadingNode
    20 => ParagraphNode
    21 => UnorderedListNode
    22 => ListItemNode
    23 => CodeBlockNode
    24 => BoldNode
    25 => ItalicNode
    26 => InlineCodeNode
    27 => LinkNode
    28 => ErrorNode
    29 => OrderedListMarkerToken
    30 => OrderedListNode
    31 => BlockQuoteMarkerToken
    32 => BlockQuoteNode
    33 => ThematicBreakToken
    34 => ThematicBreakNode
    35 => HtmlBlockOpenToken
    36 => HtmlTextToken
    37 => HtmlBlockNode
    _ => ErrorNode
  }
}
