///|
/// Pure branch selection for the list item's indented-flow shell. The parser
/// supplies only token facts and the already-computed indentation; execution
/// remains owned by cst_parser.mbt.
priv enum ListItemFlowDecision {
  Stop
  IndentedCode
  NestedList
  PrefixedBlock
  PrefixedParagraph
}

///|
fn decide_list_item_indented_flow(
  current : Token,
  next : Token,
  indent : Int?,
  context : ListItemFlowContext,
  code_indent : Int,
) -> ListItemFlowDecision {
  match (current, indent) {
    (Indentation(_), Some(indent)) if indent >= code_indent => IndentedCode
    (Indentation(_), Some(indent)) if indent >= context.content_indent =>
      match next {
        ListMarker | OrderedListMarker(_) => NestedList
        ThematicBreak
        | HeadingMarker(_)
        | BlockQuoteMarker
        | CodeFenceOpen(_, _)
        | HtmlBlockOpen(_) => PrefixedBlock
        _ => PrefixedParagraph
      }
    _ => Stop
  }
}
