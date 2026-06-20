///|
test "parse: heading" {
  let block = parse("# Hello\n")
  inspect(block, content="Document([Heading(1, [Text(\"Hello\")])])")
}

///|
test "parse: paragraph" {
  let block = parse("Hello world\n")
  inspect(block, content="Document([Paragraph([Text(\"Hello world\")])])")
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
    content="Document([UnorderedList([ListItem([Text(\"one\")]), ListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: nested list stays editor-compatible" {
  let block = parse("- parent\n  - child\n")
  inspect(
    block,
    content="Document([UnorderedList([ListItem([Text(\"parent\")])])])",
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
    content="Document([UnorderedList([ListItem([Text(\"one\")]), ListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: list item lazy continuation stays in item" {
  let block = parse("- a\nb\n")
  inspect(
    block,
    content="Document([UnorderedList([ListItem([Text(\"a\"), Text(\"\\n\"), Text(\"b\")])])])",
  )
}

///|
test "parse: non-one ordered marker lazy continuation stays in item" {
  let block = parse("- a\n2. b\n")
  inspect(
    block,
    content="Document([UnorderedList([ListItem([Text(\"a\"), Text(\"\\n\"), Text(\"2. \"), Text(\"b\")])])])",
  )
}

///|
test "parse: empty list item does not start lazy continuation paragraph" {
  inspect(
    parse("- \nfoo\n"),
    content="Document([UnorderedList([ListItem([])]), Paragraph([Text(\"foo\")])])",
  )
  inspect(
    parse("-   \nfoo\n"),
    content="Document([UnorderedList([ListItem([])]), Paragraph([Text(\"foo\")])])",
  )
  inspect(
    parse("- \n2. foo\n"),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([ListItem([])]),
      #|    UnorderedList([ListItem([Text("foo")])]),
      #|  ],
      #|)
    ),
  )
  inspect(
    parse("-   \n2. foo\n"),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([ListItem([])]),
      #|    UnorderedList([ListItem([Text("foo")])]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: list item preserves whitespace-only inline syntax" {
  inspect(
    parse("- ` `\n"),
    content="Document([UnorderedList([ListItem([InlineCode(\" \")])])])",
  )
  inspect(
    parse("- [](/)\n"),
    content="Document([UnorderedList([ListItem([Link([], \"/\")])])])",
  )
}

///|
test "parse: blank-line-separated marker change starts a new list" {
  let block = parse("- one\n\n+ two\n")
  match block {
    Document(
      [
        UnorderedList([ListItem([Text("one")])]),
        UnorderedList([ListItem([Text("two")])]),
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
        UnorderedList([ListItem([Text("one")]), ListItem([Text("two")])]),
        UnorderedList([ListItem([Text("three")])]),
      ]
    ) => inspect(true, content="true")
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
      [Paragraph(_), UnorderedList([ListItem([Text(" The doors are 6.")])])]
    ) => inspect(true, content="true")
    _ => inspect(block, content="paragraph then ordered list")
  }
}

///|
test "parse: mixed document" {
  let block = parse("# Title\n\nSome text\n\n- item\n")
  match block {
    Document(blocks) => inspect(blocks.length(), content="3")
    _ => inspect(false, content="true")
  }
}
