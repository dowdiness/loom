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
/// Experimental semantic form retained by a Markdown link or image.
pub(all) enum MarkdownIRLinkReferenceForm {
  InlineLinkForm
  FullReferenceLinkForm
  CollapsedReferenceLinkForm
  ShortcutReferenceLinkForm
} derive(Eq, Debug)

///|
/// Experimental source-aware surface metadata for a Markdown link or image.
///
/// These origins identify semantic source regions. Exact punctuation and
/// trivia remain the responsibility of the CST and source text.
pub(all) struct MarkdownIRLinkSurface {
  form : MarkdownIRLinkReferenceForm
  label_origin : MarkdownIROrigin?
  reference_label_origin : MarkdownIROrigin?
  destination_origin : MarkdownIROrigin?
  title_origin : MarkdownIROrigin?
} derive(Eq, Debug)

///|
/// Experimental semantic kind of an autolink.
pub(all) enum MarkdownIRAutolinkKind {
  UriAutolink
  EmailAutolink
} derive(Eq, Debug)

///|
/// Experimental semantic state and source marker for a GFM task list item.
pub struct MarkdownIRTask {
  priv checked : Bool
  priv marker_origin : MarkdownIROrigin
} derive(Eq, Debug)

///|
fn MarkdownIRTask::MarkdownIRTask(
  checked~ : Bool,
  marker_origin~ : MarkdownIROrigin,
) -> MarkdownIRTask {
  { checked, marker_origin }
}

///|
pub fn MarkdownIRTask::checked(self : MarkdownIRTask) -> Bool {
  self.checked
}

///|
pub fn MarkdownIRTask::marker_origin(self : MarkdownIRTask) -> MarkdownIROrigin {
  self.marker_origin
}

///|
/// Experimental source form retained for a hard line break.
pub(all) enum MarkdownIRHardBreakSurface {
  TrailingSpaces(Int)
  Backslash
} derive(Eq, Debug)

///|
/// Experimental exhaustive read view of one MarkdownIR node.
///
/// Child nodes, whole-node origins, content origins, and diagnostics remain
/// available through their common `MarkdownIR` accessors instead of being
/// repeated in every variant.
pub(all) enum MarkdownIRView {
  Document
  Heading(depth~ : Int)
  Paragraph
  BlockQuote
  UnorderedList(spread~ : Bool, marker~ : UnorderedListMarker?)
  OrderedList(spread~ : Bool, marker~ : OrderedListMarker?)
  ListItem(
    spread~ : Bool,
    marker~ : UnorderedListMarker?,
    task~ : MarkdownIRTask?
  )
  OrderedListItem(
    spread~ : Bool,
    marker~ : OrderedListMarker?,
    task~ : MarkdownIRTask?
  )
  CodeBlock(info~ : String, value~ : String)
  HtmlBlock(value~ : String)
  ThematicBreak
  Text(value~ : String)
  Bold
  Italic
  InlineCode(value~ : String)
  Link(
    destination~ : String,
    title~ : String?,
    surface~ : MarkdownIRLinkSurface
  )
  Image(
    destination~ : String,
    title~ : String?,
    surface~ : MarkdownIRLinkSurface
  )
  Autolink(
    kind~ : MarkdownIRAutolinkKind,
    display~ : String,
    destination~ : String,
    label_origin~ : MarkdownIROrigin?,
    destination_origin~ : MarkdownIROrigin?
  )
  InlineHtml(value~ : String)
  SoftBreak
  HardBreak(surface~ : MarkdownIRHardBreakSurface)
  Unsupported(message~ : String)
  Raw(value~ : String)
  Recovered(value~ : String)
} derive(Eq, Debug)

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
priv enum HardBreakSurface {
  TrailingSpaces(Int)
  Backslash
} derive(Eq, Debug)

///|
priv enum AutolinkKind {
  UriAutolinkKind
  EmailAutolinkKind
} derive(Eq, Debug)

///|
priv enum LinkReferenceForm {
  InlineLinkForm
  FullReferenceLinkForm
  CollapsedReferenceLinkForm
  ShortcutReferenceLinkForm
} derive(Eq, Debug)

///|
priv struct LinkSurface {
  form : LinkReferenceForm
  label_origin : MarkdownIROrigin?
  reference_label_origin : MarkdownIROrigin?
  destination_origin : MarkdownIROrigin?
  title_origin : MarkdownIROrigin?
  target_origin : MarkdownIROrigin?
} derive(Eq, Debug)

///|
fn hard_break_surface_text(surface : HardBreakSurface) -> String {
  match surface {
    HardBreakSurface::TrailingSpaces(count) => " ".repeat(count) + "\n"
    HardBreakSurface::Backslash => "\\\n"
  }
}

///|
priv enum MarkdownIRNode {
  Document(Array[MarkdownIR])
  Heading(Int, Array[MarkdownIR], MarkdownIROrigin?)
  Paragraph(Array[MarkdownIR], MarkdownIROrigin?)
  BlockQuote(Array[MarkdownIR])
  UnorderedList(Array[MarkdownIR], Bool, UnorderedListMarker?)
  OrderedList(Array[MarkdownIR], Bool, OrderedListMarker?)
  ListItem(
    Array[MarkdownIR],
    Bool,
    MarkdownIROrigin?,
    UnorderedListMarker?,
    MarkdownIRTask?
  )
  OrderedListItem(
    Array[MarkdownIR],
    Bool,
    MarkdownIROrigin?,
    OrderedListMarker?,
    MarkdownIRTask?
  )
  CodeBlock(String, String, MarkdownIROrigin?)
  HtmlBlock(String, MarkdownIROrigin?)
  ThematicBreak
  Text(String)
  ReferenceLinkOpener
  Bold(Array[MarkdownIR], MarkdownIROrigin?)
  Italic(Array[MarkdownIR], MarkdownIROrigin?)
  InlineCode(String, MarkdownIROrigin?)
  Link(Array[MarkdownIR], String, String?, LinkSurface)
  Image(Array[MarkdownIR], String, String?, LinkSurface)
  Autolink(AutolinkKind, String, String, MarkdownIROrigin?, MarkdownIROrigin?)
  InlineHtml(String, MarkdownIROrigin?)
  SoftBreak(MarkdownIROrigin?)
  HardBreak(HardBreakSurface, MarkdownIROrigin?)
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
  task? : MarkdownIRTask,
) -> MarkdownIR {
  { node: ListItem(children, spread, content_origin, marker, task), origin }
}

///|
fn MarkdownIR::ordered_list_item(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  spread~ : Bool,
  content_origin : MarkdownIROrigin?,
  marker~ : OrderedListMarker?,
  task? : MarkdownIRTask,
) -> MarkdownIR {
  {
    node: OrderedListItem(children, spread, content_origin, marker, task),
    origin,
  }
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
fn MarkdownIR::reference_link_opener(origin : MarkdownIROrigin) -> MarkdownIR {
  { node: ReferenceLinkOpener, origin }
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
#warnings("-unused_value")
fn MarkdownIR::link(
  children : Array[MarkdownIR],
  destination : String,
  origin : MarkdownIROrigin,
  label_origin : MarkdownIROrigin?,
  destination_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  MarkdownIR::link_with_metadata(
    children,
    destination,
    None,
    LinkReferenceForm::InlineLinkForm,
    origin,
    label_origin,
    None,
    destination_origin,
    None,
  )
}

///|
fn MarkdownIR::link_with_metadata(
  children : Array[MarkdownIR],
  destination : String,
  title : String?,
  form : LinkReferenceForm,
  origin : MarkdownIROrigin,
  label_origin : MarkdownIROrigin?,
  reference_label_origin : MarkdownIROrigin?,
  destination_origin : MarkdownIROrigin?,
  title_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  MarkdownIR::link_with_target_metadata(
    children,
    destination,
    title,
    form,
    origin,
    label_origin,
    reference_label_origin,
    destination_origin,
    title_origin,
    None,
  )
}

///|
fn MarkdownIR::link_with_target_metadata(
  children : Array[MarkdownIR],
  destination : String,
  title : String?,
  form : LinkReferenceForm,
  origin : MarkdownIROrigin,
  label_origin : MarkdownIROrigin?,
  reference_label_origin : MarkdownIROrigin?,
  destination_origin : MarkdownIROrigin?,
  title_origin : MarkdownIROrigin?,
  target_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  {
    node: Link(children, destination, title, {
      form,
      label_origin,
      reference_label_origin,
      destination_origin,
      title_origin,
      target_origin,
    }),
    origin,
  }
}

///|
fn MarkdownIR::image_from_link(
  link : MarkdownIR,
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  match link.node {
    Link(children, destination, title, surface) =>
      { node: Image(children, destination, title, surface), origin }
    _ => abort("MarkdownIR::image_from_link requires a Link node")
  }
}

///|
fn MarkdownIR::autolink(
  kind : AutolinkKind,
  display : String,
  destination : String,
  origin : MarkdownIROrigin,
  display_origin : MarkdownIROrigin?,
  destination_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  {
    node: Autolink(
      kind, display, destination, display_origin, destination_origin,
    ),
    origin,
  }
}

///|
fn MarkdownIR::inline_html(
  value : String,
  origin : MarkdownIROrigin,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIR {
  { node: InlineHtml(value, content_origin), origin }
}

///|
fn MarkdownIR::soft_break(origin : MarkdownIROrigin) -> MarkdownIR {
  { node: SoftBreak(Some(origin)), origin }
}

///|
fn MarkdownIR::hard_break(
  surface : HardBreakSurface,
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  match surface {
    HardBreakSurface::TrailingSpaces(count) if count < 2 =>
      abort("trailing-space hard break requires at least two spaces")
    _ => ()
  }
  { node: HardBreak(surface, Some(origin)), origin }
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
  source_id : @core.SourceId,
  value : String,
  origin : MarkdownIROrigin,
  diagnostics : Array[@core.Diagnostic],
) -> MarkdownIR {
  {
    node: Raw(
      value,
      recovery_diagnostics(
        source_id, "raw recovered Markdown", origin, diagnostics,
      ),
    ),
    origin,
  }
}

///|
fn MarkdownIR::recovered(
  source_id : @core.SourceId,
  value : String,
  origin : MarkdownIROrigin,
  diagnostics : Array[@core.Diagnostic],
) -> MarkdownIR {
  {
    node: Recovered(
      value,
      recovery_diagnostics(
        source_id, "recovered malformed Markdown", origin, diagnostics,
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
fn LinkReferenceForm::public_view(
  self : LinkReferenceForm,
) -> MarkdownIRLinkReferenceForm {
  match self {
    LinkReferenceForm::InlineLinkForm =>
      MarkdownIRLinkReferenceForm::InlineLinkForm
    LinkReferenceForm::FullReferenceLinkForm =>
      MarkdownIRLinkReferenceForm::FullReferenceLinkForm
    LinkReferenceForm::CollapsedReferenceLinkForm =>
      MarkdownIRLinkReferenceForm::CollapsedReferenceLinkForm
    LinkReferenceForm::ShortcutReferenceLinkForm =>
      MarkdownIRLinkReferenceForm::ShortcutReferenceLinkForm
  }
}

///|
fn LinkSurface::public_view(self : LinkSurface) -> MarkdownIRLinkSurface {
  {
    form: self.form.public_view(),
    label_origin: self.label_origin,
    reference_label_origin: self.reference_label_origin,
    destination_origin: self.destination_origin,
    title_origin: self.title_origin,
  }
}

///|
fn AutolinkKind::public_view(self : AutolinkKind) -> MarkdownIRAutolinkKind {
  match self {
    UriAutolinkKind => MarkdownIRAutolinkKind::UriAutolink
    EmailAutolinkKind => MarkdownIRAutolinkKind::EmailAutolink
  }
}

///|
fn HardBreakSurface::public_view(
  self : HardBreakSurface,
) -> MarkdownIRHardBreakSurface {
  match self {
    HardBreakSurface::TrailingSpaces(count) =>
      MarkdownIRHardBreakSurface::TrailingSpaces(count)
    HardBreakSurface::Backslash => MarkdownIRHardBreakSurface::Backslash
  }
}

///|
/// Return an exhaustive typed read view of this semantic node.
///
/// The view contains only meaning-bearing scalar and surface metadata. Use
/// `children`, `origin`, `content_origin`, and `diagnostics` for common tree
/// and source-attachment facts.
pub fn MarkdownIR::view(self : MarkdownIR) -> MarkdownIRView {
  match self.node {
    Document(_) => MarkdownIRView::Document
    Heading(depth, _, _) => MarkdownIRView::Heading(depth~)
    Paragraph(_, _) => MarkdownIRView::Paragraph
    BlockQuote(_) => MarkdownIRView::BlockQuote
    UnorderedList(_, spread, marker) =>
      MarkdownIRView::UnorderedList(spread~, marker~)
    OrderedList(_, spread, marker) =>
      MarkdownIRView::OrderedList(spread~, marker~)
    ListItem(_, spread, _, marker, task) =>
      MarkdownIRView::ListItem(spread~, marker~, task~)
    OrderedListItem(_, spread, _, marker, task) =>
      MarkdownIRView::OrderedListItem(spread~, marker~, task~)
    CodeBlock(info, value, _) => MarkdownIRView::CodeBlock(info~, value~)
    HtmlBlock(value, _) => MarkdownIRView::HtmlBlock(value~)
    ThematicBreak => MarkdownIRView::ThematicBreak
    Text(value) => MarkdownIRView::Text(value~)
    ReferenceLinkOpener => MarkdownIRView::Text(value="[")
    Bold(_, _) => MarkdownIRView::Bold
    Italic(_, _) => MarkdownIRView::Italic
    InlineCode(value, _) => MarkdownIRView::InlineCode(value~)
    Link(_, destination, title, surface) =>
      MarkdownIRView::Link(destination~, title~, surface=surface.public_view())
    Image(_, destination, title, surface) =>
      MarkdownIRView::Image(destination~, title~, surface=surface.public_view())
    Autolink(kind, display, destination, label_origin, destination_origin) =>
      MarkdownIRView::Autolink(
        kind=kind.public_view(),
        display~,
        destination~,
        label_origin~,
        destination_origin~,
      )
    InlineHtml(value, _) => MarkdownIRView::InlineHtml(value~)
    SoftBreak(_) => MarkdownIRView::SoftBreak
    HardBreak(surface, _) =>
      MarkdownIRView::HardBreak(surface=surface.public_view())
    Unsupported(message) => MarkdownIRView::Unsupported(message~)
    Raw(value, _) => MarkdownIRView::Raw(value~)
    Recovered(value, _) => MarkdownIRView::Recovered(value~)
  }
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
    ListItem(_, _, _, _, _) => "ListItem"
    OrderedListItem(_, _, _, _, _) => "OrderedListItem"
    CodeBlock(_, _, _) => "CodeBlock"
    HtmlBlock(_, _) => "HtmlBlock"
    ThematicBreak => "ThematicBreak"
    Text(_) | ReferenceLinkOpener => "Text"
    Bold(_, _) => "Bold"
    Italic(_, _) => "Italic"
    InlineCode(_, _) => "InlineCode"
    Link(_, _, _, _) => "Link"
    Image(_, _, _, _) => "Image"
    Autolink(_, _, _, _, _) => "Autolink"
    InlineHtml(_, _) => "InlineHtml"
    SoftBreak(_) => "SoftBreak"
    HardBreak(_, _) => "HardBreak"
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
    | ListItem(children, _, _, _, _)
    | OrderedListItem(children, _, _, _, _)
    | Bold(children, _)
    | Italic(children, _)
    | Link(children, _, _, _)
    | Image(children, _, _, _) => children.copy()
    CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | ThematicBreak
    | Text(_)
    | ReferenceLinkOpener
    | InlineCode(_, _)
    | Autolink(_, _, _, _, _)
    | InlineHtml(_, _)
    | SoftBreak(_)
    | HardBreak(_, _)
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
    Text(value)
    | Autolink(_, value, _, _, _)
    | InlineHtml(value, _)
    | Raw(value, _) => Some(value)
    ReferenceLinkOpener => Some("[")
    _ => None
  }
}

///|
pub fn MarkdownIR::content_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Heading(_, _, origin)
    | Paragraph(_, origin)
    | ListItem(_, _, origin, _, _)
    | OrderedListItem(_, _, origin, _, _)
    | CodeBlock(_, _, origin)
    | HtmlBlock(_, origin)
    | Bold(_, origin)
    | Italic(_, origin)
    | InlineCode(_, origin)
    | InlineHtml(_, origin)
    | SoftBreak(origin)
    | HardBreak(_, origin) => origin
    _ => None
  }
}

///|
pub fn MarkdownIR::spread(self : MarkdownIR) -> Bool? {
  match self.node {
    UnorderedList(_, spread, _)
    | OrderedList(_, spread, _)
    | ListItem(_, spread, _, _, _)
    | OrderedListItem(_, spread, _, _, _) => Some(spread)
    _ => None
  }
}

///|
pub fn MarkdownIR::list_marker(self : MarkdownIR) -> UnorderedListMarker? {
  match self.node {
    UnorderedList(_, _, marker) | ListItem(_, _, _, marker, _) => marker
    _ => None
  }
}

///|
pub fn MarkdownIR::label_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Link(_, _, _, surface) | Image(_, _, _, surface) => surface.label_origin
    Autolink(_, _, _, origin, _) => origin
    _ => None
  }
}

///|
pub fn MarkdownIR::destination_origin(self : MarkdownIR) -> MarkdownIROrigin? {
  match self.node {
    Link(_, _, _, surface) | Image(_, _, _, surface) =>
      surface.destination_origin
    Autolink(_, _, _, _, origin) => origin
    _ => None
  }
}

///|
fn markdown_ir_plain_text(children : Array[MarkdownIR]) -> String {
  let builder = StringBuilder::StringBuilder()
  fn append(node : MarkdownIR) -> Unit {
    match node.node {
      Text(value)
      | InlineCode(value, _)
      | InlineHtml(value, _)
      | Raw(value, _) => builder.write_string(value)
      ReferenceLinkOpener => builder.write_char('[')
      Autolink(_, display, _, _, _) => builder.write_string(display)
      SoftBreak(_) | HardBreak(_, _) => builder.write_char('\n')
      Bold(children, _)
      | Italic(children, _)
      | Link(children, _, _, _)
      | Image(children, _, _, _) =>
        for child in children {
          append(child)
        }
      Recovered(value, _) => builder.write_string(value)
      Unsupported(message) => builder.write_string(message)
      Document(children)
      | Heading(_, children, _)
      | Paragraph(children, _)
      | BlockQuote(children)
      | UnorderedList(children, _, _)
      | OrderedList(children, _, _)
      | ListItem(children, _, _, _, _)
      | OrderedListItem(children, _, _, _, _) =>
        for child in children {
          append(child)
        }
      CodeBlock(_, value, _) | HtmlBlock(value, _) =>
        builder.write_string(value)
      ThematicBreak => ()
    }
  }
  for child in children {
    append(child)
  }
  builder.to_string()
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
  source_id : @core.SourceId,
  message : String,
  origin : MarkdownIROrigin,
) -> @core.Diagnostic {
  let range = try! @core.TextRange::from_offsets(origin.start(), origin.end())
  @core.Diagnostic::Diagnostic(
    origin=@core.DiagnosticOrigin("parser"),
    severity=@core.DiagnosticSeverity::all()[0],
    code=Some(@core.DiagnosticCode("markdown-ir.recovery")),
    message~,
    labels=[
      @core.DiagnosticLabel::DiagnosticLabel(
        @core.LabelStyle::Primary,
        @core.SourceSpan::SourceSpan(source_id, range),
        None,
      ),
    ],
  )
}

///|
fn recovery_diagnostics(
  source_id : @core.SourceId,
  message : String,
  origin : MarkdownIROrigin,
  diagnostics : Array[@core.Diagnostic],
) -> Array[@core.Diagnostic] {
  if diagnostics.length() > 0 {
    diagnostics.copy()
  } else {
    [recovery_diagnostic(source_id, message, origin)]
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
