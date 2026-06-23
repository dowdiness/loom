///|
/// Experimental source origin for MarkdownIR nodes.
///
/// Offsets are half-open UTF-16 code-unit source ranges, matching
/// `@seam.SyntaxNode::start` / `end`. Origins point back to the original
/// source; MarkdownIR does not copy CST tokens or trivia.
pub struct MarkdownIROrigin {
  priv start : Int
  priv end : Int
} derive(Eq, Debug)

///|
fn MarkdownIROrigin::MarkdownIROrigin(
  start~ : Int,
  end~ : Int,
) -> MarkdownIROrigin {
  guard start >= 0 && start <= end else { abort("invalid MarkdownIR origin") }
  { start, end }
}

///|
pub fn MarkdownIROrigin::start(self : MarkdownIROrigin) -> Int {
  self.start
}

///|
pub fn MarkdownIROrigin::end(self : MarkdownIROrigin) -> Int {
  self.end
}

///|
fn MarkdownIROrigin::contains(
  self : MarkdownIROrigin,
  other : MarkdownIROrigin,
) -> Bool {
  self.start <= other.start && other.end <= self.end
}

///|
const RECOVERED_PARSE_ERROR = "parse error"

///|
priv enum MarkdownIRNode {
  Document(Array[MarkdownIR])
  Heading(Int, Array[MarkdownIR], MarkdownIROrigin?)
  Paragraph(Array[MarkdownIR], MarkdownIROrigin?)
  BlockQuote(Array[MarkdownIR])
  UnorderedList(Array[MarkdownIR], Bool, UnorderedListMarker?)
  OrderedList(Array[MarkdownIR], Bool, OrderedListMarker?)
  ListItem(Array[MarkdownIR], Bool, MarkdownIROrigin?, UnorderedListMarker?)
  OrderedListItem(
    Array[MarkdownIR],
    Bool,
    MarkdownIROrigin?,
    OrderedListMarker?
  )
  CodeBlock(String, String, MarkdownIROrigin?)
  HtmlBlock(String, MarkdownIROrigin?)
  ThematicBreak
  Text(String)
  Bold(Array[MarkdownIR], MarkdownIROrigin?)
  Italic(Array[MarkdownIR], MarkdownIROrigin?)
  InlineCode(String, MarkdownIROrigin?)
  Link(Array[MarkdownIR], String, MarkdownIROrigin?)
  Unsupported(String)
  Raw(String, Array[@core.Diagnostic])
  Recovered(String, Array[@core.Diagnostic])
} derive(Eq, Debug)

///|
/// Experimental Markdown semantic IR for the M1 heading/paragraph slice.
///
/// Public construction is intentionally withheld while the IR contract is
/// experimental. Build values through `experimental_markdown_ir_from_syntax`,
/// then consume them through the experimental adapters in this file.
pub struct MarkdownIR {
  priv node : MarkdownIRNode
  priv origin : MarkdownIROrigin
} derive(Eq, Debug)

///|
fn MarkdownIR::document(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  { node: Document(children), origin }
}

///|
fn MarkdownIR::heading(
  depth : Int,
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  guard depth >= 1 && depth <= 6 else {
    abort("MarkdownIR heading depth must be in 1..6")
  }
  { node: Heading(depth, children, content_origin), origin }
}

///|
fn MarkdownIR::paragraph(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: Paragraph(children, content_origin), origin }
}

///|
fn MarkdownIR::block_quote(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  { node: BlockQuote(children), origin }
}

///|
fn MarkdownIR::unordered_list(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  spread~ : Bool,
  marker~ : UnorderedListMarker?,
) -> MarkdownIR {
  { node: UnorderedList(children, spread, marker), origin }
}

///|
fn MarkdownIR::ordered_list(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  spread~ : Bool,
  marker~ : OrderedListMarker?,
) -> MarkdownIR {
  { node: OrderedList(children, spread, marker), origin }
}

///|
fn MarkdownIR::list_item(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  spread~ : Bool,
  content_origin : MarkdownIROrigin?,
  marker~ : UnorderedListMarker?,
) -> MarkdownIR {
  { node: ListItem(children, spread, content_origin, marker), origin }
}

///|
fn MarkdownIR::ordered_list_item(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  spread~ : Bool,
  content_origin : MarkdownIROrigin?,
  marker~ : OrderedListMarker?,
) -> MarkdownIR {
  { node: OrderedListItem(children, spread, content_origin, marker), origin }
}

///|
fn MarkdownIR::code_block(
  info : String,
  value : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: CodeBlock(info, value, content_origin), origin }
}

///|
fn MarkdownIR::thematic_break(origin : MarkdownIROrigin) -> MarkdownIR {
  { node: ThematicBreak, origin }
}

///|
fn MarkdownIR::html_block(
  value : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: HtmlBlock(value, content_origin), origin }
}

///|
fn MarkdownIR::text(value : String, origin : MarkdownIROrigin) -> MarkdownIR {
  { node: Text(value), origin }
}

///|
fn MarkdownIR::bold(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: Bold(children, content_origin), origin }
}

///|
fn MarkdownIR::italic(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: Italic(children, content_origin), origin }
}

///|
fn MarkdownIR::inline_code(
  value : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: InlineCode(value, content_origin), origin }
}

///|
fn MarkdownIR::link(
  children : Array[MarkdownIR],
  destination : String,
  origin : MarkdownIROrigin,
  destination_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: Link(children, destination, destination_origin), origin }
}

///|
fn MarkdownIR::unsupported(
  message : String,
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  { node: Unsupported(message), origin }
}

///|
fn MarkdownIR::raw(
  value : String,
  origin : MarkdownIROrigin,
  diagnostics : Array[@core.Diagnostic],
) -> MarkdownIR {
  {
    node: Raw(
      value,
      recovery_diagnostics("raw recovered Markdown", origin, diagnostics),
    ),
    origin,
  }
}

///|
fn MarkdownIR::recovered(
  message : String,
  origin : MarkdownIROrigin,
  diagnostics : Array[@core.Diagnostic],
) -> MarkdownIR {
  {
    node: Recovered(
      message,
      recovery_diagnostics(
        "recovered malformed Markdown: " + message,
        origin,
        diagnostics,
      ),
    ),
    origin,
  }
}

///|
pub fn MarkdownIR::origin(self : MarkdownIR) -> MarkdownIROrigin {
  self.origin
}

///|
pub fn MarkdownIR::kind_tag(self : MarkdownIR) -> String {
  match self.node {
    Document(_) => "Document"
    Heading(_, _, _) => "Heading"
    Paragraph(_, _) => "Paragraph"
    BlockQuote(_) => "BlockQuote"
    UnorderedList(_, _, _) => "UnorderedList"
    OrderedList(_, _, _) => "OrderedList"
    ListItem(_, _, _, _) => "ListItem"
    OrderedListItem(_, _, _, _) => "OrderedListItem"
    CodeBlock(_, _, _) => "CodeBlock"
    HtmlBlock(_, _) => "HtmlBlock"
    ThematicBreak => "ThematicBreak"
    Text(_) => "Text"
    Bold(_, _) => "Bold"
    Italic(_, _) => "Italic"
    InlineCode(_, _) => "InlineCode"
    Link(_, _, _) => "Link"
    Unsupported(_) => "Unsupported"
    Raw(_, _) => "Raw"
    Recovered(_, _) => "Recovered"
  }
}

///|
pub fn MarkdownIR::children(self : MarkdownIR) -> Array[MarkdownIR] {
  match self.node {
    Document(children)
    | Heading(_, children, _)
    | Paragraph(children, _)
    | BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _)
    | ListItem(children, _, _, _)
    | OrderedListItem(children, _, _, _)
    | Bold(children, _)
    | Italic(children, _)
    | Link(children, _, _) => children.copy()
    CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | ThematicBreak
    | Text(_)
    | InlineCode(_, _)
    | Unsupported(_)
    | Raw(_, _)
    | Recovered(_, _) => []
  }
}

///|
pub fn MarkdownIR::heading_depth(self : MarkdownIR) -> Int? {
  match self.node {
    Heading(depth, _, _) => Some(depth)
    _ => None
  }
}

///|
pub fn MarkdownIR::text_value(self : MarkdownIR) -> String? {
  match self.node {
    Text(value) | Raw(value, _) => Some(value)
    _ => None
  }
}

///|
pub fn MarkdownIR::content_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Heading(_, _, origin)
    | Paragraph(_, origin)
    | ListItem(_, _, origin, _)
    | OrderedListItem(_, _, origin, _)
    | CodeBlock(_, _, origin)
    | HtmlBlock(_, origin)
    | Bold(_, origin)
    | Italic(_, origin)
    | InlineCode(_, origin) => origin
    _ => None
  }
}

///|
pub fn MarkdownIR::spread(self : MarkdownIR) -> Bool? {
  match self.node {
    UnorderedList(_, spread, _)
    | OrderedList(_, spread, _)
    | ListItem(_, spread, _, _)
    | OrderedListItem(_, spread, _, _) => Some(spread)
    _ => None
  }
}

///|
pub fn MarkdownIR::list_marker(self : MarkdownIR) -> UnorderedListMarker? {
  match self.node {
    UnorderedList(_, _, marker) | ListItem(_, _, _, marker) => marker
    _ => None
  }
}

///|
pub fn MarkdownIR::destination_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Link(_, _, origin) => origin
    _ => None
  }
}

///|
pub fn MarkdownIR::is_raw(self : MarkdownIR) -> Bool {
  match self.node {
    Raw(_, _) => true
    _ => false
  }
}

///|
pub fn MarkdownIR::is_recovered(self : MarkdownIR) -> Bool {
  match self.node {
    Recovered(_, _) => true
    _ => false
  }
}

///|
pub fn MarkdownIR::is_unsupported(self : MarkdownIR) -> Bool {
  match self.node {
    Unsupported(_) => true
    _ => false
  }
}

///|
pub fn MarkdownIR::diagnostics(self : MarkdownIR) -> Array[@core.Diagnostic] {
  match self.node {
    Raw(_, diagnostics) | Recovered(_, diagnostics) => diagnostics.copy()
    _ => []
  }
}

///|
fn recovery_diagnostic(
  message : String,
  origin : MarkdownIROrigin,
) -> @core.Diagnostic {
  let primary = try
    @core.TextRange::from_offsets(origin.start(), origin.end())
  catch {
    _ => None
  } noraise {
    range => Some(range)
  }
  @core.Diagnostic::Diagnostic(
    source=@core.DiagnosticSource::parser(),
    severity=@core.DiagnosticSeverity::all()[0],
    code=Some(@core.DiagnosticCode("markdown-ir.recovery")),
    message~,
    primary~,
  )
}

///|
fn recovery_diagnostics(
  message : String,
  origin : MarkdownIROrigin,
  diagnostics : Array[@core.Diagnostic],
) -> Array[@core.Diagnostic] {
  if diagnostics.length() > 0 {
    diagnostics.copy()
  } else {
    [recovery_diagnostic(message, origin)]
  }
}

///|
fn origin_from_node(node : @seam.SyntaxNode) -> MarkdownIROrigin {
  MarkdownIROrigin(start=node.start(), end=node.end())
}

///|
fn origin_from_token(token : @seam.SyntaxToken) -> MarkdownIROrigin {
  MarkdownIROrigin(start=token.start(), end=token.end())
}

///|
fn span_origin_of_children(children : Array[MarkdownIR]) -> MarkdownIROrigin? {
  match children {
    [] => None
    [first, ..] => {
      // Safe: the match arm guarantees children is non-empty.
      let last = children.last().unwrap()
      Some(
        MarkdownIROrigin(start=first.origin().start(), end=last.origin().end()),
      )
    }
  }
}

///|
fn delimiter_text(kind : SyntaxKind) -> String? {
  match kind {
    StarToken => Some("*")
    StarStarToken => Some("**")
    BacktickToken => Some("`")
    LeftBracketToken => Some("[")
    RightBracketToken => Some("]")
    LeftParenToken => Some("(")
    RightParenToken => Some(")")
    _ => None
  }
}

///|
fn lower_inline_children_skip_with_diags(
  node : @seam.SyntaxNode,
  skip_kind : SyntaxKind?,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  let children : Array[MarkdownIR] = []
  let mut pending_newline : MarkdownIROrigin? = None
  fn push_child(child : MarkdownIR) -> Unit {
    let mut was_pending = false
    match pending_newline {
      Some(origin) => {
        // Trim trailing spaces from line before soft break
        match children.last() {
          Some({ node: Text(value), origin: child_origin }) => {
            let trimmed = value.trim_end(chars=" ".view())
            let removed = value.length() - trimmed.length()
            if removed > 0 {
              children[children.length() - 1] = {
                node: Text(trimmed.to_owned()),
                origin: MarkdownIROrigin(
                  start=child_origin.start(),
                  end=child_origin.end() - removed,
                ),
              }
            }
          }
          _ => ()
        }
        match newline_text {
          Some(text) => children.push(MarkdownIR::text(text, origin))
          None => ()
        }
        pending_newline = None
        was_pending = true
      }
      None => ()
    }
    // Trim leading spaces from line after soft break
    let child = if was_pending {
      match child.node {
        Text(value) => {
          let trimmed = value.trim_start(chars=" ".view())
          let removed = value.length() - trimmed.length()
          if removed > 0 {
            let child_origin = child.origin()
            {
              node: Text(trimmed.to_owned()),
              origin: MarkdownIROrigin(
                start=child_origin.start() + removed,
                end=child_origin.end(),
              ),
            }
          } else {
            child
          }
        }
        _ => child
      }
    } else {
      child
    }
    children.push(child)
  }
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if skip_kind is Some(kind) && token_kind == kind {
          continue
        }
        match token_kind {
          TextToken =>
            push_child(
              MarkdownIR::text(
                strip_backslash_escapes(token.text()),
                origin_from_token(token),
              ),
            )
          ErrorToken | ErrorNode => {
            let origin = origin_from_token(token)
            push_child(
              MarkdownIR::raw(
                token.text(),
                origin,
                diagnostics_in_origin(origin),
              ),
            )
          }
          NewlineToken => pending_newline = Some(origin_from_token(token))
          HeadingMarkerToken
          | ListMarkerToken
          | OrderedListMarkerToken
          | BlockQuoteMarkerToken
          | ThematicBreakToken
          | BlankLineToken
          | EofToken
          | CodeFenceOpenToken
          | CodeFenceCloseToken
          | CodeTextToken => ()
          _ =>
            match delimiter_text(token_kind) {
              Some(text) =>
                push_child(MarkdownIR::text(text, origin_from_token(token)))
              None => ()
            }
        }
      }
      @seam.SyntaxElement::Node(child_node) =>
        push_child(
          lower_inline_node_with_diags(
            child_node, newline_text, diagnostics_in_origin,
          ),
        )
    }
  }
  children
}

///|
fn lower_inline_children_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  lower_inline_children_skip_with_diags(
    node,
    None,
    Some(newline_text),
    diagnostics_in_origin,
  )
}

///|
fn lower_direct_inline_token_with_diags(
  token : @seam.SyntaxToken,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
  match token_kind {
    TextToken =>
      Some(
        MarkdownIR::text(
          strip_backslash_escapes(token.text()),
          origin_from_token(token),
        ),
      )
    ErrorToken | ErrorNode => {
      let origin = origin_from_token(token)
      Some(MarkdownIR::raw(token.text(), origin, diagnostics_in_origin(origin)))
    }
    HeadingMarkerToken
    | ListMarkerToken
    | OrderedListMarkerToken
    | BlockQuoteMarkerToken
    | ThematicBreakToken
    | BlankLineToken
    | NewlineToken
    | EofToken
    | CodeFenceOpenToken
    | CodeFenceCloseToken
    | CodeTextToken => None
    _ =>
      delimiter_text(token_kind).map(text => {
        MarkdownIR::text(text, origin_from_token(token))
      })
  }
}

///|
fn lower_direct_inline_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let node_kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match node_kind {
    HeadingNode
    | ParagraphNode
    | UnorderedListNode
    | OrderedListNode
    | HtmlBlockNode
    | ThematicBreakNode
    | CodeBlockNode
    | BlockQuoteNode => None
    _ =>
      Some(
        lower_inline_node_with_diags(node, newline_text, diagnostics_in_origin),
      )
  }
}

///|
fn lower_direct_inline_children_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  let children : Array[MarkdownIR] = []
  let mut pending_newline : MarkdownIROrigin? = None
  fn push_child(child : MarkdownIR) -> Unit {
    let mut was_pending = false
    match pending_newline {
      Some(origin) => {
        // Trim trailing spaces from line before soft break
        match children.last() {
          Some({ node: Text(value), origin: child_origin }) => {
            let trimmed = value.trim_end(chars=" ".view())
            let removed = value.length() - trimmed.length()
            if removed > 0 {
              children[children.length() - 1] = {
                node: Text(trimmed.to_owned()),
                origin: MarkdownIROrigin(
                  start=child_origin.start(),
                  end=child_origin.end() - removed,
                ),
              }
            }
          }
          _ => ()
        }
        children.push(MarkdownIR::text(newline_text, origin))
        pending_newline = None
        was_pending = true
      }
      None => ()
    }
    // Trim leading spaces from line after soft break
    let child = if was_pending {
      match child.node {
        Text(value) => {
          let trimmed = value.trim_start(chars=" ".view())
          let removed = value.length() - trimmed.length()
          if removed > 0 {
            let child_origin = child.origin()
            {
              node: Text(trimmed.to_owned()),
              origin: MarkdownIROrigin(
                start=child_origin.start() + removed,
                end=child_origin.end(),
              ),
            }
          } else {
            child
          }
        }
        _ => child
      }
    } else {
      child
    }
    children.push(child)
  }
  for element in node.direct_elements_iter() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if token_kind == NewlineToken {
          pending_newline = Some(origin_from_token(token))
        } else {
          match
            lower_direct_inline_token_with_diags(token, diagnostics_in_origin) {
            Some(child) => push_child(child)
            None => ()
          }
        }
      }
      @seam.SyntaxElement::Node(node) =>
        match
          lower_direct_inline_node_with_diags(
            node,
            Some(newline_text),
            diagnostics_in_origin,
          ) {
          Some(child) => push_child(child)
          None => ()
        }
    }
  }
  children
}

///|
fn lower_code_span(node : @seam.SyntaxNode) -> (String, MarkdownIROrigin?) {
  let buf = StringBuilder::new()
  let content_tokens : Array[MarkdownIROrigin] = []
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          BacktickToken => ()
          _ => {
            buf.write_string(token.text())
            content_tokens.push(origin_from_token(token))
          }
        }
      }
      _ => ()
    }
  }
  (buf.to_string(), span_token_origins(content_tokens))
}

///|
fn span_token_origins(origins : Array[MarkdownIROrigin]) -> MarkdownIROrigin? {
  match origins {
    [] => None
    [first, ..] => {
      let last = origins.last().unwrap()
      Some(MarkdownIROrigin(start=first.start(), end=last.end()))
    }
  }
}

///|
fn lower_link_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let display : Array[MarkdownIR] = []
  let destination_buf = StringBuilder::new()
  let destination_origins : Array[MarkdownIROrigin] = []
  let mut url_depth = 0
  let mut past_bracket = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          LeftBracketToken if !past_bracket && url_depth == 0 => ()
          RightBracketToken if url_depth == 0 => past_bracket = true
          LeftParenToken if past_bracket && url_depth == 0 => url_depth = 1
          LeftParenToken if past_bracket => {
            url_depth = url_depth + 1
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          RightParenToken if url_depth > 1 => {
            url_depth = url_depth - 1
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          RightParenToken if url_depth == 1 => url_depth = 0
          _ if url_depth > 0 => {
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          TextToken if !past_bracket =>
            display.push(
              MarkdownIR::text(token.text(), origin_from_token(token)),
            )
          ErrorToken | ErrorNode if !past_bracket => {
            let origin = origin_from_token(token)
            display.push(
              MarkdownIR::raw(
                token.text(),
                origin,
                diagnostics_in_origin(origin),
              ),
            )
          }
          _ => ()
        }
      }
      @seam.SyntaxElement::Node(child_node) =>
        if !past_bracket && url_depth == 0 {
          display.push(
            lower_inline_node_with_diags(
              child_node, newline_text, diagnostics_in_origin,
            ),
          )
        }
    }
  }
  MarkdownIR::link(
    display,
    destination_buf.to_string(),
    origin_from_node(node),
    span_token_origins(destination_origins),
  )
}

///|
fn lower_inline_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    BoldNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(StarStarToken),
        newline_text,
        diagnostics_in_origin,
      )
      MarkdownIR::bold(
        children,
        origin_from_node(node),
        span_origin_of_children(children),
      )
    }
    ItalicNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(StarToken),
        newline_text,
        diagnostics_in_origin,
      )
      MarkdownIR::italic(
        children,
        origin_from_node(node),
        span_origin_of_children(children),
      )
    }
    InlineCodeNode => {
      let (value, content_origin) = lower_code_span(node)
      MarkdownIR::inline_code(value, origin_from_node(node), content_origin)
    }
    LinkNode =>
      lower_link_node_with_diags(node, newline_text, diagnostics_in_origin)
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(node.text(), origin, diagnostics_in_origin(origin))
    }
    _ =>
      MarkdownIR::unsupported(
        "unsupported inline node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
fn is_setext_heading(node : @seam.SyntaxNode) -> Bool {
  match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let marker_start = skip_leading_spaces(marker.text(), 0)
      count_hashes(marker.text(), marker_start) == 0
    }
    None => false
  }
}

///|
/// Trim leading and trailing whitespace from setext heading inline children.
/// CommonMark spec: leading indentation (up to 3 spaces) and trailing
/// whitespace on content lines are not part of the heading's text content.
/// Also adjusts each child's origin so that position-aware consumers (mdast,
/// content-origin) receive ranges that match the trimmed text value.
fn trim_setext_heading_children(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let len = children.length()
  if len == 0 {
    return children
  }
  let result : Array[MarkdownIR] = []
  for i = 0; i < len; i = i + 1 {
    let child = children[i]
    let modified = match child.node {
      Text(value) => {
        let mut trimmed = value
        let mut origin = child.origin()
        // Trim leading whitespace on first child
        if i == 0 {
          let trimmed_view = value.trim_start(chars=" \t".view())
          let removed = value.length() - trimmed_view.length()
          if removed > 0 {
            trimmed = trimmed_view.to_owned()
            origin = MarkdownIROrigin(
              start=origin.start() + removed,
              end=origin.end(),
            )
          }
        }
        // Trim trailing whitespace on last child
        if i == len - 1 {
          let trimmed_view = trimmed.trim_end(chars=" \t".view())
          let removed = trimmed.length() - trimmed_view.length()
          if removed > 0 {
            trimmed = trimmed_view.to_owned()
            origin = MarkdownIROrigin(
              start=origin.start(),
              end=origin.end() - removed,
            )
          }
        }
        if trimmed.length() != value.length() {
          { node: Text(trimmed), origin }
        } else {
          child
        }
      }
      _ => child
    }
    result.push(modified)
  }
  result
}

///|
fn heading_depth_from_marker(node : @seam.SyntaxNode) -> Int? {
  match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let marker_start = skip_leading_spaces(marker.text(), 0)
      let n = count_hashes(marker.text(), marker_start)
      // count_hashes caps at 6, so n <= 6 is guaranteed.
      if n >= 1 {
        Some(n)
      } else {
        parse_setext_underline_depth(marker.text().view())
      }
    }
    None => None
  }
}

///|
fn lower_paragraph_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let children = normalize_paragraph_leading_spaces(
    lower_inline_children_with_newline_and_diags(
      node, newline_text, diagnostics_in_origin,
    ),
  )
  MarkdownIR::paragraph(
    children,
    origin_from_node(node),
    span_origin_of_children(children),
  )
}

///|
fn lower_container_child_with_diags(
  child : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  paragraph_newline_text : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
  match child_kind {
    ParagraphNode =>
      Some(
        lower_paragraph_with_newline_and_diags(
          child, paragraph_newline_text, diagnostics_in_origin,
        ),
      )
    HeadingNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode => Some(recurse(child))
    ErrorNode => {
      let origin = origin_from_node(child)
      Some(
        MarkdownIR::recovered(
          RECOVERED_PARSE_ERROR,
          origin,
          diagnostics_in_origin(origin),
        ),
      )
    }
    _ => None
  }
}

///|
fn list_marker_from_node(node : @seam.SyntaxNode) -> UnorderedListMarker? {
  match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
    Some(marker) => unordered_list_marker_from_text(marker.text())
    None => None
  }
}

///|
fn ordered_list_marker_from_node(node : @seam.SyntaxNode) -> OrderedListMarker? {
  match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
    Some(marker) => ordered_list_marker_from_text(marker.text())
    None => None
  }
}

///|
fn ordered_list_marker_from_ir(ir : MarkdownIR) -> OrderedListMarker? {
  match ir.node {
    OrderedListItem(_, _, _, marker) => marker
    _ => None
  }
}

///|
fn list_item_paragraph_origin(
  node : @seam.SyntaxNode,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIROrigin {
  match content_origin {
    Some(origin) => origin
    None =>
      match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
        Some(marker) => zero_width_origin_at(marker.end())
        None =>
          match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
            Some(marker) => zero_width_origin_at(marker.end())
            None => zero_width_origin_at(node.end())
          }
      }
  }
}

///|
fn trim_list_item_child_paragraph(ir : MarkdownIR) -> MarkdownIR {
  match ir.node {
    Paragraph(children, content_origin) => {
      let trimmed = match children {
        [{ node: Text(value), origin }, ..] => {
          let trimmed_value = value.trim_start(chars=" \t".view())
          let removed = value.length() - trimmed_value.length()
          if removed == 0 {
            children
          } else {
            children.mapi((index, child) => {
              if index == 0 {
                MarkdownIR::text(
                  trimmed_value.to_owned(),
                  MarkdownIROrigin(
                    start=origin.start() + removed,
                    end=origin.end(),
                  ),
                )
              } else {
                child
              }
            })
          }
        }
        _ => children
      }
      MarkdownIR::paragraph(trimmed, ir.origin(), content_origin)
    }
    _ => ir
  }
}

///|
fn append_list_item_flow_block_children(
  node : @seam.SyntaxNode,
  children : Array[MarkdownIR],
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> Unit {
  for child in node.children() {
    let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    match child_kind {
      ParagraphNode =>
        children.push(trim_list_item_child_paragraph(recurse(child)))
      HeadingNode
      | UnorderedListNode
      | OrderedListNode
      | HtmlBlockNode
      | ThematicBreakNode
      | CodeBlockNode
      | BlockQuoteNode => children.push(recurse(child))
      _ => ()
    }
  }
}

///|
fn markdown_ir_has_non_blank_inline_content(ir : MarkdownIR) -> Bool {
  match ir.node {
    Text(text) => direct_list_item_text_has_non_blank_content(text)
    _ => true
  }
}

///|
fn lower_list_item_flow_children_with_diags(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> (Array[MarkdownIR], MarkdownIROrigin?) {
  let lowered_inline_children = normalize_paragraph_leading_spaces(
    lower_direct_inline_children_with_newline_and_diags(
      node, "\n", diagnostics_in_origin,
    ),
  )
  let inline_children = retain_direct_list_item_inline_children(
    lowered_inline_children, markdown_ir_has_non_blank_inline_content,
  )
  let content_origin = span_origin_of_children(inline_children)
  let paragraph_origin = list_item_paragraph_origin(node, content_origin)
  let children = [
    MarkdownIR::paragraph(inline_children, paragraph_origin, content_origin),
  ]
  append_list_item_flow_block_children(node, children, recurse)
  (children, content_origin)
}

///|
fn code_block_info(node : @seam.SyntaxNode) -> String {
  match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
    Some(fence_token) => {
      let text = fence_token.text()
      let i = count_backticks(text, 0)
      if i < text.length() {
        text[i:].to_owned()
      } else {
        ""
      }
    }
    None => ""
  }
}

///|
fn trim_code_boundary_newlines(value : String) -> String {
  let without_leading = if value.has_prefix("\n") {
    value[1:].to_owned()
  } else {
    value
  }
  if without_leading.has_suffix("\n") {
    without_leading[:without_leading.length() - 1].to_owned()
  } else {
    without_leading
  }
}

///|
fn trim_commonmark_leading_indent_spaces(value : String) -> (String, Int) {
  // CommonMark permits up to three literal spaces of block indentation before
  // paragraph/setext heading content. Tabs and four-space indented-code
  // semantics are parser concerns and intentionally stay outside this Slice A
  // MarkdownIR normalization.
  let count = for ch in value; count = 0 {
    match ch {
      ' ' if count < 3 => continue count + 1
      _ => break count
    }
  } nobreak {
    count
  }
  if count == 0 {
    (value, 0)
  } else {
    (value[count:].to_owned(), count)
  }
}

///|
fn trim_commonmark_trailing_spaces(value : String) -> (String, Int) {
  // Setext heading content excludes trailing literal spaces before the newline.
  // Keep this ASCII-space-only so tab handling remains with the later full
  // indentation semantics slice.
  let count = for pos = value.length() - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some(' ') => continue pos - 1, count + 1
      _ => break count
    }
  }
  if count == 0 {
    (value, 0)
  } else {
    (value[:value.length() - count].to_owned(), count)
  }
}

///|
fn normalize_paragraph_leading_spaces(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  match children {
    [{ node: Text(value), origin }, ..] => {
      let (trimmed, cut) = trim_commonmark_leading_indent_spaces(value)
      if cut == 0 {
        children
      } else {
        children.mapi((index, child) => {
          if index == 0 {
            MarkdownIR::text(
              trimmed,
              MarkdownIROrigin(start=origin.start() + cut, end=origin.end()),
            )
          } else {
            child
          }
        })
      }
    }
    _ => children
  }
}

///|
fn trim_trailing_atx_closing_hashes(
  value : String,
  source_text : String,
  source_offset : Int,
  origin_end : Int,
) -> (String, Int) {
  let hash_count = for pos = value.length() - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some('#') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard hash_count > 0 else { return (value, 0) }
  let before_hash_pos = value.length() - hash_count
  let space_count = for pos = before_hash_pos - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some(' ') | Some('\t') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard origin_end >= source_offset else { return (value, 0) }
  let raw_end = origin_end - source_offset
  let raw_hash_count = for pos = raw_end - 1, count = 0 {
    guard pos >= 0 else { break count }
    match source_text.get_char(pos) {
      Some('#') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard raw_hash_count > 0 else { return (value, 0) }
  let raw_hash_start = raw_end - raw_hash_count
  // Escaped trailing hashes are content, not an ATX closing sequence. The raw
  // source still contains the backslash while `value` has already been unescaped.
  guard raw_hash_start > 0 else { return (value, 0) }
  match source_text.get_char(raw_hash_start - 1) {
    Some('\\') => (value, 0)
    Some(' ' | '\t') if before_hash_pos == 0 || space_count > 0 => {
      let cut = hash_count + space_count
      (value[:value.length() - cut].to_owned(), cut)
    }
    _ => (value, 0)
  }
}

///|
fn normalize_heading_leading_whitespace(
  children : Array[MarkdownIR],
  trim_all~ : Bool,
) -> Array[MarkdownIR] {
  if !trim_all {
    return normalize_paragraph_leading_spaces(children)
  }
  match children {
    [{ node: Text(value), origin }, ..] => {
      let trimmed_view = value.trim_start(chars=" \t".view())
      let cut = value.length() - trimmed_view.length()
      if cut == 0 {
        children
      } else {
        children.mapi((index, child) => {
          if index == 0 {
            MarkdownIR::text(
              trimmed_view.to_owned(),
              MarkdownIROrigin(start=origin.start() + cut, end=origin.end()),
            )
          } else {
            child
          }
        })
      }
    }
    _ => children
  }
}

///|
fn normalize_heading_whitespace(
  children : Array[MarkdownIR],
  source_text : String,
  source_offset : Int,
  trim_all_leading~ : Bool,
  skip_closing_hashes? : Bool = false,
) -> Array[MarkdownIR] {
  let leading_normalized = normalize_heading_leading_whitespace(
    children,
    trim_all=trim_all_leading,
  )
  match leading_normalized {
    [.., { node: Text(value), origin }] => {
      let (space_trimmed, space_cut) = trim_commonmark_trailing_spaces(value)
      let trimmed_end = origin.end() - space_cut
      let (trimmed, hash_cut) = if skip_closing_hashes {
        (space_trimmed, 0)
      } else {
        trim_trailing_atx_closing_hashes(
          space_trimmed, source_text, source_offset, trimmed_end,
        )
      }
      let cut = space_cut + hash_cut
      if cut == 0 {
        leading_normalized
      } else {
        let last_index = leading_normalized.length() - 1
        leading_normalized.mapi((index, child) => {
          if index == last_index {
            MarkdownIR::text(
              trimmed,
              MarkdownIROrigin(start=origin.start(), end=origin.end() - cut),
            )
          } else {
            child
          }
        })
      }
    }
    _ => leading_normalized
  }
}

///|
fn code_block_value(node : @seam.SyntaxNode) -> String {
  let buf = StringBuilder::new()
  let mut in_code = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          CodeFenceOpenToken => in_code = true
          CodeFenceCloseToken => in_code = false
          CodeTextToken if in_code => buf.write_string(token.text())
          IndentedCodeTextToken => {
            in_code = true
            // Strip leading whitespace matching CommonMark indented code
            // block semantics (the lexer tracks the correct content but
            // the CST token span covers the full source line).
            buf.write_string(
              token.text().trim_start(chars=" \t".view()).to_owned(),
            )
          }
          NewlineToken | BlankLineToken if in_code => buf.write_string("\n")
          _ => ()
        }
      }
      _ => ()
    }
  }
  trim_code_boundary_newlines(buf.to_string())
}

///|
/// Extract concatenated HTML content from an `HtmlBlockNode`, including the
/// opening line, text lines, and interleaved newlines. HTML blocks preserve
/// exact source formatting, so this does not trim leading or trailing newlines.
fn html_block_value(node : @seam.SyntaxNode) -> String {
  let buf = StringBuilder::new()
  let mut in_html = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          HtmlBlockOpenToken => {
            in_html = true
            // NB: HtmlBlockOpen text does not include the trailing newline;
            // the lexer emits that separately as a NewlineToken.
            buf.write_string(token.text())
          }
          // Defensive: the parser guarantees HtmlBlockOpenToken is first, so
          // in_html is always true here for well-formed CSTs.
          HtmlTextToken if in_html => buf.write_string(token.text())
          // HTML block parsing emits newline runs as NewlineToken; BlankLineToken
          // remains structural outside code blocks.
          NewlineToken if in_html => buf.write_string("\n")
          _ => ()
        }
      }
      _ => ()
    }
  }
  buf.to_string()
}

///|
fn html_block_content_origin(node : @seam.SyntaxNode) -> MarkdownIROrigin? {
  // Unlike code_block_content_origin, include HtmlBlockOpenToken: HTML blocks
  // have no close fence, and the opening line is content.
  let content_tokens : Array[@seam.SyntaxToken] = Array::new()
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          HtmlBlockOpenToken | HtmlTextToken | NewlineToken =>
            content_tokens.push(token)
          _ => ()
        }
      }
      _ => ()
    }
  }
  span_token_origins(content_tokens.map(origin_from_token))
}

///|
fn code_block_content_origin(node : @seam.SyntaxNode) -> MarkdownIROrigin? {
  let mut in_code = false
  let content_tokens : Array[@seam.SyntaxToken] = Array::new()
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          CodeFenceOpenToken => in_code = true
          CodeFenceCloseToken => in_code = false
          CodeTextToken if in_code => content_tokens.push(token)
          IndentedCodeTextToken => {
            in_code = true
            content_tokens.push(token)
          }
          NewlineToken | BlankLineToken if in_code => content_tokens.push(token)
          _ => ()
        }
      }
      _ => ()
    }
  }
  let start_offset = if content_tokens.length() > 0 {
    let first_kind : SyntaxKind = @seam.FromRawKind::from_raw(
      content_tokens[0].kind(),
    )
    if first_kind is NewlineToken {
      1
    } else {
      0
    }
  } else {
    0
  }
  let end_offset = if content_tokens.length() > start_offset {
    let last_kind : SyntaxKind = @seam.FromRawKind::from_raw(
      content_tokens[content_tokens.length() - 1].kind(),
    )
    if last_kind is NewlineToken {
      content_tokens.length() - 1
    } else {
      content_tokens.length()
    }
  } else {
    0
  }
  if start_offset < end_offset {
    Some(
      MarkdownIROrigin(
        start=content_tokens[start_offset].start(),
        end=content_tokens[end_offset - 1].end(),
      ),
    )
  } else if content_tokens.length() > start_offset {
    Some(
      MarkdownIROrigin(
        start=content_tokens[start_offset].start(),
        end=content_tokens[start_offset].start(),
      ),
    )
  } else if content_tokens.length() > 0 {
    let last_token = content_tokens[content_tokens.length() - 1]
    Some(MarkdownIROrigin(start=last_token.end(), end=last_token.end()))
  } else {
    match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
      Some(fence_token) =>
        Some(MarkdownIROrigin(start=fence_token.end(), end=fence_token.end()))
      None => None
    }
  }
}

///|
fn lower_list_children(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> Array[MarkdownIR] {
  node
  .children()
  .iter()
  .filter_map(child => {
    let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    match child_kind {
      ListItemNode => Some(recurse(child))
      _ => None
    }
  })
  .collect()
}

///|
fn lower_block_quote_children(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  node
  .children()
  .iter()
  .filter_map(child => {
    lower_container_child_with_diags(
      child, recurse, "\n", diagnostics_in_origin,
    )
  })
  .collect()
}

///|
fn list_spread_from_node(
  node : @seam.SyntaxNode,
  children : Array[MarkdownIR],
) -> Bool {
  node.direct_token_of_kind(BlankLineToken.to_raw()) is Some(_) ||
  children.iter().any(child => child.spread() == Some(true))
}

///|
/// Experimental CstFold algebra for the M1 MarkdownIR slice.
///
/// Covers documents, headings, paragraphs, and text. Other Markdown constructs
/// lower to explicit `Unsupported` IR nodes instead of cloned CST token piles.
fn experimental_markdown_ir_fold_node_with_diags(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    DocumentNode => {
      let children : Array[MarkdownIR] = node
        .children()
        .iter()
        .filter_map(child => {
          lower_container_child_with_diags(
            child, recurse, "\n", diagnostics_in_origin,
          )
        })
        .collect()
      MarkdownIR::document(children, origin_from_node(node))
    }
    HeadingNode => {
      let setext = is_setext_heading(node)
      let children = normalize_heading_whitespace(
        lower_inline_children_with_newline_and_diags(
          node, "\n", diagnostics_in_origin,
        ),
        node.text(),
        node.start(),
        trim_all_leading=!setext,
        skip_closing_hashes=setext,
      )
      let content_children = if setext {
        trim_setext_heading_children(children)
      } else {
        children
      }
      match heading_depth_from_marker(node) {
        Some(depth) =>
          MarkdownIR::heading(
            depth,
            content_children,
            origin_from_node(node),
            span_origin_of_children(content_children),
          )
        None =>
          MarkdownIR::unsupported(
            "invalid heading marker",
            origin_from_node(node),
          )
      }
    }
    ParagraphNode =>
      lower_paragraph_with_newline_and_diags(node, "\n", diagnostics_in_origin)
    BlockQuoteNode =>
      MarkdownIR::block_quote(
        lower_block_quote_children(node, recurse, diagnostics_in_origin),
        origin_from_node(node),
      )
    UnorderedListNode => {
      let children = lower_list_children(node, recurse)
      let marker = match children {
        [first, ..] => first.list_marker()
        [] => None
      }
      MarkdownIR::unordered_list(
        children,
        origin_from_node(node),
        spread=list_spread_from_node(node, children),
        marker~,
      )
    }
    OrderedListNode => {
      let children = lower_list_children(node, recurse)
      let marker = match children {
        [first, ..] => ordered_list_marker_from_ir(first)
        [] => None
      }
      MarkdownIR::ordered_list(
        children,
        origin_from_node(node),
        spread=list_spread_from_node(node, children),
        marker~,
      )
    }
    ListItemNode => {
      let (children, content_origin) = lower_list_item_flow_children_with_diags(
        node, recurse, diagnostics_in_origin,
      )
      let spread = node.direct_token_of_kind(BlankLineToken.to_raw()) is Some(_)
      match ordered_list_marker_from_node(node) {
        Some(marker) =>
          MarkdownIR::ordered_list_item(
            children,
            origin_from_node(node),
            spread~,
            content_origin,
            marker=Some(marker),
          )
        None =>
          MarkdownIR::list_item(
            children,
            origin_from_node(node),
            spread~,
            content_origin,
            marker=list_marker_from_node(node),
          )
      }
    }
    CodeBlockNode =>
      MarkdownIR::code_block(
        code_block_info(node),
        code_block_value(node),
        origin_from_node(node),
        code_block_content_origin(node),
      )
    HtmlBlockNode =>
      MarkdownIR::html_block(
        html_block_value(node),
        origin_from_node(node),
        html_block_content_origin(node),
      )
    ThematicBreakNode => MarkdownIR::thematic_break(origin_from_node(node))
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(
        RECOVERED_PARSE_ERROR,
        origin,
        diagnostics_in_origin(origin),
      )
    }
    _ =>
      MarkdownIR::unsupported(
        "unsupported node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
fn experimental_markdown_ir_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> MarkdownIR {
  experimental_markdown_ir_fold_node_with_diags(node, recurse, _ => [])
}

///|
fn diagnostic_primary_overlaps_origin(
  diagnostic : @core.Diagnostic,
  origin : MarkdownIROrigin,
) -> Bool {
  match diagnostic.primary {
    Some(range) =>
      @core.Range::new(range.start().value(), range.end().value()).overlaps(
        @core.Range::new(origin.start(), origin.end()),
      )
    None => false
  }
}

///|
fn diagnostics_in_origin(
  diagnostics : @core.DiagnosticSet,
  origin : MarkdownIROrigin,
) -> Array[@core.Diagnostic] {
  diagnostics
  .items()
  .iter()
  .filter(diagnostic => diagnostic_primary_overlaps_origin(diagnostic, origin))
  .collect()
}

///|
/// Experimental `SyntaxNode -> MarkdownIR` lowering for the M1 slice.
///
/// Built by a direct recursive walk rather than `CstFold` because MarkdownIR
/// stores absolute source origins, and `CstFold` reuses cached results
/// verbatim based on position-independent structural hashes. Using `CstFold`
/// would return stale origins after position-shifting edits. See
/// `docs/decisions/2026-06-16-markdown-ir-performance-policy.md`.
pub fn experimental_markdown_ir_from_syntax(
  root : @seam.SyntaxNode,
) -> MarkdownIR {
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node(node, lower)
  }
  lower(root)
}

///|
pub fn experimental_markdown_ir_from_syntax_with_diagnostics(
  root : @seam.SyntaxNode,
  diagnostics : @core.DiagnosticSet,
) -> MarkdownIR {
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node_with_diags(node, lower, origin => {
      diagnostics_in_origin(diagnostics, origin)
    })
  }
  lower(root)
}

///|
fn experimental_markdown_ir_to_inline(ir : MarkdownIR) -> Inline {
  match ir.node {
    Text(value) => Inline::Text(value)
    Bold(children, _) => Inline::Bold(ir_children_to_inlines(children))
    Italic(children, _) => Inline::Italic(ir_children_to_inlines(children))
    InlineCode(value, _) => Inline::InlineCode(value)
    Link(children, destination, _) =>
      Inline::Link(ir_children_to_inlines(children), destination)
    Unsupported(message) => Inline::Error(message)
    Raw(value, _) => Inline::Text(value)
    Recovered(message, _) => Inline::Error(message)
    Document(_) => Inline::Error("expected inline MarkdownIR, got document")
    Heading(_, _, _) => Inline::Error("expected inline MarkdownIR, got heading")
    Paragraph(_, _) =>
      Inline::Error("expected inline MarkdownIR, got paragraph")
    BlockQuote(_) => Inline::Error("expected inline MarkdownIR, got blockquote")
    UnorderedList(_, _, _) | OrderedList(_, _, _) =>
      Inline::Error("expected inline MarkdownIR, got list")
    ListItem(_, _, _, _) | OrderedListItem(_, _, _, _) =>
      Inline::Error("expected inline MarkdownIR, got list item")
    CodeBlock(_, _, _) =>
      Inline::Error("expected inline MarkdownIR, got code block")
    HtmlBlock(value, _) => Inline::Text(value)
    ThematicBreak =>
      Inline::Error("expected inline MarkdownIR, got thematic break")
  }
}

///|
fn experimental_markdown_ir_to_editor_inline(ir : MarkdownIR) -> Inline {
  match ir.node {
    Bold(children, _) =>
      Inline::Bold(ir_children_to_editor_inlines(children, None))
    Italic(children, _) =>
      Inline::Italic(ir_children_to_editor_inlines(children, None))
    Link(children, destination, _) =>
      Inline::Link(ir_children_to_editor_inlines(children, None), destination)
    _ => experimental_markdown_ir_to_inline(ir)
  }
}

///|
fn ir_children_to_inlines(children : Array[MarkdownIR]) -> Array[Inline] {
  children.map(experimental_markdown_ir_to_inline)
}

///|
/// Convert IR inline children for the legacy editor Block adapter. The caller
/// chooses how direct paragraph soft breaks render (`" "` for top-level
/// paragraphs, `"\n"` for list-item paragraphs); inline-formatting soft breaks
/// use `None` to match the direct CST adapter.
fn ir_children_to_editor_inlines(
  children : Array[MarkdownIR],
  newline_text : String?,
) -> Array[Inline] {
  children
  .iter()
  .filter_map(child => {
    match child.node {
      Text("\n") => newline_text.map(text => Inline::Text(text))
      _ => Some(experimental_markdown_ir_to_editor_inline(child))
    }
  })
  .collect()
}

///|
fn list_item_flow_child_to_editor_inlines(child : MarkdownIR) -> Array[Inline] {
  match child.node {
    Paragraph(paragraph_children, _) =>
      ir_children_to_editor_inlines(paragraph_children, Some("\n"))
    BlockQuote(_) | UnorderedList(_, _, _) | OrderedList(_, _, _) => []
    ListItem(item_children, _, _, _)
    | OrderedListItem(item_children, _, _, _) =>
      list_item_flow_children_to_editor_inlines(item_children)
    _ => [experimental_markdown_ir_to_inline(child)]
  }
}

///|
fn list_item_flow_children_to_editor_inlines(
  children : Array[MarkdownIR],
) -> Array[Inline] {
  children
  .iter()
  .flat_map(child => list_item_flow_child_to_editor_inlines(child).iter())
  .collect()
}

///|
pub fn experimental_markdown_ir_to_block(ir : MarkdownIR) -> Block {
  match ir.node {
    Document(children) =>
      Block::Document(children.map(experimental_markdown_ir_to_block))
    Heading(depth, children, _) =>
      Block::Heading(depth, ir_children_to_editor_inlines(children, None))
    Paragraph(children, _) =>
      Block::Paragraph(ir_children_to_editor_inlines(children, Some(" ")))
    BlockQuote(_) => Block::Error("expected editor Block, got blockquote")
    UnorderedList(children, _, _) =>
      Block::UnorderedList(children.map(experimental_markdown_ir_to_block))
    OrderedList(children, _, marker) =>
      Block::OrderedList(
        children.map(experimental_markdown_ir_to_block),
        marker,
      )
    ListItem(children, _, _, _) =>
      Block::UnorderedListItem(
        list_item_flow_children_to_editor_inlines(children),
      )
    OrderedListItem(children, _, _, marker) =>
      Block::OrderedListItem(
        list_item_flow_children_to_editor_inlines(children),
        marker,
      )
    CodeBlock(info, value, _) => Block::CodeBlock(info, value)
    HtmlBlock(value, _) => Block::HtmlBlock(value)
    ThematicBreak => Block::Error("thematic break")
    Text(_) => Block::Error("expected block MarkdownIR, got text")
    Bold(_, _) => Block::Error("expected block MarkdownIR, got bold")
    Italic(_, _) => Block::Error("expected block MarkdownIR, got italic")
    InlineCode(_, _) =>
      Block::Error("expected block MarkdownIR, got inline code")
    Link(_, _, _) => Block::Error("expected block MarkdownIR, got link")
    Unsupported(message) => Block::Error(message)
    Raw(value, _) =>
      Block::Error("expected block MarkdownIR, got raw: " + value)
    Recovered(message, _) => Block::Error(message)
  }
}

///|
fn origin_json(origin : MarkdownIROrigin) -> Json {
  { "start": origin.start(), "end": origin.end() }
}

///|
fn diagnostics_json(diagnostics : Array[@core.Diagnostic]) -> Json {
  Json::array(diagnostics.map(diagnostic => Json::string(diagnostic.format())))
}

///|
fn unist_point_json(point : @core.LineCol, offset : Int) -> Json {
  { "line": point.line + 1, "column": point.column + 1, "offset": offset }
}

///|
fn unist_position_json(
  origin : MarkdownIROrigin,
  line_index : @core.LineIndex,
) -> Json {
  let range = line_index.line_range(origin.start(), origin.end())
  {
    "start": unist_point_json(range.start, origin.start()),
    "end": unist_point_json(range.end, origin.end()),
  }
}

///|
priv struct MdastPositionContext {
  line_index : @core.LineIndex
  source : String
}

///|
fn origin_without_trailing_line_endings(
  origin : MarkdownIROrigin,
  source : String,
) -> MarkdownIROrigin {
  let mut trimmed_end = origin.end()
  while trimmed_end > origin.start() {
    let text = source_slice_between(source, origin.start(), trimmed_end)
    if text.has_suffix("\r\n") {
      trimmed_end = trimmed_end - 2
    } else if text.has_suffix("\r") || text.has_suffix("\n") {
      trimmed_end = trimmed_end - 1
    } else {
      break
    }
  }
  MarkdownIROrigin(start=origin.start(), end=trimmed_end)
}

///|
fn line_end_offset(source : String, start : Int, limit : Int) -> Int {
  let mut pos = start
  while pos < limit {
    match char_at(source, pos) {
      Some('\r') | Some('\n') | None => break
      _ => pos = @core.next_char_offset(source, pos)
    }
  }
  pos
}

///|
fn next_line_start(source : String, line_end : Int, limit : Int) -> Int {
  if line_end < limit {
    match source.view(start_offset=line_end) {
      ['\r', '\n', .. rest] => rest.start_offset()
      ['\r', .. rest] | ['\n', .. rest] => rest.start_offset()
      _ => limit
    }
  } else {
    limit
  }
}

///|
fn code_fence_close_line_start(
  origin : MarkdownIROrigin,
  source : String,
) -> Int? {
  let fence_len = count_backticks(source, origin.start())
  guard fence_len >= 3 else { return None }
  let open_line_end = line_end_offset(source, origin.start(), origin.end())
  let mut line_start = next_line_start(source, open_line_end, origin.end())
  while line_start < origin.end() {
    let ticks = count_backticks(source, line_start)
    let marker_end = line_start + ticks
    if ticks >= fence_len {
      let line_end = line_end_offset(source, marker_end, origin.end())
      let mut is_close = true
      let mut pos = marker_end
      while pos < line_end {
        match char_at(source, pos) {
          Some(' ') | Some('\t') => pos = @core.next_char_offset(source, pos)
          _ => {
            is_close = false
            break
          }
        }
      }
      if is_close {
        return Some(line_start)
      }
    }
    let line_end = line_end_offset(source, line_start, origin.end())
    line_start = next_line_start(source, line_end, origin.end())
  }
  None
}

///|
fn code_fence_close_marker_end(
  origin : MarkdownIROrigin,
  source : String,
) -> Int? {
  match code_fence_close_line_start(origin, source) {
    Some(line_start) => Some(line_end_offset(source, line_start, origin.end()))
    None => None
  }
}

///|
fn code_block_mdast_position_origin(
  origin : MarkdownIROrigin,
  source : String,
) -> MarkdownIROrigin {
  match code_fence_close_marker_end(origin, source) {
    Some(end) => MarkdownIROrigin(start=origin.start(), end~)
    None => origin
  }
}

///|
fn mdast_position_origin(
  ir : MarkdownIR,
  context : MdastPositionContext,
) -> MarkdownIROrigin {
  match ir.node {
    Heading(_, _, _)
    | Paragraph(_, _)
    | BlockQuote(_)
    | UnorderedList(_, _, _)
    | OrderedList(_, _, _)
    | ListItem(_, _, _, _)
    | OrderedListItem(_, _, _, _) =>
      origin_without_trailing_line_endings(ir.origin(), context.source)
    CodeBlock(_, _, _) =>
      code_block_mdast_position_origin(ir.origin(), context.source)
    ThematicBreak =>
      origin_without_trailing_line_endings(ir.origin(), context.source)
    _ => ir.origin()
  }
}

///|
fn mdast_json_with_position(
  json : Json,
  origin : MarkdownIROrigin,
  context : MdastPositionContext?,
) -> Json {
  guard context is Some(position_context) else { return json }
  match json {
    Object(fields) => {
      fields.set(
        "position",
        unist_position_json(origin, position_context.line_index),
      )
      Json::object(fields)
    }
    _ => json
  }
}

///|
fn mdast_json_with_optional_spread(json : Json, spread : Bool) -> Json {
  guard spread else { return json }
  match json {
    Object(fields) => {
      fields.set("spread", true)
      Json::object(fields)
    }
    _ => json
  }
}

///|
fn mdast_json_with_optional_ordered_start(
  json : Json,
  marker : OrderedListMarker?,
) -> Json {
  guard marker is Some(marker) && marker.start != 1 else { return json }
  match json {
    Object(fields) => {
      fields.set("start", Json::number(Double::from_int(marker.start)))
      Json::object(fields)
    }
    _ => json
  }
}

///|
fn zero_width_origin_at(offset : Int) -> MarkdownIROrigin {
  MarkdownIROrigin(start=offset, end=offset)
}

///|
fn mdast_children_json(
  children : Array[MarkdownIR],
  context : MdastPositionContext?,
) -> Array[Json] {
  match context {
    Some(_) => children.map(child => markdown_ir_to_mdast_json(child, context))
    None => {
      let json_children : Array[Json] = []
      let pending_text = StringBuilder::new()
      fn flush_text() -> Unit {
        let text = pending_text.to_string()
        if text.length() > 0 {
          json_children.push({ "type": "text", "value": text })
          pending_text.reset()
        }
      }
      for child in children {
        match child.node {
          Text(value) => pending_text.write_string(value)
          _ => {
            flush_text()
            json_children.push(markdown_ir_to_mdast_json(child, None))
          }
        }
      }
      flush_text()
      json_children
    }
  }
}

///|
fn markdown_ir_to_mdast_json(
  ir : MarkdownIR,
  context : MdastPositionContext?,
) -> Json {
  let json : Json = match ir.node {
    Document(children) =>
      { "type": "root", "children": mdast_children_json(children, context) }
    Heading(depth, children, _) =>
      {
        "type": "heading",
        "depth": depth,
        "children": mdast_children_json(children, context),
      }
    Paragraph(children, _) =>
      {
        "type": "paragraph",
        "children": mdast_children_json(children, context),
      }
    BlockQuote(children) =>
      {
        "type": "blockquote",
        "children": mdast_children_json(children, context),
      }
    UnorderedList(children, spread, _) =>
      mdast_json_with_optional_spread(
        {
          "type": "list",
          "ordered": false,
          "children": mdast_children_json(children, context),
        },
        spread,
      )
    OrderedList(children, spread, marker) =>
      mdast_json_with_optional_spread(
        mdast_json_with_optional_ordered_start(
          {
            "type": "list",
            "ordered": true,
            "children": mdast_children_json(children, context),
          },
          marker,
        ),
        spread,
      )
    ListItem(children, spread, _, _)
    | OrderedListItem(children, spread, _, _) =>
      mdast_json_with_optional_spread(
        {
          "type": "listItem",
          "children": mdast_children_json(children, context),
        },
        spread,
      )
    CodeBlock(info, value, _) =>
      if info.length() > 0 {
        { "type": "code", "lang": info, "value": value }
      } else {
        { "type": "code", "value": value }
      }
    HtmlBlock(value, _) => { "type": "html", "value": value }
    ThematicBreak => { "type": "thematicBreak" }
    Text(value) => { "type": "text", "value": value }
    Bold(children, _) =>
      { "type": "strong", "children": mdast_children_json(children, context) }
    Italic(children, _) =>
      { "type": "emphasis", "children": mdast_children_json(children, context) }
    InlineCode(value, _) => { "type": "inlineCode", "value": value }
    Link(children, destination, _) =>
      {
        "type": "link",
        "url": destination,
        "children": mdast_children_json(children, context),
      }
    Unsupported(message) => { "type": "mdastUnsupported", "value": message }
    Raw(value, diagnostics) =>
      {
        "type": "mdastRaw",
        "value": value,
        "origin": origin_json(ir.origin()),
        "diagnostics": diagnostics_json(diagnostics),
      }
    Recovered(message, diagnostics) =>
      {
        "type": "mdastRecovered",
        "value": message,
        "origin": origin_json(ir.origin()),
        "diagnostics": diagnostics_json(diagnostics),
      }
  }
  mdast_json_with_position(
    json,
    match context {
      Some(position_context) => mdast_position_origin(ir, position_context)
      None => ir.origin()
    },
    context,
  )
}

///|
pub fn experimental_markdown_ir_to_mdast_json(ir : MarkdownIR) -> Json {
  markdown_ir_to_mdast_json(ir, None)
}

///|
/// Export MarkdownIR to mdast-shaped JSON with unist `position` objects.
///
/// MarkdownIR origins remain half-open UTF-16 source ranges. This adapter builds
/// a `LineIndex` from the source that produced the IR and converts each origin to
/// unist points with 1-based lines/columns and 0-based UTF-16 offsets at the
/// export boundary.
pub fn experimental_markdown_ir_to_mdast_json_with_positions(
  ir : MarkdownIR,
  source : String,
) -> Json {
  guard ir.origin().end() <= source.length() else {
    abort("MarkdownIR position export source does not cover IR origin")
  }
  markdown_ir_to_mdast_json(
    ir,
    Some({ line_index: @core.LineIndex::new(source), source }),
  )
}

///|
fn source_slice_between(source : String, start : Int, end : Int) -> String {
  guard start >= 0 && start <= end && end <= source.length() else {
    abort("invalid MarkdownIR origin bounds")
  }
  source[start:end].to_owned()
}

///|
fn source_slice(source : String, origin : MarkdownIROrigin) -> String {
  source_slice_between(source, origin.start(), origin.end())
}

///|
/// Experimental preserve-mode rewrite for unchanged IR.
///
/// This is intentionally source-slice based: the caller must pass the source
/// that produced the IR. MarkdownIR itself does not store trivia or token lists.
pub fn experimental_markdown_ir_preserve_rewrite(
  ir : MarkdownIR,
  source : String,
) -> String {
  source_slice(source, ir.origin())
}

///|
fn original_block_trailing_newline(
  source : String,
  origin : MarkdownIROrigin,
) -> String {
  let text = source_slice(source, origin)
  if text.has_suffix("\r\n") {
    "\r\n"
  } else if text.has_suffix("\r") {
    "\r"
  } else if text.has_suffix("\n") {
    "\n"
  } else {
    ""
  }
}

///|
fn local_transform_inline_text(
  children : Array[MarkdownIR],
  source : String,
  target_origin : MarkdownIROrigin,
  replacement_text : String,
) -> String {
  match children {
    [] => ""
    [first, ..] => {
      let buf = StringBuilder::new()
      for child in children; cursor = first.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          match child.node {
            Text(_) | Raw(_, _) =>
              buf.write_string(source_slice(source, child_origin))
            InlineCode(value, _) => buf.write_string("`" + value + "`")
            _ => buf.write_string(source_slice(source, child_origin))
          }
        }
        continue child_origin.end()
      } nobreak {
        buf.to_string()
      }
    }
  }
}

///|
fn code_block_markdown(info : String, value : String) -> String {
  @core.Renderable::unparse(Block::CodeBlock(info, value))
}

///|
fn max_backtick_run(value : String) -> Int {
  let mut max_run = 0
  let mut cur_run = 0
  for i = 0; i < value.length(); i = i + 1 {
    match value.code_unit_at(i).to_char() {
      Some('`') => {
        cur_run = cur_run + 1
        if cur_run > max_run {
          max_run = cur_run
        }
      }
      _ => cur_run = 0
    }
  }
  max_run
}

///|
fn code_block_backtick_width(value : String, minimum_width : Int) -> Int {
  let run_width = max_backtick_run(value)
  let required_width = if run_width >= 3 { run_width + 1 } else { 3 }
  if minimum_width > required_width {
    minimum_width
  } else {
    required_width
  }
}

///|
fn local_code_block_suffix(
  source : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin,
  fence_width : Int,
) -> String {
  match code_fence_close_line_start(origin, source) {
    Some(close_start) => {
      let close_width = count_backticks(source, close_start)
      if close_width < fence_width {
        "`".repeat(fence_width) +
        source_slice_between(source, close_start + close_width, origin.end())
      } else {
        source_slice_between(source, close_start, origin.end())
      }
    }
    None => source_slice_between(source, content_origin.end(), origin.end())
  }
}

///|
fn code_block_content_line_ending(
  source : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin,
) -> String {
  let prefix = source_slice_between(
    source,
    origin.start(),
    content_origin.start(),
  )
  if prefix.has_suffix("\r\n") {
    "\r\n"
  } else if prefix.has_suffix("\r") {
    "\r"
  } else {
    "\n"
  }
}

///|
fn local_code_block_markdown(
  source : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin,
  value : String,
) -> String {
  let original_width = count_backticks(source, origin.start())
  let minimum_width = if original_width >= 3 { original_width } else { 3 }
  let fence_width = code_block_backtick_width(value, minimum_width)
  let opening = "`".repeat(fence_width) +
    source_slice_between(
      source,
      origin.start() + original_width,
      content_origin.start(),
    )
  let suffix_prefix = match code_fence_close_line_start(origin, source) {
    Some(close_start) =>
      source_slice_between(source, content_origin.end(), close_start)
    None => ""
  }
  let zero_content = content_origin.start() == content_origin.end()
  let content_line_ending = code_block_content_line_ending(
    source, origin, content_origin,
  )
  let opening_suffix = if zero_content &&
    value != "" &&
    !opening.has_suffix("\n") &&
    !opening.has_suffix("\r") {
    content_line_ending
  } else {
    ""
  }
  let suffix = local_code_block_suffix(
    source, origin, content_origin, fence_width,
  )
  let replacement_ends_with_line_ending = value.has_suffix("\n") ||
    value.has_suffix("\r")
  let replacement_suffix = if value != "" &&
    suffix_prefix == "" &&
    (zero_content || (suffix == "" && replacement_ends_with_line_ending)) {
    content_line_ending
  } else {
    ""
  }
  opening + opening_suffix + value + replacement_suffix + suffix_prefix + suffix
}

///|
fn local_transform_render(
  ir : MarkdownIR,
  source : String,
  target_origin : MarkdownIROrigin,
  replacement_text : String,
) -> String {
  if ir.origin() == target_origin {
    return replacement_text
  }
  match ir.node {
    Document(children) => {
      let buf = StringBuilder::new()
      let final_cursor = for child in children; cursor = ir.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          buf.write_string(source_slice(source, child_origin))
        }
        continue child_origin.end()
      } nobreak {
        cursor
      }
      buf.write_string(
        source_slice_between(source, final_cursor, ir.origin().end()),
      )
      buf.to_string()
    }
    Heading(depth, children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      "#".repeat(depth) +
      " " +
      rendered +
      original_block_trailing_newline(source, ir.origin())
    }
    Paragraph(children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      rendered + original_block_trailing_newline(source, ir.origin())
    }
    BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _) => {
      let buf = StringBuilder::new()
      let final_cursor = for child in children; cursor = ir.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          buf.write_string(source_slice(source, child_origin))
        }
        continue child_origin.end()
      } nobreak {
        cursor
      }
      buf.write_string(
        source_slice_between(source, final_cursor, ir.origin().end()),
      )
      buf.to_string()
    }
    ListItem(children, _, _, _) | OrderedListItem(children, _, _, _) => {
      let buf = StringBuilder::new()
      let final_cursor = for child in children; cursor = ir.origin().start() {
        let child_origin = child.origin()
        buf.write_string(
          source_slice_between(source, cursor, child_origin.start()),
        )
        if child_origin.contains(target_origin) {
          buf.write_string(
            local_transform_render(
              child, source, target_origin, replacement_text,
            ),
          )
        } else {
          buf.write_string(source_slice(source, child_origin))
        }
        continue child_origin.end()
      } nobreak {
        cursor
      }
      buf.write_string(
        source_slice_between(source, final_cursor, ir.origin().end()),
      )
      buf.to_string()
    }
    CodeBlock(_info, _value, content_origin) =>
      if content_origin == Some(target_origin) {
        local_code_block_markdown(
          source,
          ir.origin(),
          target_origin,
          replacement_text,
        )
      } else {
        source_slice(source, ir.origin())
      }
    ThematicBreak => source_slice(source, ir.origin())
    HtmlBlock(_, _) => source_slice(source, ir.origin())
    Text(_) | Raw(_, _) => source_slice(source, ir.origin())
    Bold(children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      "**" + rendered + "**"
    }
    Italic(children, content_origin) => {
      let rendered = if content_origin == Some(target_origin) {
        replacement_text
      } else {
        local_transform_inline_text(
          children, source, target_origin, replacement_text,
        )
      }
      "*" + rendered + "*"
    }
    InlineCode(value, content_origin) =>
      if content_origin == Some(target_origin) {
        "`" + replacement_text + "`"
      } else {
        "`" + value + "`"
      }
    Link(children, destination, destination_origin) => {
      let rendered_destination = if destination_origin == Some(target_origin) {
        replacement_text
      } else {
        destination
      }
      "[" +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      "](" +
      rendered_destination +
      ")"
    }
    Unsupported(_message) | Recovered(_message, _) =>
      // The caller only reaches this branch when target_origin is inside the
      // unsupported/recovered node's origin. Emit the replacement text rather
      // than a diagnostic comment so the edit is not silently lost.
      replacement_text
  }
}

///|
/// Experimental local-transform rewrite for the M1 text slice.
///
/// Unchanged document gaps and sibling nodes are copied from `source` by origin;
/// the block containing `target_origin` is re-rendered with `replacement_text`.
/// The target origin must come from the supplied IR, for example from `origin`,
/// `content_origin`, or `destination_origin`; `MarkdownIROrigin` construction is
/// intentionally not public while the rewrite contract is experimental. This
/// intentionally demonstrates local rewrite semantics without promoting CST
/// trivia into MarkdownIR.
pub fn experimental_markdown_ir_local_transform_rewrite(
  ir : MarkdownIR,
  source : String,
  target_origin~ : MarkdownIROrigin,
  replacement_text~ : String,
) -> String {
  if ir.origin().contains(target_origin) {
    local_transform_render(ir, source, target_origin, replacement_text)
  } else {
    experimental_markdown_ir_preserve_rewrite(ir, source)
  }
}

///|
fn canonical_inline_text(children : Array[MarkdownIR]) -> String {
  children.map(child => canonical_format_with_list_marker(child, Dash)).join("")
}

///|
fn indent_canonical_block(text : String, indent : String) -> String {
  text.split("\n").map(line => indent + line.to_owned()).join("\n")
}

///|
fn canonical_nested_flow_child(
  child : MarkdownIR,
  list_marker : UnorderedListMarker,
  previous_nested_marker : UnorderedListMarker?,
) -> (String, UnorderedListMarker?) {
  let (marker, next_previous) = match child.node {
    UnorderedList(_, _, surface_marker) => {
      let marker = match previous_nested_marker {
        Some(previous_marker) =>
          boundary_preserving_list_marker(previous_marker, surface_marker)
        None => list_marker
      }
      (marker, Some(marker))
    }
    _ => (list_marker, None)
  }
  (
    "\n" +
    indent_canonical_block(
      canonical_format_with_list_marker(child, marker),
      "  ",
    ),
    next_previous,
  )
}

///|
fn canonical_nested_flow_children(
  children : ArrayView[MarkdownIR],
  list_marker : UnorderedListMarker,
) -> String {
  let buf = StringBuilder::new()
  for child in children; previous_nested_marker = None {
    let (rendered, next_previous) = canonical_nested_flow_child(
      child, list_marker, previous_nested_marker,
    )
    buf.write_string(rendered)
    continue next_previous
  }
  buf.to_string()
}

///|
fn canonical_list_item_flow(
  marker_text : String,
  children : Array[MarkdownIR],
  list_marker : UnorderedListMarker,
) -> String {
  match children {
    [] => marker_text + " "
    [first, .. rest] => {
      let first_text = canonical_format_with_list_marker(first, list_marker)
      marker_text +
      " " +
      first_text +
      canonical_nested_flow_children(rest, list_marker)
    }
  }
}

///|
fn boundary_preserving_list_marker(
  previous_marker : UnorderedListMarker,
  surface_marker : UnorderedListMarker?,
) -> UnorderedListMarker {
  match surface_marker {
    Some(marker) if marker != previous_marker => marker
    _ =>
      match previous_marker {
        Dash => Plus
        Star | Plus => Dash
      }
  }
}

///|
fn canonical_document_format(children : Array[MarkdownIR]) -> String {
  let buf = StringBuilder::new()
  let mut previous_list_marker : UnorderedListMarker? = None
  for i, child in children {
    if i > 0 {
      buf.write_string("\n\n")
    }
    match child.node {
      UnorderedList(_, _, surface_marker) => {
        let marker = match previous_list_marker {
          Some(previous_marker) =>
            boundary_preserving_list_marker(previous_marker, surface_marker)
          None => Dash
        }
        buf.write_string(canonical_format_with_list_marker(child, marker))
        previous_list_marker = Some(marker)
      }
      OrderedList(_, _, _) => {
        buf.write_string(canonical_format_with_list_marker(child, Dash))
        previous_list_marker = None
      }
      _ => {
        buf.write_string(canonical_format_with_list_marker(child, Dash))
        previous_list_marker = None
      }
    }
  }
  buf.to_string()
}

///|
fn canonical_format_with_list_marker(
  ir : MarkdownIR,
  list_marker : UnorderedListMarker,
) -> String {
  match ir.node {
    Document(children) => canonical_document_format(children)
    Heading(depth, children, _) =>
      "#".repeat(depth) + " " + canonical_inline_text(children)
    Paragraph(children, _) => canonical_inline_text(children)
    BlockQuote(children) =>
      indent_canonical_block(canonical_document_format(children), "> ")
    UnorderedList(children, _, _) =>
      children
      .map(child => canonical_format_with_list_marker(child, list_marker))
      .join("\n")
    OrderedList(children, _, _) =>
      children
      .map(child => canonical_format_with_list_marker(child, list_marker))
      .join("\n")
    ListItem(children, _, _, _) =>
      canonical_list_item_flow(list_marker.text(), children, list_marker)
    OrderedListItem(children, _, _, marker) => {
      let item_marker = match marker {
        Some(marker) => marker.text()
        None => "1."
      }
      canonical_list_item_flow(item_marker, children, list_marker)
    }
    CodeBlock(info, value, _) => code_block_markdown(info, value)
    HtmlBlock(value, _) => value
    ThematicBreak => "---"
    Text(value) | Raw(value, _) => value
    Bold(children, _) => "**" + canonical_inline_text(children) + "**"
    Italic(children, _) => "*" + canonical_inline_text(children) + "*"
    InlineCode(value, _) => "`" + value + "`"
    Link(children, destination, _) =>
      "[" + canonical_inline_text(children) + "](" + destination + ")"
    Unsupported(message) => "<!-- unsupported MarkdownIR: " + message + " -->"
    Recovered(message, _) if message == RECOVERED_PARSE_ERROR =>
      "<!-- recovered MarkdownIR: " + message + " -->"
    Recovered(message, _) => message
  }
}

///|
pub fn experimental_markdown_ir_canonical_format(ir : MarkdownIR) -> String {
  canonical_format_with_list_marker(ir, Dash)
}
