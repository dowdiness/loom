///|
/// Token type consumed by Loom.
///
/// Official `@tokens.Token` values carry payloads that are not currently `Eq`,
/// so this skeleton stores the stable official `TokenKind` only. Payload-aware
/// parsing can be added later without changing the lexer adapter boundary.
pub(all) enum MoonToken {
  Official(kind~ : @tokens.TokenKind)
  Whitespace
  Error(String)
  EOF
} derive(Eq, Debug)

///|
pub impl Show for MoonToken with fn output(self, logger) {
  match self {
    Official(kind~) => {
      logger.write_string(kind.to_string())
      logger.write_string("/")
      logger.write_string(MoonbitSyntaxKind::from_token_kind(kind).to_string())
    }
    Whitespace => logger.write_string("Whitespace")
    Error(message) => logger.write_string("error: " + message)
    EOF => logger.write_string("EOF")
  }
}

///|
pub impl @seam.IsTrivia for MoonToken with fn is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for MoonToken with fn is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for MoonToken with fn to_raw(self) {
  match self {
    Official(kind~) => MoonbitSyntaxKind::from_token_kind(kind).to_raw()
    Whitespace => TriviaToken.to_raw()
    Error(_) => ErrorToken.to_raw()
    EOF => EofToken.to_raw()
  }
}

///|
fn MoonToken::syntax_kind(self : MoonToken) -> MoonbitSyntaxKind {
  match self {
    Official(kind~) => MoonbitSyntaxKind::from_token_kind(kind)
    Whitespace => TriviaToken
    Error(_) => ErrorToken
    EOF => EofToken
  }
}

///|
fn MoonToken::is_layout_token(self : MoonToken) -> Bool {
  match self {
    Official(kind~) =>
      match kind {
        TK_NEWLINE | TK_COMMENT => true
        _ => false
      }
    _ => false
  }
}

///|
fn MoonToken::is_item_delimiter(self : MoonToken) -> Bool {
  match self {
    Official(kind=TK_SEMI) => true
    EOF => true
    _ => false
  }
}

///|
fn MoonToken::starts_item_body(
  self : MoonToken,
  item_kind : MoonbitSyntaxKind,
) -> Bool {
  match (item_kind, self) {
    (FunctionItemNode | StructItemNode | EnumItemNode, Official(kind=TK_LBRACE)) =>
      true
    (StructItemNode, Official(kind=TK_LPAREN)) => true
    (LetItemNode | FunctionItemNode | TypeItemNode, Official(kind=TK_EQUAL)) =>
      true
    _ => false
  }
}

///|
fn MoonToken::starts_legacy_type_body(
  self : MoonToken,
  type_name_seen : Bool,
) -> Bool {
  match (type_name_seen, self) {
    (true, Official(kind~)) =>
      match kind {
        TK_LBRACKET | TK_COMMENT | TK_NEWLINE => false
        _ => true
      }
    _ => false
  }
}

///|
fn MoonToken::is_type_item_keyword(self : MoonToken) -> Bool {
  match self {
    Official(kind=TK_TYPE | TK_TYPEALIAS) => true
    _ => false
  }
}

///|
fn MoonToken::is_type_header_name(self : MoonToken) -> Bool {
  match self {
    Official(kind=TK_UIDENT | TK_LIDENT) => true
    _ => false
  }
}

///|
fn MoonToken::source_item_node_kind(self : MoonToken) -> MoonbitSyntaxKind? {
  match self {
    Official(kind~) =>
      match kind {
        TK_LET | TK_LETREC | TK_CONST => Some(LetItemNode)
        TK_FN | TK_FNALIAS => Some(FunctionItemNode)
        TK_STRUCT => Some(StructItemNode)
        TK_ENUM | TK_EXTENUM | TK_ENUMVIEW => Some(EnumItemNode)
        TK_TYPE | TK_TYPEALIAS => Some(TypeItemNode)
        _ => None
      }
    _ => None
  }
}

///|
fn MoonToken::is_source_item_prefix(self : MoonToken) -> Bool {
  match self {
    Official(kind=TK_ATTRIBUTE) => true
    Official(kind~) =>
      match kind {
        TK_PUB | TK_PRIV | TK_EXTERN | TK_ASYNC | TK_DECLARE => true
        _ => false
      }
    _ => false
  }
}

///|
fn MoonToken::accepts_source_item_prefix_group_payload(
  self : MoonToken,
) -> Bool {
  match self {
    Official(kind=TK_PUB) => true
    _ => false
  }
}

///|
fn MoonToken::accepts_source_item_prefix_literal_payload(
  self : MoonToken,
) -> Bool {
  match self {
    Official(kind=TK_EXTERN) => true
    _ => false
  }
}

///|
fn MoonToken::is_source_item_prefix_literal_payload(self : MoonToken) -> Bool {
  match self {
    Official(kind~) =>
      match kind {
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
        | TK_TRUE => true
        _ => false
      }
    _ => false
  }
}

///|
fn MoonToken::opens_balanced_group(self : MoonToken) -> Bool {
  match self {
    Official(kind~) =>
      match kind {
        TK_LPAREN | TK_LBRACKET | TK_LBRACE => true
        _ => false
      }
    _ => false
  }
}

///|
fn MoonToken::closes_balanced_group(self : MoonToken) -> Bool {
  match self {
    Official(kind~) =>
      match kind {
        TK_RPAREN | TK_RBRACKET | TK_RBRACE => true
        _ => false
      }
    _ => false
  }
}

///|
fn MoonToken::next_group_depth(self : MoonToken, depth : Int) -> Int {
  if self.opens_balanced_group() {
    depth + 1
  } else if self.closes_balanced_group() && depth > 0 {
    depth - 1
  } else {
    depth
  }
}

///|
fn MoonToken::from_official(token : @tokens.Token) -> MoonToken {
  match token.kind() {
    TK_EOF => EOF
    kind => Official(kind~)
  }
}
