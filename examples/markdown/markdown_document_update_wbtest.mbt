///|
fn document_update_replace(
  source : String,
  start : Int,
  delete_len : Int,
  inserted : String,
) -> String {
  source[:start].to_owned() + inserted + source[start + delete_len:].to_owned()
}

///|
fn document_update_match_indexes(
  update : MarkdownDocumentUpdate,
  previous : MarkdownPreviousUpdate?,
) -> Array[Int?] {
  update
  .top_level_blocks(previous~)
  .map(block => block.matched_previous_block_index())
}

///|
fn assert_document_update_matches_direct(
  parser : @loom.SyntaxParser,
  update : MarkdownDocumentUpdate,
  extensions : MarkdownExtensions,
) -> Unit raise {
  let snapshot = parser.snapshot().read_or_abort()
  let direct = experimental_markdown_ir_from_syntax_snapshot(
    snapshot,
    extensions~,
  )
  assert_eq(update.document().semantic_read().ir(), direct)
  assert_eq(
    update.top_level_blocks(previous=None).length(),
    direct.children().length(),
  )
}

///|
test "document updates gate matches by the accepted direct previous update" {
  let source = "Alpha.\n\nBeta.\n"
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-gating"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let updates = MarkdownDocumentUpdates(parser)

  let initial = updates.document_update()
  assert_eq(document_update_match_indexes(initial, None), [None, None])

  let repeated = updates.document_update()
  assert_eq(
    document_update_match_indexes(repeated, Some(initial.as_previous())),
    [Some(0), Some(1)],
  )

  let skipped = updates.document_update()
  assert_eq(
    document_update_match_indexes(skipped, Some(initial.as_previous())),
    [None, None],
  )
  assert_eq(
    document_update_match_indexes(skipped, Some(repeated.as_previous())),
    [Some(0), Some(1)],
  )
}

///|
test "document updates expose only unchanged direct-previous blocks" {
  let source = "Alpha.\n\nBeta.\n\nGamma.\n"
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-local-edit"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let updates = MarkdownDocumentUpdates(parser)
  let initial = updates.document_update()

  let beta = source.find("Beta").unwrap()
  let changed = document_update_replace(source, beta, 1, "Z")
  parser.apply_edit(@core.Edit::replace(beta, beta + 1, beta + 1), changed)
  let update = updates.document_update()
  assert_document_update_matches_direct(
    parser,
    update,
    MarkdownExtensions::none(),
  )
  assert_eq(
    document_update_match_indexes(update, Some(initial.as_previous())),
    [Some(0), None, Some(2)],
  )
  assert_eq(document_update_match_indexes(update, None), [None, None, None])
}

///|
test "document updates reject a previous update from another producer" {
  let source = "Alpha.\n\nBeta.\n"
  let first_parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-first-producer"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let first = MarkdownDocumentUpdates(first_parser).document_update()
  let replacement_parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-replacement-producer"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let replacement = MarkdownDocumentUpdates(replacement_parser).document_update()
  assert_eq(
    document_update_match_indexes(replacement, Some(first.as_previous())),
    [None, None],
  )
}

///|
test "document updates hide matches for insert delete move and definitions" {
  let source = "[ref]: /a\n\nAlpha [x][ref].\n\nBeta.\n"
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-fallbacks"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let updates = MarkdownDocumentUpdates(parser)
  let initial = updates.document_update()

  let insertion = source.find("Beta").unwrap()
  let inserted_text = "Inserted.\n\n"
  let inserted_source = document_update_replace(
    source, insertion, 0, inserted_text,
  )
  parser.apply_edit(
    @core.Edit::insert(insertion, inserted_text.length()),
    inserted_source,
  )
  let inserted = updates.document_update()
  assert_eq(
    document_update_match_indexes(inserted, Some(initial.as_previous())),
    [None, None, None],
  )

  parser.apply_edit(
    @core.Edit::delete(insertion, insertion + inserted_text.length()),
    source,
  )
  let deleted = updates.document_update()
  assert_eq(
    document_update_match_indexes(deleted, Some(inserted.as_previous())),
    [None, None],
  )

  let definition = source.find("/a").unwrap() + 1
  let changed_definition = document_update_replace(source, definition, 1, "b")
  parser.apply_edit(
    @core.Edit::replace(definition, definition + 1, definition + 1),
    changed_definition,
  )
  let definition_update = updates.document_update()
  assert_eq(
    document_update_match_indexes(
      definition_update,
      Some(deleted.as_previous()),
    ),
    [None, None],
  )
}

///|
test "document updates preserve task semantics and recover after fallback" {
  let source = "- [ ] first task\n\nParagraph alpha.\n\nTail omega.\n"
  let extensions = MarkdownExtensions::task_list()
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-task-list"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let updates = MarkdownDocumentUpdates(parser, extensions~)
  let initial = updates.document_update()
  assert_document_update_matches_direct(parser, initial, extensions)

  let task_position = source.find("[ ]").unwrap() + 1
  let checked_source = document_update_replace(source, task_position, 1, "x")
  parser.apply_edit(
    @core.Edit::replace(task_position, task_position + 1, task_position + 1),
    checked_source,
  )
  let checked = updates.document_update()
  assert_document_update_matches_direct(parser, checked, extensions)
  assert_eq(
    document_update_match_indexes(checked, Some(initial.as_previous())),
    [None, Some(1), Some(2)],
  )

  let tail = checked_source.find("Tail").unwrap()
  let recovered_source = document_update_replace(
    checked_source, tail, 0, "```\n",
  )
  parser.apply_edit(@core.Edit::insert(tail, 4), recovered_source)
  let recovered = updates.document_update()
  assert_document_update_matches_direct(parser, recovered, extensions)
  assert_true(
    document_update_match_indexes(recovered, Some(checked.as_previous())).all(match_index => {
      match_index is None
    }),
  )
}

///|
test "document updates fail closed for moves and duplicate block content" {
  let source = "Same.\n\nMiddle.\n\nSame.\n"
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-move"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let updates = MarkdownDocumentUpdates(parser)
  let initial = updates.document_update()
  let moved_source = "Same.\n\nSame.\n\nMiddle.\n"
  parser.apply_edit(
    @core.Edit::replace(0, source.length(), moved_source.length()),
    moved_source,
  )
  let moved = updates.document_update()
  assert_eq(document_update_match_indexes(moved, Some(initial.as_previous())), [
    None,
    None,
    None,
  ])
}

///|
test "document updates hide matches while diagnostics are present" {
  let source = "Alpha.\n\nBeta.\n"
  let parser = @loom.new_syntax_parser(
    @core.SourceId("document-update-diagnostics"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let updates = MarkdownDocumentUpdates(parser)
  let initial = updates.document_update()
  let snapshot = parser.snapshot().read_or_abort()
  snapshot.diagnostics.push(
    @core.lexer_diagnostic_at(
      parser.source_id(),
      "synthetic diagnostic",
      0,
      1,
      "document-update-test.dirty",
    ),
  )
  let dirty = updates.document_update()
  assert_eq(document_update_match_indexes(dirty, Some(initial.as_previous())), [
    None,
    None,
  ])
}

///|
test "document update match validation rejects duplicate and invalid indexes" {
  assert_eq(validated_document_update_matches([Some(0), Some(0)], Some(2)), [
    None,
    None,
  ])
  assert_eq(validated_document_update_matches([Some(0), Some(2)], Some(2)), [
    None,
    None,
  ])
  assert_eq(validated_document_update_matches([Some(1), Some(0)], Some(2)), [
    Some(1),
    Some(0),
  ])
}

///|
test "document update nodes belong only to their update document" {
  let source = "Alpha.\n\nBeta.\n"
  let source_id = @core.SourceId("document-update-node-membership")
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let update = MarkdownDocumentUpdates(parser).document_update()
  let document = update.document()
  let node = update.top_level_blocks(previous=None)[0].node()
  assert_true(document.source_span(node) is Some(_))
  assert_true(parse(source, source_id~).source_span(node) is None)
}

///|
test "lightweight nodes require their document for source queries" {
  let source_id = @core.SourceId("lightweight-node-membership")
  let first = parse("Alpha.\n", source_id~)
  let node = first.root().children()[0]
  assert_true(first.source_span(node) is Some(_))

  let second = parse("Alpha.\n", source_id~)
  assert_true(second.source_span(node) is None)
  assert_true(node.view() is MarkdownNodeView::Paragraph)
  assert_true(
    node.children()[0].view() is MarkdownNodeView::Text(value="Alpha."),
  )
}
