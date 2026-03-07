///|
enum FTok {
  A
  Err
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
fn fstep_lexer(source : String, start : Int) -> @core.LexStep[FTok] {
  if start >= source.length() {
    return Done
  }
  if source.code_unit_at(start).to_int() == 97 {
    return Produced(
      @core.TokenInfo::new(A, start, start + 1),
      next_offset=start + 1,
    )
  }
  Invalid(at=start, width=1, message="unexpected char")
}

///|
fn frender_tokens(tokens : Array[@core.TokenInfo[FTok]]) -> String {
  tokens
  .map(t => {
    t.token.to_string() + "@" + t.start.to_string() + "-" + t.end.to_string()
  })
  .join(",")
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
fn fgrammar(
  error_token? : FTok? = None,
  prefix_lexer? : @core.PrefixLexer[FTok]? = None,
) -> Grammar[FTok, FKind, @seam.SyntaxNode] {
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
  Grammar::new(
    spec~,
    tokenize=ftokenize,
    to_ast=fn(s) { s },
    on_lex_error=fn(_msg) {
      let cst = @seam.CstNode::new(fkind_raw(KErr), [])
      @seam.SyntaxNode::from_cst(cst)
    },
    error_token~,
    prefix_lexer~,
  )
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

///|
test "create_buffer: prefix_lexer + error_token uses explicit error token" {
  let lexer = @core.PrefixLexer::new(lex_step=fstep_lexer)
  let buffer = create_buffer(
    "a!a",
    ftokenize,
    Eof,
    Some(Err),
    prefix_lexer=Some(lexer),
  )
  let rendered = frender_tokens(buffer.get_tokens())
  inspect(rendered, content="A@0-1,Err@1-2,A@2-3,Eof@3-3")
}

///|
test "new_imperative_parser: step-based path reuse matches full reparse" {
  let grammar = fgrammar(
    error_token=Some(Err),
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=fstep_lexer)),
  )
  let parser = new_imperative_parser("aaaaa", grammar)
  let _ = parser.parse()
  let incr = parser.edit(@core.Edit::delete(2, 3), "aaaa")
  // Verify reuse occurred
  inspect(parser.get_last_reuse_count() > 0, content="true")
  // Verify incremental result matches full reparse
  let full_parser = new_imperative_parser("aaaa", grammar)
  let full = full_parser.parse()
  inspect(
    @core.tree_diff(incr.cst_node(), full.cst_node()).length(),
    content="0",
  )
}

///|
test "create_buffer: prefix_lexer without error_token raises on invalid step" {
  let lexer = @core.PrefixLexer::new(lex_step=fstep_lexer)
  let raised = try {
    ignore(create_buffer("a!a", ftokenize, Eof, None, prefix_lexer=Some(lexer)))
    false
  } catch {
    @core.LexError(_) => true
  }
  inspect(raised, content="true")
}
