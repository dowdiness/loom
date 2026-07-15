///|
test "parse: heading" {
  let block = parse("# Hello\n")
  inspect(block, content="Document([Heading(1, [Text(\"Hello\")])])")
}

///|
test "parse: ATX heading inline recovery stops at line ending" {
  inspect(
    parse("# *foo\nbar*\n"),
    content=(
      #|Document(
      #|  [
      #|    Heading(1, [Error("*"), Text("foo")]),
      #|    Paragraph([Text("bar"), Error("*")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: setext heading preserves legacy heading depth" {
  inspect(
    parse("Foo\n---\n"),
    content="Document([Heading(2, [Text(\"Foo\")])])",
  )
  inspect(parse("Foo\n- \n"), content="Document([Heading(2, [Text(\"Foo\")])])")
  inspect(
    parse("Foo\n-  \n"),
    content="Document([Heading(2, [Text(\"Foo\")])])",
  )
  inspect(
    parse("First\nsecond\n---\n"),
    content="Document([Heading(2, [Text(\"First\"), Text(\"second\")])])",
  )
  inspect(
    parse("First\nsecond\n===\n"),
    content="Document([Heading(1, [Text(\"First\"), Text(\"second\")])])",
  )
}

///|
test "parse: setext underline stops multiline emphasis recovery" {
  inspect(
    parse("Foo *bar\n====\nbaz*\n"),
    content=(
      #|Document(
      #|  [
      #|    Heading(1, [Text("Foo "), Error("*"), Text("bar")]),
      #|    Paragraph([Text("baz"), Error("*")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: setext continuation stops multiline emphasis recovery" {
  inspect(
    parse("Foo\nbar *baz\n====\nqux*\n"),
    content=(
      #|Document(
      #|  [
      #|    Heading(1, [Text("Foo"), Text("bar "), Error("*"), Text("baz")]),
      #|    Paragraph([Text("qux"), Error("*")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: ordered list item setext probe stops at ordered item boundary" {
  inspect(
    parse("1. Foo\n2. bar\n---\n"),
    content=(
      #|Document(
      #|  [
      #|    OrderedList(
      #|      [
      #|        OrderedListItem([Text("Foo")], Some({ start: 1, delimiter: Period })),
      #|        OrderedListItem([Text("bar")], Some({ start: 2, delimiter: Period })),
      #|      ],
      #|      Some({ start: 1, delimiter: Period }),
      #|    ),
      #|    Paragraph([Text("---")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: paragraph" {
  let block = parse("Hello world\n")
  inspect(block, content="Document([Paragraph([Text(\"Hello world\")])])")
}

///|
test "parse: three-space-prefixed fence is code block" {
  inspect(
    parse("   ```\ncode\n   ```\n"),
    content="Document([CodeBlock(\"\", \"code\")])",
  )
}

///|
test "parse: three-space-prefixed quote is block quote" {
  let (cst, _) = try! parse_cst("   > quote\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      inspect(kind, content="BlockQuoteNode")
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: blockquote preserves legacy text projection" {
  let block = parse("> quote\n")
  inspect(block, content="Document([Paragraph([Text(\"> quote\")])])")
}

///|
test "parse: blockquote lazy continuation stays in quoted paragraph CST" {
  let (cst, _) = try! parse_cst("> bar\nbaz\n> foo\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      inspect(quote_kind, content="BlockQuoteNode")
      match quote.children() {
        [paragraph] => {
          let paragraph_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            paragraph.kind(),
          )
          inspect(paragraph_kind, content="ParagraphNode")
        }
        _ => inspect(quote.children().length(), content="one paragraph")
      }
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: blockquote lazy continuation preserves legacy text projection" {
  let block = parse("> bar\nbaz\n")
  inspect(block, content="Document([Paragraph([Text(\"> bar\\nbaz\")])])")
}

///|
test "parse: blockquote lazy continuation rejects thematic break line" {
  let (cst, _) = try! parse_cst("> foo\n---\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote, separator] => {
      let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      let separator_kind : SyntaxKind = @seam.FromRawKind::from_raw(
        separator.kind(),
      )
      inspect(quote_kind, content="BlockQuoteNode")
      inspect(separator_kind, content="ThematicBreakNode")
    }
    _ =>
      inspect(syntax.children().length(), content="blockquote then separator")
  }
}

///|
test "parse: thematic break preserves legacy text projection" {
  let block = parse("---\n")
  inspect(block, content="Document([Paragraph([Text(\"---\")])])")
}

///|
test "parse: list-item thematic break after marker is CST block child" {
  let (cst, _) = try! parse_cst("- Foo\n- * * *\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [_, item] =>
          match item.children() {
            [separator] => {
              let separator_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                separator.kind(),
              )
              inspect(separator_kind, content="ThematicBreakNode")
            }
            _ => inspect(item.children().length(), content="one thematic break")
          }
        _ => inspect(list.children().length(), content="two list items")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: list-item thematic break preserves legacy text projection" {
  let block = parse("- * * *\n")
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"* * *\")])])])",
  )
}

///|
test "parse: empty list item does not promote indented underline to setext heading" {
  let (cst, _) = try! parse_cst("- \n  ---\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list, ..] =>
      match list.children() {
        [item] => {
          for child in item.children() {
            let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(
              child.kind(),
            )
            if child_kind is HeadingNode {
              fail("empty list item must not contain a setext heading")
            }
          }
          inspect(item.children().length(), content="0")
        }
        _ => inspect(list.children().length(), content="one list item")
      }
    _ =>
      inspect(syntax.children().length(), content="list plus following block")
  }
}

///|
test "parse: blockquote lazy continuation accepts indented thematic text" {
  for source in ["> foo\n    ---\n", "> foo\n\t---\n"] {
    let (cst, _) = try! parse_cst(source)
    let syntax = @seam.SyntaxNode::from_cst(cst)
    match syntax.children() {
      [quote] => {
        let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
        inspect(quote_kind, content="BlockQuoteNode")
        match quote.children() {
          [paragraph] => {
            let paragraph_kind : SyntaxKind = @seam.FromRawKind::from_raw(
              paragraph.kind(),
            )
            inspect(paragraph_kind, content="ParagraphNode")
          }
          _ => inspect(quote.children().length(), content="one paragraph")
        }
      }
      _ => inspect(syntax.children().length(), content="one blockquote")
    }
  }
}

///|
test "parse: blockquote setext heading has heading CST child" {
  let (cst, _) = try! parse_cst("> foo\n> ---\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      inspect(quote_kind, content="BlockQuoteNode")
      match quote.children() {
        [heading] => {
          let heading_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            heading.kind(),
          )
          inspect(heading_kind, content="HeadingNode")
        }
        _ => inspect(quote.children().length(), content="one heading")
      }
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: multi-line paragraph" {
  let block = parse("line one\nline two\n\n")
  inspect(
    block,
    content="Document([Paragraph([Text(\"line one\"), Text(\" \"), Text(\"line two\")])])",
  )
}

///|
test "parse: multi-line paragraph unparse keeps soft break" {
  let block = parse("line one\nline two\n\n")
  inspect(@core.Renderable::unparse(block), content="line one line two")
}

///|
test "parse: code block" {
  let block = parse("```python\nx = 1\n```\n")
  inspect(block, content="Document([CodeBlock(\"python\", \"x = 1\")])")
}

///|
test "parse: list" {
  let block = parse("- one\n- two\n")
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"one\")]), UnorderedListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: nested list stays editor-compatible" {
  let block = parse("- parent\n  - child\n")
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"parent\")])])])",
  )
}

///|
fn assert_nested_list_cst_shape(
  source : String,
  top_level_item_count : Int,
  nested_item_count : Int,
) -> Unit raise {
  let (cst, _) = try! parse_cst(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] => {
      let list_kind : SyntaxKind = @seam.FromRawKind::from_raw(list.kind())
      inspect(list_kind, content="UnorderedListNode")
      inspect(
        list.children().length(),
        content=top_level_item_count.to_string(),
      )
      match list.children() {
        [item, ..] => {
          let item_kind : SyntaxKind = @seam.FromRawKind::from_raw(item.kind())
          inspect(item_kind, content="ListItemNode")
          match item.children() {
            [nested] => {
              let nested_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                nested.kind(),
              )
              inspect(nested_kind, content="UnorderedListNode")
              inspect(
                nested.children().length(),
                content=nested_item_count.to_string(),
              )
            }
            _ => inspect(item.children().length(), content="one nested list")
          }
        }
        _ => inspect(list.children().length(), content="at least one item")
      }
    }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: nested list has nested CST container" {
  try! assert_nested_list_cst_shape("- parent\n  - child\n", 1, 1)
}

///|
test "parse: multi-item nested list stays in one CST container" {
  try! assert_nested_list_cst_shape("- a\n  - b\n  - c\n", 1, 2)
}

///|
test "parse: outdented marker resumes top-level list after nested CST container" {
  try! assert_nested_list_cst_shape("- a\n  - b\n- c\n", 2, 1)
}

///|
test "parse: indented non-one ordered marker starts nested ordered CST container" {
  let (cst, _) = try! parse_cst("- a\n  2. b\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [item] =>
          match item.children() {
            [nested] => {
              let nested_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                nested.kind(),
              )
              inspect(nested_kind, content="OrderedListNode")
            }
            _ => inspect(item.children().length(), content="one nested list")
          }
        _ => inspect(list.children().length(), content="one item")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: loose list separated by blank line" {
  let block = parse("- one\n\n- two\n")
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"one\")]), UnorderedListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: list item lazy continuation stays in item" {
  let block = parse("- a\nb\n")
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"a\"), Text(\"\\n\"), Text(\"b\")])])])",
  )
}

///|
test "parse: non-one ordered marker lazy continuation stays in item" {
  let block = parse("- a\n2. b\n")
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"a\"), Text(\"\\n\"), Text(\"2. \"), Text(\"b\")])])])",
  )
}

///|
test "parse: empty list item does not start lazy continuation paragraph" {
  inspect(
    parse("- \nfoo\n"),
    content="Document([UnorderedList([UnorderedListItem([])]), Paragraph([Text(\"foo\")])])",
  )
  inspect(
    parse("-   \nfoo\n"),
    content="Document([UnorderedList([UnorderedListItem([])]), Paragraph([Text(\"foo\")])])",
  )
  inspect(
    parse("- \n2. foo\n"),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([UnorderedListItem([])]),
      #|    OrderedList(
      #|      [OrderedListItem([Text("foo")], Some({ start: 2, delimiter: Period }))],
      #|      Some({ start: 2, delimiter: Period }),
      #|    ),
      #|  ],
      #|)
    ),
  )
  inspect(
    parse("-   \n2. foo\n"),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([UnorderedListItem([])]),
      #|    OrderedList(
      #|      [OrderedListItem([Text("foo")], Some({ start: 2, delimiter: Period }))],
      #|      Some({ start: 2, delimiter: Period }),
      #|    ),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: list item preserves whitespace-only inline syntax" {
  inspect(
    parse("- ` `\n"),
    content="Document([UnorderedList([UnorderedListItem([InlineCode(\" \")])])])",
  )
  inspect(
    parse("- [](/)\n"),
    content="Document([UnorderedList([UnorderedListItem([Link([], \"/\")])])])",
  )
}

///|
test "parse: blank-line-separated marker change starts a new list" {
  let same = parse("- one\n\n- two\n")
  inspect(
    same,
    content="Document([UnorderedList([UnorderedListItem([Text(\"one\")]), UnorderedListItem([Text(\"two\")])])])",
  )
  let block = parse("- one\n\n+ two\n")
  match block {
    Document(
      [
        UnorderedList([UnorderedListItem([Text("one")])]),
        UnorderedList([UnorderedListItem([Text("two")])]),
      ]
    ) => inspect(true, content="true")
    _ => inspect(block, content="two separate lists")
  }
}

///|
test "parse: ordered list delimiter change starts a new editor-compatible list" {
  let block = parse("1. one\n2. two\n3) three\n")
  match block {
    Document(
      [
        OrderedList(
          [
            OrderedListItem([Text("one")], Some(first_item_marker)),
            OrderedListItem([Text("two")], Some(second_item_marker)),
          ],
          Some(first_list_marker)
        ),
        OrderedList(
          [OrderedListItem([Text("three")], Some(third_item_marker))],
          Some(second_list_marker)
        ),
      ]
    ) => {
      inspect(first_list_marker.text(), content="1.")
      inspect(first_item_marker.text(), content="1.")
      inspect(second_item_marker.text(), content="2.")
      inspect(second_list_marker.text(), content="3)")
      inspect(third_item_marker.text(), content="3)")
    }
    _ => inspect(block, content="ordered delimiter boundary")
  }
}

///|
test "parse: non-one ordered marker does not interrupt paragraph" {
  let block = parse("The number of windows is\n14.  The doors are 6.\n")
  match block {
    Document(
      [
        Paragraph(
          [
            Text("The number of windows is"),
            Text(" "),
            Text("14. "),
            Text(" The doors are 6."),
          ]
        ),
      ]
    ) => inspect(true, content="true")
    _ => inspect(block, content="single paragraph")
  }
}

///|
test "parse: one-start ordered marker interrupts paragraph" {
  let block = parse("The number of windows is\n1.  The doors are 6.\n")
  match block {
    Document(
      [
        Paragraph(_),
        OrderedList(
          [OrderedListItem([Text(" The doors are 6.")], Some(item_marker))],
          Some(list_marker)
        ),
      ]
    ) => {
      inspect(list_marker.text(), content="1.")
      inspect(item_marker.text(), content="1.")
    }
    _ => inspect(block, content="paragraph then ordered list")
  }
}

///|
test "parse: ordered list unparse preserves start and delimiter" {
  let block = parse("3) three\n4) four\n")
  inspect(@core.Renderable::unparse(block), content="3) three\n4) four")
}

///|
test "parse: mixed document" {
  let block = parse("# Title\n\nSome text\n\n- item\n")
  match block {
    Document(blocks) => inspect(blocks.length(), content="3")
    _ => inspect(false, content="true")
  }
}
