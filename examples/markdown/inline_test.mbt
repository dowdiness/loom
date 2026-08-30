///|
test "inline: bold" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "**bold**\n",
  )
  inspect(block, content="Document([Paragraph([Bold([Text(\"bold\")])])])")
}

///|
test "inline: italic" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "*italic*\n",
  )
  inspect(block, content="Document([Paragraph([Italic([Text(\"italic\")])])])")
}

///|
test "inline: emphasis honors preceding backslash parity" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\" + "\\" + "*em*\n",
    ),
    content="Document([Paragraph([Text(\"\\\\\"), Italic([Text(\"em\")])])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\" + "\\" + "\\" + "\\" + "*em*\n",
    ),
    content="Document([Paragraph([Text(\"\\\\\\\\\"), Italic([Text(\"em\")])])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\" + "\\" + "\\" + "*em*\n",
    ),
    content="Document([Paragraph([Text(\"\\\\*em*\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\* literal *unclosed\n",
    ),
    content="Document([Paragraph([Text(\"* literal *unclosed\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\* literal!*unclosed\n",
    ),
    content="Document([Paragraph([Text(\"* literal!*unclosed\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "[x](\\*u) tail*\n",
    ),
    content="Document([Paragraph([Link([Text(\"x\")], \"\\\\*u\"), Text(\" tail*\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*a **b** c*\n",
    ),
    content="Document([Paragraph([Text(\"*a \"), Bold([Text(\"b\")]), Text(\" c*\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "[\\*literal*](/)\n",
    ),
    content="Document([Paragraph([Link([Text(\"*literal*\")], \"/\")])])",
  )
}

///|
test "inline: escaped emphasis stays literal beside non-BMP text" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*😈*\n",
    ),
    content="Document([Paragraph([Text(\"*😈*\")])])",
  )
}

///|
test "inline: escaped and unmatched emphasis stays literal" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*a b**\n",
    ),
    content="Document([Paragraph([Text(\"*a b**\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*\\*literal**\n",
    ),
    content="Document([Paragraph([Text(\"**literal**\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*a \\*b***\n",
    ),
    content="Document([Paragraph([Text(\"*a *b***\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*a \\*b\nc**\n",
    ),
    content="Document([Paragraph([Text(\"*a *b\"), Text(\" \"), Text(\"c**\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*a [oops tail*\n",
    ),
    content="Document([Paragraph([Text(\"*a \"), Text(\"[\"), Text(\"oops tail*\")])])",
  )
}

///|
test "inline: literal emphasis markers stay container-local" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\*a [x**](/) b*\n",
    ),
    content="Document([Paragraph([Text(\"*a \"), Link([Text(\"x**\")], \"/\"), Text(\" b*\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "[\\*\\*😈**](/)\n",
    ),
    content="Document([Paragraph([Link([Text(\"**😈**\")], \"/\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "- \\*a \\*b**\n",
    ),
    content="Document([UnorderedList([UnorderedListItem([Text(\"*a *b**\")])])])",
  )
}

///|
test "inline: italic can contain bold" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "*foo **bar** baz*\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Italic([Text(\"foo \"), Bold([Text(\"bar\")]), Text(\" baz\")])])])",
  )
}

///|
test "inline: ordered marker can remain paragraph text inside multiline emphasis" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "*foo\n2. bar*\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Italic([Text(\"foo\"), Text(\"2. \"), Text(\"bar\")])])])",
  )
}

///|
test "inline: unmatched emphasis stays literal at ordered list boundaries" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "1. *foo\n2. bar*\n",
  )
  inspect(
    block,
    content=(
      #|Document(
      #|  [
      #|    OrderedList(
      #|      [
      #|        OrderedListItem([Text("*foo")], Some({ start: 1, delimiter: Period })),
      #|        OrderedListItem([Text("bar*")], Some({ start: 2, delimiter: Period })),
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
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "`code`\n",
  )
  inspect(block, content="Document([Paragraph([InlineCode(\"code\")])])")
}

///|
test "inline: link" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "[click](http://example.com)\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"click\")], \"http://example.com\")])])",
  )
}

///|
test "inline: link destination preserves balanced parentheses" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "[wiki](page_(C).html)\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"wiki\")], \"page_(C).html\")])])",
  )
}

///|
test "inline: link destination preserves delimiter characters" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "[api](docs/*items*`v1`)\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Link([Text(\"api\")], \"docs/*items*`v1`\")])])",
  )
}

///|
test "inline: bold inside paragraph" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "Hello **world** end\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Text(\"Hello \"), Bold([Text(\"world\")]), Text(\" end\")])])",
  )
}

///|
test "inline: bold in heading" {
  let block = parse_block_ast(
    @core.SourceId("markdown-inline-test-document"),
    "# **Bold** title\n",
  )
  inspect(
    block,
    content="Document([Heading(1, [Bold([Text(\"Bold\")]), Text(\" title\")])])",
  )
}

///|
test "inline: equal-length code span preserves unequal interior delimiter run" {
  inspect(
    parse_block_ast(@core.SourceId("markdown-inline-test-document"), "`a``b`\n"),
    content="Document([Paragraph([InlineCode(\"a``b\")])])",
  )
}

///|
test "inline: unmatched code-span run preserves following inline syntax" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "``unclosed *em* [link](/)\n",
    ),
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
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\`literal `code`\n",
    ),
    content="Document([Paragraph([Text(\"`literal \"), InlineCode(\"code\")])])",
  )
}

///|
test "inline: escaped literal backtick joins text in link display" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "[\\`literal](/)\n",
    ),
    content="Document([Paragraph([Link([Text(\"`literal\")], \"/\")])])",
  )
}

///|
test "inline: even backslash parity permits a code span" {
  match
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "\\\\``code``\n",
    ) {
    Document([Paragraph([Text(prefix), InlineCode(value)])]) => {
      inspect(prefix, content="\\")
      inspect(value, content="code")
    }
    _ => inspect(false, content="even backslash parity permits a code span")
  }
}

///|
test "inline: backslash before code-span closer remains raw content" {
  match
    parse_block_ast(@core.SourceId("markdown-inline-test-document"), "`a\\`\n") {
    Document([Paragraph([InlineCode(value)])]) => inspect(value, content="a\\")
    _ => inspect(false, content="backslash before closer remains code content")
  }
}

///|
test "inline: emphasis delegates maximal code spans to the container index" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "*`a``b`*\n",
    ),
    content="Document([Paragraph([Italic([InlineCode(\"a``b\")])])])",
  )
}

///|
test "inline: link text delegates maximal code spans to the container index" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-inline-test-document"),
      "[`a``b`](/)\n",
    ),
    content="Document([Paragraph([Link([InlineCode(\"a``b\")], \"/\")])])",
  )
}
