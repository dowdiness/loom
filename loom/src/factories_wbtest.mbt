///|
enum FTok {
  A
  Eof
} derive(Eq, Show)

///|
impl @seam.IsTrivia for FTok with is_trivia(_) {
  false
}

///|
impl @seam.IsEof for FTok with is_eof(self) {
  self == Eof
}

///|
enum FKind {
  KChar
  KExpr
  KRoot
  KWs
  KErr
} derive(Show)

///|
fn fkind_raw(k : FKind) -> @seam.RawKind {
  let n = match k {
    KChar => 0
    KExpr => 1
    KRoot => 2
    KWs => 3
    KErr => 4
  }
  @seam.RawKind(n)
}

///|
impl @seam.ToRawKind for FKind with to_raw(self) {
  fkind_raw(self)
}

///|
fn ftokenize(s : String) -> Array[@core.TokenInfo[FTok]] raise @core.LexError {
  let tokens : Array[@core.TokenInfo[FTok]] = []
  let mut i = 0
  while i < s.length() {
    if s.code_unit_at(i).to_int() == 97 {
      tokens.push(@core.TokenInfo::new(A, i, i + 1))
      i = i + 1
    } else {
      raise @core.LexError("unexpected char")
    }
  }
  tokens.push(@core.TokenInfo::new(Eof, s.length(), s.length()))
  tokens
}

///|
fn froot(ctx : @core.ParserContext[FTok, FKind]) -> Unit {
  while not(ctx.at_eof()) {
    ctx.node(KExpr, fn() {
      if ctx.at(A) {
        ctx.emit_token(KChar)
      } else {
        ctx.error("expected 'a'")
        if not(ctx.at_eof()) {
          ctx.bump_error()
        }
      }
    })
  }
}

///|
fn fgrammar() -> Grammar[FTok, FKind, @seam.SyntaxNode] {
  let spec = @core.LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    Eof,
    cst_token_matches=fn(raw, _text, tok) {
      raw == fkind_raw(KChar) && tok == A
    },
    parse_root=froot,
  )
  Grammar::new(spec~, tokenize=ftokenize, to_ast=fn(s) { s }, on_lex_error=fn(
    _msg,
  ) {
    let cst = @seam.CstNode::new(fkind_raw(KErr), [])
    @seam.SyntaxNode::from_cst(cst)
  })
}

///|
test "new_imperative_parser: uses old_end damage coordinates for shrink edits" {
  let grammar = fgrammar()
  let parser = new_imperative_parser("aaaaa", grammar)
  let _ = parser.parse()
  let incr = parser.edit(@core.Edit::delete(2, 3), "aaaa")
  inspect(parser.get_last_reuse_count(), content="1")

  let full_parser = new_imperative_parser("aaaa", grammar)
  let full = full_parser.parse()
  inspect(
    @core.tree_diff(incr.cst_node(), full.cst_node()).length(),
    content="0",
  )
}
