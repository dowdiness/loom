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
test "parse: loose list separated by blank line" {
  let block = parse("- one\n\n- two\n")
  inspect(
    block,
    content="Document([UnorderedList([ListItem([Text(\"one\")]), ListItem([Text(\"two\")])])])",
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
test "parse: mixed document" {
  let block = parse("# Title\n\nSome text\n\n- item\n")
  match block {
    Document(blocks) => inspect(blocks.length(), content="3")
    _ => inspect(false, content="true")
  }
}
