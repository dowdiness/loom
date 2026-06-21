///|
/// Build a parse_root closure from a grammar IR value.
pub fn interpret(
  ir : GrammarIr,
) -> (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit {
  fn(ctx) { run_expr(ctx, ir, ir.rule(RuleId::Source)) }
}

///|
/// Evaluate one grammar IR expression against a parser context.
/// Unsupported constructors that should never appear in a well-formed
/// IR produce a spike-local diagnostic error rather than silently no-op.
pub fn run_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
  expr : Expr,
) -> Unit {
  match expr {
    Expr::Empty => ()
    Expr::Emit(token, kind) => {
      if ctx.at(token) {
        ctx.emit_token(kind)
      }
    }
    Expr::Expect(token, kind, msg) => {
      let _ = ctx.expect(token, kind)
      let _ = msg
    }
    Expr::Node(kind, body) => ctx.node(kind, () => run_expr(ctx, ir, body))
    Expr::Ref(RuleId::Application) => parse_application_ir(ctx, ir)
    Expr::Ref(RuleId::Binary) => parse_binary_ir(ctx, ir)
    Expr::Ref(rule_id) => run_expr(ctx, ir, ir.rule(rule_id))
    Expr::Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if (alt.starts)(token) {
          run_expr(ctx, ir, alt.body)
          break
        }
      }
    }
    Expr::RepeatTopLevel(_, cripple_reuse) => parse_top_level_repeat(ctx, ir, cripple_reuse)
    Expr::RepeatWhile(_, _) => {
      ctx.error(
        "SPIKE: RepeatWhile not yet wired (Task 4+); ensure IR uses correct variant",
      )
      ctx.emit_error_placeholder()
    }
    Expr::WrapIfNext(_, _, _, _) => {
      ctx.error(
        "SPIKE: WrapIfNext not yet wired (Task 4); ensure IR uses correct variant",
      )
      ctx.emit_error_placeholder()
    }
    Expr::ManualParamList => {
      ctx.error(
        "SPIKE: ManualParamList not yet implemented (Task 6); implement param list first",
      )
      ctx.emit_error_placeholder()
    }
    Expr::ErrorUntil(_, msg) => {
      ctx.error(msg)
      ctx.start_node(@syntax.ErrorNode)
      ctx.emit_error_placeholder()
      ctx.finish_node()
    }
  }
}

///|
fn atom_starts_token(t : @token.Token) -> Bool {
  match t {
    @token.LeftParen | @token.LBrace | @token.Identifier | @token.Integer | @token.Hole =>
      true
    _ => false
  }
}

///|
/// Pratt application parser — mirrors A's parse_application with
/// allow_newline_application=false (newline-spanning application is a
/// ReplicationResidual delta catalogued in Task 11).
fn parse_application_ir(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  let mark = ctx.mark()
  run_expr(ctx, ir, ir.rule(RuleId::Atom))
  guard atom_starts_token(ctx.peek()) else { return }
  ctx.wrap_at(mark, @syntax.AppExpr, fn() {
    while atom_starts_token(ctx.peek()) {
      run_expr(ctx, ir, ir.rule(RuleId::Atom))
    }
  })
}

///|
/// Pratt binary parser — mirrors A's parse_binary_op.
fn parse_binary_ir(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  let mark = ctx.mark()
  parse_application_ir(ctx, ir)
  match ctx.peek() {
    @token.Plus | @token.Minus =>
      ctx.wrap_at(mark, @syntax.BinaryExpr, fn() {
        while true {
          match ctx.peek() {
            @token.Plus => {
              ctx.emit_token(@syntax.PlusToken)
              parse_application_ir(ctx, ir)
            }
            @token.Minus => {
              ctx.emit_token(@syntax.MinusToken)
              parse_application_ir(ctx, ir)
            }
            _ => break
          }
        }
      })
    _ => ()
  }
}

///|
fn token_starts_definition(t : @token.Token) -> Bool {
  match t {
    @token.Fn | @token.Let => true
    _ => false
  }
}

///|
/// Parse one top-level definition — mirrors A's parse_definition_item/parse_let_item.
/// Fn definitions are stubbed (Task 6 adds ParamList + BlockExpr).
fn parse_definition_ir(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  match ctx.peek() {
    @token.Let =>
      ctx.node(@syntax.LetDef, fn() {
        ctx.emit_token(@syntax.LetKeyword)
        match ctx.peek() {
          @token.Identifier => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("expected name after 'let'")
            ctx.emit_error_placeholder()
          }
        }
        let _ = ctx.expect(@token.Eq, @syntax.EqToken)
        parse_binary_ir(ctx, ir)
      })
    @token.Fn => {
      ctx.error("SPIKE: fn definitions not yet implemented (Task 6)")
      ctx.emit_error_placeholder()
    }
    _ => ()
  }
}

///|
/// Consume delimiter newlines by emitting NewlineToken — mirrors A's
/// consume_newline_tokens. flush_trivia MUST NOT be used here: @token.Newline
/// is non-trivia (is_trivia = self == Whitespace), so flush_trivia leaves the
/// cursor on the delimiter newline and exits the definition loop early.
fn consume_delimiter_newlines(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  while ctx.at(@token.Newline) {
    ctx.emit_token(@syntax.NewlineToken)
  }
}

///|
/// Top-level source parser — mirrors A's parse_lambda_root.
/// Handles definitions with repeat-group reuse, optional trailing expression,
/// and trailing-token error recovery.
pub fn parse_top_level_repeat(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
  cripple_reuse : Bool,
) -> Unit {
  consume_delimiter_newlines(ctx)
  while token_starts_definition(ctx.peek()) {
    if !cripple_reuse && ctx.try_reuse_repeat_group() {
      consume_delimiter_newlines(ctx)
      continue
    }
    parse_definition_ir(ctx, ir)
    consume_delimiter_newlines(ctx)
  }
  match ctx.peek() {
    @token.EOF => ()
    _ => parse_binary_ir(ctx, ir)
  }
  consume_delimiter_newlines(ctx)
  match ctx.peek() {
    @token.EOF => ()
    _ => {
      ctx.error("unexpected tokens after expression")
      ctx.start_node(@syntax.ErrorNode)
      while ctx.peek() != @token.EOF {
        ctx.bump_error()
      }
      ctx.finish_node()
    }
  }
}
