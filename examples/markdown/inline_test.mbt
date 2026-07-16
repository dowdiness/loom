///|
test "inline: bold" {
  let block = parse("**bold**\n")
  inspect(block, content="Document([Paragraph([Bold([Text(\"bold\")])])])")
}

///|
test "inline: italic" {
  let block = parse("*italic*\n")
  inspect(block, content="Document([Paragraph([Italic([Text(\"italic\")])])])")
}

///|
test "inline: italic can contain bold" {
  let block = parse("*foo **bar** baz*\n")
  inspect(
    block,
    content="Document([Paragraph([Italic([Text(\"foo \"), Bold([Text(\"bar\")]), Text(\" baz\")])])])",
  )
}

///|
test "inline: ordered marker can remain paragraph text inside multiline emphasis" {
  let block = parse("*foo\n2. bar*\n")
  inspect(
    block,
    content="Document([Paragraph([Italic([Text(\"foo\"), Text(\"2. \"), Text(\"bar\")])])])",
  )
}

///|
test "inline: multiline emphasis stops at ordered list item boundary" {
  let block = parse("1. *foo\n2. bar*\n")
  inspect(
    block,
    content=(
      #|Document(
      #|  [
      #|    OrderedList(
      #|      [
      #|        OrderedListItem(
      #|          [Error("*"), Text("foo")],
      #|          Some({ start: 1, delimiter: Period }),
      #|        ),
      #|        OrderedListItem(
      #|          [Text("bar"), Error("*")],
      #|          Some({ start: 2, delimiter: Period }),
      #|        ),
      #|      ],
      #|      Some({ start: 1, delimiter: Period }),
      #|    ),
      #|  ],
      #|)
    ),
  )
}

///|
test "inline: inline code" {
  let block = parse("`code`\n")
  inspect(block, content="Document([Paragraph([InlineCode(\"code\")])])")
}

///|
test "inline: link" {
  let block = parse("[click](http://example.com)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"click\")], \"http://example.com\")])])",
  )
}

///|
test "inline: link destination preserves balanced parentheses" {
  let block = parse("[wiki](page_(C).html)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"wiki\")], \"page_(C).html\")])])",
  )
}

///|
test "inline: link destination preserves delimiter characters" {
  let block = parse("[api](docs/*items*`v1`)\n")
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"api\")], \"docs/*items*`v1`\")])])",
  )
}

///|
test "inline: bold inside paragraph" {
  let block = parse("Hello **world** end\n")
  inspect(
    block,
    content="Document([Paragraph([Text(\"Hello \"), Bold([Text(\"world\")]), Text(\" end\")])])",
  )
}

///|
test "inline: bold in heading" {
  let block = parse("# **Bold** title\n")
  inspect(
    block,
    content="Document([Heading(1, [Bold([Text(\"Bold\")]), Text(\" title\")])])",
  )
}

///|
test "inline: equal-length code span preserves unequal interior delimiter run" {
  inspect(
    parse("`a``b`\n"),
    content="Document([Paragraph([InlineCode(\"a``b\")])])",
  )
}

///|
test "inline: unmatched code-span run preserves following inline syntax" {
  inspect(
    parse("``unclosed *em* [link](/)\n"),
    content=(
      #|Document(
      #|  [
      #|    Paragraph(
      #|      [
      #|        Text("``"),
      #|        Text("unclosed "),
      #|        Italic([Text("em")]),
      #|        Text(" "),
      #|        Link([Text("link")], "/"),
      #|      ],
      #|    ),
      #|  ],
      #|)

    ),
  )
}

///|
test "inline: escaped outer run stays literal before a later code span" {
  inspect(
    parse("\\`literal `code`\n"),
    content="Document([Paragraph([Text(\"`literal \"), InlineCode(\"code\")])])",
  )
}
///|
test "inline: escaped literal backtick joins text in link display" {
  inspect(
    parse("[\\`literal](/)\n"),
    content="Document([Paragraph([Link([Text(\"`literal\")], \"/\")])])",
  )
}

///|
test "inline: even backslash parity permits a code span" {
  match parse("\\\\``code``\n") {
    Document([Paragraph([Text(prefix), InlineCode(value)])]) => {
      inspect(prefix, content="\\")
      inspect(value, content="code")
    }
    _ => inspect(false, content="even backslash parity permits a code span")
  }
}

///|
test "inline: backslash before code-span closer remains raw content" {
  match parse("`a\\`\n") {
    Document([Paragraph([InlineCode(value)])]) =>
      inspect(value, content="a\\")
    _ => inspect(false, content="backslash before closer remains code content")
  }
}

///|
test "inline: emphasis delegates maximal code spans to the container index" {
  inspect(
    parse("*`a``b`*\n"),
    content="Document([Paragraph([Italic([InlineCode(\"a``b\")])])])",
  )
}

///|
test "inline: link text delegates maximal code spans to the container index" {
  inspect(
    parse("[`a``b`](/)\n"),
    content="Document([Paragraph([Link([InlineCode(\"a``b\")], \"/\")])])",
  )
}
