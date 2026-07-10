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
/// HTML tag/element names are ASCII case-insensitive per spec — the lexer's
/// raw-text mode switch and this parser-side gate must agree, so both call
/// this single function rather than duplicating the tag-name check.
fn is_raw_text_tag(name : String) -> Bool {
  let lower = name.to_lower()
  lower == "script" || lower == "style"
}

///|
fn is_sync_point(token : @token.Token) -> Bool {
  match token {
    @token.OpenTag(_) | @token.CloseTag(_) | @token.EOF => true
    _ => false
  }
}

///|
fn parse_element(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  depth~ : Int,
) -> Unit {
  if depth > MAX_DEPTH {
    ctx.error("Maximum HTML nesting depth exceeded")
    if is_sync_point(ctx.peek()) {
      ctx.start_node(@syntax.ErrorNode)
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
    @token.OpenTag(name) => {
      let tag_name = name
      let is_void = is_void_tag(tag_name)
      let is_raw = is_raw_text_tag(tag_name)
      ctx.start_node(@syntax.ElementNode)
      ctx.emit_token(@syntax.OpenTagToken)

      if is_void {
        ctx.finish_node()
        return
      }

      if is_raw {
        match ctx.peek() {
          @token.RawText => {
            ctx.start_node(@syntax.RawTextLeaf)
            ctx.emit_token(@syntax.RawTextToken)
            ctx.finish_node()
          }
          _ => ()
        }
        finish_element(ctx, tag_name)
        ctx.finish_node()
        return
      }

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
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_name : String,
  depth~ : Int,
) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      @token.CloseTag(name) if name == tag_name => {
        ctx.emit_token(@syntax.CloseTagToken)
        return
      }
      @token.CloseTag(other_name) => {
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
      @token.OpenTag(_) => parse_element(ctx, depth~)
      @token.Text => {
        ctx.start_node(@syntax.TextLeaf)
        ctx.emit_token(@syntax.TextToken)
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
fn finish_element(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_name : String,
) -> Unit {
  // Loop invariant: peek() returns a CloseTag or we're at EOF.
  // is_sync_point includes CloseTag(_) and EOF, so skip_until won't loop.
  match ctx.peek() {
    @token.CloseTag(name) if name == tag_name =>
      ctx.emit_token(@syntax.CloseTagToken)
    @token.CloseTag(name) => {
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
fn parse_html_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.RootNode)
  if ctx.peek() == @token.EOF {
    ctx.error("Empty HTML input")
    ctx.emit_error_placeholder()
    ctx.finish_node()
    return
  }
  while !ctx.at_eof() {
    match ctx.peek() {
      @token.OpenTag(_) => parse_element(ctx, depth=0)
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
        // A stray CloseTag at the root is itself a sync point, so plain
        // skip_until would consume nothing and spin here forever (loom #646).
        // skip_until_progress guarantees we consume the offending token.
        ctx.error("Unexpected token")
        let _ = ctx.skip_until_progress(is_sync_point)
      }
    }
  }
  ctx.finish_node()
}

///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  html_grammar.parse_cst(source)
}
