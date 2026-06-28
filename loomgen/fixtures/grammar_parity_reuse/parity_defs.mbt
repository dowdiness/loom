///|
enum ReuseToken {
  Int
  Skip
  EOF
} derive(Eq, @debug.Debug)

///|
impl Show for ReuseToken with fn output(self, logger) {
  logger.write_string(
    match self {
      Int => "Int"
      Skip => "Skip"
      EOF => "EOF"
    },
  )
}

///|
impl @seam.IsTrivia for ReuseToken with fn is_trivia(_self) {
  false
}

///|
impl @seam.IsEof for ReuseToken with fn is_eof(self) {
  self == ReuseToken::EOF
}

///|
impl @seam.ToRawKind for ReuseToken with fn to_raw(self) {
  match self {
    Int => @seam.RawKind(1)
    Skip => @seam.RawKind(2)
    EOF => @seam.RawKind(0)
  }
}

///|
enum ReuseKind {
  Root
  IntToken
  IntItem
  SkipKind
  Error
  Incomplete
} derive(Eq, @debug.Debug)

///|
impl @seam.ToRawKind for ReuseKind with fn to_raw(self) {
  match self {
    Root => @seam.RawKind(10)
    IntToken => @seam.RawKind(11)
    IntItem => @seam.RawKind(15)
    SkipKind => @seam.RawKind(14)
    Error => @seam.RawKind(12)
    Incomplete => @seam.RawKind(13)
  }
}

///|
fn repeat_ir() -> @grammar.GrammarIr[ReuseToken, ReuseKind] {
  let rules : Map[String, @grammar.Expr[ReuseToken, ReuseKind]] = {
    "source": @grammar.Expr::Node(
      ReuseKind::Root,
      @grammar.Expr::RepeatTopLevel(
        "item",
        starts=@grammar.Pred::IsToken(ReuseToken::Int),
        delim=@grammar.Pred::IsToken(ReuseToken::Skip),
        delim_kind=ReuseKind::SkipKind,
        between_msg="between",
        after_msg="after",
      ),
    ),
    "item": @grammar.Expr::Node(
      ReuseKind::IntItem,
      @grammar.Expr::Emit(ReuseToken::Int, ReuseKind::IntToken),
    ),
  }
  @grammar.GrammarIr::GrammarIr(rules, root="source")
}

///|
fn reuse_spec(
  parse : (@core.ParserContext[ReuseToken, ReuseKind]) -> Unit,
) -> @core.LanguageSpec[ReuseToken, ReuseKind] {
  @core.LanguageSpec::new(
    ReuseKind::Root,
    ReuseKind::Error,
    ReuseKind::Root,
    ReuseToken::EOF,
    incomplete_kind=ReuseKind::Incomplete,
    parse_root=parse,
    reuse_size_threshold=0,
  )
}

///|
fn repeat_tokens() -> Array[@core.TokenInfo[ReuseToken]] {
  [
    @core.TokenInfo::new(ReuseToken::Int, 1),
    @core.TokenInfo::new(ReuseToken::Skip, 1),
    @core.TokenInfo::new(ReuseToken::Int, 1),
    @core.TokenInfo::new(ReuseToken::EOF, 0),
  ]
}

///|
fn repeat_starts() -> Array[Int] {
  [0, 1, 2, 3]
}
