///|
fn markdown_test_roles(source : String) -> Array[MarkdownRoleSpan] {
  let parser = @loom.new_syntax_parser(
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  project_markdown_roles(parser.syntax_tree().read_or_abort())
}

///|
test "markdown roles heading marker and UTF-16 text" {
  let roles = markdown_test_roles("## café 😀\n")
  let expected : Array[MarkdownRoleSpan] = [
    MarkdownRoleSpan(role=HeadingMarker, start=0, end=3),
    MarkdownRoleSpan(role=HeadingText, start=3, end=10),
  ]
  guard roles == expected else {
    fail("expected heading marker and UTF-16 text spans")
  }
}

///|
test "markdown roles unordered and ordered list marker and content" {
  let unordered = markdown_test_roles("- item\n")
  let ordered = markdown_test_roles("1. item\n")
  guard unordered ==
    [
      MarkdownRoleSpan(role=ListMarker, start=0, end=2),
      MarkdownRoleSpan(role=ListContent, start=2, end=6),
    ] else {
    fail("expected unordered list marker and content spans")
  }
  guard ordered ==
    [
      MarkdownRoleSpan(role=ListMarker, start=0, end=3),
      MarkdownRoleSpan(role=ListContent, start=3, end=7),
    ] else {
    fail("expected ordered list marker and content spans")
  }
}

///|
test "markdown roles fenced code delimiters and content" {
  let roles = markdown_test_roles("```js\ncode\n```\n")
  let expected : Array[MarkdownRoleSpan] = [
    MarkdownRoleSpan(role=CodeFenceDelimiter, start=0, end=5),
    MarkdownRoleSpan(role=CodeFenceContent, start=6, end=10),
    MarkdownRoleSpan(role=CodeFenceDelimiter, start=11, end=15),
  ]
  guard roles == expected else {
    fail("expected fenced code delimiter and content spans")
  }
}

///|
test "markdown roles inline code delimiter and content" {
  let roles = markdown_test_roles("`code`\n")
  let expected : Array[MarkdownRoleSpan] = [
    MarkdownRoleSpan(role=InlineCodeDelimiter, start=0, end=1),
    MarkdownRoleSpan(role=InlineCodeContent, start=1, end=5),
    MarkdownRoleSpan(role=InlineCodeDelimiter, start=5, end=6),
  ]
  guard roles == expected else {
    fail("expected inline code delimiter and content spans")
  }
}

///|
test "markdown roles bold and italic delimiters and content" {
  let roles = markdown_test_roles("**bold** and *italic*\n")
  let expected : Array[MarkdownRoleSpan] = [
    MarkdownRoleSpan(role=EmphasisDelimiter, start=0, end=2),
    MarkdownRoleSpan(role=EmphasisContent, start=2, end=6),
    MarkdownRoleSpan(role=EmphasisDelimiter, start=6, end=8),
    MarkdownRoleSpan(role=EmphasisDelimiter, start=13, end=14),
    MarkdownRoleSpan(role=EmphasisContent, start=14, end=20),
    MarkdownRoleSpan(role=EmphasisDelimiter, start=20, end=21),
  ]
  guard roles == expected else {
    fail("expected emphasis delimiter and content spans")
  }
}

///|
test "markdown roles link punctuation label and balanced destination" {
  let roles = markdown_test_roles("[text](page_(C).html)\n")
  let expected : Array[MarkdownRoleSpan] = [
    MarkdownRoleSpan(role=Punctuation, start=0, end=1),
    MarkdownRoleSpan(role=LinkText, start=1, end=5),
    MarkdownRoleSpan(role=Punctuation, start=5, end=6),
    MarkdownRoleSpan(role=Punctuation, start=6, end=7),
    MarkdownRoleSpan(role=LinkDestination, start=7, end=12),
    MarkdownRoleSpan(role=LinkDestination, start=12, end=13),
    MarkdownRoleSpan(role=LinkDestination, start=13, end=14),
    MarkdownRoleSpan(role=LinkDestination, start=14, end=15),
    MarkdownRoleSpan(role=LinkDestination, start=15, end=20),
    MarkdownRoleSpan(role=Punctuation, start=20, end=21),
  ]
  guard roles == expected else {
    fail("expected link label, punctuation, and balanced destination spans")
  }
}

///|
test "markdown roles expose source-backed recovery without diagnostics" {
  let parser = @loom.new_syntax_parser(
    "**unclosed\n",
    markdown_grammar.to_syntax_grammar(),
  )
  let roles = project_markdown_roles(parser.syntax_tree().read_or_abort())
  let expected : Array[MarkdownRoleSpan] = [
    MarkdownRoleSpan(role=MarkdownRole::Error, start=0, end=2),
  ]
  guard roles == expected else {
    fail("expected source-backed error span for unclosed emphasis")
  }
}

///|
test "markdown role export names are stable lower-kebab" {
  let roles : Array[MarkdownRole] = [
    HeadingMarker,
    HeadingText,
    ListMarker,
    ListContent,
    CodeFenceDelimiter,
    CodeFenceContent,
    InlineCodeDelimiter,
    InlineCodeContent,
    EmphasisDelimiter,
    EmphasisContent,
    LinkText,
    LinkDestination,
    Punctuation,
    Error,
  ]
  let expected = [
    "heading-marker", "heading-text", "list-marker", "list-content", "code-fence-delimiter",
    "code-fence-content", "inline-code-delimiter", "inline-code-content", "emphasis-delimiter",
    "emphasis-content", "link-text", "link-destination", "punctuation", "error",
  ]
  guard roles.map(fn(role) { role.export_name() }) == expected else {
    fail("expected stable Markdown role export names")
  }
}

///|
test "markdown role exports preserve exact source order" {
  let exported = export_markdown_role_spans(
    markdown_test_roles("[text](page_(C).html)\n"),
  )
  inspect(
    exported.to_json().stringify(),
    content=(
      #|[{"start":0,"end":1,"role":"punctuation"},{"start":1,"end":5,"role":"link-text"},{"start":5,"end":6,"role":"punctuation"},{"start":6,"end":7,"role":"punctuation"},{"start":7,"end":12,"role":"link-destination"},{"start":12,"end":13,"role":"link-destination"},{"start":13,"end":14,"role":"link-destination"},{"start":14,"end":15,"role":"link-destination"},{"start":15,"end":20,"role":"link-destination"},{"start":20,"end":21,"role":"punctuation"}]
    ),
  )
}

///|
test "markdown role spans after edit match fresh parser" {
  let source = "# Hello\n"
  let updated = "## World\n"
  let parser = @loom.new_syntax_parser(
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  parser.apply_edit(@core.Edit::new(0, 8, 9), updated)
  let incremental_roles = project_markdown_roles(
    parser.syntax_tree().read_or_abort(),
  )
  let fresh_parser = @loom.new_syntax_parser(
    updated,
    markdown_grammar.to_syntax_grammar(),
  )
  let fresh_roles = project_markdown_roles(
    fresh_parser.syntax_tree().read_or_abort(),
  )
  guard incremental_roles == fresh_roles else {
    fail("expected edited Markdown role spans to match a fresh parser")
  }
}
