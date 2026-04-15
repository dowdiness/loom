///|
pub(all) enum SyntaxKind {
  LambdaToken
  DotToken
  LeftParenToken
  RightParenToken
  PlusToken
  MinusToken
  IfKeyword
  ThenKeyword
  ElseKeyword
  IdentToken
  IntToken
  WhitespaceToken
  ErrorToken
  EofToken
  LambdaExpr
  AppExpr
  BinaryExpr
  IfExpr
  ParenExpr
  IntLiteral
  VarRef
  ErrorNode
  SourceFile
  LetKeyword
  EqToken
  LetDef // NEW: top-level let x = e (no 'in')
  NewlineToken // NEW: \n token — delimiter between LetDefs in source-file grammar
  LBraceToken // {
  RBraceToken // }
  CommaToken // ,
  SemicolonToken // ;
  ParamList // ( Ident , Ident , ... )
  BlockExpr // { LetDef* Expression? }
  HoleToken // _
  HoleLiteral // _ (hole expression node)
  ColonToken // :    (raw 37)
  ArrowToken // ->   (raw 38)
  TypeAnnot // : Type  wrapper node (raw 39)
  TypeInt // Int type keyword (raw 40)
  TypeUnit // Unit type keyword (raw 41)
  TypeArrow // Type -> Type (raw 42)
} derive(Debug, Eq)

///|
pub impl Show for SyntaxKind with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    LambdaToken
    | DotToken
    | LeftParenToken
    | RightParenToken
    | PlusToken
    | MinusToken
    | IfKeyword
    | ThenKeyword
    | ElseKeyword
    | IdentToken
    | IntToken
    | WhitespaceToken
    | ErrorToken
    | EofToken
    | LetKeyword
    | EqToken
    | NewlineToken
    | LBraceToken
    | RBraceToken
    | CommaToken
    | SemicolonToken
    | HoleToken
    | ColonToken
    | ArrowToken => true
    _ => false
  }
}

///|
pub impl @seam.ToRawKind for SyntaxKind with to_raw(self) {
  let n : Int = match self {
    LambdaToken => 0
    DotToken => 1
    LeftParenToken => 2
    RightParenToken => 3
    PlusToken => 4
    MinusToken => 5
    IfKeyword => 6
    ThenKeyword => 7
    ElseKeyword => 8
    IdentToken => 9
    IntToken => 10
    WhitespaceToken => 11
    ErrorToken => 12
    EofToken => 13
    LambdaExpr => 14
    AppExpr => 15
    BinaryExpr => 16
    IfExpr => 17
    ParenExpr => 18
    IntLiteral => 19
    VarRef => 20
    ErrorNode => 21
    SourceFile => 22
    LetKeyword => 23
    EqToken => 25
    LetDef => 27
    NewlineToken => 28
    LBraceToken => 29
    RBraceToken => 30
    CommaToken => 31
    SemicolonToken => 32
    ParamList => 33
    BlockExpr => 34
    HoleToken => 35
    HoleLiteral => 36
    ColonToken => 37
    ArrowToken => 38
    TypeAnnot => 39
    TypeInt => 40
    TypeUnit => 41
    TypeArrow => 42
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for SyntaxKind with from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => LambdaToken
    1 => DotToken
    2 => LeftParenToken
    3 => RightParenToken
    4 => PlusToken
    5 => MinusToken
    6 => IfKeyword
    7 => ThenKeyword
    8 => ElseKeyword
    9 => IdentToken
    10 => IntToken
    11 => WhitespaceToken
    12 => ErrorToken
    13 => EofToken
    14 => LambdaExpr
    15 => AppExpr
    16 => BinaryExpr
    17 => IfExpr
    18 => ParenExpr
    19 => IntLiteral
    20 => VarRef
    21 => ErrorNode
    22 => SourceFile
    23 => LetKeyword
    25 => EqToken
    27 => LetDef
    28 => NewlineToken
    29 => LBraceToken
    30 => RBraceToken
    31 => CommaToken
    32 => SemicolonToken
    33 => ParamList
    34 => BlockExpr
    35 => HoleToken
    36 => HoleLiteral
    37 => ColonToken
    38 => ArrowToken
    39 => TypeAnnot
    40 => TypeInt
    41 => TypeUnit
    42 => TypeArrow
    _ => ErrorNode
  }
}

///|
pub impl @seam.IsTrivia for SyntaxKind with is_trivia(self) {
  self == WhitespaceToken
}

///|
pub impl @seam.IsError for SyntaxKind with is_error(self) {
  self == ErrorToken
}
