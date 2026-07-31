///|
test "native regression: CommonMark 254 list-relative quote makes progress" {
  // Minimal form of CommonMark 0.31.2 example 254 that previously repeated an
  // empty BlockQuoteNode until native EventBuffer growth aborted the process.
  let source_id = @core.SourceId(
    "markdown-native-regression-commonmark-254-minimal",
  )
  let source = "1.  \n    > y\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.text(), content=source)
  inspect(diagnostics.is_empty(), content="true")
  match syntax.children() {
    [list] => {
      let list_kind : SyntaxKind = @seam.FromRawKind::from_raw(list.kind())
      inspect(list_kind, content="OrderedListNode")
      match list.children() {
        [item] => {
          let item_kind : SyntaxKind = @seam.FromRawKind::from_raw(item.kind())
          inspect(item_kind, content="ListItemNode")
          match item.children() {
            [quote] => {
              let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                quote.kind(),
              )
              inspect(quote_kind, content="BlockQuoteNode")
              inspect(quote.text(), content="    > y\n")
            }
            _ => inspect(item.children().length(), content="one block quote")
          }
        }
        _ => inspect(list.children().length(), content="one list item")
      }
    }
    _ => inspect(syntax.children().length(), content="one ordered list")
  }
}

///|
test "native regression: CommonMark 254 full input completes" {
  let source_id = @core.SourceId(
    "markdown-native-regression-commonmark-254-full",
  )
  let source = "1.  A paragraph\n" +
    "    with two lines.\n" +
    "\n" +
    "        indented code\n" +
    "\n" +
    "    > A block quote.\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  inspect(@seam.SyntaxNode::from_cst(cst).text(), content=source)
  inspect(diagnostics.is_empty(), content="true")
}
