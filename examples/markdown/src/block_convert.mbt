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
          | UnorderedListNode
          | CodeBlockNode
          | ErrorNode => blocks.push(recurse(child))
          _ => () // skip BlankLine/Newline tokens at top level
        }
      }
      Block::Document(blocks)
    }
    HeadingNode => {
      // Re-parse heading level from CST token text because the Token payload
      // (HeadingMarker(Int)) is lost across the CST boundary — CST stores raw text only.
      let mut level = 1
      match node.find_token(HeadingMarkerToken.to_raw()) {
        Some(marker) => {
          let n = count_hashes(marker.text(), 0)
          if n > 0 {
            level = n
          }
        }
        None => ()
      }
      let inlines = convert_inline_children(node)
      Block::Heading(level, inlines)
    }
    ParagraphNode => {
      let inlines = convert_inline_children(node)
      Block::Paragraph(inlines)
    }
    UnorderedListNode => {
      let items : Array[Block] = []
      for child in node.children() {
        items.push(recurse(child))
      }
      Block::UnorderedList(items)
    }
    ListItemNode => {
      let inlines = convert_inline_children(node)
      Block::ListItem(inlines)
    }
    CodeBlockNode => {
      // Re-parse info string from CST token text (same reason as heading level above).
      let mut info = ""
      match node.find_token(CodeFenceOpenToken.to_raw()) {
        Some(fence_tok) => {
          let text = fence_tok.text()
          let i = count_backticks(text, 0)
          if i < text.length() {
            info = text[i:].to_string()
          }
        }
        None => ()
      }
      // Collect code content: walk all tokens between fences, preserving
      // blank lines (Newline tokens without intervening CodeText).
      let code_buf = StringBuilder::new()
      let mut in_code = false
      for elem in node.all_children() {
        match elem {
          @seam.SyntaxElement::Token(tok) => {
            let tk : SyntaxKind = @seam.FromRawKind::from_raw(tok.kind())
            match tk {
              CodeFenceOpenToken => in_code = true
              CodeFenceCloseToken => in_code = false
              CodeTextToken if in_code => code_buf.write_string(tok.text())
              NewlineToken if in_code => code_buf.write_string("\n")
              _ => ()
            }
          }
          _ => ()
        }
      }
      // Trim leading newline (the one right after CodeFenceOpen)
      let code_str = code_buf.to_string()
      let trimmed = if code_str.length() > 0 &&
        code_str.code_unit_at(0).to_char() == Some('\n') {
        code_str.substring(start=1)
      } else {
        code_str
      }
      // Trim trailing newline (the one right before CodeFenceClose)
      let final_code = if trimmed.length() > 0 &&
        trimmed.code_unit_at(trimmed.length() - 1).to_char() == Some('\n') {
        trimmed.substring(end=trimmed.length() - 1)
      } else {
        trimmed
      }
      Block::CodeBlock(info, final_code)
    }
    ErrorNode => Block::Error("parse error")
    _ => Block::Error("unknown node: " + kind.to_string())
  }
}
