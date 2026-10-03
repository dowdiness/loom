///|
/// Expected HTML in this file comes from the CommonMark 0.31.2 reference
/// implementation (`commonmark.js` 0.31.2 via `npx commonmark -t html`), the
/// same version as the pinned `tools/commonmark-0.31.2-spec.json` corpus.

///|
/// A continuation line of a list item inside a blockquote stays in that item
/// instead of becoming a sibling block of the quote.
test "quoted list item keeps its continuation line" {
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "shortcut-link", "> - [label]\n>   next\n\n[label]: /url\n",
    "<blockquote>\n<ul>\n<li><a href=\"/url\">label</a>\nnext</li>\n</ul>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "ordinary-text", "> - plain\n>   next\n", "<blockquote>\n<ul>\n<li>plain\nnext</li>\n</ul>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "reference-image", "> - ![label]\n>   next\n\n[label]: /url\n",
    "<blockquote>\n<ul>\n<li><img src=\"/url\" alt=\"label\" />\nnext</li>\n</ul>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "ordered-item", "> 1. plain\n>    next\n", "<blockquote>\n<ol>\n<li>plain\nnext</li>\n</ol>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "lazy-quoted-line", "> - plain\n> next\n", "<blockquote>\n<ul>\n<li>plain\nnext</li>\n</ul>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "nested-blockquote", "> > - plain\n> >   next\n",
    "<blockquote>\n<blockquote>\n<ul>\n<li>plain\nnext</li>\n</ul>\n</blockquote>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "triple-nested-blockquote", "> > > - plain\n> > >   next\n",
    "<blockquote>\n<blockquote>\n<blockquote>\n<ul>\n<li>plain\nnext</li>\n</ul>\n</blockquote>\n</blockquote>\n</blockquote>\n",
  )
}

///|
/// Multiple continuation lines stay in the item, and a following sibling item
/// still opens a new list item instead of being swallowed as text.
test "quoted list item spans lines and stops at the next item" {
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "three-lines", "> - plain\n>   next\n>   more\n",
    "<blockquote>\n<ul>\n<li>plain\nnext\nmore</li>\n</ul>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "sibling-item", "> - plain\n>   next\n> - second\n",
    "<blockquote>\n<ul>\n<li>plain\nnext</li>\n<li>second</li>\n</ul>\n</blockquote>\n",
  )
}

///|
/// Hard breaks on the item's own line survive inside the same container.
test "quoted list item keeps hard breaks in the same container" {
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "trailing-spaces-hard-break", "> - plain  \n>   next\n",
    "<blockquote>\n<ul>\n<li>plain<br />\nnext</li>\n</ul>\n</blockquote>\n",
  )
  assert_commonmark_blockquote_html_regression(
    "quoted-list-continuation", "trailing-backslash-hard-break", "> - plain\\\n>   next\n",
    "<blockquote>\n<ul>\n<li>plain<br />\nnext</li>\n</ul>\n</blockquote>\n",
  )
}

///|
fn first_descendant_of_kind(
  node : @markdown.MarkdownIR,
  kind : String,
) -> @markdown.MarkdownIR? {
  if node.kind_tag() == kind {
    return Some(node)
  }
  for child in node.children() {
    match first_descendant_of_kind(child, kind) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
/// The continuation belongs to the list item in the CST, keeps the source
/// origins ordered inside the item, and stays lossless.
test "quoted list continuation keeps CST ownership and lossless text" {
  let sources = [
    "> - [label]\n>   next\n\n[label]: /url\n", "> - plain\n>   next\n", "> > - plain\n> >   next\n",
  ]
  for source in sources {
    let source_id = @core.SourceId("markdown-quoted-list-continuation-cst")
    let (cst, diagnostics) = try! @markdown.parse_cst(source_id, source)
    assert_true(diagnostics.is_empty())
    let root = @seam.SyntaxNode::from_cst(cst)
    assert_eq(root.text(), source)
    // Fresh lowering agrees with the CST-backed path for the same source.
    let ir = @markdown.parse(source).semantic_read().ir()
    assert_eq(
      ir,
      @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
        source_id, root, diagnostics,
      ),
    )
    // The first list item owns the continuation line.
    let item = first_descendant_of_kind(ir, "ListItem").unwrap()
    let paragraph = item.children()[0]
    assert_eq(paragraph.kind_tag(), "Paragraph")
    let paragraph_children = paragraph.children()
    let mut continuation_text = ""
    for child in paragraph_children {
      match child.text_value() {
        Some(value) if value == "next" => continuation_text = value
        _ => ()
      }
    }
    assert_eq(continuation_text, "next")
    assert_true(paragraph.origin().end() >= item.origin().end())
  }
}

///|
/// Fresh parsing and the keyed semantic attachment agree before and after
/// prefix insertion for quoted list continuations.
test "quoted list continuation agrees across fresh and keyed lowering" {
  let sources = [
    "> - [label]\n>   next\n\n[label]: /url\n", "> - plain\n>   next\n", "> - plain\n> next\n",
    "> 1. plain\n>    next\n", "> > - plain\n> >   next\n", "> - plain  \n>   next\n",
    "> - plain\\\n>   next\n", "> - plain\n>   next\n> - second\n",
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
/// Editing the continuation indentation keeps the keyed document equal to a
/// fresh parse of the edited source. The new source is derived from the
/// validated change set, so the edit evidence and the text cannot drift.
test "quoted list continuation tracks indentation edits" {
  let source = "> - plain\n>   next\n"
  let parser = @loom.new_parser(
    @core.SourceId("markdown"),
    source,
    @markdown.markdown_grammar,
  )
  let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  assert_eq(attachment.document(), @markdown.parse(source).semantic_read().ir())
  // Continuation indent 2 -> 3 columns.
  let widen = @text_change.ChangeSet::ChangeSet(source_length=source.length(), changes=[
    @text_change.TextChange::ReplaceRange(start=12, delete_len=0, inserted=" "),
  ])
  let wider = widen.apply(source).unwrap()
  assert_eq(wider, "> - plain\n>    next\n")
  parser.apply_changes(widen, wider)
  assert_eq(attachment.document(), @markdown.parse(wider).semantic_read().ir())
  // Continuation indent 3 -> 1 columns (still a lazy continuation line).
  let narrow = @text_change.ChangeSet::ChangeSet(source_length=wider.length(), changes=[
    @text_change.TextChange::ReplaceRange(start=12, delete_len=2, inserted=""),
  ])
  let narrower = narrow.apply(wider).unwrap()
  assert_eq(narrower, "> - plain\n>  next\n")
  parser.apply_changes(narrow, narrower)
  assert_eq(
    attachment.document(),
    @markdown.parse(narrower).semantic_read().ir(),
  )
  // Continuation indent back to 2 columns.
  let restore = @text_change.ChangeSet::ChangeSet(
    source_length=narrower.length(),
    changes=[
      @text_change.TextChange::ReplaceRange(
        start=12,
        delete_len=0,
        inserted=" ",
      ),
    ],
  )
  let restored = restore.apply(narrower).unwrap()
  assert_eq(restored, source)
  parser.apply_changes(restore, restored)
  assert_eq(attachment.document(), @markdown.parse(source).semantic_read().ir())
  attachment.dispose()
}

///|
/// Exercise the incremental edit API separately from validated atomic changes.
test "quoted list continuation tracks apply_edit indentation changes" {
  let source = "> - plain\n>   next\n"
  let parser = @loom.new_parser(
    @core.SourceId("markdown"),
    source,
    @markdown.markdown_grammar,
  )
  let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  assert_eq(attachment.document(), @markdown.parse(source).semantic_read().ir())
  // Insert one space at 12: continuation indent 2 -> 3 columns.
  let wider = source[:12].to_owned() + " " + source[12:].to_owned()
  assert_eq(wider, "> - plain\n>    next\n")
  parser.apply_edit(@core.Edit::new(12, 0, 1), wider)
  assert_eq(attachment.document(), @markdown.parse(wider).semantic_read().ir())
  // Delete two spaces at 12: continuation indent 3 -> 1 columns.
  let narrower = wider[:12].to_owned() + wider[14:].to_owned()
  assert_eq(narrower, "> - plain\n>  next\n")
  parser.apply_edit(@core.Edit::new(12, 2, 0), narrower)
  assert_eq(
    attachment.document(),
    @markdown.parse(narrower).semantic_read().ir(),
  )
  // Insert one space at 12: continuation indent 1 -> 2 columns.
  let restored = narrower[:12].to_owned() + " " + narrower[12:].to_owned()
  assert_eq(restored, source)
  parser.apply_edit(@core.Edit::new(12, 0, 1), restored)
  assert_eq(attachment.document(), @markdown.parse(source).semantic_read().ir())
  attachment.dispose()
}
