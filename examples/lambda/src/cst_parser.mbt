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
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
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
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
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
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
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
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    lambda_spec,
    cursor~,
    prev_diagnostics~,
  )
}

// ─── Grammar helpers ──────────────────────────────────────────────────────────

///|
fn at_stop_token(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  match ctx.peek() {
    @token.RightParen | @token.Then | @token.Else | @token.In | @token.EOF =>
      true
    _ => false
  }
}

///|
fn lambda_expect(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expected : @token.Token,
  kind : @syntax.SyntaxKind,
) -> Unit {
  let current = ctx.peek()
  match (current, expected) {
    (a, b) if a == b => ctx.emit_token(kind)
    _ => {
      ctx.error("Expected " + @token.print_token(expected))
      ctx.emit_error_placeholder()
    }
  }
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
  parse_let_expr(ctx)
}

///|
fn parse_let_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  match ctx.peek() {
    @token.Let =>
      ctx.node(@syntax.LetExpr, () => {
        ctx.emit_token(@syntax.LetKeyword)
        match ctx.peek() {
          @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("Expected variable name after 'let'")
            ctx.emit_error_placeholder()
          }
        }
        lambda_expect(ctx, @token.Eq, @syntax.EqToken)
        parse_let_expr(ctx)
        lambda_expect(ctx, @token.In, @syntax.InKeyword)
        parse_let_expr(ctx)
      })
    _ => parse_binary_op(ctx)
  }
}

///|
fn parse_binary_op(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_application(ctx)
  match ctx.peek() {
    @token.Plus | @token.Minus =>
      ctx.wrap_at(mark, @syntax.BinaryExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          match ctx.peek() {
            @token.Plus => {
              ctx.emit_token(@syntax.PlusToken)
              parse_application(ctx)
            }
            @token.Minus => {
              ctx.emit_token(@syntax.MinusToken)
              parse_application(ctx)
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
) -> Unit {
  let mark = ctx.mark()
  parse_atom(ctx)
  match ctx.peek() {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda =>
      ctx.wrap_at(mark, @syntax.AppExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          match ctx.peek() {
            @token.LeftParen
            | @token.Identifier(_)
            | @token.Integer(_)
            | @token.Lambda => parse_atom(ctx)
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
      ctx.node(@syntax.LambdaExpr, () => {
        ctx.emit_token(@syntax.LambdaToken)
        match ctx.peek() {
          @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("Expected parameter after λ")
            ctx.emit_error_placeholder()
          }
        }
        lambda_expect(ctx, @token.Dot, @syntax.DotToken)
        parse_expression(ctx)
      })
    @token.If =>
      ctx.node(@syntax.IfExpr, fn() {
        ctx.emit_token(@syntax.IfKeyword)
        parse_expression(ctx)
        lambda_expect(ctx, @token.Then, @syntax.ThenKeyword)
        parse_expression(ctx)
        lambda_expect(ctx, @token.Else, @syntax.ElseKeyword)
        parse_expression(ctx)
      })
    @token.LeftParen =>
      ctx.node(@syntax.ParenExpr, fn() {
        ctx.emit_token(@syntax.LeftParenToken)
        parse_expression(ctx)
        lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken)
      })
    _ => {
      ctx.error("Unexpected token")
      if at_stop_token(ctx) {
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        ctx.start_node(@syntax.ErrorNode)
        ctx.bump_error()
        ctx.finish_node()
      }
    }
  }
}

// ─── Source-file grammar (LetDef* Expression?) ────────────────────────────────

/// Parse a top-level `let` item for source-file grammar.
///
/// Shape:
///   - `let x = e`      -> LetDef
///   - `let x = e in b` -> LetExpr
///
/// Returns true when parsed as LetDef, false when parsed as LetExpr.
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
  lambda_expect(ctx, @token.Eq, @syntax.EqToken)
  parse_expression(ctx)
  let mut is_def = true
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
  while ctx.peek() == @token.Newline {
    ctx.emit_token(@syntax.NewlineToken)
  }
  while ctx.peek() == @token.Let && not(parsed_final_expr) {
    if parse_source_file_let_item(ctx) {
      while ctx.peek() == @token.Newline {
        ctx.emit_token(@syntax.NewlineToken)
      }
    } else {
      parsed_final_expr = true
    }
  }
  if not(parsed_final_expr) {
    while ctx.peek() == @token.Newline {
      ctx.emit_token(@syntax.NewlineToken)
    }
    match ctx.peek() {
      @token.EOF => ()
      _ => parse_expression(ctx)
    }
  }
  while ctx.peek() == @token.Newline {
    ctx.emit_token(@syntax.NewlineToken)
  }
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
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
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
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
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
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    source_file_spec,
  )
}
