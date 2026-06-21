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
    Expr::Emit(token, kind) => if ctx.at(token) { ctx.emit_token(kind) }
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
    Expr::RepeatTopLevel(_, cripple_reuse) =>
      parse_top_level_repeat(ctx, ir, cripple_reuse)
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
    Expr::ManualParamList => parse_param_list_exact(ctx)
    Expr::ManualAtom => parse_atom_ir(ctx, ir)
    Expr::ErrorUntil(stop, msg) => {
      ctx.error(msg)
      parse_error_node_until(ctx, stop)
    }
  }
}

///|
fn atom_starts_token(t : @token.Token) -> Bool {
  match t {
    @token.LeftParen
    | @token.LBrace
    | @token.Identifier
    | @token.Integer
    | @token.Hole => true
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
    @token.Fn =>
      ctx.node(@syntax.LetDef, fn() {
        ctx.emit_token(@syntax.FnKeyword)
        match ctx.peek() {
          @token.Identifier => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("Expected function name after 'fn'")
            ctx.emit_error_placeholder()
          }
        }
        if ctx.peek() == @token.LeftParen {
          parse_param_list_exact(ctx)
        } else {
          ctx.error("Expected parameter list after function name")
          ctx.emit_error_placeholder()
        }
        match ctx.peek() {
          @token.LBrace => parse_block_expr_ir(ctx, ir)
          _ => {
            ctx.error("Expected function body")
            ctx.emit_error_placeholder()
          }
        }
      })
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

///|
/// Parameter list parser — mirrors A's parse_param_list(allow_empty=true).
/// Uses start_at + finish_node to match A's mark-based CST shape.
/// Type annotations are not parsed (spike scope: untyped lambda only).
fn parse_param_list_exact(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  ctx.emit_token(@syntax.LeftParenToken)
  match ctx.peek() {
    @token.RightParen => ()
    @token.Identifier => {
      ctx.emit_token(@syntax.IdentToken)
      while ctx.at(@token.Comma) {
        ctx.emit_token(@syntax.CommaToken)
        match ctx.peek() {
          @token.Identifier => ctx.emit_token(@syntax.IdentToken)
          @token.RightParen => {
            ctx.error("Trailing comma in parameter list")
            break
          }
          _ => {
            ctx.error("Expected parameter name")
            ctx.emit_error_placeholder()
          }
        }
      }
    }
    _ => {
      ctx.error("Expected parameter name")
      ctx.emit_error_placeholder()
    }
  }
  let _ = ctx.expect(@token.RightParen, @syntax.RightParenToken)
  ctx.start_at(mark, @syntax.ParamList)
  ctx.finish_node()
}

///|
/// Minimal block-expression parser for fn definition bodies in the spike.
/// Mirrors A's parse_block_expr for the subset: `{ expr }` and `{}`.
fn parse_block_expr_ir(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  ctx.start_node(@syntax.BlockExpr)
  ctx.emit_token(@syntax.LBraceToken)
  consume_delimiter_newlines(ctx)
  if ctx.peek() == @token.RBrace {
    ctx.error("Empty block expression")
  } else if ctx.peek() != @token.EOF {
    parse_binary_ir(ctx, ir)
    consume_delimiter_newlines(ctx)
  }
  let _ = ctx.expect(@token.RBrace, @syntax.RBraceToken)
  ctx.finish_node()
}

///|
/// Sync points: tokens where error recovery should stop consuming.
/// Mirrors A's `is_sync_point` in cst_parser.mbt.
pub fn spike_is_sync_point(t : @token.Token) -> Bool {
  match t {
    @token.Newline
    | @token.RightParen
    | @token.LBrace
    | @token.RBrace
    | @token.Semicolon
    | @token.Lambda
    | @token.Let
    | @token.Fn
    | @token.FatArrow
    | @token.If
    | @token.Then
    | @token.Else
    | @token.EOF => true
    _ => false
  }
}

///|
/// Emit a missing-token diagnostic with an error placeholder.
/// Use for required tokens that were not found.
pub fn emit_missing(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  message : String,
) -> Unit {
  ctx.error(message)
  ctx.emit_error_placeholder()
}

///|
/// Emit an ErrorNode containing either an error placeholder (when already at a
/// sync point) or bump'd tokens (when mid-garbage, consumed until sync).
/// Mirrors A's parse_atom `_` fallthrough.
pub fn parse_error_node_until(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  stop : (@token.Token) -> Bool,
) -> Unit {
  if stop(ctx.peek()) {
    ctx.start_node(@syntax.ErrorNode)
    ctx.emit_error_placeholder()
    ctx.finish_node()
  } else {
    let _ = ctx.skip_until(stop)
  }
}

///|
/// Atom parser — E2 escape hatch mirroring A's parse_atom for the spike's
/// supported subset: Int, Identifier, Hole, LeftParen (paren expr only, no
/// arrow lambda), LBrace (block expr), and error fallback. If-then-else is
/// out-of-scope for the spike and produces a D2a divergence (classified).
fn parse_atom_ir(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  match ctx.peek() {
    @token.Integer =>
      ctx.node(@syntax.IntLiteral, fn() { ctx.emit_token(@syntax.IntToken) })
    @token.Identifier =>
      ctx.node(@syntax.VarRef, fn() { ctx.emit_token(@syntax.IdentToken) })
    @token.Hole =>
      ctx.node(@syntax.HoleLiteral, fn() { ctx.emit_token(@syntax.HoleToken) })
    @token.LBrace => parse_block_expr_ir(ctx, ir)
    @token.LeftParen =>
      // Simplified: no arrow lambda detection — classified D2a divergence for
      // arrow-lambda inputs. Paren expr only.
      ctx.node(@syntax.ParenExpr, fn() {
        ctx.emit_token(@syntax.LeftParenToken)
        parse_binary_ir(ctx, ir)
        let _ = ctx.expect(@token.RightParen, @syntax.RightParenToken)
      })
    _ => {
      ctx.error("Unexpected token in expression")
      parse_error_node_until(ctx, spike_is_sync_point)
    }
  }
}
