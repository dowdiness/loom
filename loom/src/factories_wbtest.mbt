///|
enum FTok {
  A
  Ws
  Err
  Eof
} derive(Eq, Debug)

///|
impl @seam.IsTrivia for FTok with is_trivia(self) {
  self == Ws
}

///|
impl @seam.IsEof for FTok with is_eof(self) {
  self == Eof
}

///|
impl @seam.ToRawKind for FTok with to_raw(self) {
  let n = match self {
    A => 0
    Ws => 3
    Err => 4
    Eof => 5
  }
  @seam.RawKind(n)
}

///|
enum FKind {
  KChar
  KExpr
  KRoot
  KWs
  KErr
} derive(Debug)

///|
enum FMode {
  FNormal
} derive(Eq)

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
fn ftokenize_requires_terminator(
  s : String,
) -> Array[@core.TokenInfo[FTok]] raise @core.LexError {
  if s.length() == 0 || s.code_unit_at(s.length() - 1).to_int() != 46 {
    raise @core.LexError("terminator required")
  }
  let tokens : Array[@core.TokenInfo[FTok]] = []
  let mut i = 0
  while i < s.length() {
    match s.code_unit_at(i).to_int() {
      97 => tokens.push(@core.TokenInfo::new(A, 1))
      46 => tokens.push(@core.TokenInfo::new(Ws, 1))
      _ => raise @core.LexError("unexpected char")
    }
    i = i + 1
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
fn fmode_step_lexer(
  source : String,
  start : Int,
  mode : FMode,
) -> (@core.LexStep[FTok], FMode) {
  if start >= source.length() {
    return (Done, mode)
  }
  if source.code_unit_at(start).to_int() == 33 {
    return (Invalid(at=start, width=1, message="bad mode"), mode)
  }
  (Produced(@core.TokenInfo::new(A, 1), next_offset=start + 1), mode)
}

///|
fn flex_from_tokenize(
  s : String,
  tokenize : (String) -> Array[@core.TokenInfo[FTok]] raise @core.LexError,
  error_token : FTok,
) -> @core.LexResult[FTok] {
  let result : Result[Array[@core.TokenInfo[FTok]], @core.LexError] = try? tokenize(
    s,
  )
  match result {
    Ok(tokens) => @core.LexResult(tokens)
    Err(@core.LexError(msg)) =>
      @core.LexResult(
        [
          @core.TokenInfo::new(error_token, s.length()),
          @core.TokenInfo::new(Eof, 0),
        ],
        diagnostics=@core.DiagnosticSet::single(
          @core.Diagnostic::lexer_error_at(msg, 0, s.length(), "lex-error"),
        ),
      )
  }
}

///|
fn flex(s : String) -> @core.LexResult[FTok] {
  flex_from_tokenize(s, ftokenize, Err)
}

///|
fn flex_recoverable_steps(s : String) -> @core.LexResult[FTok] {
  let buffer = @core.TokenBuffer::new_from_steps(
    s,
    @core.PrefixLexer::new(lex_step=fstep_lexer),
    eof_token=Eof,
    error_token=Err,
  )
  @core.LexResult::with_starts(
    buffer.get_tokens(),
    buffer.get_starts(),
    diagnostics=buffer.get_diagnostics(),
  )
}

///|
fn fbang_offset(source : String) -> Int? {
  for i = 0; i < source.length(); i = i + 1 {
    if source.code_unit_at(i).to_int() == 33 {
      return Some(i)
    }
  }
  None
}

///|
fn flex_late_error(s : String) -> @core.LexResult[FTok] {
  match fbang_offset(s) {
    Some(offset) =>
      @core.LexResult::with_starts(
        [@core.TokenInfo::new(Err, 1), @core.TokenInfo::new(Eof, 0)],
        [offset, s.length()],
        diagnostics=@core.DiagnosticSet::single(
          @core.Diagnostic::lexer_error_at(
            "unexpected char",
            offset,
            offset + 1,
            "lex-error",
          ),
        ),
      )
    None => flex_recoverable_steps(s)
  }
}

///|
fn frender_tokens(tokens : Array[@core.TokenInfo[FTok]]) -> String {
  let mut offset = 0
  tokens
  .map(t => {
    let start = offset
    let end = offset + t.len
    offset = end
    @debug.to_string(t.token) + "@" + start.to_string() + "-" + end.to_string()
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
fn fblock_root(ctx : @core.ParserContext[FTok, FKind]) -> Unit {
  ctx.node(KExpr, fn() {
    while !ctx.at_eof() {
      if ctx.at(A) {
        ctx.emit_token(KChar)
      } else {
        ctx.error("expected 'a'")
        if !ctx.at_eof() {
          ctx.bump_error()
        }
      }
    }
  })
}

///|
fn fgrammar() -> Grammar[FTok, FKind, @seam.SyntaxNode] {
  let spec = @core.LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    Eof,
    parse_root=froot,
    reuse_size_threshold=0,
  )
  Grammar::new(spec~, lex=flex, fold_node=fn(s, _recurse) { s })
}

///|
fn fterminator_grammar_with_tokenize(
  tokenize : (String) -> Array[@core.TokenInfo[FTok]] raise @core.LexError,
) -> Grammar[FTok, FKind, @seam.SyntaxNode] {
  let spec = @core.LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    Eof,
    parse_root=froot,
    reuse_size_threshold=0,
  )
  Grammar::new(
    spec~,
    lex=fn(s) { flex_from_tokenize(s, tokenize, Err) },
    fold_node=fn(s, _recurse) { s },
    incremental_relex_enabled=false,
  )
}

///|
fn frecoverable_root_reparse_grammar() -> Grammar[FTok, FKind, @seam.SyntaxNode] {
  let spec = @core.LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    Eof,
    parse_root=froot,
    reuse_size_threshold=0,
  )
  let root_kind = fkind_raw(KRoot)
  Grammar::new(
    spec~,
    lex=flex_recoverable_steps,
    fold_node=fn(s, _recurse) { s },
    incremental_relex_enabled=false,
    block_reparse_spec=Some({
      is_reparseable: fn(kind) { kind == root_kind },
      get_reparser: fn(kind) {
        if kind == root_kind {
          Some(froot)
        } else {
          None
        }
      },
      is_balanced: fn(_tokens) { true },
    }),
  )
}

///|
fn flate_error_root_reparse_grammar() -> Grammar[FTok, FKind, @seam.SyntaxNode] {
  let spec = @core.LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    Eof,
    parse_root=fblock_root,
    reuse_size_threshold=0,
  )
  let block_kind = fkind_raw(KExpr)
  Grammar::new(
    spec~,
    lex=flex_late_error,
    fold_node=fn(s, _recurse) { s },
    incremental_relex_enabled=false,
    block_reparse_spec=Some({
      is_reparseable: fn(kind) { kind == block_kind },
      get_reparser: fn(kind) {
        if kind == block_kind {
          Some(fblock_root)
        } else {
          None
        }
      },
      is_balanced: fn(_tokens) { true },
    }),
  )
}

///|
test "new_imperative_parser: uses old_end damage coordinates for shrink edits" {
  let grammar = fgrammar()
  let parser = new_imperative_parser("aaaaa", grammar)
  let _ = parser.parse()
  let incr = parser.edit(@core.Edit::delete(2, 3), "aaaa")
  // Pure deletion enables left-adjacent reuse: all four surviving one-token
  // KExpr nodes are reused.
  inspect(parser.get_last_reuse_count(), content="4")

  let full_parser = new_imperative_parser("aaaa", grammar)
  let full = full_parser.parse()
  inspect(
    @core.tree_diff(incr.syntax.cst_node(), full.syntax.cst_node()).length(),
    content="0",
  )
}

///|
test "create_buffer: total recoverable lex preserves error token diagnostics" {
  let buffer = create_buffer("a!a", flex_recoverable_steps, Eof)
  let rendered = frender_tokens(buffer.get_tokens())
  inspect(rendered, content="A@0-1,Err@1-2,A@2-3,Eof@3-3")
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"unexpected char [1,2]\"]",
  )
}

///|
test "create_buffer: clean total lex has no diagnostics" {
  let buffer = create_buffer("aaa", flex_recoverable_steps, Eof)
  let rendered = frender_tokens(buffer.get_tokens())
  inspect(rendered, content="A@0-1,A@1-2,A@2-3,Eof@3-3")
  debug_inspect(buffer.get_diagnostics().format(), content="[]")
}

///|
test "create_buffer: total lex keeps invalid message in diagnostics" {
  let buffer = create_buffer("a!a", flex_recoverable_steps, Eof)
  let rendered = frender_tokens(buffer.get_tokens())
  inspect(rendered, content="A@0-1,Err@1-2,A@2-3,Eof@3-3")
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"unexpected char [1,2]\"]",
  )
}

///|
test "new_imperative_parser: incremental path reuse matches full reparse" {
  let grammar = fgrammar()
  let parser = new_imperative_parser("aaaaa", grammar)
  let _ = parser.parse()
  let incr = parser.edit(@core.Edit::delete(2, 3), "aaaa")
  // Verify reuse occurred
  inspect(parser.get_last_reuse_count() > 0, content="true")
  // Verify incremental result matches full reparse
  let full_parser = new_imperative_parser("aaaa", grammar)
  let full = full_parser.parse()
  inspect(
    @core.tree_diff(incr.syntax.cst_node(), full.syntax.cst_node()).length(),
    content="0",
  )
}

///|
test "new_imperative_parser: full-only lex rebuild is not a diagnostic" {
  let saw_edit_full_lex = Ref(false)
  let grammar = fterminator_grammar_with_tokenize(s => {
    if s == "aaaaa." {
      saw_edit_full_lex.val = true
    }
    ftokenize_requires_terminator(s)
  })
  let parser = new_imperative_parser("aaaa.", grammar)
  ignore(parser.parse())
  ignore(parser.edit(@core.Edit::insert(1, 1), "aaaaa."))
  inspect(saw_edit_full_lex.val, content="true")
  debug_inspect(parser.diagnostics().format(), content="[]")
}

///|
test "new_imperative_parser: block reparse recomputes lexer diagnostics" {
  let grammar = frecoverable_root_reparse_grammar()
  let parser = new_imperative_parser("aaa", grammar)
  ignore(parser.parse())
  ignore(parser.edit(@core.Edit::new(1, 1, 1), "a!a"))
  inspect(parser.get_last_reuse_count(), content="1")
  let mut saw_lex_diagnostic = false
  for diagnostic in parser.diagnostics().format() {
    if diagnostic.contains("unexpected char") {
      saw_lex_diagnostic = true
    }
  }
  inspect(saw_lex_diagnostic, content="true")
}

///|
test "reparse_block preserves block lexer diagnostics" {
  let grammar = frecoverable_root_reparse_grammar()
  let parser = new_imperative_parser("aaa", grammar)
  let old_syntax = parser.parse()
  let block_spec = match grammar.block_reparse_spec {
    Some(spec) => spec
    None => abort("expected block reparse spec")
  }
  let lex = fn(source : String) -> @core.LexResult[FTok] {
    let result = flex_recoverable_steps(source)
    let diagnostics = result.diagnostics.copy()
    diagnostics.push(
      @core.Diagnostic::lexer_error_at(
        "block-only lexer diagnostic", 0, 1, "block-lex",
      ),
    )
    @core.LexResult::with_starts(result.tokens, result.starts, diagnostics~)
  }
  let result = @core.reparse_block(
    old_syntax.syntax,
    "a!a",
    @core.Edit::new(1, 1, 1),
    lex,
    grammar.spec,
    block_spec,
    @core.DiagnosticSet::empty(),
  )
  let diagnostics = match result {
    Some((_, diagnostics)) => diagnostics
    None => abort("expected block reparse result")
  }
  let mut saw_lex_diagnostic = false
  for diagnostic in diagnostics.format() {
    if diagnostic.contains("block-only lexer diagnostic") {
      saw_lex_diagnostic = true
    }
  }
  inspect(saw_lex_diagnostic, content="true")
}

///|
test "new_imperative_parser: block reparse preserves explicit LexResult starts" {
  let grammar = flate_error_root_reparse_grammar()
  let parser = new_imperative_parser("aaa", grammar)
  ignore(parser.parse())
  let incr = parser.edit(@core.Edit::insert(1, 1), "a!aa")
  inspect(parser.get_last_reuse_count(), content="1")
  let full_parser = new_imperative_parser("a!aa", grammar)
  let full = full_parser.parse()
  inspect(
    @core.tree_diff(incr.syntax.cst_node(), full.syntax.cst_node()).length(),
    content="0",
  )
}

///|
/// Lexer diagnostic preservation in `Parser::diagnostics()`.
///
/// Total high-level lexing should publish a tree plus diagnostics for malformed
/// input. Recovery on a subsequent clean source clears the lexer diagnostic.
test "new_parser: lexer diagnostic surfaces and clears on recovery" {
  let grammar = fgrammar()
  let parser = new_parser("!", grammar)
  let rt = parser.runtime()
  ignore(rt.read(parser.syntax_tree()))
  let diags = rt.read(parser.diagnostics())
  let mut saw_lex_diagnostic = false
  for diagnostic in diags.format() {
    if diagnostic.contains("unexpected char") {
      saw_lex_diagnostic = true
    }
  }
  inspect(saw_lex_diagnostic, content="true")
  parser.set_source("aaa")
  inspect(rt.read(parser.diagnostics()).length(), content="0")
  ignore(rt.read(parser.syntax_tree()))
}

///|
test "create_buffer: strict-wrapper total lex keeps diagnostic" {
  let buffer = create_buffer("a!a", flex, Eof)
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"unexpected char [0,3]\"]",
  )
}

///|
test "create_buffer: mode lex keeps total diagnostics" {
  let state = @core.erase_mode_lexer(
    @core.ModeLexer::{ lex_step: fmode_step_lexer, initial_mode: FNormal },
    Eof,
    error_token=Err,
  )
  let lex = fn(source : String) -> @core.LexResult[FTok] {
    let result = (state.tokenize)(source)
    let diagnostics = result.diagnostics()
    diagnostics.push(
      @core.Diagnostic::lexer_error_at("soft mode note", 0, 1, "lex-note"),
    )
    @core.LexResult::with_starts(result.tokens(), result.starts(), diagnostics~)
  }
  let buffer = create_buffer("a", lex, Eof, mode_relex=Some(state))
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"soft mode note [0,1]\"]",
  )
}

///|
test "create_buffer: mode update skips total lex on incremental path" {
  let state = @core.erase_mode_lexer(
    @core.ModeLexer::{ lex_step: fmode_step_lexer, initial_mode: FNormal },
    Eof,
    error_token=Err,
  )
  let lex_calls : Ref[Int] = Ref(0)
  let lex = fn(source : String) -> @core.LexResult[FTok] {
    lex_calls.val = lex_calls.val + 1
    let result = (state.tokenize)(source)
    let diagnostics = result.diagnostics()
    diagnostics.push(
      @core.Diagnostic::lexer_error_at(
        "mode source length " + source.length().to_string(),
        0,
        source.length(),
        "lex-note",
      ),
    )
    @core.LexResult::with_starts(result.tokens(), result.starts(), diagnostics~)
  }
  let buffer = create_buffer("a", lex, Eof, mode_relex=Some(state))
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"mode source length 1 [0,1]\"]",
  )
  inspect(lex_calls.val, content="1")
  buffer.update(@core.Edit::insert(1, 1), "aa")
  inspect(lex_calls.val, content="1")
  debug_inspect(buffer.get_token(0), content="A")
  debug_inspect(buffer.get_token(1), content="A")
  debug_inspect(buffer.get_token(2), content="Eof")
}

///|
test "create_buffer: mode lex respects incremental opt out" {
  let state = @core.erase_mode_lexer(
    @core.ModeLexer::{ lex_step: fmode_step_lexer, initial_mode: FNormal },
    Eof,
    error_token=Err,
  )
  let lex = fn(source : String) -> @core.LexResult[FTok] {
    (state.tokenize)(source)
  }
  let buffer = create_buffer(
    "a",
    lex,
    Eof,
    incremental_relex_enabled=false,
    mode_relex=Some(state),
  )
  let updated : Result[Unit, @core.LexError] = try? buffer.update(
    @core.Edit::insert(1, 1),
    "a!",
  )
  inspect(updated is Ok(_), content="true")
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"bad mode [1,2]\"]",
  )
  debug_inspect(buffer.get_token(0), content="A")
  debug_inspect(buffer.get_token(1), content="Err")
}

///|
test "create_buffer: recovered mode lex updates incrementally" {
  let state = @core.erase_mode_lexer(
    @core.ModeLexer::{ lex_step: fmode_step_lexer, initial_mode: FNormal },
    Eof,
    error_token=Err,
  )
  let lex = fn(source : String) -> @core.LexResult[FTok] {
    (state.tokenize)(source)
  }
  let buffer = create_buffer("!", lex, Eof, mode_relex=Some(state))
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"bad mode [0,1]\"]",
  )
  let updated : Result[Unit, @core.LexError] = try? buffer.update(
    @core.Edit::insert(1, 1),
    "!!",
  )
  inspect(updated is Ok(_), content="true")
  debug_inspect(
    buffer.get_diagnostics().format(),
    content="[\"bad mode [0,1]\", \"bad mode [1,2]\"]",
  )
  debug_inspect(buffer.get_token(0), content="Err")
  debug_inspect(buffer.get_token(1), content="Err")
}
