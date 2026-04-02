// Recursive descent parser for JSON with error recovery.

///|
const MAX_ERRORS : Int = 50

// ─── Grammar helpers ──────────────────────────────────────────────────────────

///|
fn is_value_start(token : Token) -> Bool {
  match token {
    LBrace | LBracket | StringLit | NumberLit | True | False | Null => true
    _ => false
  }
}

///|
fn is_sync_point(token : Token) -> Bool {
  match token {
    RBrace | RBracket | Comma | EOF => true
    _ => false
  }
}

///|
/// Parse a comma-separated list of elements with trailing-comma and
/// missing-comma error recovery.
fn parse_comma_separated(
  ctx : @core.ParserContext[Token, SyntaxKind],
  parse_element : (@core.ParserContext[Token, SyntaxKind]) -> Unit,
  is_element_start : (Token) -> Bool,
  closing_token : Token,
  element_name : String,
) -> Unit {
  parse_element(ctx)
  while ctx.peek() == Comma {
    ctx.emit_token(CommaToken)
    if ctx.peek() == closing_token {
      ctx.error("Trailing comma")
      break
    }
    parse_element(ctx)
  }
  // Missing comma recovery
  while is_element_start(ctx.peek()) {
    ctx.error("Expected ',' between " + element_name)
    parse_element(ctx)
    while ctx.peek() == Comma {
      ctx.emit_token(CommaToken)
      if ctx.peek() == closing_token {
        ctx.error("Trailing comma")
        break
      }
      parse_element(ctx)
    }
  }
}

///|
/// Expect a specific token, consuming it if present.
/// Returns true when the token was consumed, false when recovery fired.
fn json_expect(
  ctx : @core.ParserContext[Token, SyntaxKind],
  expected : Token,
  kind : SyntaxKind,
) -> Bool {
  if ctx.peek() == expected {
    ctx.emit_token(kind)
    true
  } else {
    ctx.error("Expected " + expected.to_string())
    false
  }
}

// ─── Grammar (entry point + rules) ───────────────────────────────────────────

///|
fn parse_value(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  if ctx.error_count >= MAX_ERRORS {
    // Consume token to avoid infinite loops in parse_comma_separated
    ctx.bump_error()
    return
  }
  match ctx.peek() {
    LBrace => parse_object(ctx)
    LBracket => parse_array(ctx)
    StringLit => ctx.node(StringValue, fn() { ctx.emit_token(StringToken) })
    NumberLit => ctx.node(NumberValue, fn() { ctx.emit_token(NumberToken) })
    True => ctx.node(BoolValue, fn() { ctx.emit_token(TrueKeyword) })
    False => ctx.node(BoolValue, fn() { ctx.emit_token(FalseKeyword) })
    Null => ctx.node(NullValue, fn() { ctx.emit_token(NullKeyword) })
    _ => {
      ctx.error("Expected JSON value")
      if is_sync_point(ctx.peek()) {
        ctx.start_node(ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        let _ = ctx.skip_until(is_sync_point)
      }
    }
  }
}

///|
/// Parse object: `{ member (, member)* }`
pub fn parse_object(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ObjectNode, fn() {
    ctx.emit_token(LBraceToken) // {
    if ctx.peek() != RBrace && ctx.peek() != EOF {
      parse_comma_separated(
        ctx,
        parse_member,
        fn(t) { t is StringLit },
        RBrace,
        "members",
      )
    }
    let _ = json_expect(ctx, RBrace, RBraceToken)
  })
}

///|
/// Parse array: `[ value (, value)* ]`
pub fn parse_array(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ArrayNode, fn() {
    ctx.emit_token(LBracketToken) // [
    if ctx.peek() != RBracket && ctx.peek() != EOF {
      parse_comma_separated(
        ctx,
        parse_value,
        is_value_start,
        RBracket,
        "elements",
      )
    }
    let _ = json_expect(ctx, RBracket, RBracketToken)
  })
}

///|
/// Parse member: `string : value`
fn parse_member(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(MemberNode, fn() {
    match ctx.peek() {
      StringLit => ctx.emit_token(StringToken)
      _ => {
        ctx.error("Expected string key")
        ctx.emit_error_placeholder()
      }
    }
    let _ = json_expect(ctx, Colon, ColonToken)
    parse_value(ctx)
  })
}

///|
/// Root entry point for JSON grammar.
fn parse_json_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  if ctx.peek() == EOF {
    ctx.error("Empty JSON input")
    return
  }
  parse_value(ctx)
  if ctx.peek() != EOF {
    ctx.error("Unexpected tokens after JSON value")
    let _ = ctx.skip_until(fn(t) { t == EOF })
  }
}

// ─── Public API ──────────────────────────────────────────────────────────────

///|
/// Parse a source string into a CST with error recovery.
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[Token]]) raise @core.LexError {
  json_grammar.parse_cst(source)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor (for incremental use).
pub fn parse_cst_recover_with_tokens(
  source : String,
  tokens : Array[@core.TokenInfo[Token]],
  cursor : @core.ReuseCursor[Token, SyntaxKind]?,
  prev_diagnostics? : Array[@core.Diagnostic[Token]]? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[Token]], Int) {
  let starts = @core.build_starts(tokens)
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    json_spec,
    cursor~,
    prev_diagnostics~,
  )
}

///|
/// Make a ReuseCursor for incremental parsing.
pub fn make_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@core.TokenInfo[Token]],
  source : String,
) -> @core.ReuseCursor[Token, SyntaxKind] {
  let starts = @core.build_starts(tokens)
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    fn(i) {
      source.view(start_offset=starts[i], end_offset=starts[i] + tokens[i].len)
    },
    json_spec,
  )
}
