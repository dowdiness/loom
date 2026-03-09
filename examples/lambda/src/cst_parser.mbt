///|
const MAX_ERRORS : Int = 50

///|
/// Create a ReuseCursor from an old syntax tree and a pre-tokenized new stream.
pub fn make_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@token.TokenInfo[@token.Token]],
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  let starts = @core.build_starts(tokens)
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    lambda_spec,
  )
}

///|
/// Strict: raises ParseError on first syntax error (backward compat).
pub fn parse_cst(source : String) -> @seam.CstNode raise {
  let (cst, errors) = parse_cst_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, diag.got_token)
  }
  cst
}

///|
/// Recovering: returns tree with ErrorNodes + diagnostic list.
/// Only raises for LexError (unrecoverable).
pub fn parse_cst_recover(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let tokens = @lexer.tokenize(source)
  let starts = @core.build_starts(tokens)
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    lambda_spec,
  )
  (cst, diagnostics)
}

///|
/// Parse with reuse cursor for incremental parsing with subtree reuse.
pub fn parse_cst_with_cursor(
  source : String,
  tokens : Array[@token.TokenInfo[@token.Token]],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind],
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  let starts = @core.build_starts(tokens)
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    lambda_spec,
    cursor=Some(cursor),
    prev_diagnostics~,
  )
}

///|
/// Parse with pre-tokenized input and optional reuse cursor.
pub fn parse_cst_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo[@token.Token]],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  let starts = @core.build_starts(tokens)
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    lambda_spec,
    cursor~,
    prev_diagnostics~,
  )
}

// ─── Grammar helpers ──────────────────────────────────────────────────────────

///|
fn token_starts_expression(token : @token.Token) -> Bool {
  match token {
    @token.Let
    | @token.If
    | @token.LeftParen
    | @token.Lambda
    | @token.Identifier(_)
    | @token.Integer(_) => true
    _ => false
  }
}

///|
fn token_is_binary_operator(token : @token.Token) -> Bool {
  match token {
    @token.Plus | @token.Minus => true
    _ => false
  }
}

///|
fn token_starts_application_atom(token : @token.Token) -> Bool {
  match token {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda => true
    _ => false
  }
}

///|
fn peek_after_newlines(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> @token.Token {
  let mut pos = ctx.position
  while pos < ctx.token_count {
    let token = (ctx.get_token)(pos)
    match token {
      @token.Newline => pos = pos + 1
      _ => return token
    }
  }
  @token.EOF
}

///|
fn consume_newline_tokens(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  let mut count = 0
  while ctx.peek() == @token.Newline {
    ctx.emit_token(@syntax.NewlineToken)
    count = count + 1
  }
  count
}

///|
fn consume_soft_newlines_before_expression(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  if ctx.peek() == @token.Newline &&
    token_starts_expression(peek_after_newlines(ctx)) {
    let _ = consume_newline_tokens(ctx)
  }
}

///|
fn consume_soft_newlines_before_expected(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expected : @token.Token,
) -> Unit {
  if ctx.peek() == @token.Newline && peek_after_newlines(ctx) == expected {
    let _ = consume_newline_tokens(ctx)
  }
}

///|
fn consume_soft_newlines_before_binary_operator(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  if ctx.peek() == @token.Newline &&
    token_is_binary_operator(peek_after_newlines(ctx)) {
    let _ = consume_newline_tokens(ctx)
  }
}

///|
fn consume_soft_newlines_before_application_atom(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  if ctx.peek() == @token.Newline &&
    token_starts_application_atom(peek_after_newlines(ctx)) {
    let _ = consume_newline_tokens(ctx)
  }
}

///|
/// Expect a specific token, consuming optional soft newlines before it.
/// Returns true when the token was consumed, false when recovery fired.
fn lambda_expect(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expected : @token.Token,
  kind : @syntax.SyntaxKind,
) -> Bool {
  consume_soft_newlines_before_expected(ctx, expected)
  let current = ctx.peek()
  match (current, expected) {
    (a, b) if a == b => {
      ctx.emit_token(kind)
      true
    }
    _ => {
      ctx.error("Expected " + @token.print_token(expected))
      ctx.emit_error_placeholder()
      false
    }
  }
}

///|
/// Tokens where error recovery should stop — structural delimiters and
/// expression-starters that can begin a valid recovery parse.
/// Excludes Identifier/Integer (too common to be reliable sync points).
fn is_sync_point(t : @token.Token) -> Bool {
  match t {
    @token.Newline
    | @token.RightParen
    | @token.In
    | @token.Lambda
    | @token.Let
    | @token.If
    | @token.Then
    | @token.Else
    | @token.EOF => true
    _ => false
  }
}

///|
/// Skip malformed paren payload while preserving parent-level sync tokens.
///
/// Stops at:
/// - `)` at depth 0 (so the caller can consume it), or
/// - any parent sync token at depth 0 (`in`/`then`/`else`/...).
///
/// Nested parens are still balanced so inner `)` do not prematurely stop.
fn skip_until_paren_close_or_sync(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  let mut depth = 0
  let mut skipped = 0
  let mut wrapped = false
  while ctx.peek() != @token.EOF {
    let token = ctx.peek()
    if token == @token.RightParen {
      if depth == 0 {
        break
      }
      depth = depth - 1
    } else if token == @token.LeftParen {
      depth = depth + 1
    } else if depth == 0 && is_sync_point(token) {
      break
    }
    if not(wrapped) {
      ctx.start_node(@syntax.ErrorNode)
      wrapped = true
    }
    ctx.bump_error()
    skipped = skipped + 1
  }
  if wrapped {
    ctx.finish_node()
  }
  skipped
}

// ─── Grammar (entry point + rules) ───────────────────────────────────────────

///|
/// Entry point — wired into lambda_spec as parse_root.
fn parse_lambda_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_expression(ctx)
  match ctx.peek() {
    @token.EOF => ctx.flush_trivia()
    _ => {
      ctx.error("Unexpected tokens after expression")
      ctx.start_node(@syntax.ErrorNode)
      while ctx.peek() != @token.EOF {
        ctx.bump_error()
      }
      ctx.finish_node()
      ctx.flush_trivia()
    }
  }
}

///|
fn parse_expression(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_expression_with_mode(ctx, true)
}

///|
// NOTE: consume_soft_newlines_before_expression fires regardless of
// allow_newline_application. This is intentional: the flag guards
// newline-spanning *application* (f\nx treated as (f x)), not whether the
// expression itself may be preceded by a newline. Callers that pass
// allow_newline_application=false (i.e. parse_source_file_let_item) invoke
// this immediately after consuming `=`, where no leading newline exists.
fn parse_expression_with_mode(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  consume_soft_newlines_before_expression(ctx)
  parse_let_expr(ctx, allow_newline_application)
}

///|
fn parse_let_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  match ctx.peek() {
    @token.Let =>
      ctx.node_with_recovery(
        @syntax.LetExpr,
        () => {
          ctx.emit_token(@syntax.LetKeyword)
          match ctx.peek() {
            @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
            _ => {
              ctx.error("Expected variable name after 'let'")
              ctx.emit_error_placeholder()
            }
          }
          let _ = lambda_expect(ctx, @token.Eq, @syntax.EqToken)
          parse_let_expr(ctx, allow_newline_application)
          if not(lambda_expect(ctx, @token.In, @syntax.InKeyword)) {
            return false
          }
          parse_let_expr(ctx, allow_newline_application)
          true
        },
        is_sync_point,
      )
    _ => parse_binary_op(ctx, allow_newline_application)
  }
}

///|
fn parse_binary_op(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  let mark = ctx.mark()
  parse_application(ctx, allow_newline_application)
  // (A) Prime: consume newline so the match below can see the operator.
  consume_soft_newlines_before_binary_operator(ctx)
  match ctx.peek() {
    @token.Plus | @token.Minus =>
      ctx.wrap_at(mark, @syntax.BinaryExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          // (B) Loop: consume newline before each subsequent operator.
          // Do NOT remove — (A) handled only the first; (B) handles the rest.
          consume_soft_newlines_before_binary_operator(ctx)
          match ctx.peek() {
            @token.Plus => {
              ctx.emit_token(@syntax.PlusToken)
              parse_application(ctx, allow_newline_application)
            }
            @token.Minus => {
              ctx.emit_token(@syntax.MinusToken)
              parse_application(ctx, allow_newline_application)
            }
            _ => break
          }
        }
      })
    _ => ()
  }
}

///|
fn parse_application(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  let mark = ctx.mark()
  if allow_newline_application {
    consume_soft_newlines_before_application_atom(ctx)
  }
  parse_atom(ctx, allow_newline_application)
  if allow_newline_application {
    consume_soft_newlines_before_application_atom(ctx)
  }
  match ctx.peek() {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda =>
      ctx.wrap_at(mark, @syntax.AppExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          if allow_newline_application {
            consume_soft_newlines_before_application_atom(ctx)
          }
          match ctx.peek() {
            @token.LeftParen
            | @token.Identifier(_)
            | @token.Integer(_)
            | @token.Lambda => parse_atom(ctx, allow_newline_application)
            _ => break
          }
        }
      })
    _ => ()
  }
}

///|
fn parse_atom(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  if ctx.error_count >= MAX_ERRORS {
    return
  }
  match ctx.peek() {
    @token.Integer(_) =>
      ctx.node(@syntax.IntLiteral, fn() { ctx.emit_token(@syntax.IntToken) })
    @token.Identifier(_) =>
      ctx.node(@syntax.VarRef, fn() { ctx.emit_token(@syntax.IdentToken) })
    @token.Lambda =>
      ctx.node_with_recovery(
        @syntax.LambdaExpr,
        () => {
          ctx.emit_token(@syntax.LambdaToken)
          match ctx.peek() {
            @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
            _ => {
              ctx.error("Expected parameter after λ")
              ctx.emit_error_placeholder()
            }
          }
          if not(lambda_expect(ctx, @token.Dot, @syntax.DotToken)) {
            return false
          }
          parse_expression_with_mode(ctx, allow_newline_application)
          true
        },
        is_sync_point,
      )
    @token.If =>
      ctx.node_with_recovery(
        @syntax.IfExpr,
        () => {
          ctx.emit_token(@syntax.IfKeyword)
          parse_expression_with_mode(ctx, allow_newline_application)
          if not(lambda_expect(ctx, @token.Then, @syntax.ThenKeyword)) {
            return false
          }
          parse_expression_with_mode(ctx, allow_newline_application)
          if not(lambda_expect(ctx, @token.Else, @syntax.ElseKeyword)) {
            return false
          }
          parse_expression_with_mode(ctx, allow_newline_application)
          true
        },
        is_sync_point,
      )
    @token.LeftParen =>
      ctx.node(@syntax.ParenExpr, () => {
        ctx.emit_token(@syntax.LeftParenToken)
        parse_expression_with_mode(ctx, allow_newline_application)
        if not(lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken)) {
          // RightParen missing — recover inside parens, but don't consume
          // parent-level delimiters (`in`/`then`/`else`/...) needed upstream.
          let _ = skip_until_paren_close_or_sync(ctx)
          if ctx.peek() == @token.RightParen {
            ctx.emit_token(@syntax.RightParenToken)
          }
        }
      })
    _ => {
      ctx.error("Unexpected token")
      if is_sync_point(ctx.peek()) {
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        let _ = ctx.skip_until(is_sync_point)
      }
    }
  }
}

// ─── Source-file grammar (LetDef* Expression?) ────────────────────────────────

///|
/// Parse a top-level `let` item for source-file grammar.
///
/// Shape:
///   - `let x = e`      -> LetDef
///   - `let x = e in b` -> LetExpr
///
/// Returns true when parsed as LetDef, false when parsed as LetExpr.
///
/// Uses allow_newline_application=false so that a newline after the RHS
/// stops the expression rather than continuing it into the next definition.
/// A `let` token inside the RHS always starts a nested let-expression —
/// never a sibling top-level definition — so consuming a leading newline
/// before it is correct.
fn parse_source_file_let_item(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  let mark = ctx.mark()
  ctx.emit_token(@syntax.LetKeyword)
  match ctx.peek() {
    @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
    _ => {
      ctx.error("Expected variable name after 'let'")
      ctx.emit_error_placeholder()
    }
  }
  let _ = lambda_expect(ctx, @token.Eq, @syntax.EqToken)
  parse_expression_with_mode(ctx, false)
  let mut is_def = true
  consume_soft_newlines_before_expected(ctx, @token.In)
  if ctx.peek() == @token.In {
    is_def = false
    ctx.emit_token(@syntax.InKeyword)
    parse_expression(ctx)
  }
  let kind = if is_def { @syntax.LetDef } else { @syntax.LetExpr }
  ctx.start_at(mark, kind)
  ctx.finish_node()
  is_def
}

///|
/// Entry point for source-file grammar: LetDef* Expression?
/// Newline tokens (from tokenize_layout) delimit definitions and are emitted
/// explicitly into the CST as direct children of SourceFile. They are token
/// children (not node children), so `SyntaxNode::children()` (node-only) never
/// yields them. Only `SyntaxNode::all_children()` would see them. The term
/// converter uses `children()`, so it only encounters LetDef and expression nodes.
/// Callers that use `all_children()` must handle `NewlineToken` explicitly.
fn parse_source_file_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mut parsed_final_expr = false
  let _ = consume_newline_tokens(ctx)
  while ctx.peek() == @token.Let && not(parsed_final_expr) {
    if parse_source_file_let_item(ctx) {
      let delimiter_count = consume_newline_tokens(ctx)
      if delimiter_count == 0 && ctx.peek() == @token.Let {
        ctx.error("Expected newline between top-level definitions")
      }
    } else {
      parsed_final_expr = true
    }
  }
  if not(parsed_final_expr) {
    let _ = consume_newline_tokens(ctx)
    match ctx.peek() {
      @token.EOF => ()
      _ => parse_expression(ctx)
    }
  }
  let _ = consume_newline_tokens(ctx)
  match ctx.peek() {
    @token.EOF => ()
    _ => {
      ctx.error("Unexpected tokens after expression")
      ctx.start_node(@syntax.ErrorNode)
      while ctx.peek() != @token.EOF {
        ctx.bump_error()
      }
      ctx.finish_node()
    }
  }
  ctx.flush_trivia()
}

///|
/// Parse a source file (LetDef* Expression?). Returns tree with error recovery.
pub fn parse_source_file(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let tokens = @lexer.tokenize_layout(source)
  let starts = @core.build_starts(tokens)
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    source_file_spec,
  )
  (cst, diagnostics)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor (for incremental use).
pub fn parse_source_file_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo[@token.Token]],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  let starts = @core.build_starts(tokens)
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    source_file_spec,
    cursor~,
    prev_diagnostics~,
  )
}

///|
/// Make a ReuseCursor for incremental source-file parsing.
pub fn make_source_file_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@token.TokenInfo[@token.Token]],
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  let starts = @core.build_starts(tokens)
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    source_file_spec,
  )
}
