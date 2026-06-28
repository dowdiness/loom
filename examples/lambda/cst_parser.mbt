///|
const MAX_ERRORS : Int = 50

// ─── Grammar helpers ──────────────────────────────────────────────────────────

///|
fn token_starts_expression(token : @token.Token) -> Bool {
  match token {
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
    | @token.LBrace
    | @token.Identifier
    | @token.Integer
    | @token.Hole => true
    _ => false
  }
}

///|
/// Consume consecutive Newline tokens, emitting each into the CST.
/// Returns the number consumed. Used by parse_lambda_root to check whether
/// a required newline separator was present between top-level definitions.
fn consume_newline_tokens(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  for count = 0 {
    guard ctx.peek() == @token.Newline else { break count }
    ctx.emit_token(@syntax.NewlineToken)
    continue count + 1
  }
}

///|
/// Consume Newline and Semicolon tokens as block delimiters.
/// Returns the number of delimiters consumed.
fn consume_delimiters(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Int {
  let mut count = 0
  while true {
    match ctx.peek() {
      @token.Newline => ctx.emit_token(@syntax.NewlineToken)
      @token.Semicolon => ctx.emit_token(@syntax.SemicolonToken)
      _ => break
    }
    count += 1
  }
  count
}

///|
fn consume_soft_newlines_before_expression(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    token_starts_expression,
  )
}

///|
fn consume_soft_newlines_before_expected(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expected : @token.Token,
) -> Unit {
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    t => t == expected,
  )
}

///|
fn consume_soft_newlines_before_binary_operator(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    token_is_binary_operator,
  )
}

///|
fn consume_soft_newlines_before_application_atom(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    token_starts_application_atom,
  )
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
  let mut paren_depth = 0
  let mut brace_depth = 0
  let mut skipped = 0
  let mut wrapped = false
  while ctx.peek() != @token.EOF {
    let token = ctx.peek()
    if token == @token.RightParen {
      if paren_depth == 0 && brace_depth == 0 {
        break
      }
      if paren_depth > 0 {
        paren_depth = paren_depth - 1
      }
    } else if token == @token.LeftParen {
      paren_depth = paren_depth + 1
    } else if token == @token.RBrace {
      if brace_depth == 0 && paren_depth == 0 {
        break
      }
      if brace_depth > 0 {
        brace_depth = brace_depth - 1
      }
    } else if token == @token.LBrace {
      brace_depth = brace_depth + 1
    } else if paren_depth == 0 && brace_depth == 0 && is_sync_point(token) {
      break
    }
    if !wrapped {
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
// allow_newline_application=false (i.e. parse_let_item) invoke
// this immediately after consuming `=`, where no leading newline exists.
fn parse_expression_with_mode(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  consume_soft_newlines_before_expression(ctx)
  parse_binary_op(ctx, allow_newline_application)
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
        while !ctx.too_many_errors(MAX_ERRORS) {
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
    | @token.LBrace
    | @token.Identifier
    | @token.Integer
    | @token.Hole =>
      ctx.wrap_at(mark, @syntax.AppExpr, fn() {
        while !ctx.too_many_errors(MAX_ERRORS) {
          if allow_newline_application {
            consume_soft_newlines_before_application_atom(ctx)
          }
          match ctx.peek() {
            @token.LeftParen
            | @token.LBrace
            | @token.Identifier
            | @token.Integer
            | @token.Hole => parse_atom(ctx, allow_newline_application)
            _ => break
          }
        }
      })
    _ => ()
  }
}

///|
fn token_starts_definition(token : @token.Token) -> Bool {
  match token {
    @token.Fn | @token.Let => true
    _ => false
  }
}

///|
fn parse_definition_item(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  match ctx.peek() {
    @token.Fn => parse_fn_item(ctx)
    @token.Let => parse_let_item(ctx)
    _ => ()
  }
}

///|
/// Parse block expression: { ((FnDef | LetDef) (Newline|;))* Expression? }
/// Uses the same LetDef/Expression structure as SourceFile but delimited by {}.
pub fn parse_block_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.BlockExpr)
  ctx.emit_token(@syntax.LBraceToken) // {
  let _ = consume_delimiters(ctx)
  // Empty block check
  if ctx.peek() == @token.RBrace {
    ctx.error("Empty block expression")
    ctx.emit_token(@syntax.RBraceToken) // }
    ctx.finish_node()
    return
  }
  // Function and value definitions
  while token_starts_definition(ctx.peek()) {
    parse_definition_item(ctx)
    let delim_count = consume_delimiters(ctx)
    if delim_count == 0 &&
      ctx.peek() != @token.RBrace &&
      ctx.peek() != @token.EOF {
      ctx.error("Expected ';' or newline between definitions")
    }
  }
  let _ = consume_delimiters(ctx)
  // Trailing expression (optional)
  if ctx.peek() != @token.RBrace && ctx.peek() != @token.EOF {
    parse_expression(ctx)
  }
  let _ = consume_delimiters(ctx)
  if !lambda_expect(ctx, @token.RBrace, @syntax.RBraceToken) {
    let _ = skip_until_paren_close_or_sync(ctx)
    if ctx.peek() == @token.RBrace {
      ctx.emit_token(@syntax.RBraceToken)
    }
  }
  ctx.finish_node()
}

///|
fn token_after_soft_newlines(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  start_index : Int,
) -> @token.Token? {
  for index = start_index {
    match ctx.peek_nth(index) {
      @token.EOF => break None
      @token.Newline => continue index + 1
      token => break Some(token)
    }
  }
}

///|
fn token_after_matching_right_paren(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> @token.Token? {
  for index = 1, paren_depth = 0 {
    match ctx.peek_nth(index) {
      @token.EOF => break None
      @token.LeftParen => continue index + 1, paren_depth + 1
      @token.RightParen =>
        if paren_depth == 0 {
          break token_after_soft_newlines(ctx, index + 1)
        } else {
          continue index + 1, paren_depth - 1
        }
      _ => continue index + 1, paren_depth
    }
  }
}

///|
fn left_paren_starts_arrow_lambda(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  match token_after_matching_right_paren(ctx) {
    Some(@token.FatArrow) => true
    _ => false
  }
}

///|
fn parse_arrow_lambda(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  ctx.node_with_recovery(
    @syntax.LambdaExpr,
    () => {
      let _ = parse_param_list(ctx, allow_empty=false)
      if !lambda_expect(ctx, @token.FatArrow, @syntax.FatArrowToken) {
        return false
      }
      ctx.node(@syntax.LambdaBody, fn() {
        match ctx.peek() {
          @token.LBrace => parse_block_expr(ctx)
          _ => parse_expression_with_mode(ctx, allow_newline_application)
        }
      })
      true
    },
    is_sync_point,
  )
}

///|
fn parse_atom(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  if ctx.too_many_errors(MAX_ERRORS) {
    return
  }
  match ctx.peek() {
    @token.Integer =>
      ctx.node(@syntax.IntLiteral, fn() { ctx.emit_token(@syntax.IntToken) })
    @token.Identifier =>
      ctx.node(@syntax.VarRef, fn() { ctx.emit_token(@syntax.IdentToken) })
    @token.If =>
      ctx.node_with_recovery(
        @syntax.IfExpr,
        () => {
          ctx.emit_token(@syntax.IfKeyword)
          ctx.node(@syntax.IfCondition, fn() {
            parse_expression_with_mode(ctx, allow_newline_application)
          })
          if !lambda_expect(ctx, @token.Then, @syntax.ThenKeyword) {
            return false
          }
          ctx.node(@syntax.IfThen, fn() {
            parse_expression_with_mode(ctx, allow_newline_application)
          })
          if !lambda_expect(ctx, @token.Else, @syntax.ElseKeyword) {
            return false
          }
          ctx.node(@syntax.IfElse, fn() {
            parse_expression_with_mode(ctx, allow_newline_application)
          })
          true
        },
        is_sync_point,
      )
    @token.Hole =>
      ctx.node(@syntax.HoleLiteral, fn() { ctx.emit_token(@syntax.HoleToken) })
    @token.LBrace => parse_block_expr(ctx)
    @token.LeftParen =>
      if left_paren_starts_arrow_lambda(ctx) {
        parse_arrow_lambda(ctx, allow_newline_application)
      } else {
        ctx.node(@syntax.ParenExpr, () => {
          ctx.emit_token(@syntax.LeftParenToken)
          parse_expression_with_mode(ctx, allow_newline_application)
          if !lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken) {
            // RightParen missing — recover inside parens, but don't consume
            // parent-level delimiters (`in`/`then`/`else`/...) needed upstream.
            let _ = skip_until_paren_close_or_sync(ctx)
            if ctx.peek() == @token.RightParen {
              ctx.emit_token(@syntax.RightParenToken)
            }
          }
        })
      }
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

// ─── Lambda grammar ((FnDef | LetDef)* Expression?) ───────────────────────────

///|
/// Parse parameter list: ( Ident , Ident , ... )
/// Returns the number of identifier parameters consumed.
fn parse_param_list(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_empty~ : Bool,
) -> Int {
  let mark = ctx.mark()
  let mut count = 0
  ctx.emit_token(@syntax.LeftParenToken) // (
  match ctx.peek() {
    @token.RightParen =>
      if !allow_empty {
        ctx.error("Empty parameter list")
        ctx.emit_error_placeholder()
      }
    @token.Identifier => {
      ctx.emit_token(@syntax.IdentToken)
      count += 1
      if ctx.peek() == @token.Colon {
        parse_type_annotation(ctx)
      }
      while ctx.peek() == @token.Comma {
        ctx.emit_token(@syntax.CommaToken) // ,
        match ctx.peek() {
          @token.Identifier => {
            ctx.emit_token(@syntax.IdentToken)
            count += 1
          }
          @token.RightParen => {
            ctx.error("Trailing comma in parameter list")
            break
          }
          _ => {
            ctx.error("Expected parameter name")
            ctx.emit_error_placeholder()
          }
        }
        if ctx.peek() == @token.Colon {
          parse_type_annotation(ctx)
        }
      }
    }
    _ => {
      ctx.error("Expected parameter name")
      ctx.emit_error_placeholder()
    }
  }
  let _ = lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken) // )
  ctx.start_at(mark, @syntax.ParamList)
  ctx.finish_node()
  count
}

///|
/// Parse a value declaration: `let x = e` -> LetDef.
///
/// Unlike the old lambda example's `let f(x) = e` sugar, MoonBit-style `let`
/// declarations do not take parameter lists. Use `fn f(x) { e }` for functions.
fn parse_let_item(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.node(@syntax.LetDef, fn() {
    ctx.emit_token(@syntax.LetKeyword)
    match ctx.peek() {
      @token.Identifier => ctx.emit_token(@syntax.IdentToken)
      _ => {
        ctx.error("Expected variable name after 'let'")
        ctx.emit_error_placeholder()
      }
    }
    if ctx.peek() == @token.LeftParen {
      ctx.error("'let' declarations do not take parameter lists; use 'fn'")
    }
    let _ = lambda_expect(ctx, @token.Eq, @syntax.EqToken)
    parse_expression_with_mode(ctx, false)
  })
}

///|
/// Parse a named function definition: `fn f(x, y) { e }` -> LetDef.
///
/// Uses a brace-delimited body so edits inside one function have a stable
/// right boundary for block reparse/reuse.
fn parse_fn_item(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
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
      let _ = parse_param_list(ctx, allow_empty=true)
    } else {
      ctx.error("Expected parameter list after function name")
      ctx.emit_error_placeholder()
    }
    match ctx.peek() {
      @token.LBrace => parse_block_expr(ctx)
      _ => {
        ctx.error("Expected function body")
        ctx.emit_error_placeholder()
      }
    }
  })
}

///|
/// Entry point for lambda grammar: (FnDef | LetDef)* Expression?
/// Newline tokens (from tokenize) delimit definitions and are emitted
/// explicitly into the CST as direct children of SourceFile. They are token
/// children (not node children), so `SyntaxNode::children()` (node-only) never
/// yields them. Only `SyntaxNode::all_children()` would see them. The term
/// converter uses `children()`, so it only encounters LetDef and expression nodes.
/// Callers that use `all_children()` must handle `NewlineToken` explicitly.
fn parse_lambda_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let _ = consume_newline_tokens(ctx)
  while token_starts_definition(ctx.peek()) {
    // Try to reuse an entire RepeatGroup of LetDef siblings.
    // On hit, the group is emitted as a single ReuseNode and position
    // advances past all covered tokens — O(log n) vs O(n) reparsing.
    if ctx.try_reuse_repeat_group() {
      let _ = consume_newline_tokens(ctx)
      continue
    }
    parse_definition_item(ctx)
    let delimiter_count = consume_newline_tokens(ctx)
    if delimiter_count == 0 && ctx.peek() != @token.EOF {
      if token_starts_definition(ctx.peek()) {
        ctx.error("Expected newline between top-level definitions")
      } else {
        ctx.error("Expected newline after top-level definition")
      }
    }
  }
  let _ = consume_newline_tokens(ctx)
  match ctx.peek() {
    @token.EOF => ()
    _ => parse_expression(ctx)
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
/// Get the text of the current non-trivia token without consuming it.
fn peek_text(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> String {
  ctx.current_token_text().to_owned()
}

///|
fn parse_type(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_atom_type(ctx)
  if ctx.peek() == @token.Arrow {
    ctx.emit_token(@syntax.ArrowToken)
    parse_type(ctx) // right-recursive
    ctx.start_at(mark, @syntax.TypeArrow)
    ctx.finish_node()
  }
}

///|
fn parse_atom_type(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  match ctx.peek() {
    @token.Identifier => {
      let text = peek_text(ctx)
      match text {
        "Int" =>
          ctx.node(@syntax.TypeInt, fn() { ctx.emit_token(@syntax.IdentToken) })
        "Unit" =>
          ctx.node(@syntax.TypeUnit, fn() { ctx.emit_token(@syntax.IdentToken) })
        _ => {
          ctx.error("expected type, got identifier '" + text + "'")
          ctx.emit_error_placeholder()
        }
      }
    }
    @token.LeftParen => {
      ctx.emit_token(@syntax.LeftParenToken)
      parse_type(ctx)
      let _ = lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken)
    }
    _ => {
      ctx.error("expected type")
      ctx.emit_error_placeholder()
    }
  }
}

///|
fn parse_type_annotation(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.node(@syntax.TypeAnnot, fn() {
    ctx.emit_token(@syntax.ColonToken)
    parse_type(ctx)
  })
}

///|
/// Parse a source string (LetDef* Expression?). Returns tree with error recovery.
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  lambda_grammar.parse_cst(source)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor (for incremental use).
pub fn parse_cst_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo[@token.Token]],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics? : @core.DiagnosticSet? = None,
) -> (@seam.CstNode, @core.DiagnosticSet, Int) {
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

///|
/// Make a ReuseCursor from explicit damage coordinates.
///
/// Prefer `make_reuse_cursor_with_edit` when an `Edit` is available. This
/// compatibility helper immediately converts the raw coordinates to `Edit` so
/// cursor construction still follows the edit-based path.
pub fn make_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@token.TokenInfo[@token.Token]],
  source : String,
  old_token_cache? : @core.OldTokenCache = @core.OldTokenCache::empty(),
  allow_left_adjacent_reuse? : Bool = false,
  new_damage_end? : Int = damage_end,
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  let edit = @core.Edit::new(
    damage_start,
    damage_end - damage_start,
    new_damage_end - damage_start,
  )
  make_reuse_cursor_with_edit(
    old_tree,
    edit,
    tokens,
    source,
    old_token_cache~,
    allow_left_adjacent_reuse~,
  )
}

///|
/// Make a ReuseCursor from a compact edit operation.
///
/// This is the preferred helper for edit-driven incremental parsing.
pub fn make_reuse_cursor_with_edit(
  old_tree : @seam.CstNode,
  edit : @core.Edit,
  tokens : Array[@token.TokenInfo[@token.Token]],
  source : String,
  old_token_cache? : @core.OldTokenCache = @core.OldTokenCache::empty(),
  allow_left_adjacent_reuse? : Bool = false,
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  let starts = @core.build_starts(tokens)
  @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    fn(i) {
      source.view(start_offset=starts[i], end_offset=starts[i] + tokens[i].len)
    },
    lambda_spec,
    old_token_cache~,
    allow_left_adjacent_reuse~,
  )
}
