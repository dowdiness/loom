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
      // Extract level from the HeadingMarker token
      let mut level = 1
      match node.find_token(HeadingMarkerToken.to_raw()) {
        Some(marker) => {
          // Count # characters in marker text
          let text = marker.text()
          let mut n = 0
          let len = text.length()
          while n < len {
            match text.code_unit_at(n).to_char() {
              Some('#') => n = n + 1
              _ => break
            }
          }
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
      // Extract info string from CodeFenceOpen token
      let mut info = ""
      match node.find_token(CodeFenceOpenToken.to_raw()) {
        Some(fence_tok) => {
          let text = fence_tok.text()
          // Info string is everything after the backticks
          let mut i = 0
          while i < text.length() {
            match text.code_unit_at(i).to_char() {
              Some('`') => i = i + 1
              _ => break
            }
          }
          if i < text.length() {
            info = text[i:].to_string()
          }
        }
        None => ()
      }
      // Collect code text content
      let code_buf = StringBuilder::new()
      let code_tokens = node.tokens_of_kind(CodeTextToken.to_raw())
      for i, tok in code_tokens {
        if i > 0 {
          code_buf.write_string("\n")
        }
        code_buf.write_string(tok.text())
      }
      Block::CodeBlock(info, code_buf.to_string())
    }
    ErrorNode => Block::Error("parse error")
    _ => Block::Error("unknown node: " + kind.to_string())
  }
}
