///|
enum ParityToken {
  Int
  EOF
} derive(Eq, @debug.Debug)

///|
impl Show for ParityToken with fn output(self, logger) {
  logger.write_string(
    match self {
      Int => "Int"
      EOF => "EOF"
    },
  )
}

///|
impl @seam.IsTrivia for ParityToken with fn is_trivia(_self) {
  false
}

///|
impl @seam.IsEof for ParityToken with fn is_eof(self) {
  self == ParityToken::EOF
}

///|
impl @seam.ToRawKind for ParityToken with fn to_raw(self) {
  match self {
    Int => @seam.RawKind(1)
    EOF => @seam.RawKind(0)
  }
}

///|
enum ParityKind {
  Root
  IntToken
  Error
  Incomplete
} derive(Eq, @debug.Debug)

///|
impl @seam.ToRawKind for ParityKind with fn to_raw(self) {
  match self {
    Root => @seam.RawKind(10)
    IntToken => @seam.RawKind(11)
    Error => @seam.RawKind(12)
    Incomplete => @seam.RawKind(13)
  }
}

///|
fn tok(t : ParityToken) -> @core.TokenInfo[ParityToken] {
  @core.TokenInfo::new(t, if t == ParityToken::EOF { 0 } else { 1 })
}

///|
fn simple_ir() -> @grammar.GrammarIr[ParityToken, ParityKind] {
  let rules : Map[String, @grammar.Expr[ParityToken, ParityKind]] = {
    "source": @grammar.Expr::Node(
      ParityKind::Root,
      @grammar.Expr::Emit(ParityToken::Int, ParityKind::IntToken),
    ),
  }
  @grammar.GrammarIr::GrammarIr(rules, root="source")
}

///|
fn parity_spec(
  parse : (@core.ParserContext[ParityToken, ParityKind]) -> Unit,
) -> @core.LanguageSpec[ParityToken, ParityKind] {
  @core.LanguageSpec::new(
    ParityKind::Root,
    ParityKind::Error,
    ParityKind::Root,
    ParityToken::EOF,
    incomplete_kind=ParityKind::Incomplete,
    parse_root=parse,
  )
}
