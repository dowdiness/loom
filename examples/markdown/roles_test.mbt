///|
fn markdown_test_roles(source : String) -> Array[MarkdownRoleSpan] {
  let parser = @loom.new_syntax_parser(
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  project_markdown_roles(parser.syntax_tree().read_or_abort())
}

///|
fn markdown_test_observations(
  spans : Array[MarkdownRoleSpan],
) -> Array[(MarkdownRole, Int, Int)] {
  spans.map(fn(span) { (span.role(), span.start(), span.end()) })
}

///|
fn markdown_test_find_link_node(node : @seam.SyntaxNode) -> @seam.SyntaxNode? {
  if SyntaxKind::from_raw(node.kind()) == LinkNode {
    return Some(node)
  }
  for element in node.direct_elements_iter() {
    match element {
      Node(child) =>
        match markdown_test_find_link_node(child) {
          Some(link_node) => return Some(link_node)
          None => ()
        }
      Token(_) => ()
    }
  }
  None
}

///|
test "markdown roles heading marker and UTF-16 text" {
  let roles = markdown_test_roles("## café 😀\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (HeadingMarker, 0, 3),
    (HeadingText, 3, 10),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected heading marker and UTF-16 text spans")
  }
}

///|
test "markdown roles preserve the shared role for setext underlines" {
  let roles = markdown_test_roles("Title\n---\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (HeadingText, 0, 5),
    (HeadingMarker, 6, 9),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected setext underline to retain the heading marker role")
  }
}

///|
test "markdown roles unordered and ordered list marker and content" {
  let unordered = markdown_test_roles("- item\n")
  let ordered = markdown_test_roles("1. item\n")
  guard markdown_test_observations(unordered) ==
    [(ListMarker, 0, 2), (ListContent, 2, 6)] else {
    fail("expected unordered list marker and content spans")
  }
  guard markdown_test_observations(ordered) ==
    [(ListMarker, 0, 3), (ListContent, 3, 7)] else {
    fail("expected ordered list marker and content spans")
  }
}

///|
test "markdown roles fenced code delimiters and content" {
  let roles = markdown_test_roles("```js\ncode\n```\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (CodeFenceDelimiter, 0, 5),
    (CodeFenceContent, 6, 10),
    (CodeFenceDelimiter, 11, 15),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected fenced code delimiter and content spans")
  }
}

///|
test "markdown roles inline code delimiter and content" {
  let roles = markdown_test_roles("`code`\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (InlineCodeDelimiter, 0, 1),
    (InlineCodeContent, 1, 5),
    (InlineCodeDelimiter, 5, 6),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected inline code delimiter and content spans")
  }
}

///|
test "markdown roles bold and italic delimiters and content" {
  let roles = markdown_test_roles("**bold** and *italic*\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (EmphasisDelimiter, 0, 2),
    (EmphasisContent, 2, 6),
    (EmphasisDelimiter, 6, 8),
    (EmphasisDelimiter, 13, 14),
    (EmphasisContent, 14, 20),
    (EmphasisDelimiter, 20, 21),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected emphasis delimiter and content spans")
  }
}

///|
test "markdown roles link punctuation label and balanced destination" {
  let roles = markdown_test_roles("[text](page_(C).html)\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (Punctuation, 0, 1),
    (LinkText, 1, 5),
    (Punctuation, 5, 6),
    (Punctuation, 6, 7),
    (LinkDestination, 7, 12),
    (LinkDestination, 12, 13),
    (LinkDestination, 13, 14),
    (LinkDestination, 14, 15),
    (LinkDestination, 15, 20),
    (Punctuation, 20, 21),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected link label, punctuation, and balanced destination spans")
  }
}

///|
test "markdown roles project a LinkNode directly like its document root" {
  let parser = @loom.new_syntax_parser(
    "[text](page_(C).html)\n",
    markdown_grammar.to_syntax_grammar(),
  )
  let root = parser.syntax_tree().read_or_abort()
  let root_roles = project_markdown_roles(root)
  guard markdown_test_find_link_node(root) is Some(link_node) else {
    fail("expected parsed link subtree")
  }
  let direct_roles = project_markdown_roles(link_node)
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (Punctuation, 0, 1),
    (LinkText, 1, 5),
    (Punctuation, 5, 6),
    (Punctuation, 6, 7),
    (LinkDestination, 7, 12),
    (LinkDestination, 12, 13),
    (LinkDestination, 13, 14),
    (LinkDestination, 14, 15),
    (LinkDestination, 15, 20),
    (Punctuation, 20, 21),
  ]
  guard direct_roles == root_roles &&
    markdown_test_observations(direct_roles) == expected else {
    fail("expected direct LinkNode projection to match the complete root spans")
  }
}

///|
test "markdown roles expose source-backed recovery without diagnostics" {
  let parser = @loom.new_syntax_parser(
    "**unclosed\n",
    markdown_grammar.to_syntax_grammar(),
  )
  let roles = project_markdown_roles(parser.syntax_tree().read_or_abort())
  let expected : Array[(MarkdownRole, Int, Int)] = [(MarkdownRole::Error, 0, 2)]
  guard markdown_test_observations(roles) == expected else {
    fail("expected source-backed error span for unclosed emphasis")
  }
}

///|
test "markdown roles omit block quote wrapper but project supported descendants" {
  let roles = markdown_test_roles("> # heading\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (HeadingMarker, 2, 4),
    (HeadingText, 4, 11),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected block quote marker omission with nested heading roles")
  }
}

///|
test "markdown roles omit unsupported thematic break and HTML wrappers" {
  let thematic_break = markdown_test_roles("---\n")
  let html = markdown_test_roles("<div>\ntext\n</div>\n")
  guard thematic_break.is_empty() && html.is_empty() else {
    fail("expected unsupported wrapper constructs to produce no roles")
  }
}

///|
test "markdown role exports use stable lower-kebab names" {
  let sources = [
    "## text\n", "- item\n", "```js\ncode\n```\n", "`code`\n", "**bold**\n", "[text](page)\n",
    "**unclosed\n",
  ]
  let actual = sources.map(fn(source) {
    export_markdown_role_spans(markdown_test_roles(source)).stringify()
  })
  let expected = [
    "[{\"start\":0,\"end\":3,\"role\":\"heading-marker\"},{\"start\":3,\"end\":7,\"role\":\"heading-text\"}]",
    "[{\"start\":0,\"end\":2,\"role\":\"list-marker\"},{\"start\":2,\"end\":6,\"role\":\"list-content\"}]",
    "[{\"start\":0,\"end\":5,\"role\":\"code-fence-delimiter\"},{\"start\":6,\"end\":10,\"role\":\"code-fence-content\"},{\"start\":11,\"end\":15,\"role\":\"code-fence-delimiter\"}]",
    "[{\"start\":0,\"end\":1,\"role\":\"inline-code-delimiter\"},{\"start\":1,\"end\":5,\"role\":\"inline-code-content\"},{\"start\":5,\"end\":6,\"role\":\"inline-code-delimiter\"}]",
    "[{\"start\":0,\"end\":2,\"role\":\"emphasis-delimiter\"},{\"start\":2,\"end\":6,\"role\":\"emphasis-content\"},{\"start\":6,\"end\":8,\"role\":\"emphasis-delimiter\"}]",
    "[{\"start\":0,\"end\":1,\"role\":\"punctuation\"},{\"start\":1,\"end\":5,\"role\":\"link-text\"},{\"start\":5,\"end\":6,\"role\":\"punctuation\"},{\"start\":6,\"end\":7,\"role\":\"punctuation\"},{\"start\":7,\"end\":11,\"role\":\"link-destination\"},{\"start\":11,\"end\":12,\"role\":\"punctuation\"}]",
    "[{\"start\":0,\"end\":2,\"role\":\"error\"}]",
  ]
  guard actual == expected else {
    fail("expected stable lower-kebab names from projected JSON fixtures")
  }
}

///|
test "markdown role exports preserve exact source order" {
  let exported = export_markdown_role_spans(
    markdown_test_roles("[text](page_(C).html)\n"),
  )
  inspect(
    exported.stringify(),
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

///|
test "markdown roles use node-local precedence in heading text" {
  let roles = markdown_test_roles("## café **bold** 😀\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (HeadingMarker, 0, 3),
    (HeadingText, 3, 8),
    (EmphasisDelimiter, 8, 10),
    (EmphasisContent, 10, 14),
    (EmphasisDelimiter, 14, 16),
    (HeadingText, 16, 19),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected nested emphasis roles to override heading text locally")
  }
}

///|
test "markdown roles use node-local precedence in list content" {
  let roles = markdown_test_roles("- café **bold** 😀\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (ListMarker, 0, 2),
    (ListContent, 2, 7),
    (EmphasisDelimiter, 7, 9),
    (EmphasisContent, 9, 13),
    (EmphasisDelimiter, 13, 15),
    (ListContent, 15, 18),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected nested emphasis roles to override list content locally")
  }
}

///|
test "markdown roles use node-local precedence in link label text" {
  let roles = markdown_test_roles("[café **bold** 😀](dest)\n")
  let expected : Array[(MarkdownRole, Int, Int)] = [
    (Punctuation, 0, 1),
    (LinkText, 1, 6),
    (EmphasisDelimiter, 6, 8),
    (EmphasisContent, 8, 12),
    (EmphasisDelimiter, 12, 14),
    (LinkText, 14, 17),
    (Punctuation, 17, 18),
    (Punctuation, 18, 19),
    (LinkDestination, 19, 23),
    (Punctuation, 23, 24),
  ]
  guard markdown_test_observations(roles) == expected else {
    fail("expected nested emphasis roles to override link text locally")
  }
}
