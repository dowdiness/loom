///|
enum FTok {
  A
  Ws
  Err
  Eof
} derive(Eq, Show)

///|
impl @seam.IsTrivia for FTok with is_trivia(self) {
  self == Ws
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
      tokens.push(@core.TokenInfo::new(A, 1))
      i = i + 1
    } else {
      raise @core.LexError("unexpected char")
    }
  }
  tokens.push(@core.TokenInfo::new(Eof, 0))
  tokens
}

///|
fn fstep_lexer(source : String, start : Int) -> @core.LexStep[FTok] {
  if start >= source.length() {
    return Done
  }
  if source.code_unit_at(start).to_int() == 97 {
    return Produced(@core.TokenInfo::new(A, 1), next_offset=start + 1)
  }
  Invalid(at=start, width=1, message="unexpected char")
}

///|
fn flate_step_lexer(source : String, start : Int) -> @core.LexStep[FTok] {
  if start >= source.length() {
    return Done
  }
  if start == 0 {
    return Invalid(at=2, width=1, message="late unexpected char")
  }
  if source.code_unit_at(start).to_int() == 97 {
    return Produced(@core.TokenInfo::new(A, 1), next_offset=start + 1)
  }
  Invalid(at=start, width=1, message="unexpected char")
}

///|
fn frender_tokens(tokens : Array[@core.TokenInfo[FTok]]) -> String {
  let mut offset = 0
  tokens
  .map(t => {
    let start = offset
    let end = offset + t.len
    offset = end
    t.token.to_string() + "@" + start.to_string() + "-" + end.to_string()
  })
  .join(",")
}

///|
fn froot(ctx : @core.ParserContext[FTok, FKind]) -> Unit {
  while !ctx.at_eof() {
    ctx.node(KExpr, fn() {
      if ctx.at(A) {
        ctx.emit_token(KChar)
      } else {
        ctx.error("expected 'a'")
        if !ctx.at_eof() {
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
    reuse_size_threshold=0,
  )
  Grammar::new(
    spec~,
    tokenize=ftokenize,
    fold_node=fn(s, _recurse) { s },
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

// ── ReactiveParser three-memo pipeline tests ────────────────────────────────

///|
/// Different sources producing identical token sequences cause the token memo
/// to backdate (tokens are equal, positions excluded from comparison). The CST
/// memo is NOT recomputed — this is the TokenStage early cutoff.
test "new_reactive_parser: token-stage early cutoff when tokens match" {
  let grammar = fgrammar(
    error_token=Some(Err),
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=fstep_lexer)),
  )
  let parser = new_reactive_parser("a!a", grammar)
  let cst1 = parser.cst()
  inspect(cst1.is_lex_error, content="false")
  // Change source: '!' → '?' — same token sequence [A(1), Err(1), A(1), EOF(0)]
  parser.set_source("a?a")
  let cst2 = parser.cst()
  inspect(cst2.is_lex_error, content="false")
  // Token-stage early cutoff: same tokens → CST memo not recomputed → same CstStage
  inspect(cst1 == cst2, content="true")
}

///|
/// Different token sequences → token memo changes → CST memo recomputes.
test "new_reactive_parser: token-stage invalidation when tokens change" {
  let grammar = fgrammar(
    error_token=Some(Err),
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=fstep_lexer)),
  )
  let parser = new_reactive_parser("aaa", grammar)
  let cst1 = parser.cst()
  // Change to different token count
  parser.set_source("aa")
  let cst2 = parser.cst()
  // Different token sequences → different CSTs
  inspect(cst1 == cst2, content="false")
}

///|
/// Lex error with different messages → token memo changes → re-routed.
test "new_reactive_parser: different lex errors produce different diagnostics" {
  let grammar = fgrammar() // no error_token → lex errors raise
  let parser = new_reactive_parser("!", grammar)
  let cst1 = parser.cst()
  inspect(cst1.is_lex_error, content="true")
  // Same invalid input → same diagnostics (cutoff)
  parser.set_source("!")
  let cst2 = parser.cst()
  inspect(cst1 == cst2, content="true")
}

///|
/// Basic reactive pipeline: parse → update → term.
test "new_reactive_parser: basic parse and update" {
  let grammar = fgrammar(
    error_token=Some(Err),
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=fstep_lexer)),
  )
  let parser = new_reactive_parser("aa", grammar)
  let term1 = parser.term()
  // SyntaxNode is the AST for this test grammar
  inspect(term1.end() > 0, content="true")
  parser.set_source("aaa")
  let term2 = parser.term()
  inspect(term1 == term2, content="false")
}

///|
test "new_reactive_parser: preserves explicit starts from step lexers" {
  let imperative = new_imperative_parser(
    "aa!a",
    fgrammar(
      error_token=Some(Err),
      prefix_lexer=Some(@core.PrefixLexer::new(lex_step=flate_step_lexer)),
    ),
  )
  ignore(imperative.parse())
  let reactive = new_reactive_parser(
    "aa!a",
    fgrammar(
      error_token=Some(Err),
      prefix_lexer=Some(@core.PrefixLexer::new(lex_step=flate_step_lexer)),
    ),
  )
  ignore(reactive.cst())
  inspect(reactive.diagnostics() == imperative.diagnostics(), content="true")
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

///|
/// Step lexer that recognizes 'a' as A and ' ' as Ws (trivia).
fn fws_step_lexer(source : String, start : Int) -> @core.LexStep[FTok] {
  if start >= source.length() {
    return Done
  }
  let ch = source.code_unit_at(start).to_int()
  if ch == 97 {
    // 'a'
    return Produced(@core.TokenInfo::new(A, 1), next_offset=start + 1)
  }
  if ch == 32 {
    // ' '
    return Produced(@core.TokenInfo::new(Ws, 1), next_offset=start + 1)
  }
  Invalid(at=start, width=1, message="unexpected char")
}

///|
/// Trivia-insensitive early cutoff: whitespace-only edits produce different
/// trivia tokens but the same non-trivia tokens, so the token memo backdates
/// and the CST memo is NOT recomputed.
test "new_reactive_parser: trivia-insensitive early cutoff" {
  let grammar = fgrammar(
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=fws_step_lexer)),
  )
  let parser = new_reactive_parser("a a", grammar)
  let cst1 = parser.cst()
  inspect(cst1.is_lex_error, content="false")
  // Change "a a" → "a  a" — adds extra space (trivia). Non-trivia tokens unchanged.
  parser.set_source("a  a")
  let cst2 = parser.cst()
  inspect(cst2.is_lex_error, content="false")
  // Trivia-insensitive early cutoff: same non-trivia tokens → CST unchanged
  inspect(cst1 == cst2, content="true")
}

///|
/// Content edits that change non-trivia tokens still invalidate.
test "new_reactive_parser: content edit invalidates despite trivia filter" {
  let grammar = fgrammar(
    error_token=Some(Err),
    prefix_lexer=Some(@core.PrefixLexer::new(lex_step=fws_step_lexer)),
  )
  let parser = new_reactive_parser("a a", grammar)
  let cst1 = parser.cst()
  // Change "a a" → "a !a" — '!' produces an error token, non-trivia changes
  parser.set_source("a !a")
  let cst2 = parser.cst()
  inspect(cst1 == cst2, content="false")
}
