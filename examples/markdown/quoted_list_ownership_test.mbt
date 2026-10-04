///|
/// CommonMark 0.31.2 expected HTML for issue #966. The CST checks below
/// independently verify ownership before semantic lowering.

///|
fn quoted_ownership_cases() -> Array[(String, String, String)] {
  [
    (
      "15-second-paragraph", "> - plain\n>\n>   next\n", "<blockquote>\n<ul>\n<li>\n<p>plain</p>\n<p>next</p>\n</li>\n</ul>\n</blockquote>\n",
    ),
    (
      "20-nested-list", "> - plain\n>   - nested\n", "<blockquote>\n<ul>\n<li>plain\n<ul>\n<li>nested</li>\n</ul>\n</li>\n</ul>\n</blockquote>\n",
    ),
    (
      "21-heading", "> - plain\n>   # heading\n", "<blockquote>\n<ul>\n<li>plain\n<h1>heading</h1>\n</li>\n</ul>\n</blockquote>\n",
    ),
    (
      "23-fenced-code", "> - plain\n>   ```\n>   code\n>   ```\n", "<blockquote>\n<ul>\n<li>plain\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n</blockquote>\n",
    ),
    (
      "26-quote-exits-list-with-list", "- > - plain\n>   next\n", "<ul>\n<li>\n<blockquote>\n<ul>\n<li>plain</li>\n</ul>\n</blockquote>\n</li>\n</ul>\n<blockquote>\n<p>next</p>\n</blockquote>\n",
    ),
    (
      "27-quote-exits-list-with-paragraph", "- > plain\n>   next\n", "<ul>\n<li>\n<blockquote>\n<p>plain</p>\n</blockquote>\n</li>\n</ul>\n<blockquote>\n<p>next</p>\n</blockquote>\n",
    ),
    (
      "28-second-paragraph", "> - plain\n>   next\n>\n>   more\n", "<blockquote>\n<ul>\n<li>\n<p>plain\nnext</p>\n<p>more</p>\n</li>\n</ul>\n</blockquote>\n",
    ),
    (
      "29-nested-ordered-list", "> - a\n>   1. b\n>      c\n", "<blockquote>\n<ul>\n<li>a\n<ol>\n<li>b\nc</li>\n</ol>\n</li>\n</ul>\n</blockquote>\n",
    ),
  ]
}

///|
fn quoted_ownership_syntax_kind(
  node : @seam.SyntaxNode,
) -> @markdown.SyntaxKind {
  @seam.FromRawKind::from_raw(node.kind())
}

///|
fn quoted_ownership_syntax_has_descendant(
  node : @seam.SyntaxNode,
  wanted : @markdown.SyntaxKind,
) -> Bool {
  for child in node.children() {
    if quoted_ownership_syntax_kind(child) == wanted {
      return true
    }
    if quoted_ownership_syntax_has_descendant(child, wanted) {
      return true
    }
  }
  false
}

///|
fn quoted_ownership_syntax_has_descendant_text(
  node : @seam.SyntaxNode,
  wanted : @markdown.SyntaxKind,
  fragment : String,
) -> Bool {
  for child in node.children() {
    if quoted_ownership_syntax_kind(child) == wanted &&
      child.text().contains(fragment) {
      return true
    }
    if quoted_ownership_syntax_has_descendant_text(child, wanted, fragment) {
      return true
    }
  }
  false
}

///|
fn quoted_ownership_find_list_item(
  node : @seam.SyntaxNode,
  text : String,
) -> @seam.SyntaxNode? {
  if quoted_ownership_syntax_kind(node) == ListItemNode &&
    node.text().contains(text) {
    return Some(node)
  }
  for child in node.children() {
    match quoted_ownership_find_list_item(child, text) {
      Some(item) => return Some(item)
      None => ()
    }
  }
  None
}

///|
fn quoted_ownership_assert_no_recovery(
  node : @markdown.MarkdownIR,
) -> Unit raise {
  let kind = node.kind_tag()
  assert_false(kind == "Recovered")
  assert_false(kind == "Error")
  assert_false(kind == "Unsupported")
  assert_false(kind == "Raw")
  for child in node.children() {
    quoted_ownership_assert_no_recovery(child)
  }
}

///|
fn quoted_ownership_assert_ir_origin(
  source : String,
  node : @markdown.MarkdownIR,
  fragment : String,
) -> Unit raise {
  let origin = node.origin()
  assert_true(origin.start() >= 0)
  assert_true(origin.end() <= source.length())
  assert_true(origin.start() < origin.end())
  assert_true(source[origin.start():origin.end()].contains(fragment))
}

///|
fn quoted_ownership_assert_cst(
  label : String,
  source : String,
  root : @seam.SyntaxNode,
) -> Unit raise {
  let list_item = match label {
    "26-quote-exits-list-with-list" | "27-quote-exits-list-with-paragraph" =>
      quoted_ownership_find_list_item(root, "plain").unwrap()
    "29-nested-ordered-list" =>
      quoted_ownership_find_list_item(root, "a").unwrap()
    _ => quoted_ownership_find_list_item(root, "plain").unwrap()
  }
  match label {
    "15-second-paragraph" =>
      assert_true(
        quoted_ownership_syntax_has_descendant_text(
          list_item,
          ParagraphNode,
          "next",
        ),
      )
    "20-nested-list" =>
      assert_true(
        quoted_ownership_syntax_has_descendant(list_item, UnorderedListNode),
      )
    "21-heading" =>
      assert_true(
        quoted_ownership_syntax_has_descendant(list_item, HeadingNode),
      )
    "23-fenced-code" =>
      assert_true(
        quoted_ownership_syntax_has_descendant(list_item, CodeBlockNode),
      )
    "26-quote-exits-list-with-list" | "27-quote-exits-list-with-paragraph" => {
      assert_true(
        quoted_ownership_syntax_has_descendant(list_item, BlockQuoteNode),
      )
      match root.children() {
        [list, quote] => {
          assert_true(quoted_ownership_syntax_kind(list) is UnorderedListNode)
          assert_true(quoted_ownership_syntax_kind(quote) is BlockQuoteNode)
          assert_true(quote.text().contains("next"))
        }
        _ => fail("root quote must be a sibling of the list")
      }
    }
    "28-second-paragraph" =>
      assert_true(
        quoted_ownership_syntax_has_descendant_text(
          list_item,
          ParagraphNode,
          "more",
        ),
      )
    "29-nested-ordered-list" =>
      assert_true(
        quoted_ownership_syntax_has_descendant(list_item, OrderedListNode),
      )
    _ => fail("unknown quoted ownership case")
  }
  assert_eq(root.text(), source)
}

///|
test "issue 966 quoted-list ownership matches CommonMark HTML and CST" {
  for (label, source, expected_html) in quoted_ownership_cases() {
    assert_commonmark_blockquote_html_regression(
      "quoted-list-ownership", label, source, expected_html,
    )
    let source_id = @core.SourceId("markdown-quoted-list-ownership-" + label)
    let (cst, diagnostics) = try! @markdown.parse_cst(source_id, source)
    assert_true(diagnostics.is_empty())
    let root = @seam.SyntaxNode::from_cst(cst)
    quoted_ownership_assert_cst(label, source, root)
    let ir = @markdown.parse(source, source_id~).semantic_read().ir()
    quoted_ownership_assert_no_recovery(ir)
    match label {
      "15-second-paragraph" => {
        let item = first_descendant_of_kind(ir, "ListItem").unwrap()
        assert_eq(item.children().length(), 2)
        quoted_ownership_assert_ir_origin(source, item.children()[1], "next")
      }
      "20-nested-list" => {
        let item = first_descendant_of_kind(ir, "ListItem").unwrap()
        let nested = first_descendant_of_kind(item, "UnorderedList").unwrap()
        assert_true(item.origin().start() < nested.origin().start())
        assert_true(nested.origin().end() <= item.origin().end())
        quoted_ownership_assert_ir_origin(source, nested, "nested")
      }
      "21-heading" => {
        let item = first_descendant_of_kind(ir, "ListItem").unwrap()
        let heading = first_descendant_of_kind(item, "Heading").unwrap()
        assert_true(item.origin().start() < heading.origin().start())
        assert_true(heading.origin().end() <= item.origin().end())
        quoted_ownership_assert_ir_origin(source, heading, "heading")
      }
      "23-fenced-code" => {
        let item = first_descendant_of_kind(ir, "ListItem").unwrap()
        let code = first_descendant_of_kind(item, "CodeBlock").unwrap()
        assert_true(item.origin().start() < code.origin().start())
        assert_true(code.origin().end() <= item.origin().end())
        quoted_ownership_assert_ir_origin(source, code, "code")
      }
      "28-second-paragraph" => {
        let item = first_descendant_of_kind(ir, "ListItem").unwrap()
        assert_eq(item.children().length(), 2)
        quoted_ownership_assert_ir_origin(source, item.children()[1], "more")
      }
      "29-nested-ordered-list" => {
        let item = first_descendant_of_kind(ir, "ListItem").unwrap()
        let nested = first_descendant_of_kind(item, "OrderedList").unwrap()
        assert_true(item.origin().start() < nested.origin().start())
        assert_true(nested.origin().end() <= item.origin().end())
        quoted_ownership_assert_ir_origin(source, nested, "1. b")
      }
      "26-quote-exits-list-with-list" | "27-quote-exits-list-with-paragraph" =>
        match ir.children() {
          [list, quote] => {
            assert_eq(list.kind_tag(), "UnorderedList")
            assert_eq(quote.kind_tag(), "BlockQuote")
            quoted_ownership_assert_ir_origin(source, quote, "next")
          }
          _ => fail("lowered root must retain the exiting quote as a sibling")
        }
      _ => fail("unknown quoted ownership case")
    }
  }
}

///|
fn quoted_ownership_assert_owned_quote_cst(
  source_id : @core.SourceId,
  source : String,
) -> Unit raise {
  let (cst, diagnostics) = @markdown.parse_cst(source_id, source)
  assert_true(diagnostics.is_empty())
  let root = @seam.SyntaxNode::from_cst(cst)
  assert_eq(root.text(), source)
  match root.children() {
    [list] => {
      assert_true(quoted_ownership_syntax_kind(list) is UnorderedListNode)
      let item = quoted_ownership_find_list_item(list, "plain").unwrap()
      assert_true(
        quoted_ownership_syntax_has_descendant_text(
          item,
          BlockQuoteNode,
          "next",
        ),
      )
    }
    _ => fail("owned quote must remain inside the root list CST")
  }
}

///|
fn quoted_ownership_assert_syntax_clean(
  parser : @loom.SyntaxParser,
) -> Unit raise {
  assert_true(parser.snapshot().read_or_abort().diagnostics.is_empty())
}

///|
fn quoted_ownership_assert_incremental_parity(
  label : String,
  source_id : @core.SourceId,
  source : String,
  expected_html : String,
  widen_continuation? : Bool = true,
) -> Unit raise {
  let parser = @loom.new_parser(source_id, source, @markdown.markdown_grammar)
  // Semantic attachment collection only retains observed parser views.
  let diagnostics_watch = parser.diagnostics().watch()
  defer diagnostics_watch.dispose()
  assert_true(diagnostics_watch.read_or_abort().is_empty())
  let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  let syntax_parser = @loom.new_syntax_parser(
    source_id,
    source,
    @markdown.markdown_grammar.to_syntax_grammar(),
  )
  let updates = @markdown.MarkdownDocumentUpdates(syntax_parser)
  quoted_ownership_assert_syntax_clean(syntax_parser)
  let initial_ir = @markdown.parse(source, source_id~).semantic_read().ir()
  assert_true(parser.diagnostics().read_or_abort().is_empty())
  assert_eq(attachment.document(), initial_ir)
  assert_eq(
    updates.document_update().document().semantic_read().ir(),
    initial_ir,
  )
  assert_eq(
    @markdown.experimental_markdown_ir_to_commonmark_html(initial_ir),
    expected_html,
  )

  // Insert a blank physical prefix; it does not alter the expected rendered blocks.
  let prefixed = "\n" + source
  parser.apply_edit(@core.Edit::insert(0, 1), prefixed)
  let prefix_change = @text_change.ChangeSet::ChangeSet(
    source_length=source.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(
        start=0,
        delete_len=0,
        inserted="\n",
      ),
    ],
  )
  syntax_parser.apply_changes(prefix_change, prefixed)
  quoted_ownership_assert_syntax_clean(syntax_parser)
  let fresh_prefixed = @markdown.parse(prefixed, source_id~)
    .semantic_read()
    .ir()
  match parser.diagnostics().read() {
    Ok(diagnostics) => assert_true(diagnostics.is_empty())
    Err(error) => fail(label + " prefix diagnostics: " + error.format_path())
  }
  quoted_ownership_assert_no_recovery(fresh_prefixed)
  assert_eq(attachment.document(), fresh_prefixed)
  let update = updates.document_update()
  assert_eq(update.document().semantic_read().ir(), fresh_prefixed)
  assert_eq(
    @markdown.experimental_markdown_ir_to_commonmark_html(fresh_prefixed),
    expected_html,
  )

  // A leading list-indent change transfers the second quote from the root
  // into the list item for #26/#27. Deleting the same prefix restores exit.
  if label is "26-quote-exits-list-with-list" ||
    label is "27-quote-exits-list-with-paragraph" {
    let line_break = source.find("\n>   next").unwrap()
    let ownership_start = line_break + 2
    let owned_source = prefixed[:ownership_start].to_owned() +
      "  " +
      prefixed[ownership_start:].to_owned()
    parser.apply_edit(@core.Edit::insert(ownership_start, 2), owned_source)
    let owned_change = @text_change.ChangeSet::ChangeSet(
      source_length=prefixed.length(),
      changes=[
        @text_change.TextChange::ReplaceRange(
          start=ownership_start,
          delete_len=0,
          inserted="  ",
        ),
      ],
    )
    syntax_parser.apply_changes(owned_change, owned_source)
    quoted_ownership_assert_owned_quote_cst(source_id, owned_source)
    quoted_ownership_assert_syntax_clean(syntax_parser)
    let expected_owned_html = if label is "26-quote-exits-list-with-list" {
      "<ul>\n<li>\n<blockquote>\n<ul>\n<li>plain\nnext</li>\n</ul>\n</blockquote>\n</li>\n</ul>\n"
    } else {
      "<ul>\n<li>\n<blockquote>\n<p>plain\nnext</p>\n</blockquote>\n</li>\n</ul>\n"
    }
    let fresh_owned = @markdown.parse(owned_source, source_id~)
      .semantic_read()
      .ir()
    quoted_ownership_assert_no_recovery(fresh_owned)
    assert_true(parser.diagnostics().read_or_abort().is_empty())
    assert_eq(attachment.document(), fresh_owned)
    assert_eq(
      updates.document_update().document().semantic_read().ir(),
      fresh_owned,
    )
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(fresh_owned),
      expected_owned_html,
    )
    let restored_source = owned_source[:ownership_start].to_owned() +
      owned_source[ownership_start + 2:].to_owned()
    parser.apply_edit(
      @core.Edit::delete(ownership_start, ownership_start + 2),
      restored_source,
    )
    let restore_change = @text_change.ChangeSet::ChangeSet(
      source_length=owned_source.length(),
      changes=[
        @text_change.TextChange::ReplaceRange(
          start=ownership_start,
          delete_len=2,
          inserted="",
        ),
      ],
    )
    syntax_parser.apply_changes(restore_change, restored_source)
    quoted_ownership_assert_syntax_clean(syntax_parser)
    let fresh_restored = @markdown.parse(restored_source, source_id~)
      .semantic_read()
      .ir()
    quoted_ownership_assert_no_recovery(fresh_restored)
    assert_true(parser.diagnostics().read_or_abort().is_empty())
    assert_eq(attachment.document(), fresh_restored)
    assert_eq(
      updates.document_update().document().semantic_read().ir(),
      fresh_restored,
    )
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(fresh_restored),
      expected_html,
    )
  }

  // Widen quoted continuation indentation while keeping block ownership.
  match source.find("\n>   ") {
    Some(line_break) if widen_continuation && source.has_prefix("> ") => {
      // The first space after `>` is quote syntax; this inserts item indent.
      let edit_start = line_break + 4
      let wider = prefixed[:edit_start].to_owned() +
        " " +
        prefixed[edit_start:].to_owned()
      parser.apply_edit(@core.Edit::insert(edit_start, 1), wider)
      let wide_change = @text_change.ChangeSet::ChangeSet(
        source_length=prefixed.length(),
        changes=[
          @text_change.TextChange::ReplaceRange(
            start=edit_start,
            delete_len=0,
            inserted=" ",
          ),
        ],
      )
      syntax_parser.apply_changes(wide_change, wider)
      quoted_ownership_assert_syntax_clean(syntax_parser)
      let fresh_wider = @markdown.parse(wider, source_id~).semantic_read().ir()
      assert_true(parser.diagnostics().read_or_abort().is_empty())
      quoted_ownership_assert_no_recovery(fresh_wider)
      assert_eq(attachment.document(), fresh_wider)
      assert_eq(
        updates.document_update().document().semantic_read().ir(),
        fresh_wider,
      )
      assert_eq(
        @markdown.experimental_markdown_ir_to_commonmark_html(fresh_wider),
        expected_html,
      )

      // On a nested bullet, reducing the two-column item indent to one column
      // makes the marker a sibling item; restoring it re-nests the list.
      if source is "> - plain\n>   - nested\n" {
        let narrow_start = edit_start
        let narrower = wider[:narrow_start].to_owned() +
          wider[narrow_start + 2:].to_owned()
        parser.apply_edit(
          @core.Edit::delete(narrow_start, narrow_start + 2),
          narrower,
        )
        let narrow_change = @text_change.ChangeSet::ChangeSet(
          source_length=wider.length(),
          changes=[
            @text_change.TextChange::ReplaceRange(
              start=narrow_start,
              delete_len=2,
              inserted="",
            ),
          ],
        )
        syntax_parser.apply_changes(narrow_change, narrower)
        quoted_ownership_assert_syntax_clean(syntax_parser)
        let fresh_narrower = @markdown.parse(narrower, source_id~)
          .semantic_read()
          .ir()
        assert_true(parser.diagnostics().read_or_abort().is_empty())
        quoted_ownership_assert_no_recovery(fresh_narrower)
        assert_eq(attachment.document(), fresh_narrower)
        assert_eq(
          updates.document_update().document().semantic_read().ir(),
          fresh_narrower,
        )
        assert_eq(
          @markdown.experimental_markdown_ir_to_commonmark_html(fresh_narrower),
          "<blockquote>\n<ul>\n<li>plain</li>\n<li>nested</li>\n</ul>\n</blockquote>\n",
        )
        let restored = narrower[:narrow_start].to_owned() +
          "  " +
          narrower[narrow_start:].to_owned()
        parser.apply_edit(@core.Edit::insert(narrow_start, 2), restored)
        let restore_change = @text_change.ChangeSet::ChangeSet(
          source_length=narrower.length(),
          changes=[
            @text_change.TextChange::ReplaceRange(
              start=narrow_start,
              delete_len=0,
              inserted="  ",
            ),
          ],
        )
        syntax_parser.apply_changes(restore_change, restored)
        quoted_ownership_assert_syntax_clean(syntax_parser)
        let fresh_restored = @markdown.parse(restored, source_id~)
          .semantic_read()
          .ir()
        assert_true(parser.diagnostics().read_or_abort().is_empty())
        quoted_ownership_assert_no_recovery(fresh_restored)
        assert_eq(attachment.document(), fresh_restored)
        assert_eq(
          updates.document_update().document().semantic_read().ir(),
          fresh_restored,
        )
        assert_eq(
          @markdown.experimental_markdown_ir_to_commonmark_html(fresh_restored),
          expected_html,
        )
      }
    }
    _ => ()
  }
  attachment.dispose()
}

///|
test "issue 966 quoted ownership remains fresh across keyed and document updates" {
  for (label, source, expected_html) in quoted_ownership_cases() {
    quoted_ownership_assert_incremental_parity(
      label,
      @core.SourceId("markdown-quoted-list-updates-" + label),
      source,
      expected_html,
    )
  }
}

///|
test "quoted list sibling separators retain the next marker columns" {
  let cases = [
    (
      "tab-blank-ordered", "> 10. a\n>\t\n>    11. b\n", "<blockquote>\n<ol start=\"10\">\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ol>\n</blockquote>\n",
    ),
    (
      "heading-sibling", "> - plain\n>   # heading\n> - sibling\n", "<blockquote>\n<ul>\n<li>plain\n<h1>heading</h1>\n</li>\n<li>sibling</li>\n</ul>\n</blockquote>\n",
    ),
    (
      "fence-sibling", "> - plain\n>   ```\n>   code\n>   ```\n> - sibling\n", "<blockquote>\n<ul>\n<li>plain\n<pre><code>code\n</code></pre>\n</li>\n<li>sibling</li>\n</ul>\n</blockquote>\n",
    ),
  ]
  for (label, source, expected) in cases {
    assert_commonmark_blockquote_html_regression(
      "owned-siblings", label, source, expected,
    )
    quoted_ownership_assert_incremental_parity(
      label,
      @core.SourceId("quoted-sibling-" + label),
      source,
      expected,
      widen_continuation=false,
    )
  }
}

///|
test "nested quoted fence edits preserve literal quote content" {
  for depth in [1, 2, 3] {
    let prefix = Array::make(depth, "> ").join("")
    let source = prefix +
      "- plain\n" +
      prefix +
      "  ```\n" +
      prefix +
      "  > literal\n" +
      prefix +
      "  ```\n"
    let source_id = @core.SourceId("nested-quoted-fence")
    let expected = Array::make(depth, "<blockquote>\n").join("") +
      "<ul>\n<li>plain\n<pre><code>&gt; literal\n</code></pre>\n</li>\n</ul>\n" +
      Array::make(depth, "</blockquote>\n").join("")
    quoted_ownership_assert_incremental_parity(
      "nested-fence", source_id, source, expected,
    )
    let parser = @loom.new_parser(source_id, source, @markdown.markdown_grammar)
    let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    defer attachment.dispose()
    let syntax_parser = @loom.new_syntax_parser(
      source_id,
      source,
      @markdown.markdown_grammar.to_syntax_grammar(),
    )
    let updates = @markdown.MarkdownDocumentUpdates(syntax_parser)
    let initial = @markdown.parse(source, source_id~).semantic_read().ir()
    assert_eq(attachment.document(), initial)
    assert_eq(
      updates.document_update().document().semantic_read().ir(),
      initial,
    )
    let start = source.find("literal").unwrap()
    let changed = source[:start].to_owned() +
      "edited" +
      source[start + 7:].to_owned()
    parser.apply_edit(@core.Edit::new(start, 7, 6), changed)
    syntax_parser.apply_changes(
      @text_change.ChangeSet::ChangeSet(source_length=source.length(), changes=[
        @text_change.TextChange::ReplaceRange(
          start~,
          delete_len=7,
          inserted="edited",
        ),
      ]),
      changed,
    )
    let fresh = @markdown.parse(changed, source_id~).semantic_read().ir()
    assert_eq(attachment.document(), fresh)
    assert_eq(updates.document_update().document().semantic_read().ir(), fresh)
    quoted_ownership_assert_syntax_clean(syntax_parser)
    quoted_ownership_assert_no_recovery(fresh)
    let (cst, diagnostics) = @markdown.parse_cst(source_id, changed)
    assert_true(diagnostics.is_empty())
    assert_eq(@seam.SyntaxNode::from_cst(cst).text(), changed)
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(fresh),
      Array::make(depth, "<blockquote>\n").join("") +
      "<ul>\n<li>plain\n<pre><code>&gt; edited\n</code></pre>\n</li>\n</ul>\n" +
      Array::make(depth, "</blockquote>\n").join(""),
    )
  }
}

///|
test "quoted fence ends when its physical quote depth decreases" {
  let source = "> > ```\n> only outer\n> > ```\n"
  let expected = "<blockquote>\n<blockquote>\n<pre><code></code></pre>\n</blockquote>\n<p>only outer</p>\n<blockquote>\n<pre><code></code></pre>\n</blockquote>\n</blockquote>\n"
  quoted_ownership_assert_incremental_parity(
    "fence-depth-exit",
    @core.SourceId("fence-depth-exit"),
    source,
    expected,
  )
}

///|
test "detached quoted fence replay stops at the preceding quoted close" {
  let source = "> > ```\n> > old\n> > ```\n\n> ```\n> new\n> ```\n"
  let start = source.find("> new").unwrap()
  let session = @markdown.MarkdownLexSession::MarkdownLexSession()
  let (prefix, mode) = session.step(source, start, QuotedCodeBlock(3, '`'))
  match prefix {
    Produced(info, next_offset~) => {
      assert_true(info.token is BlockQuoteMarker)
      assert_eq(next_offset, start + 2)
      let (body, _) = session.step(source, next_offset, mode)
      match body {
        Produced(info, next_offset~) => {
          assert_true(info.token is CodeText("new"))
          assert_eq(next_offset, start + 5)
        }
        _ => fail("expected the later fence's code body")
      }
    }
    _ => fail("expected the later fence's single quote prefix")
  }
}

///|
test "detached quoted fence EOF retains its depth for an appended line" {
  let source = "> > ```\n> > old\n"
  let session = @markdown.MarkdownLexSession::MarkdownLexSession()
  let (step, mode) = session.step(
    source,
    source.length(),
    QuotedCodeBlock(3, '`'),
  )
  assert_true(step is Done)
  let appended = source + "> > new\n> > ```\n"
  let (prefix, _) = session.step(appended, source.length(), mode)
  match prefix {
    Produced(info, next_offset~) => {
      assert_true(info.token is BlockQuoteMarker)
      assert_eq(next_offset, source.length() + 4)
    }
    _ => fail("expected both retained quote markers after EOF append")
  }
}

///|
test "quoted fence prefixes retain list-owned indentation between markers" {
  let quoted = "<blockquote>\n<ol start=\"10\">\n<li>\n<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n"
  let cases = [
    ("same-line", "> 10. > ```\n>     > code\n>     > ```\n", quoted),
    ("optional-indent", "> 10. > ```\n>        > code\n>     > ```\n", quoted),
    ("tab-indent", "> 10. > ```\n> \t  > code\n>     > ```\n", quoted),
    ("tab-quote-padding", "> 10. > ```\n>\t  > code\n>     > ```\n", quoted),
    (
      "tab-list-padding", "> 10.\t> ```\n>       > code\n>       > ```\n", quoted,
    ),
    (
      "root-list", "10. > ```\n    > code\n    > ```\n", "<ol start=\"10\">\n<li>\n<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n</li>\n</ol>\n",
    ),
    (
      "literal-marker", "> 10. > ```\n>     > > code\n>     > ```\n", "<blockquote>\n<ol start=\"10\">\n<li>\n<blockquote>\n<pre><code>&gt; code\n</code></pre>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n",
    ),
    (
      "later-opening", "> 10. text\n>     > ```\n>     > code\n>     > ```\n", "<blockquote>\n<ol start=\"10\">\n<li>text\n<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n",
    ),
    (
      "later-optional-opening", "> 10. text\n>        > ```\n>     > code\n>     > ```\n",
      "<blockquote>\n<ol start=\"10\">\n<li>text\n<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n</li>\n</ol>\n</blockquote>\n",
    ),
  ]
  for (label, source, expected) in cases {
    let source_id = @core.SourceId("list-owned-fence-" + label)
    quoted_ownership_assert_incremental_parity(
      label,
      source_id,
      source,
      expected,
      widen_continuation=false,
    )
    let parser = @loom.new_parser(source_id, source, @markdown.markdown_grammar)
    let diagnostics = parser.diagnostics().watch()
    defer diagnostics.dispose()
    assert_true(diagnostics.read_or_abort().is_empty())
    let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    defer attachment.dispose()
    let syntax_parser = @loom.new_syntax_parser(
      source_id,
      source,
      @markdown.markdown_grammar.to_syntax_grammar(),
    )
    let updates = @markdown.MarkdownDocumentUpdates(syntax_parser)
    let initial = attachment.document()
    assert_eq(
      updates.document_update().document().semantic_read().ir(),
      initial,
    )
    let start = source.find("code").unwrap()
    let changed = source[:start].to_owned() +
      "edited" +
      source[start + 4:].to_owned()
    parser.apply_edit(@core.Edit::new(start, 4, 6), changed)
    syntax_parser.apply_changes(
      @text_change.ChangeSet::ChangeSet(source_length=source.length(), changes=[
        @text_change.TextChange::ReplaceRange(
          start~,
          delete_len=4,
          inserted="edited",
        ),
      ]),
      changed,
    )
    let fresh = @markdown.parse(changed, source_id~).semantic_read().ir()
    assert_eq(attachment.document(), fresh)
    assert_eq(updates.document_update().document().semantic_read().ir(), fresh)
    assert_true(diagnostics.read_or_abort().is_empty())
    quoted_ownership_assert_syntax_clean(syntax_parser)
    quoted_ownership_assert_no_recovery(fresh)
    let (cst, errors) = @markdown.parse_cst(source_id, changed)
    assert_true(errors.is_empty())
    assert_eq(@seam.SyntaxNode::from_cst(cst).text(), changed)
    let expected_start = expected.find("code\n").unwrap()
    assert_eq(
      @markdown.experimental_markdown_ir_to_commonmark_html(fresh),
      expected[:expected_start].to_owned() +
      "edited" +
      expected[expected_start + 4:].to_owned(),
    )
  }
}

///|
test "quoted fence ownership bands agree in cold and session stepping" {
  for
    (prefix, owned) in [
      (">     > ", true),
      (">        > ", true),
      ("> \t  > ", true),
      (">\t  > ", true),
      (">    > ", false),
      (">         > ", false),
      ("> \t> ", false),
      ("> ", false),
    ] {
    let opening = "> 10. > ```\n"
    let source = opening + prefix + "code\n>     > ```\n"
    let session = @markdown.MarkdownLexSession::MarkdownLexSession()
    let (_, session_mode) = session.step(
      source,
      opening.length() - 1,
      QuotedCodeBlock(3, '`'),
    )
    let (_, cold_mode) = @markdown.markdown_lex_step(
      source,
      opening.length() - 1,
      QuotedCodeBlock(3, '`'),
    )
    assert_eq(session_mode, cold_mode)
    assert_eq(
      session_mode,
      if owned {
        QuotedCodeBlock(3, '`')
      } else {
        LineStart
      },
    )
    if owned {
      let (step, mode) = session.step(source, opening.length(), session_mode)
      let (cold_step, _) = @markdown.markdown_lex_step(
        source,
        opening.length(),
        cold_mode,
      )
      for path, prefix_step in [step, cold_step] {
        match prefix_step {
          Produced(info, next_offset~) => {
            assert_true(info.token is BlockQuoteMarker)
            if next_offset != opening.length() + prefix.length() {
              fail("prefix \{Repr(prefix)}, path \{path}: \{next_offset}")
            }
          }
          _ => fail("expected the complete owned quote prefix")
        }
      }
      let (body, _) = session.step(
        source,
        opening.length() + prefix.length(),
        mode,
      )
      match body {
        Produced(info, next_offset~) => {
          assert_true(info.token is CodeText("code"))
          assert_eq(next_offset, opening.length() + prefix.length() + 4)
        }
        _ => fail("expected code after the list-owned quote prefix")
      }
    }
  }
  let source = "> 10. > ```\n>     > old\n"
  let session = @markdown.MarkdownLexSession::MarkdownLexSession()
  let (_, mode) = session.step(source, source.length(), QuotedCodeBlock(3, '`'))
  let appended = source + ">     > new\n>     > ```\n"
  let (prefix, _) = session.step(appended, source.length(), mode)
  match prefix {
    Produced(info, next_offset~) => {
      assert_true(info.token is BlockQuoteMarker)
      assert_eq(next_offset, source.length() + 8)
    }
    _ => fail("expected retained list indentation after EOF append")
  }
}
