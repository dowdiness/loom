///|
/// Coarse token classes used by the skeleton parser.
///
/// `MoonToken` keeps the official `@tokens.TokenKind` alongside this class so
/// future work can refine the grammar without changing the lexer boundary.
pub(all) enum MoonTokenClass {
  Trivia
  Semicolon
  Identifier
  Literal
  Attribute
  Delimiter
  KeywordOrOperator
} derive(Eq, Debug)

///|
pub impl Show for MoonTokenClass with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Token type consumed by Loom.
///
/// Official `@tokens.Token` values carry payloads that are not currently `Eq`,
/// so this skeleton stores the stable official `TokenKind` plus a coarse class.
pub(all) enum MoonToken {
  Official(kind~ : @tokens.TokenKind, class~ : MoonTokenClass)
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for MoonToken with fn output(self, logger) {
  match self {
    Official(kind~, class~) => {
      logger.write_string(kind.to_string())
      logger.write_string("/")
      logger.write_string(class.to_string())
    }
    Whitespace => logger.write_string("Whitespace")
    Error(message) => logger.write_string("error: " + message)
    EOF => logger.write_string("EOF")
  }
}

///|
pub impl @seam.IsTrivia for MoonToken with fn is_trivia(self) {
  match self {
    Official(class=Trivia, ..) | Whitespace => true
    _ => false
  }
}

///|
pub impl @seam.IsEof for MoonToken with fn is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for MoonToken with fn to_raw(self) {
  match self {
    Official(class~, ..) => class.to_raw()
    Whitespace => Trivia.to_raw()
    Error(_) => ErrorToken.to_raw()
    EOF => EofToken.to_raw()
  }
}

///|
fn MoonTokenClass::to_syntax_kind(self : MoonTokenClass) -> MoonbitSyntaxKind {
  match self {
    Trivia => TriviaToken
    Semicolon => SemicolonToken
    Identifier => IdentifierToken
    Literal => LiteralToken
    Attribute => AttributeToken
    Delimiter => DelimiterToken
    KeywordOrOperator => KeywordOrOperatorToken
  }
}

///|
pub impl @seam.ToRawKind for MoonTokenClass with fn to_raw(self) {
  self.to_syntax_kind().to_raw()
}

///|
fn MoonToken::syntax_kind(self : MoonToken) -> MoonbitSyntaxKind {
  match self {
    Official(class~, ..) => class.to_syntax_kind()
    Whitespace => TriviaToken
    Error(_) => ErrorToken
    EOF => EofToken
  }
}

///|
fn MoonToken::is_item_delimiter(self : MoonToken) -> Bool {
  match self {
    Official(class=Semicolon, ..) => true
    EOF => true
    _ => false
  }
}

///|
fn MoonToken::from_official(token : @tokens.Token) -> MoonToken {
  match token.kind() {
    TK_EOF => EOF
    kind => Official(kind~, class=classify_official_token_kind(kind))
  }
}

///|
fn classify_official_token_kind(kind : @tokens.TokenKind) -> MoonTokenClass {
  match kind {
    TK_NEWLINE | TK_COMMENT => Trivia
    TK_SEMI => Semicolon
    TK_LIDENT
    | TK_UIDENT
    | TK_DOT_LIDENT
    | TK_DOT_UIDENT
    | TK_PACKAGE_NAME
    | TK_POST_LABEL => Identifier
    TK_CHAR
    | TK_INT
    | TK_BYTE
    | TK_BYTES
    | TK_FLOAT
    | TK_DOUBLE
    | TK_STRING
    | TK_MULTILINE_STRING
    | TK_MULTILINE_INTERP
    | TK_INTERP
    | TK_REGEX_LITERAL
    | TK_REGEX_INTERP
    | TK_DOT_INT
    | TK_FALSE
    | TK_TRUE => Literal
    TK_ATTRIBUTE => Attribute
    TK_LPAREN
    | TK_RPAREN
    | TK_LBRACKET
    | TK_RBRACKET
    | TK_LBRACE
    | TK_RBRACE
    | TK_COMMA
    | TK_COLON
    | TK_COLONCOLON
    | TK_DOT_LPAREN => Delimiter
    _ => KeywordOrOperator
  }
}
