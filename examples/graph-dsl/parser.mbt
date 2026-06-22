///|
const MAX_ERRORS : Int = 50

///|
fn is_statement_start(token : Token) -> Bool {
  token == Identifier
}

///|
fn is_value_start(token : Token) -> Bool {
  match token {
    Number | StringLit | Identifier => true
    _ => false
  }
}

///|
fn is_argument_end(token : Token) -> Bool {
  match token {
    Comma | RParen | Newline | EOF => true
    _ => false
  }
}

///|
fn graph_expect(
  ctx : @core.ParserContext[Token, SyntaxKind],
  expected : Token,
  kind : SyntaxKind,
  label : String,
) -> Bool {
  if ctx.peek() == expected {
    ctx.emit_token(kind)
    true
  } else {
    ctx.error("Expected " + label)
    ctx.emit_error_placeholder()
    false
  }
}

///|
fn parse_value(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ValueNode, fn() {
    match ctx.peek() {
      Number => {
        ctx.emit_token(NumberToken)
        if ctx.peek() == Identifier {
          // Unit suffix, for example `440Hz` or `2ms`. The projection assigns
          // the semantic Unit role; syntactically it is still an identifier.
          ctx.emit_token(IdentifierToken)
        }
      }
      StringLit => ctx.emit_token(StringToken)
      Identifier => ctx.emit_token(IdentifierToken)
      _ => {
        ctx.error("Expected argument value")
        if is_argument_end(ctx.peek()) {
          ctx.emit_error_placeholder()
        } else {
          ctx.bump_error()
        }
      }
    }
  })
}

///|
fn parse_argument(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(ArgumentNode, fn() {
    if ctx.peek() == Identifier {
      ctx.emit_token(IdentifierToken)
    } else {
      ctx.error("Expected argument name")
      ctx.emit_error_placeholder()
    }
    let _ = graph_expect(ctx, Colon, ColonToken, "':'")
    parse_value(ctx)
  })
}

///|
fn parse_arguments(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  let mut need_argument = true
  while ctx.peek() != RParen && ctx.peek() != Newline && ctx.peek() != EOF {
    if need_argument {
      if is_value_start(ctx.peek()) {
        parse_argument(ctx)
        need_argument = false
      } else {
        ctx.error("Expected argument")
        ctx.bump_error()
        need_argument = false
      }
    } else if ctx.peek() == Comma {
      ctx.emit_token(CommaToken)
      need_argument = true
    } else if ctx.peek() == Identifier {
      ctx.error("Expected ',' between arguments")
      parse_argument(ctx)
      need_argument = false
    } else {
      ctx.error("Expected ',' or ')' after argument")
      ctx.bump_error()
    }
  }
}

///|
fn parse_call(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(CallNode, fn() {
    if ctx.peek() == Identifier {
      ctx.emit_token(IdentifierToken)
    } else {
      ctx.error("Expected constructor name")
      ctx.emit_error_placeholder()
    }
    if graph_expect(ctx, LParen, LParenToken, "'('") {
      parse_arguments(ctx)
      let _ = graph_expect(ctx, RParen, RParenToken, "')'")
    }
  })
}

///|
fn parse_output(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.node(OutputNode, fn() {
    ctx.emit_token(ArrowToken)
    if ctx.peek() == Identifier {
      ctx.emit_token(IdentifierToken)
    } else {
      ctx.error("Expected output name")
      ctx.emit_error_placeholder()
    }
  })
}

///|
fn skip_statement_tail(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  while ctx.peek() != Newline && ctx.peek() != EOF {
    ctx.error("Unexpected token after graph binding")
    ctx.bump_error()
  }
}

///|
fn parse_binding(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  if ctx.too_many_errors(MAX_ERRORS) {
    ctx.bump_error()
    return
  }
  ctx.node(BindingNode, fn() {
    if ctx.peek() == Identifier {
      ctx.emit_token(IdentifierToken)
    } else {
      ctx.error("Expected node binding name")
      ctx.emit_error_placeholder()
    }
    let _ = graph_expect(ctx, Equal, EqualToken, "'='")
    parse_call(ctx)
    if ctx.peek() == Arrow {
      parse_output(ctx)
    }
  })
  skip_statement_tail(ctx)
}

///|
fn parse_graph_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      Newline => ctx.emit_token(NewlineToken)
      token if is_statement_start(token) => parse_binding(ctx)
      _ => {
        ctx.error("Expected graph node binding")
        ctx.bump_error()
      }
    }
  }
}

///|
let graph_spec : @core.LanguageSpec[Token, SyntaxKind] = @core.LanguageSpec::new(
  WhitespaceToken,
  ErrorToken,
  RootNode,
  EOF,
  parse_root=parse_graph_root,
  reuse_size_threshold=0,
)
