// Recursive descent parser for simplified JSX with error recovery,
// implementing the streaming-prefix recovery design validated in the
// 2026-07-10 Task 1.1 design gate (canopy
// docs/plans/2026-07-09-jsx-incremental-parser-generative-ui.md,
// "Design B — error recovery on a streaming JSX prefix").
//
// Recovery philosophy follows examples/html/cst_parser.mbt: diagnostics
// annotate, they never gate node creation — an unclosed element, fragment,
// or expression keeps every already-parsed child (Design B's hard CST-shape
// requirement for Phase 2's incremental visible growth). EOF inside a tag
// gets its own direct diagnose-and-finish exit; every non-EOF recovery loop
// uses skip_until_progress, never plain skip_until (loom #647 precedent).

///|
const MAX_ERRORS : Int = 50

///|
const MAX_DEPTH : Int = 512

///|
/// Sync points for recovery: tag boundaries and EOF, mirroring html's
/// OpenTag/CloseTag/EOF set at jsx's finer token granularity.
fn is_sync_point(token : @token.Token) -> Bool {
  match token {
    @token.OpenTagStart
    | @token.TagEnd
    | @token.SelfCloseEnd
    | @token.FragmentOpen
    | @token.FragmentClose
    | @token.EOF => true
    _ => false
  }
}

///|
/// True when the next tokens form a close-tag prefix (`<` `/`). jsx has no
/// dedicated close-tag token: `</name>` lexes as OpenTagStart, Slash,
/// TagName, TagEnd.
fn at_close_tag(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  ctx.peek() is @token.OpenTagStart && ctx.peek_nth(1) is @token.Slash
}

///|
/// Read the close tag's name without consuming anything. jsx tokens carry
/// no payload, so the name is only reachable as the TagName token's source
/// text — consume up to it speculatively and roll back. Returns None when
/// no TagName follows `</` (input truncated right after the slash).
fn peek_close_tag_name(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> String? {
  ctx.speculative(() => {
    ctx.emit_token(@syntax.OpenTagStartToken)
    ctx.emit_token(@syntax.SlashToken)
    if ctx.peek() is @token.TagName {
      Some(ctx.current_token_text().to_owned())
    } else {
      None
    }
  })
}

///|
/// Consume a close-tag sequence (`<` `/` [name] [`>`]) into the current
/// node. The caller has already decided this close tag belongs to the
/// element/fragment being finished; a missing `>` (EOF) is diagnosed but
/// the node still closes normally.
fn emit_close_tag(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_name : String,
) -> Unit {
  ctx.emit_token(@syntax.OpenTagStartToken)
  ctx.emit_token(@syntax.SlashToken)
  if ctx.peek() is @token.TagName {
    ctx.emit_token(@syntax.TagNameToken)
  }
  match ctx.peek() {
    @token.TagEnd => ctx.emit_token(@syntax.TagEndToken)
    _ => ctx.error("Truncated close tag: </" + tag_name + ">")
  }
}

///|
fn parse_text_leaf(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.TextLeaf)
  ctx.emit_token(@syntax.TextToken)
  ctx.finish_node()
}

///|
/// Parse a `{...}` embedded-expression span (Design B case 4). The node is
/// assembled from real tokens like any other subtree; on EOF without a
/// closing brace it finishes with whatever content it already collected.
/// An ExprStringUnterminated child additionally means EOF hit inside a
/// string literal, which gets its own additive diagnostic alongside — not
/// instead of — the missing-`}` one.
fn parse_expr_span(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.ExprSpanNode)
  ctx.emit_token(@syntax.BraceOpenToken)
  while true {
    match ctx.peek() {
      @token.ExprRawText => ctx.emit_token(@syntax.ExprRawTextToken)
      @token.ExprStringUnterminated => {
        ctx.error("Unterminated string literal in expression")
        ctx.emit_token(@syntax.ExprStringUnterminatedToken)
      }
      @token.BraceClose => {
        ctx.emit_token(@syntax.BraceCloseToken)
        ctx.finish_node()
        return
      }
      // The lexer only produces the three kinds above inside an expression,
      // so this is the EOF exit: diagnose and finish with the children
      // already collected.
      _ => {
        ctx.error("Unclosed expression: missing '}'")
        ctx.finish_node()
        return
      }
    }
  }
}

///|
/// Parse one attribute: `name`, `name=value` with a string-literal or
/// `{expr}` value. An unterminated string value arrives as a normal
/// AttrStringLitUnterminated token (content preserved by the lexer); the
/// parser is what pushes the diagnostic on top of it (Design B case 3).
fn parse_attribute(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.AttrNode)
  ctx.emit_token(@syntax.AttrNameToken)
  if ctx.peek() is @token.Eq {
    ctx.emit_token(@syntax.EqToken)
    match ctx.peek() {
      @token.AttrStringLit => ctx.emit_token(@syntax.AttrStringLitToken)
      @token.AttrStringLitUnterminated => {
        ctx.error("Unterminated attribute string literal")
        ctx.emit_token(@syntax.AttrStringLitUnterminatedToken)
      }
      @token.BraceOpen => parse_expr_span(ctx)
      _ => ctx.error("Expected attribute value")
    }
  }
  ctx.finish_node()
}

///|
/// Parse an element from its OpenTagStart. The tag-body loop has exactly
/// two families of exits per Design B case 3: EOF gets its own direct
/// diagnose-and-finish branch (nothing left to skip past), and any other
/// unexpected token goes through skip_until_progress — never plain
/// skip_until, whose no-progress hazard on a token that is already a sync
/// point is what loom #647 fixed at html's root.
fn parse_element(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  depth~ : Int,
) -> Unit {
  if depth > MAX_DEPTH {
    ctx.error("Maximum JSX nesting depth exceeded")
    let _ = ctx.skip_until_progress(is_sync_point)
    return
  }
  if ctx.too_many_errors(MAX_ERRORS) {
    ctx.bump_error()
    return
  }
  ctx.start_node(@syntax.ElementNode)
  ctx.emit_token(@syntax.OpenTagStartToken)
  let tag_name = if ctx.peek() is @token.TagName {
    let name = ctx.current_token_text().to_owned()
    ctx.emit_token(@syntax.TagNameToken)
    name
  } else {
    ctx.error("Expected tag name")
    ""
  }
  while true {
    match ctx.peek() {
      @token.SelfCloseEnd => {
        ctx.emit_token(@syntax.SelfCloseEndToken)
        ctx.finish_node()
        return
      }
      @token.TagEnd => {
        ctx.emit_token(@syntax.TagEndToken)
        parse_content(ctx, tag_name, depth=depth + 1)
        ctx.finish_node()
        return
      }
      @token.AttrName => parse_attribute(ctx)
      @token.EOF => {
        ctx.error("Truncated tag: <" + tag_name + ">")
        ctx.finish_node()
        return
      }
      _ => {
        ctx.error("Unexpected token in tag")
        let _ = ctx.skip_until_progress(is_sync_point)
      }
    }
  }
}

///|
/// Element-content loop (Design B case 2): children are emitted as normal
/// CST children of the open element until a matching close tag, a
/// mismatch (which unwinds to let an ancestor claim the close tag, per
/// html's precedent), or EOF — where the diagnostic is pushed and the
/// caller still finishes the node with every child intact.
fn parse_content(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  tag_name : String,
  depth~ : Int,
) -> Unit {
  while !ctx.at_eof() {
    if at_close_tag(ctx) {
      match peek_close_tag_name(ctx) {
        Some(name) if name == tag_name => {
          emit_close_tag(ctx, tag_name)
          return
        }
        Some(other) => {
          ctx.error(
            "Mismatched close tag: expected </" +
            tag_name +
            ">, got </" +
            other +
            ">",
          )
          ctx.emit_error_placeholder()
          return
        }
        // `</` truncated by EOF before any name: claim it for the element
        // being closed rather than guessing at a mismatch.
        None => {
          emit_close_tag(ctx, tag_name)
          return
        }
      }
    }
    match ctx.peek() {
      @token.OpenTagStart => parse_element(ctx, depth~)
      @token.FragmentOpen => parse_fragment(ctx, depth~)
      @token.FragmentClose => {
        ctx.error("Mismatched close tag: expected </" + tag_name + ">, got </>")
        ctx.emit_error_placeholder()
        return
      }
      @token.Text => parse_text_leaf(ctx)
      @token.BraceOpen => parse_expr_span(ctx)
      _ => {
        ctx.error("Unexpected token in element content")
        let _ = ctx.skip_until_progress(is_sync_point)
      }
    }
  }
  ctx.error("Unclosed JSX element: <" + tag_name + ">")
}

///|
fn parse_fragment(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  depth~ : Int,
) -> Unit {
  if depth > MAX_DEPTH {
    ctx.error("Maximum JSX nesting depth exceeded")
    let _ = ctx.skip_until_progress(is_sync_point)
    return
  }
  if ctx.too_many_errors(MAX_ERRORS) {
    ctx.bump_error()
    return
  }
  ctx.start_node(@syntax.FragmentNode)
  ctx.emit_token(@syntax.FragmentOpenToken)
  parse_fragment_content(ctx, depth=depth + 1)
  ctx.finish_node()
}

///|
/// Fragment-content loop — same shape as parse_content with FragmentClose
/// as the matching close; a named close tag here is a mismatch that
/// unwinds to an ancestor element.
fn parse_fragment_content(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  depth~ : Int,
) -> Unit {
  while !ctx.at_eof() {
    if at_close_tag(ctx) {
      let got = match peek_close_tag_name(ctx) {
        Some(name) => "</" + name + ">"
        None => "</"
      }
      ctx.error("Mismatched close tag: expected </>, got " + got)
      ctx.emit_error_placeholder()
      return
    }
    match ctx.peek() {
      @token.FragmentClose => {
        ctx.emit_token(@syntax.FragmentCloseToken)
        return
      }
      @token.OpenTagStart => parse_element(ctx, depth~)
      @token.FragmentOpen => parse_fragment(ctx, depth~)
      @token.Text => parse_text_leaf(ctx)
      @token.BraceOpen => parse_expr_span(ctx)
      _ => {
        ctx.error("Unexpected token in fragment content")
        let _ = ctx.skip_until_progress(is_sync_point)
      }
    }
  }
  ctx.error("Unclosed JSX fragment")
}

///|
fn parse_jsx_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  // The parse entry point already wraps all events in spec.root_kind
  // (RootNode) — the grammar must not open a second one (markdown/json
  // precedent; html's own root double-wraps, unasserted by its tests).
  if ctx.peek() is @token.EOF {
    ctx.error("Empty JSX input")
    ctx.emit_error_placeholder()
    return
  }
  while !ctx.at_eof() {
    if at_close_tag(ctx) {
      // A stray close tag at the root is consumed as one contiguous error
      // unit with a single diagnostic — jsx's fine-grained tokens would
      // otherwise cascade one diagnostic per token of the sequence.
      ctx.error("Unexpected close tag")
      ctx.start_node(@syntax.ErrorNode)
      ctx.bump_error()
      ctx.bump_error()
      if ctx.peek() is @token.TagName {
        ctx.bump_error()
      }
      if ctx.peek() is @token.TagEnd {
        ctx.bump_error()
      }
      ctx.finish_node()
      continue
    }
    match ctx.peek() {
      @token.OpenTagStart => parse_element(ctx, depth=0)
      @token.FragmentOpen => parse_fragment(ctx, depth=0)
      @token.Text => parse_text_leaf(ctx)
      @token.BraceOpen => parse_expr_span(ctx)
      _ => {
        ctx.error("Unexpected token")
        let _ = ctx.skip_until_progress(is_sync_point)
      }
    }
  }
}

///|
/// Syntax-only grammar for Step 4: CST + diagnostics without an AST fold.
/// Step 5 (fold_node/ast.mbt) will add the full Grammar on top of the same
/// spec and lexer.
let jsx_syntax_grammar : @loom.SyntaxGrammar[@token.Token, @syntax.SyntaxKind] = @loom.SyntaxGrammar::new(
  spec=jsx_spec,
  lex~,
  incremental_relex_enabled=false,
  mode_relex=Some(jsx_mode_relex_state),
)

///|
pub fn parse_cst(
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError {
  jsx_syntax_grammar.parse_cst(source)
}
