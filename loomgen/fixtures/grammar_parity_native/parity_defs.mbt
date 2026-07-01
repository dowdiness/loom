///|
enum NativeParityToken {
  Int
  EOF
} derive(Eq, @debug.Debug)

///|
impl Show for NativeParityToken with fn output(self, logger) {
  logger.write_string(
    match self {
      Int => "Int"
      EOF => "EOF"
    },
  )
}

///|
impl @seam.IsTrivia for NativeParityToken with fn is_trivia(_self) {
  false
}

///|
impl @seam.IsEof for NativeParityToken with fn is_eof(self) {
  self == NativeParityToken::EOF
}

///|
impl @seam.ToRawKind for NativeParityToken with fn to_raw(self) {
  match self {
    Int => @seam.RawKind(1)
    EOF => @seam.RawKind(0)
  }
}

///|
enum NativeParityKind {
  Root
  IntToken
  Error
  Incomplete
} derive(Eq, @debug.Debug)

///|
impl @seam.ToRawKind for NativeParityKind with fn to_raw(self) {
  match self {
    Root => @seam.RawKind(10)
    IntToken => @seam.RawKind(11)
    Error => @seam.RawKind(12)
    Incomplete => @seam.RawKind(13)
  }
}

///|
fn tok(t : NativeParityToken) -> @core.TokenInfo[NativeParityToken] {
  @core.TokenInfo::new(t, if t == NativeParityToken::EOF { 0 } else { 1 })
}

///|
/// A "delegate_to_inner" native stands in for a context-sensitive production
/// (e.g. HTML tag-stack matching) that must re-enter the declarative grammar
/// to parse a context-free sub-production — here, the `inner` rule.
fn native_ir() -> @grammar.GrammarIr[NativeParityToken, NativeParityKind] {
  let rules : Map[String, @grammar.Expr[NativeParityToken, NativeParityKind]] = {
    "source": @grammar.Expr::Node(
      NativeParityKind::Root,
      @grammar.Expr::Native("delegate_to_inner"),
    ),
    "inner": @grammar.Expr::Emit(
      NativeParityToken::Int,
      NativeParityKind::IntToken,
    ),
  }
  @grammar.GrammarIr::GrammarIr(rules, root="source")
}

///|
/// Interpreted-path registry: the native re-enters the grammar via
/// `call_rule`, mirroring what a hand-written HTML native would do to parse a
/// context-free sub-production (spec issue #541).
fn native_registry() -> Map[
  String,
  @grammar.NativeRule[NativeParityToken, NativeParityKind],
] {
  { "delegate_to_inner": (_ctx, call_rule) => call_rule("inner") }
}

///|
fn native_parity_spec(
  parse : (@core.ParserContext[NativeParityToken, NativeParityKind]) -> Unit,
) -> @core.LanguageSpec[NativeParityToken, NativeParityKind] {
  @core.LanguageSpec::new(
    NativeParityKind::Root,
    NativeParityKind::Error,
    NativeParityKind::Root,
    NativeParityToken::EOF,
    incomplete_kind=NativeParityKind::Incomplete,
    parse_root=parse,
  )
}
