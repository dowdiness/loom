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
    Expr::RepeatTopLevel(_, _) => {
      ctx.error(
        "SPIKE: RepeatTopLevel not yet implemented (Task 5); ensure IR uses Task 5 lowering",
      )
      ctx.emit_error_placeholder()
    }
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
