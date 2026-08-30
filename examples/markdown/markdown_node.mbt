///|
/// stable semantic form retained by a Markdown link or image.
pub(all) enum MarkdownReferenceForm {
  Inline
  FullReference
  CollapsedReference
  ShortcutReference
} derive(Eq, Debug)

///|
/// semantic kind of an autolink.
pub(all) enum MarkdownAutolinkKind {
  Uri
  Email
} derive(Eq, Debug)

///|
/// source form retained for a hard line break.
pub(all) enum MarkdownHardBreakForm {
  TrailingSpaces(Int)
  Backslash
} derive(Eq, Debug)

///|
/// exhaustive public read view of one Markdown semantic node.
///
/// Children and source attachment stay on `MarkdownNode`; the view contains
/// only the semantic and rendering metadata needed to interpret this node.
pub(all) enum MarkdownNodeView {
  Document
  Heading(depth~ : Int)
  Paragraph
  BlockQuote
  UnorderedList(spread~ : Bool, marker~ : UnorderedListMarker?)
  OrderedList(spread~ : Bool, marker~ : OrderedListMarker?)
  ListItem(
    spread~ : Bool,
    marker~ : UnorderedListMarker?,
    task_checked~ : Bool?
  )
  OrderedListItem(
    spread~ : Bool,
    marker~ : OrderedListMarker?,
    task_checked~ : Bool?
  )
  CodeBlock(info~ : String, value~ : String)
  HtmlBlock(value~ : String)
  ThematicBreak
  Text(value~ : String)
  Strong
  Emphasis
  InlineCode(value~ : String)
  Link(
    destination~ : String,
    title~ : String?,
    reference_form~ : MarkdownReferenceForm
  )
  Image(
    destination~ : String,
    title~ : String?,
    reference_form~ : MarkdownReferenceForm
  )
  Autolink(
    kind~ : MarkdownAutolinkKind,
    display~ : String,
    destination~ : String
  )
  InlineHtml(value~ : String)
  SoftBreak
  HardBreak(form~ : MarkdownHardBreakForm)
  Unsupported(message~ : String)
  Raw(value~ : String)
  Recovered(value~ : String)
} derive(Eq, Debug)

///|
/// Detached, opaque semantic node owned by one document snapshot.
pub(all) struct MarkdownNode {
  priv document_marker : Ref[Unit]
  priv node : MarkdownIR
}

///|
/// Return this detached document's retained semantic root.
pub fn MarkdownDocument::root(self : MarkdownDocument) -> MarkdownNode {
  { document_marker: self.node_marker, node: self.ir }
}

///|
/// Return the exhaustive typed view of this node.
pub fn MarkdownNode::view(self : MarkdownNode) -> MarkdownNodeView {
  markdown_node_view_from_ir(self.node.view())
}

///|
/// Return detached opaque child nodes.
pub fn MarkdownNode::children(self : MarkdownNode) -> Array[MarkdownNode] {
  self.node
  .children()
  .map(node => { document_marker: self.document_marker, node })
}

///|
fn markdown_reference_form_from_ir(
  form : MarkdownIRLinkReferenceForm,
) -> MarkdownReferenceForm {
  match form {
    InlineLinkForm => Inline
    FullReferenceLinkForm => FullReference
    CollapsedReferenceLinkForm => CollapsedReference
    ShortcutReferenceLinkForm => ShortcutReference
  }
}

///|
fn markdown_node_view_from_ir(view : MarkdownIRView) -> MarkdownNodeView {
  match view {
    MarkdownIRView::Document => MarkdownNodeView::Document
    Heading(depth~) => MarkdownNodeView::Heading(depth~)
    Paragraph => MarkdownNodeView::Paragraph
    BlockQuote => MarkdownNodeView::BlockQuote
    UnorderedList(spread~, marker~) =>
      MarkdownNodeView::UnorderedList(spread~, marker~)
    OrderedList(spread~, marker~) =>
      MarkdownNodeView::OrderedList(spread~, marker~)
    ListItem(spread~, marker~, task~) =>
      MarkdownNodeView::ListItem(
        spread~,
        marker~,
        task_checked=task.map(task => task.checked()),
      )
    OrderedListItem(spread~, marker~, task~) =>
      MarkdownNodeView::OrderedListItem(
        spread~,
        marker~,
        task_checked=task.map(task => task.checked()),
      )
    CodeBlock(info~, value~) => MarkdownNodeView::CodeBlock(info~, value~)
    HtmlBlock(value~) => MarkdownNodeView::HtmlBlock(value~)
    ThematicBreak => MarkdownNodeView::ThematicBreak
    Text(value~) => MarkdownNodeView::Text(value~)
    Bold => MarkdownNodeView::Strong
    Italic => MarkdownNodeView::Emphasis
    InlineCode(value~) => MarkdownNodeView::InlineCode(value~)
    Link(destination~, title~, surface~) =>
      MarkdownNodeView::Link(
        destination~,
        title~,
        reference_form=markdown_reference_form_from_ir(surface.form),
      )
    Image(destination~, title~, surface~) =>
      MarkdownNodeView::Image(
        destination~,
        title~,
        reference_form=markdown_reference_form_from_ir(surface.form),
      )
    Autolink(kind~, display~, destination~, ..) =>
      MarkdownNodeView::Autolink(
        kind=match kind {
          UriAutolink => MarkdownAutolinkKind::Uri
          EmailAutolink => MarkdownAutolinkKind::Email
        },
        display~,
        destination~,
      )
    InlineHtml(value~) => MarkdownNodeView::InlineHtml(value~)
    SoftBreak => MarkdownNodeView::SoftBreak
    HardBreak(surface~) =>
      MarkdownNodeView::HardBreak(
        form=match surface {
          MarkdownIRHardBreakSurface::TrailingSpaces(count) =>
            MarkdownHardBreakForm::TrailingSpaces(count)
          Backslash => MarkdownHardBreakForm::Backslash
        },
      )
    Unsupported(message~) => MarkdownNodeView::Unsupported(message~)
    Raw(value~) => MarkdownNodeView::Raw(value~)
    Recovered(value~) => MarkdownNodeView::Recovered(value~)
  }
}
