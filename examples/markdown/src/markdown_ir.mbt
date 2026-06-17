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
priv enum MarkdownIRNode {
  Document(Array[MarkdownIR])
  Heading(Int, Array[MarkdownIR], MarkdownIROrigin?)
  Paragraph(Array[MarkdownIR], MarkdownIROrigin?)
  UnorderedList(Array[MarkdownIR])
  ListItem(Array[MarkdownIR], MarkdownIROrigin?)
  CodeBlock(String, String, MarkdownIROrigin?)
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
fn MarkdownIR::unordered_list(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  { node: UnorderedList(children), origin }
}

///|
fn MarkdownIR::list_item(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: ListItem(children, content_origin), origin }
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
    UnorderedList(_) => "UnorderedList"
    ListItem(_, _) => "ListItem"
    CodeBlock(_, _, _) => "CodeBlock"
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
    | UnorderedList(children)
    | ListItem(children, _)
    | Bold(children, _)
    | Italic(children, _)
    | Link(children, _, _) => children.copy()
    CodeBlock(_, _, _)
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
    | ListItem(_, origin)
    | CodeBlock(_, _, origin)
    | Bold(_, origin)
    | Italic(_, origin)
    | InlineCode(_, origin) => origin
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
    match pending_newline {
      Some(origin) => {
        match newline_text {
          Some(text) => children.push(MarkdownIR::text(text, origin))
          None => ()
        }
        pending_newline = None
      }
      None => ()
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
            push_child(MarkdownIR::text(token.text(), origin_from_token(token)))
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
          lower_inline_node_with_diags(child_node, diagnostics_in_origin),
        )
    }
  }
  children
}

///|
fn lower_inline_children_with_diags(
  node : @seam.SyntaxNode,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  lower_inline_children_skip_with_diags(node, None, None, diagnostics_in_origin)
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
            lower_inline_node_with_diags(child_node, diagnostics_in_origin),
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
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    BoldNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(StarStarToken),
        None,
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
        None,
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
    LinkNode => lower_link_node_with_diags(node, diagnostics_in_origin)
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
fn heading_depth_from_marker(node : @seam.SyntaxNode) -> Int? {
  match node.direct_token_of_kind(HeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let n = count_hashes(marker.text(), 0)
      // count_hashes caps at 6, so n <= 6 is guaranteed.
      if n >= 1 {
        Some(n)
      } else {
        None
      }
    }
    None => None
  }
}

///|
fn lower_document_child_with_diags(
  child : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> MarkdownIR? {
  let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
  match child_kind {
    HeadingNode | ParagraphNode | UnorderedListNode | CodeBlockNode =>
      Some(recurse(child))
    ErrorNode => {
      let origin = origin_from_node(child)
      Some(
        MarkdownIR::recovered(
          "parse error",
          origin,
          diagnostics_in_origin(origin),
        ),
      )
    }
    _ => None
  }
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
          NewlineToken if in_code => buf.write_string("\n")
          _ => ()
        }
      }
      _ => ()
    }
  }
  trim_code_boundary_newlines(buf.to_string())
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
          lower_document_child_with_diags(child, recurse, diagnostics_in_origin)
        })
        .collect()
      MarkdownIR::document(children, origin_from_node(node))
    }
    HeadingNode => {
      let children = lower_inline_children_with_diags(
        node, diagnostics_in_origin,
      )
      match heading_depth_from_marker(node) {
        Some(depth) =>
          MarkdownIR::heading(
            depth,
            children,
            origin_from_node(node),
            span_origin_of_children(children),
          )
        None =>
          MarkdownIR::unsupported(
            "invalid heading marker",
            origin_from_node(node),
          )
      }
    }
    ParagraphNode => {
      let children = lower_inline_children_with_newline_and_diags(
        node, " ", diagnostics_in_origin,
      )
      MarkdownIR::paragraph(
        children,
        origin_from_node(node),
        span_origin_of_children(children),
      )
    }
    UnorderedListNode => {
      let children : Array[MarkdownIR] = node
        .children()
        .iter()
        .filter_map(child => {
          let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            child.kind(),
          )
          match child_kind {
            ListItemNode => Some(recurse(child))
            _ => None
          }
        })
        .collect()
      MarkdownIR::unordered_list(children, origin_from_node(node))
    }
    ListItemNode => {
      let children = lower_inline_children_with_diags(
        node, diagnostics_in_origin,
      )
      MarkdownIR::list_item(
        children,
        origin_from_node(node),
        span_origin_of_children(children),
      )
    }
    CodeBlockNode =>
      MarkdownIR::code_block(
        code_block_info(node),
        code_block_value(node),
        origin_from_node(node),
        None,
      )
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(
        "parse error",
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
    UnorderedList(_) => Inline::Error("expected inline MarkdownIR, got list")
    ListItem(_, _) => Inline::Error("expected inline MarkdownIR, got list item")
    CodeBlock(_, _, _) =>
      Inline::Error("expected inline MarkdownIR, got code block")
  }
}

///|
fn ir_children_to_inlines(children : Array[MarkdownIR]) -> Array[Inline] {
  children.map(experimental_markdown_ir_to_inline)
}

///|
pub fn experimental_markdown_ir_to_block(ir : MarkdownIR) -> Block {
  match ir.node {
    Document(children) =>
      Block::Document(children.map(experimental_markdown_ir_to_block))
    Heading(depth, children, _) =>
      Block::Heading(depth, ir_children_to_inlines(children))
    Paragraph(children, _) => Block::Paragraph(ir_children_to_inlines(children))
    UnorderedList(children) =>
      Block::UnorderedList(children.map(experimental_markdown_ir_to_block))
    ListItem(children, _) => Block::ListItem(ir_children_to_inlines(children))
    CodeBlock(info, value, _) => Block::CodeBlock(info, value)
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
pub fn experimental_markdown_ir_to_mdast_json(ir : MarkdownIR) -> Json {
  match ir.node {
    Document(children) =>
      {
        "type": "root",
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    Heading(depth, children, _) =>
      {
        "type": "heading",
        "depth": depth,
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    Paragraph(children, _) =>
      {
        "type": "paragraph",
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    UnorderedList(children) =>
      {
        "type": "list",
        "ordered": false,
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    ListItem(children, _) =>
      {
        "type": "listItem",
        "children": [
          {
            "type": "paragraph",
            "children": children.map(experimental_markdown_ir_to_mdast_json),
          },
        ],
      }
    CodeBlock(info, value, _) =>
      if info.length() > 0 {
        { "type": "code", "lang": info, "value": value }
      } else {
        { "type": "code", "value": value }
      }
    Text(value) => { "type": "text", "value": value }
    Bold(children, _) =>
      {
        "type": "strong",
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    Italic(children, _) =>
      {
        "type": "emphasis",
        "children": children.map(experimental_markdown_ir_to_mdast_json),
      }
    InlineCode(value, _) => { "type": "inlineCode", "value": value }
    Link(children, destination, _) =>
      {
        "type": "link",
        "url": destination,
        "children": children.map(experimental_markdown_ir_to_mdast_json),
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
  if source_slice(source, origin).has_suffix("\n") {
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
            Text(value) | Raw(value, _) => buf.write_string(value)
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
fn local_transform_render(
  ir : MarkdownIR,
  source : String,
  target_origin : MarkdownIROrigin,
  replacement_text : String,
) -> String {
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
    Heading(depth, children, _) =>
      "#".repeat(depth) +
      " " +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      original_block_trailing_newline(source, ir.origin())
    Paragraph(children, _) =>
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      original_block_trailing_newline(source, ir.origin())
    UnorderedList(children) => {
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
    ListItem(children, _) =>
      "- " +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      )
    CodeBlock(info, value, _) =>
      if ir.origin() == target_origin {
        replacement_text
      } else {
        code_block_markdown(info, value)
      }
    Text(value) | Raw(value, _) =>
      if ir.origin() == target_origin {
        replacement_text
      } else {
        value
      }
    Bold(children, _) =>
      "**" +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      "**"
    Italic(children, _) =>
      "*" +
      local_transform_inline_text(
        children, source, target_origin, replacement_text,
      ) +
      "*"
    InlineCode(value, content_origin) =>
      if ir.origin() == target_origin {
        replacement_text
      } else if content_origin == Some(target_origin) {
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
/// This intentionally demonstrates local rewrite semantics without promoting
/// CST trivia into MarkdownIR.
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
  children.map(experimental_markdown_ir_canonical_format).join("")
}

///|
pub fn experimental_markdown_ir_canonical_format(ir : MarkdownIR) -> String {
  match ir.node {
    Document(children) =>
      children.map(experimental_markdown_ir_canonical_format).join("\n\n")
    Heading(depth, children, _) =>
      "#".repeat(depth) + " " + canonical_inline_text(children)
    Paragraph(children, _) => canonical_inline_text(children)
    UnorderedList(children) =>
      children.map(experimental_markdown_ir_canonical_format).join("\n")
    ListItem(children, _) => "- " + canonical_inline_text(children)
    CodeBlock(info, value, _) => code_block_markdown(info, value)
    Text(value) | Raw(value, _) => value
    Bold(children, _) => "**" + canonical_inline_text(children) + "**"
    Italic(children, _) => "*" + canonical_inline_text(children) + "*"
    InlineCode(value, _) => "`" + value + "`"
    Link(children, destination, _) =>
      "[" + canonical_inline_text(children) + "](" + destination + ")"
    Unsupported(message) => "<!-- unsupported MarkdownIR: " + message + " -->"
    Recovered(message, _) => "<!-- recovered MarkdownIR: " + message + " -->"
  }
}
