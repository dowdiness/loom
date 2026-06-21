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
      spike_expect(ctx, token, kind)
      let _ = msg
    }
    Expr::Node(kind, body) => ctx.node(kind, () => run_expr(ctx, ir, body))
    Expr::Ref(rule_id) => run_expr(ctx, ir, ir.rule(rule_id))
    Expr::Seq(exprs) =>
      for e in exprs {
        run_expr(ctx, ir, e)
      }
    Expr::PrattApp(atom_rule, app_kind, starts) => {
      let mark = ctx.mark()
      run_expr(ctx, ir, ir.rule(atom_rule))
      guard starts(ctx.peek()) else { return }
      ctx.wrap_at(mark, app_kind, fn() {
        while starts(ctx.peek()) {
          run_expr(ctx, ir, ir.rule(atom_rule))
        }
      })
    }
    Expr::PrattBinary(prefix_rule, binary_kind, ops) => {
      let mark = ctx.mark()
      run_expr(ctx, ir, ir.rule(prefix_rule))
      guard ops.iter().any(fn(pair) { ctx.peek() == pair.0 }) else { return }
      ctx.wrap_at(mark, binary_kind, fn() {
        while true {
          match ops.iter().find_first(fn(pair) { ctx.peek() == pair.0 }) {
            None => break
            Some(pair) => {
              ctx.emit_token(pair.1)
              run_expr(ctx, ir, ir.rule(prefix_rule))
            }
          }
        }
      })
    }
    Expr::RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred(ctx.peek()) {
        run_expr(ctx, ir, body)
      }
    Expr::Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if (alt.starts)(token) {
          run_expr(ctx, ir, alt.body)
          break
        }
      }
    }
    Expr::RepeatTopLevel(rule_id, starts_pred, tail_expr, cripple_reuse) =>
      parse_top_level_repeat(
        ctx, ir, rule_id, starts_pred, tail_expr, cripple_reuse,
      )
    Expr::WrapIfNext(_, _, _, _) => {
      ctx.error(
        "SPIKE: WrapIfNext not yet wired; ensure IR uses correct variant",
      )
      ctx.emit_error_placeholder()
    }
    Expr::ManualDefinition => parse_definition_ir(ctx, ir)
    Expr::ManualBlockDelimiterCheck => parse_block_delimiter_check(ctx)
    Expr::ManualNewlineAppExpr => parse_newline_app_expr(ctx, ir)
    Expr::ManualParamList => parse_param_list_exact(ctx)
    Expr::EmitError(msg) => ctx.error(msg)
    Expr::ErrorUntil(stop, msg) => {
      ctx.error(msg)
      parse_error_node_until(ctx, stop)
    }
  }
}

///|
/// Mirror lambda_expect: consume soft newlines when the expected token follows,
/// then call ctx.expect. All required-token sites route through here so B
/// replicates A's consume_soft_newlines_before_expected behavior.
fn spike_expect(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  token : @token.Token,
  kind : @syntax.SyntaxKind,
) -> Unit {
  // loom#436: expect_after_skip — mirrors lambda_expect → consume_soft_newlines_before_expected
  let _ = ctx.expect_after_skip(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    token,
    kind,
  )
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
/// Mirrors A's token_starts_expression: any token that may open a binary
/// expression (atoms + if-then-else). Used to gate soft-newline consumption
/// before an expression so that `let x =\n1` is treated like `let x = 1`.
fn spike_starts_expression(t : @token.Token) -> Bool {
  match t {
    @token.If
    | @token.LeftParen
    | @token.LBrace
    | @token.Hole
    | @token.Identifier
    | @token.Integer => true
    _ => false
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
        // P2: mirror parse_let_item's LeftParen guard — A emits this diagnostic
        // before expecting =, so D2a diverges without it.
        if ctx.peek() == @token.LeftParen {
          ctx.error("'let' declarations do not take parameter lists; use 'fn'")
        }
        spike_expect(ctx, @token.Eq, @syntax.EqToken)
        // P2: mirror parse_expression_with_mode's consume_soft_newlines_before_expression
        // so `let x =\n1` is accepted (A routes through parse_expression_with_mode).
        let _ = ctx.consume_while_emit_if(
          t => t == @token.Newline,
          @syntax.NewlineToken,
          spike_starts_expression,
        )
        run_expr(ctx, ir, ir.rule(RuleId::Expression))
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
          @token.LBrace => run_expr(ctx, ir, ir.rule(RuleId::Atom))
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
/// Consume delimiter newlines by emitting NewlineToken, returning the count.
/// Mirrors A's consume_newline_tokens (returns Int). flush_trivia MUST NOT be
/// used here: @token.Newline is non-trivia, so flush_trivia leaves the cursor
/// on the delimiter newline and exits the definition loop early.
fn consume_delimiter_newlines(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  for count = 0 {
    guard ctx.at(@token.Newline) else { break count }
    ctx.emit_token(@syntax.NewlineToken)
    continue count + 1
  }
}

///|
/// ManualBlockDelimiterCheck implementation: consume delimiter newlines after a
/// block definition and emit a diagnostic when count is zero and the next token
/// is not '}' or EOF (same as A's block delimiter check in parse_block_expr).
fn parse_block_delimiter_check(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let count = consume_delimiter_newlines(ctx)
  if count == 0 {
    match ctx.peek() {
      @token.RBrace | @token.EOF => ()
      _ => ctx.error("Expected ';' or newline between definitions")
    }
  }
}

///|
/// ManualNewlineAppExpr implementation: parse a binary expression where the
/// application sub-rule uses allow_newline_application=true. Mirrors A's
/// parse_expression_with_mode(ctx, true) used for top-level and block trailing
/// expressions.
///
/// Structure mirrors parse_binary_op in cst_parser.mbt:
///   1. Mark for potential wrap.
///   2. Parse application layer with newline consumption between atoms.
///   3. Check for binary operators (consuming soft newlines before them).
///   4. If operator found, wrap the whole expression in BinaryExpr and loop.
fn parse_newline_app_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  let mark = ctx.mark()
  parse_app_with_newline(ctx, ir)
  // Consume soft newlines only when followed by a binary operator, then wrap.
  let op_pairs : Array[(@token.Token, @syntax.SyntaxKind)] = [
    (@token.Plus, @syntax.PlusToken),
    (@token.Minus, @syntax.MinusToken),
  ]
  let has_op = fn(t) { op_pairs.iter().any(fn(p) { t == p.0 }) }
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    has_op,
  )
  guard has_op(ctx.peek()) else { return }
  ctx.wrap_at(mark, @syntax.BinaryExpr, fn() {
    while true {
      match op_pairs.iter().find_first(fn(p) { ctx.peek() == p.0 }) {
        None => break
        Some(pair) => {
          ctx.emit_token(pair.1)
          parse_app_with_newline(ctx, ir)
          let _ = ctx.consume_while_emit_if(
            t => t == @token.Newline,
            @syntax.NewlineToken,
            has_op,
          )
        }
      }
    }
  })
}

///|
/// Application parser with allow_newline_application=true. Mirrors A's
/// parse_application(ctx, allow_newline_application=true): consumes soft
/// newlines between atoms when the token after the newlines is an atom-starter.
fn parse_app_with_newline(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
) -> Unit {
  let mark = ctx.mark()
  run_expr(ctx, ir, ir.rule(RuleId::Atom))
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    atom_starts_token,
  )
  guard atom_starts_token(ctx.peek()) else { return }
  ctx.wrap_at(mark, @syntax.AppExpr, fn() {
    while true {
      run_expr(ctx, ir, ir.rule(RuleId::Atom))
      let _ = ctx.consume_while_emit_if(
        t => t == @token.Newline,
        @syntax.NewlineToken,
        atom_starts_token,
      )
      guard atom_starts_token(ctx.peek()) else { break }
    }
  })
}

///|
/// Top-level source parser — mirrors A's parse_lambda_root.
/// Handles definitions with repeat-group reuse, optional trailing expression,
/// and trailing-token error recovery.
///
/// rule_id: the IR rule dispatched for each item (e.g. RuleId::Definition).
/// starts_pred: lookahead predicate that determines whether the next token
///   opens a new item (e.g. token_starts_definition for lambda).
/// tail_expr: evaluated once after the item loop exits but before EOF. Use
///   Expr::Empty to silently accept an empty tail (statement-only grammars)
///   or a rule/manual variant to parse a trailing expression.
pub fn parse_top_level_repeat(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  ir : GrammarIr,
  rule_id : RuleId,
  starts_pred : (@token.Token) -> Bool,
  tail_expr : Expr,
  cripple_reuse : Bool,
) -> Unit {
  let _ = consume_delimiter_newlines(ctx)
  while starts_pred(ctx.peek()) {
    if !cripple_reuse && ctx.try_reuse_repeat_group() {
      let _ = consume_delimiter_newlines(ctx)
      continue
    }
    run_expr(ctx, ir, ir.rule(rule_id))
    // Mirror parse_lambda_root's delimiter_count check: when no newline
    // separates a definition from what follows, emit the same diagnostic A emits.
    let delimiter_count = consume_delimiter_newlines(ctx)
    if delimiter_count == 0 && ctx.peek() != @token.EOF {
      if starts_pred(ctx.peek()) {
        ctx.error("Expected newline between top-level definitions")
      } else {
        ctx.error("Expected newline after top-level definition")
      }
    }
  }
  match ctx.peek() {
    @token.EOF => ()
    _ => run_expr(ctx, ir, tail_expr)
  }
  let _ = consume_delimiter_newlines(ctx)
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
  spike_expect(ctx, @token.RightParen, @syntax.RightParenToken)
  ctx.start_at(mark, @syntax.ParamList)
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
