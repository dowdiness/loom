///|
fn reference_candidate_semantics_ir(
  source : String,
  extensions? : @markdown.MarkdownExtensions = @markdown.MarkdownExtensions::none(),
) -> @markdown.MarkdownIR raise {
  let source_id = @core.SourceId("markdown-reference-candidate-semantics")
  let parser = try! @loom.new_syntax_parser(
    source_id,
    source,
    @markdown.markdown_grammar.to_syntax_grammar(),
  )
  let snapshot = parser.snapshot().read_or_abort()
  assert_eq(snapshot.source_id, source_id)
  let from_snapshot = @markdown.experimental_markdown_ir_from_syntax_snapshot(
    snapshot,
    extensions~,
  )
  let from_syntax = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    snapshot.syntax,
    snapshot.diagnostics,
    extensions~,
  )
  assert_eq(from_snapshot, from_syntax)
  from_snapshot
}

///|
fn reference_candidate_semantics_assert_no_recovered(
  node : @markdown.MarkdownIR,
) -> Unit raise {
  assert_false(node.is_recovered())
  for child in node.children() {
    reference_candidate_semantics_assert_no_recovered(child)
  }
}

///|
test "reference candidates become ordinary literal Markdown when unresolved" {
  let cases = [
    ("[unclosed\n", "<p>[unclosed</p>\n"),
    ("[text](\n", "<p>[text](</p>\n"),
    ("- [y] ordinary\n", "<ul>\n<li>[y] ordinary</li>\n</ul>\n"),
    ("𐐀[unclosed\n", "<p>𐐀[unclosed</p>\n"),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = reference_candidate_semantics_ir(
      source,
      extensions=@markdown.MarkdownExtensions::task_list(),
    )
    reference_candidate_semantics_assert_no_recovered(ir)
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(ir),
      expected_html,
    )
  }
}

///|
test "reference candidates still resolve every supported reference form" {
  let cases = [
    (
      "[label]\n\n[label]: /shortcut\n", "<p><a href=\"/shortcut\">label</a></p>\n",
    ),
    ("[text][label]\n\n[label]: /full\n", "<p><a href=\"/full\">text</a></p>\n"),
    (
      "[label][]\n\n[label]: /collapsed\n", "<p><a href=\"/collapsed\">label</a></p>\n",
    ),
    (
      "![label]\n\n[label]: /image.png\n", "<p><img src=\"/image.png\" alt=\"label\" /></p>\n",
    ),
    (
      "*[label*]\n\n[label*]: /emphasis\n", "<p>*<a href=\"/emphasis\">label*</a></p>\n",
    ),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = reference_candidate_semantics_ir(source)
    reference_candidate_semantics_assert_no_recovered(ir)
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(ir),
      expected_html,
    )
  }
}

///|
test "code-owned and escaped brackets never become reference candidates" {
  let cases = [
    ("\\[label]\n\n[label]: /url\n", "<p>[label]</p>\n"),
    ("[foo`](/uri)`\n\n[foo]: /url\n", "<p>[foo<code>](/uri)</code></p>\n"),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = reference_candidate_semantics_ir(source)
    reference_candidate_semantics_assert_no_recovered(ir)
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(ir),
      expected_html,
    )
  }
}

///|
test "container whitespace has identical source origins in fresh and keyed IR" {
  let sources = [
    "> - [label]\n>   next\n\n[label]: /url\n", "> - plain\n>   next\n", "> - ![label]  \n>   next\n\n[label]: /url\n",
    "> > - [label]\n> >   next\n\n[label]: /url\n", "- first\n\n    [label]\n\n[label]: /url\n",
  ]
  for source in sources {
    let parser = @loom.new_parser(
      @core.SourceId("markdown"),
      source,
      @markdown.markdown_grammar,
    )
    let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    let direct = @markdown.parse(source).semantic_read().ir()
    assert_eq(attachment.document(), direct)
    let shifted = "prefix\n\n" + source
    parser.apply_edit(@core.Edit::new(0, 0, 8), shifted)
    assert_eq(
      attachment.document(),
      @markdown.parse(shifted).semantic_read().ir(),
    )
    attachment.dispose()
  }
}

///|
test "list inline sequences complete references and images" {
  let cases = [
    (
      "- [label]\n\n[label]: /first\n[label]: /second\n", "<ul>\n<li><a href=\"/first\">label</a></li>\n</ul>\n",
    ),
    (
      "> - [label]\n\n[label]: /url\n", "<blockquote>\n<ul>\n<li><a href=\"/url\">label</a></li>\n</ul>\n</blockquote>\n",
    ),
    (
      "1. [label][]\n\n[label]: /url\n", "<ol>\n<li><a href=\"/url\">label</a></li>\n</ol>\n",
    ),
    (
      "- ![label]\n\n[label]: /url\n", "<ul>\n<li><img src=\"/url\" alt=\"label\" /></li>\n</ul>\n",
    ),
    (
      "- *[label*]\n\n[label*]: /url\n", "<ul>\n<li>*<a href=\"/url\">label*</a></li>\n</ul>\n",
    ),
    ("- \\[label]\n\n[label]: /url\n", "<ul>\n<li>[label]</li>\n</ul>\n"),
    (
      "- [foo *bar [baz][ref]*][ref]\n\n[ref]: /uri\n", "<ul>\n<li>[foo <em>bar <a href=\"/uri\">baz</a></em>]<a href=\"/uri\">ref</a></li>\n</ul>\n",
    ),
    (
      "- ![foo [bar](/url)](/url2)\n", "<ul>\n<li><img src=\"/url2\" alt=\"foo bar\" /></li>\n</ul>\n",
    ),
  ]
  for (source, expected_html) in cases {
    let direct = @markdown.parse(source).semantic_read().ir()
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(direct),
      expected_html,
    )
    let parser = @loom.new_parser(
      @core.SourceId("markdown"),
      source,
      @markdown.markdown_grammar,
    )
    let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    assert_eq(attachment.document(), direct)
    attachment.dispose()
  }
}

///|
test "definition-only list content keeps its source anchor in keyed lowering" {
  let source = "- [Foo\n    bar]: /url\n\n[Baz][Foo bar]\n"
  let direct = @markdown.parse(source).semantic_read().ir()
  let paragraph = direct.children()[0].children()[0].children()[0]
  assert_eq(paragraph.origin().start(), 2)
  assert_eq(paragraph.origin().end(), 2)
  assert_true(paragraph.content_origin() is None)
  assert_true(paragraph.children().is_empty())
  let parser = @loom.new_parser(
    @core.SourceId("markdown"),
    source,
    @markdown.markdown_grammar,
  )
  let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  assert_eq(attachment.document(), direct)
  let shifted = "prefix\n\n" + source
  parser.apply_edit(@core.Edit::new(0, 0, 8), shifted)
  assert_eq(
    attachment.document(),
    @markdown.parse(shifted).semantic_read().ir(),
  )
  attachment.dispose()
}

///|
test "container references survive definition removal and restoration without changing their blocks" {
  let blocks = [
    "- [label]\n\n", "> - [label]\n>   next\n\n", "> - ![label]  \n>   next\n\n",
    "> > - [label]\n> >   next\n\n", "- first\n\n    [label]\n\n",
  ]
  for block in blocks {
    let definition = "[label]: /url\n"
    let initial = block + definition
    let changed = block + "[label]: /new\n"
    let parser = @loom.new_parser(
      @core.SourceId("markdown"),
      initial,
      @markdown.markdown_grammar,
    )
    let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    let original = attachment.document()
    assert_eq(original, @markdown.parse(initial).semantic_read().ir())
    let original_html = @markdown.experimental_markdown_ir_to_commonmark_html(
      original,
    )
    assert_true(original_html.contains("/url"))
    parser.apply_edit(@core.Edit::new(block.length() + 9, 4, 4), changed)
    let updated = attachment.document()
    assert_eq(updated, @markdown.parse(changed).semantic_read().ir())
    let updated_html = @markdown.experimental_markdown_ir_to_commonmark_html(
      updated,
    )
    assert_true(updated_html.contains("/new"))
    assert_false(updated_html.contains("/url"))
    parser.apply_edit(
      @core.Edit::new(block.length(), definition.length(), 0),
      block,
    )
    let missing = attachment.document()
    assert_eq(missing, @markdown.parse(block).semantic_read().ir())
    let missing_html = @markdown.experimental_markdown_ir_to_commonmark_html(
      missing,
    )
    assert_true(missing_html.contains("[label]"))
    assert_false(missing_html.contains("/url"))
    parser.apply_edit(
      @core.Edit::new(block.length(), 0, definition.length()),
      initial,
    )
    assert_eq(attachment.document(), original)
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(original),
      original_html,
    )
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(updated),
      updated_html,
    )
    attachment.dispose()
  }
}

///|
test "paragraph and heading whitespace precedes deferred reference completion" {
  let cases = [
    (
      ">   [label]\n>   next\n\n[label]: /url\n", "<blockquote>\n<p><a href=\"/url\">label</a>\nnext</p>\n</blockquote>\n",
    ),
    (
      "- first\n\n    [label]\n\n[label]: /url\n", "<ul>\n<li>\n<p>first</p>\n<p><a href=\"/url\">label</a></p>\n</li>\n</ul>\n",
    ),
    (
      "#   [label]   #\n\n[label]: /url\n", "<h1><a href=\"/url\">label</a></h1>\n",
    ),
    (
      "  [label]  \n====\n\n[label]: /url\n", "<h1><a href=\"/url\">label</a></h1>\n",
    ),
  ]
  for (source, expected_html) in cases {
    let parser = @loom.new_parser(
      @core.SourceId("markdown"),
      source,
      @markdown.markdown_grammar,
    )
    let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    let direct = @markdown.parse(source).semantic_read().ir()
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(direct),
      expected_html,
    )
    assert_eq(attachment.document(), direct)
    attachment.dispose()
  }
}
