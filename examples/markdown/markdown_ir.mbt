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
  Link(Array[MarkdownIR], String, MarkdownIROrigin?, MarkdownIROrigin?)
  HardBreak(MarkdownIROrigin?)
  Unsupported(String)
  Raw(String, Array[@core.Diagnostic])
  Recovered(String, Array[@core.Diagnostic])
} derive(Eq, Debug)

///|
/// Experimental Markdown semantic IR for the M1 heading/paragraph slice.
///
/// Public construction is intentionally withheld while the IR contract is
/// experimental. Build values through `experimental_markdown_ir_from_syntax`,
/// then consume them through the experimental adapters in this package.
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
  label_origin : MarkdownIROrigin?,
  destination_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  {
    node: Link(children, destination, label_origin, destination_origin),
    origin,
  }
}

///|
fn MarkdownIR::hard_break(origin : MarkdownIROrigin) -> MarkdownIR {
  { node: HardBreak(Some(origin)), origin }
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
    Link(_, _, _, _) => "Link"
    HardBreak(_) => "HardBreak"
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
    | Link(children, _, _, _) => children.copy()
    CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | ThematicBreak
    | Text(_)
    | InlineCode(_, _)
    | HardBreak(_)
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
    | InlineCode(_, origin)
    | HardBreak(origin) => origin
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
pub fn MarkdownIR::label_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Link(_, _, origin, _) => origin
    _ => None
  }
}

///|
pub fn MarkdownIR::destination_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Link(_, _, _, origin) => origin
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
fn zero_width_origin_at(offset : Int) -> MarkdownIROrigin {
  MarkdownIROrigin(start=offset, end=offset)
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
