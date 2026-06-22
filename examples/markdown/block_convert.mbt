///|
fn trim_trailing_line_ending(text : String) -> String {
  if text.has_suffix("\r\n") {
    text[:text.length() - 2].to_owned()
  } else if text.has_suffix("\r") || text.has_suffix("\n") {
    text[:text.length() - 1].to_owned()
  } else {
    text
  }
}

///|
/// Algebra for CstFold: convert SyntaxNode to Block.
pub fn markdown_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> Block,
) -> Block {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    DocumentNode => {
      let blocks : Array[Block] = []
      for child in node.children() {
        let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
        // Skip BlankLine nodes at document level (they're structural separators)
        match child_kind {
          HeadingNode
          | ParagraphNode
          | BlockQuoteNode
          | UnorderedListNode
          | OrderedListNode
          | CodeBlockNode
          | HtmlBlockNode
          | ThematicBreakNode
          | ErrorNode => blocks.push(recurse(child))
          _ => () // skip BlankLine/Newline tokens at top level
        }
      }
      Block::Document(blocks)
    }
    HeadingNode => {
      // Re-parse heading level from CST token text because Token payloads
      // (HeadingMarker(Int), setext underline depth) are lost across the CST
      // boundary — CST stores raw text only.
      let level = heading_depth_from_marker(node).unwrap_or(1)
      let inlines = convert_inline_children(node)
      Block::Heading(level, inlines)
    }
    ParagraphNode => {
      let inlines = convert_inline_children_with_newline(node, " ")
      Block::Paragraph(inlines)
    }
    BlockQuoteNode =>
      Block::Paragraph([Inline::Text(trim_trailing_line_ending(node.text()))])
    UnorderedListNode => Block::UnorderedList(node.children().map(recurse))
    OrderedListNode => {
      let items = node.children().map(recurse)
      let marker = match items {
        [OrderedListItem(_, marker), ..] => marker
        _ => None
      }
      Block::OrderedList(items, marker)
    }
    ListItemNode => {
      let inlines = convert_direct_inline_children_with_newline(node, "\n")
      match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
        Some(token) =>
          Block::OrderedListItem(
            inlines,
            ordered_list_marker_from_text(token.text()),
          )
        None => Block::UnorderedListItem(inlines)
      }
    }
    CodeBlockNode => {
      // Re-parse info string from CST token text (same reason as heading level above).
      let info = match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
        Some(fence_tok) => {
          let text = fence_tok.text()
          let i = count_backticks(text, 0)
          if i < text.length() {
            text[i:].to_owned()
          } else {
            ""
          }
        }
        None => ""
      }
      Block::CodeBlock(info, code_block_value(node))
    }
    HtmlBlockNode => Block::HtmlBlock(html_block_value(node))
    ThematicBreakNode =>
      Block::Paragraph([Inline::Text(trim_trailing_line_ending(node.text()))])
    ErrorNode => Block::Error(RECOVERED_PARSE_ERROR)
    _ => Block::Error("unknown node: " + kind.to_string())
  }
}
