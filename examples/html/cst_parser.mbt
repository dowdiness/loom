// Recursive descent parser for simplified HTML with error recovery.

///|
const MAX_ERRORS : Int = 50

///|
const MAX_DEPTH : Int = 512

///|
fn is_void_tag(name : String) -> Bool {
  match name {
    "area"
    | "base"
    | "br"
    | "col"
    | "embed"
    | "hr"
    | "img"
    | "input"
    | "link"
    | "meta"
    | "param"
    | "source"
    | "track"
    | "wbr" => true
    _ => false
  }
}

///|
fn is_raw_text_tag(name : String) -> Bool {
  name == "script" || name == "style"
}

///|
fn is_sync_point(token : Token) -> Bool {
  match token {
    OpenTag(_) | CloseTag(_) | EOF => true
    _ => false
  }
}

///|
/// Parse an HTML element: open tag, children, close tag.
fn parse_element(
  ctx : @core.ParserContext[Token, SyntaxKind],
  depth~ : Int,
) -> Unit {
  if depth > MAX_DEPTH {
    ctx.error("Maximum HTML nesting depth exceeded")
    if is_sync_point(ctx.peek()) {
      ctx.start_node(ErrorNode)
      ctx.emit_error_placeholder()
      ctx.finish_node()
    } else {
      let _ = ctx.skip_until(is_sync_point)
    }
    return
  }
  if ctx.too_many_errors(MAX_ERRORS) {
    ctx.bump_error()
    return
  }

  match ctx.peek() {
    OpenTag(name) => {
      let tag_name = name
      let is_void = is_void_tag(tag_name)
      let is_raw = is_raw_text_tag(tag_name)
      ctx.start_node(ElementNode)
      ctx.emit_token(OpenTagToken)

      if is_void {
        ctx.finish_node()
        return
      }

      if is_raw {
        match ctx.peek() {
          RawText => {
            ctx.start_node(RawTextLeaf)
            ctx.emit_token(RawTextToken)
            ctx.finish_node()
          }
          _ => ()
        }
        finish_element(ctx, tag_name)
        ctx.finish_node()
        return
      }

      // Normal element: parse children until matching close tag
      parse_content(ctx, tag_name, depth=depth + 1)
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
  ctx : @core.ParserContext[Token, SyntaxKind],
  tag_name : String,
  depth~ : Int,
) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      CloseTag(name) if name == tag_name => {
        ctx.emit_token(CloseTagToken)
        return
      }
      CloseTag(other_name) => {
        ctx.error(
          "Mismatched close tag: expected </" +
          tag_name +
          ">, got </" +
          other_name +
          ">",
        )
        ctx.emit_error_placeholder()
        return
      }
      OpenTag(_) => parse_element(ctx, depth~)
      Text => {
        ctx.start_node(TextLeaf)
        ctx.emit_token(TextToken)
        ctx.finish_node()
      }
      _ => {
        ctx.error("Unexpected token in element content")
        let _ = ctx.skip_until(is_sync_point)
      }
    }
  }
  ctx.error("Unclosed element: " + tag_name)
}

///|
/// Expect a matching close tag for the given tag name.
fn finish_element(
  ctx : @core.ParserContext[Token, SyntaxKind],
  tag_name : String,
) -> Unit {
  match ctx.peek() {
    CloseTag(name) if name == tag_name => ctx.emit_token(CloseTagToken)
    CloseTag(name) => {
      ctx.error(
        "Mismatched close tag: expected </" +
        tag_name +
        ">, got </" +
        name +
        ">",
      )
      ctx.emit_error_placeholder()
    }
    _ => {
      ctx.error("Expected </" + tag_name + ">")
      ctx.emit_error_placeholder()
    }
  }
}

///|
fn parse_html_root(ctx : @core.ParserContext[Token, SyntaxKind]) -> Unit {
  ctx.start_node(RootNode)
  if ctx.peek() == EOF {
    ctx.error("Empty HTML input")
    ctx.emit_error_placeholder()
    ctx.finish_node()
    return
  }
  while !ctx.at_eof() {
    match ctx.peek() {
      OpenTag(_) => parse_element(ctx, depth=0)
      Comment => {
        ctx.start_node(CommentNode)
        ctx.emit_token(CommentToken)
        ctx.finish_node()
      }
      Doctype => {
        ctx.start_node(DoctypeNode)
        ctx.emit_token(DoctypeToken)
        ctx.finish_node()
      }
      Text => {
        ctx.start_node(TextLeaf)
        ctx.emit_token(TextToken)
        ctx.finish_node()
      }
      _ => {
        ctx.error("Unexpected token")
        let _ = ctx.skip_until(is_sync_point)
      }
    }
  }
  ctx.finish_node()
}
