// Recursive descent parser for simplified HTML with error recovery.
//
// This is a simplified tree builder, NOT a full HTML5 spec parser.
// Out of scope: optional closing tags, implied elements, foster parenting,
// namespace handling, entity references, and attribute value resolution.
// See AGENTS.md for the design rationale.

///|
const MAX_ERRORS : Int = 50

///|
const MAX_DEPTH : Int = 512

///|
fn parse_element(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_stack : Array[String],
  try_parse_rule : (String) -> Bool,
  depth~ : Int,
) -> Unit {
  if depth > MAX_DEPTH {
    ctx.error("Maximum HTML nesting depth exceeded")
    let _ = ctx.skip_until_progress(@token.is_sync_point)
    return
  }
  if ctx.too_many_errors(MAX_ERRORS) {
    let _ = ctx.skip_until_progress(@token.is_sync_point)
    return
  }

  match ctx.peek() {
    @token.OpenTag(name) => {
      let tag_name = name
      let kind = @syntax.classify_element(tag_name)
      let is_void = match kind {
        Some(value) => @syntax.is_void_element(value)
        None => false
      }
      let is_raw = match kind {
        Some(value) => @syntax.is_raw_text_element(value)
        None => false
      }
      ctx.start_node(@syntax.ElementNode)
      ctx.emit_token(@syntax.OpenTagToken)

      if is_void {
        ctx.finish_node()
        return
      }

      let base = tag_stack.length()
      let normalized_name = ascii_lower_tag_name(tag_name)
      tag_stack.push(normalized_name)
      if is_raw {
        match ctx.peek() {
          @token.RawText => {
            ctx.start_node(@syntax.RawTextLeaf)
            ctx.emit_token(@syntax.RawTextToken)
            ctx.finish_node()
          }
          _ => ()
        }
        finish_element(ctx, tag_stack, try_parse_rule, tag_name)
        while tag_stack.length() > base {
          ignore(tag_stack.pop())
        }
        ctx.finish_node()
        return
      }

      parse_content(ctx, tag_stack, try_parse_rule, tag_name, depth=depth + 1)
      while tag_stack.length() > base {
        ignore(tag_stack.pop())
      }
      ctx.finish_node()
    }
    _ => {
      ctx.error("Expected HTML element")
      ctx.emit_error_placeholder()
    }
  }
}

///|
fn parse_content(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_stack : Array[String],
  try_parse_rule : (String) -> Bool,
  tag_name : String,
  depth~ : Int,
) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      @token.CloseTag(name) => {
        if try_parse_rule("close_boundary") {
          ctx.emit_token(@syntax.CloseTagToken)
          return
        }
        let expected = tag_stack.last()
        match expected {
          Some(expected_name) =>
            ctx.error(
              "Mismatched close tag: expected </" +
              expected_name +
              ">, got </" +
              name +
              ">",
            )
          None => ctx.error("Unexpected close tag: </" + name + ">")
        }
        ctx.emit_error_placeholder()
        return
      }
      @token.OpenTag(_) => parse_element(ctx, tag_stack, try_parse_rule, depth~)
      @token.Text => {
        ctx.start_node(@syntax.TextLeaf)
        ctx.emit_token(@syntax.TextToken)
        ctx.finish_node()
      }
      _ => {
        ctx.error("Unexpected token in element content")
        let _ = ctx.skip_until_progress(@token.is_sync_point)
      }
    }
  }
  ctx.error("Unclosed element: " + tag_name)
}

///|
fn finish_element(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_stack : Array[String],
  try_parse_rule : (String) -> Bool,
  tag_name : String,
) -> Unit {
  match ctx.peek() {
    @token.CloseTag(name) =>
      if try_parse_rule("close_boundary") {
        ctx.emit_token(@syntax.CloseTagToken)
      } else {
        let expected = tag_stack.last()
        match expected {
          Some(expected_name) =>
            ctx.error(
              "Mismatched close tag: expected </" +
              expected_name +
              ">, got </" +
              name +
              ">",
            )
          None => ctx.error("Unexpected close tag: </" + name + ">")
        }
        ctx.emit_error_placeholder()
      }
    _ => {
      ctx.error("Expected </" + tag_name + ">")
      ctx.emit_error_placeholder()
    }
  }
}

///|
fn parse_html_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_stack : Array[String],
  try_parse_rule : (String) -> Bool,
) -> Unit {
  if ctx.peek() == @token.EOF {
    ctx.error("Empty HTML input")
    ctx.emit_error_placeholder()
    return
  }
  while !ctx.at_eof() {
    match ctx.peek() {
      @token.OpenTag(_) =>
        parse_element(ctx, tag_stack, try_parse_rule, depth=0)
      @token.Comment => {
        ctx.start_node(@syntax.CommentNode)
        ctx.emit_token(@syntax.CommentToken)
        ctx.finish_node()
      }
      @token.Doctype => {
        ctx.start_node(@syntax.DoctypeNode)
        ctx.emit_token(@syntax.DoctypeToken)
        ctx.finish_node()
      }
      @token.Text => {
        ctx.start_node(@syntax.TextLeaf)
        ctx.emit_token(@syntax.TextToken)
        ctx.finish_node()
      }
      _ => {
        ctx.error("Unexpected token")
        let _ = ctx.skip_until_progress(@token.is_sync_point)
      }
    }
  }
}

///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  html_grammar.parse_cst(source)
}
