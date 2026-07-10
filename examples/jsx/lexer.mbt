// Mode-aware lexer for simplified JSX, implementing the embedded-expression
// mode-switch design validated in the 2026-07-10 Task 1.1 design gate
// (canopy docs/plans/2026-07-09-jsx-incremental-parser-generative-ui.md,
// "Design A — embedded-expression mode switch").

///|
fn is_jsx_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
fn is_jsx_name_start_char(c : Char) -> Bool {
  let n = c.to_int()
  n is ('a'..='z') || n is ('A'..='Z') || c == '_'
}

///|
fn is_jsx_name_char(c : Char) -> Bool {
  let n = c.to_int()
  n is ('a'..='z') ||
  n is ('A'..='Z') ||
  n is ('0'..='9') ||
  c == '-' ||
  c == '_' ||
  c == ':'
}

///|
fn is_jsx_quote(c : Char) -> Bool {
  c == '"' || c == '\'' || c == '`'
}

///|
/// Lex mode. `TagBody(expects_tag_name~)` is Task 1.2's mechanical
/// extension of Design A's `TagBody` (the design gate explicitly scoped
/// "how TagBody recognizes an attribute name vs `>`/`/>`" out of Task 1.1) —
/// `expects_tag_name` is true immediately after `OpenTagStart`/`Slash`
/// (the next identifier is the tag's own name), false afterward (subsequent
/// identifiers are attribute names).
///
/// `JsExprRaw(depth~, origin~)` is Design A's brace-depth-in-mode shape,
/// following the `CodeBlock(fence_len)`/`HtmlBlockUntil(delimiter)`
/// precedent in `examples/markdown/lexer.mbt`.
///
/// Design A also describes a `JsExprString(quote~, depth~, origin~)` mode
/// for string-literal scanning inside an expression. This lexer realizes
/// that behavior without a persisted mode value: `lex_expr_string_literal`
/// below scans an entire quoted literal (open quote to matching close, or
/// EOF) within a single `lex_step` call — the same one-call-spans-many-
/// characters shape `read_attr_value`/`OpenTag` already use in
/// `examples/html/lexer.mbt` — then returns directly to `JsExprRaw` with
/// depth carried through unchanged. This produces the exact token stream
/// Design A/B specify (a separate `ExprRawText`/`ExprStringUnterminated`
/// token per string boundary, so the parser can see where a string starts
/// and ends) without needing a fifth mode variant to thread across calls.
pub(all) enum JsxLexMode {
  Children
  TagBody(expects_tag_name~ : Bool)
  JsExprRaw(depth~ : Int, origin~ : ExprOrigin)
} derive(Eq, Debug)

///|
/// Which context an embedded `{...}` expression was entered from, so its
/// closing `}` knows which mode to resume — `TagBody` is the one concrete
/// resume state for `FromAttrValue` (Design A, Codex round-2 fix).
pub(all) enum ExprOrigin {
  FromChildren
  FromAttrValue
} derive(Eq, Debug)

///|
fn lex_children(
  source : String,
  pos : Int,
) -> (@core.LexStep[@token.Token], JsxLexMode) {
  let cursor = @core.LexCursor::new(source, pos)
  match cursor.peek() {
    Some('<') =>
      if cursor.starts_with("</>") {
        ignore(cursor.advance_code_units(3))
        (cursor.produced(@token.FragmentClose), Children)
      } else if cursor.starts_with("<>") {
        ignore(cursor.advance_code_units(2))
        (cursor.produced(@token.FragmentOpen), Children)
      } else {
        ignore(cursor.advance_char())
        (cursor.produced(@token.OpenTagStart), TagBody(expects_tag_name=true))
      }
    Some('{') => {
      ignore(cursor.advance_char())
      (
        cursor.produced(@token.BraceOpen),
        JsExprRaw(depth=1, origin=FromChildren),
      )
    }
    Some(_) => {
      while !cursor.is_done() {
        match cursor.peek() {
          Some('<') | Some('{') => break
          _ => ignore(cursor.advance_char())
        }
      }
      (cursor.produced(@token.Text), Children)
    }
    None => (Done, Children)
  }
}

///|
/// Scan a quoted attribute value from the opening quote, preserving
/// whatever was scanned as a normal `Produced` token even if EOF is hit
/// before the closing quote — `AttrStringLitUnterminated` instead of a
/// framework-injected error token, per Design B case 3 (Codex round 1).
fn lex_attr_string(
  cursor : @core.LexCursor,
  quote : Char,
) -> (@core.LexStep[@token.Token], JsxLexMode) {
  ignore(cursor.advance_char())
  while !cursor.is_done() {
    match cursor.peek() {
      Some(ch) if ch == quote => {
        ignore(cursor.advance_char())
        return (
          cursor.produced(@token.AttrStringLit),
          TagBody(expects_tag_name=false),
        )
      }
      Some('\\') => {
        ignore(cursor.advance_char())
        if !cursor.is_done() {
          ignore(cursor.advance_char())
        }
      }
      _ => ignore(cursor.advance_char())
    }
  }
  (
    cursor.produced(@token.AttrStringLitUnterminated),
    TagBody(expects_tag_name=false),
  )
}

///|
fn lex_tag_body(
  source : String,
  pos : Int,
  expects_tag_name : Bool,
) -> (@core.LexStep[@token.Token], JsxLexMode) {
  let cursor = @core.LexCursor::new(source, pos)
  match cursor.peek() {
    Some(ch) if is_jsx_whitespace(ch) => {
      ignore(cursor.take_while(is_jsx_whitespace))
      (cursor.produced(@token.Whitespace), TagBody(expects_tag_name~))
    }
    Some('/') if cursor.starts_with("/>") => {
      ignore(cursor.advance_code_units(2))
      (cursor.produced(@token.SelfCloseEnd), Children)
    }
    Some('/') => {
      ignore(cursor.advance_char())
      (cursor.produced(@token.Slash), TagBody(expects_tag_name~))
    }
    Some('>') => {
      ignore(cursor.advance_char())
      (cursor.produced(@token.TagEnd), Children)
    }
    Some('=') => {
      ignore(cursor.advance_char())
      (cursor.produced(@token.Eq), TagBody(expects_tag_name=false))
    }
    Some('{') => {
      ignore(cursor.advance_char())
      (
        cursor.produced(@token.BraceOpen),
        JsExprRaw(depth=1, origin=FromAttrValue),
      )
    }
    Some(quote) if is_jsx_quote(quote) => lex_attr_string(cursor, quote)
    Some(ch) if is_jsx_name_start_char(ch) => {
      ignore(cursor.take_while(is_jsx_name_char))
      let kind = if expects_tag_name { @token.TagName } else { @token.AttrName }
      (cursor.produced(kind), TagBody(expects_tag_name=false))
    }
    Some(_) => {
      ignore(cursor.advance_char())
      (
        cursor.invalid("unexpected character in tag"),
        TagBody(expects_tag_name~),
      )
    }
    None => (Done, TagBody(expects_tag_name~))
  }
}

///|
/// Scan a string/template literal inside an embedded expression, from the
/// opening quote through the matching unescaped quote or EOF. Depth is
/// carried through unchanged — string content never participates in brace
/// counting, not even backtick literals containing `${...}` (Design A
/// explicitly scopes nested template-literal `${}` tracking out of Phase 1;
/// a bare `` ` `` here is just another opaque delimiter, same rule as
/// `"`/`'`). Returns `ExprStringUnterminated` instead of `ExprRawText` when
/// EOF is hit inside the string, so the parser can push an additive
/// "unterminated string literal in expression" diagnostic distinct from
/// "missing `}`" (Design B case 4, Codex round-2 gap).
fn lex_expr_string_literal(
  cursor : @core.LexCursor,
  quote : Char,
  depth : Int,
  origin : ExprOrigin,
) -> (@core.LexStep[@token.Token], JsxLexMode) {
  ignore(cursor.advance_char())
  while !cursor.is_done() {
    match cursor.peek() {
      Some(ch) if ch == quote => {
        ignore(cursor.advance_char())
        return (cursor.produced(@token.ExprRawText), JsExprRaw(depth~, origin~))
      }
      Some('\\') => {
        ignore(cursor.advance_char())
        if !cursor.is_done() {
          ignore(cursor.advance_char())
        }
      }
      _ => ignore(cursor.advance_char())
    }
  }
  (cursor.produced(@token.ExprStringUnterminated), JsExprRaw(depth~, origin~))
}

///|
/// Scan raw expression content, tracking depth locally starting from the
/// mode's current depth. Stops (without consuming) at a quote character —
/// handing off to `lex_expr_string_literal` on the next call — or at the
/// `}` that closes depth back to the outermost level, so that closing
/// brace becomes its own `BraceClose` token on the following call. Nested
/// `{`/`}` are counted but never separately tokenized: they are ordinary
/// characters within this `ExprRawText` run (Design B case 4 / Codex
/// round-2 "multiple tokens don't imply multiple projection nodes").
fn lex_expr_raw(
  source : String,
  pos : Int,
  depth : Int,
  origin : ExprOrigin,
) -> (@core.LexStep[@token.Token], JsxLexMode) {
  let cursor = @core.LexCursor::new(source, pos)
  match cursor.peek() {
    None => (Done, JsExprRaw(depth~, origin~))
    Some(quote) if is_jsx_quote(quote) =>
      lex_expr_string_literal(cursor, quote, depth, origin)
    Some('}') if depth == 1 => {
      ignore(cursor.advance_char())
      let return_mode = match origin {
        FromChildren => Children
        FromAttrValue => TagBody(expects_tag_name=false)
      }
      (cursor.produced(@token.BraceClose), return_mode)
    }
    Some(_) => {
      let mut local_depth = depth
      let mut stop = false
      while !cursor.is_done() && !stop {
        match cursor.peek() {
          Some('{') => {
            local_depth = local_depth + 1
            ignore(cursor.advance_char())
          }
          Some('}') =>
            if local_depth == 1 {
              stop = true
            } else {
              local_depth = local_depth - 1
              ignore(cursor.advance_char())
            }
          Some(q) if is_jsx_quote(q) => stop = true
          _ => ignore(cursor.advance_char())
        }
      }
      (
        cursor.produced(@token.ExprRawText),
        JsExprRaw(depth=local_depth, origin~),
      )
    }
  }
}

///|
/// Mode-aware lex step. Dispatches to mode-specific lexer.
pub fn jsx_lex_step(
  source : String,
  pos : Int,
  mode : JsxLexMode,
) -> (@core.LexStep[@token.Token], JsxLexMode) {
  if pos >= source.length() {
    return (Done, mode)
  }
  match mode {
    Children => lex_children(source, pos)
    TagBody(expects_tag_name~) => lex_tag_body(source, pos, expects_tag_name)
    JsExprRaw(depth~, origin~) => lex_expr_raw(source, pos, depth, origin)
  }
}

///|
/// The ModeLexer instance for JSX.
pub let jsx_mode_lexer : @core.ModeLexer[@token.Token, JsxLexMode] = {
  lex_step: jsx_lex_step,
  initial_mode: Children,
}

///|
let jsx_mode_relex_state : @core.ModeRelexState[@token.Token] = @core.erase_mode_lexer(
  jsx_mode_lexer,
  @token.EOF,
  error_token=@token.Error(""),
  error_token_from_message=Some(msg => @token.Error(msg)),
)

///|
pub fn lex(input : String) -> @core.LexResult[@token.Token] {
  (jsx_mode_relex_state.tokenize)(input)
}
