///|
fn semantic_session_replace(
  source : String,
  start : Int,
  delete_len : Int,
  inserted : String,
) -> String {
  source[:start].to_owned() + inserted + source[start + delete_len:].to_owned()
}

///|
fn assert_semantic_publication_matches_direct(
  parser : @loom.SyntaxParser,
  publication : MarkdownSemanticPublication,
  extensions : MarkdownExtensions,
) -> Unit raise {
  let snapshot = parser.snapshot().read_or_abort()
  let direct = experimental_markdown_ir_from_syntax_snapshot(
    snapshot,
    extensions~,
  )
  assert_eq(publication.document(), direct)
  assert_eq(
    publication.top_level_revision_keys().length(),
    direct.children().length(),
  )
}

///|
test "semantic session can continue a caller-owned revision-key sequence" {
  let source = "Alpha.\n\nBeta.\n"
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("semantic-session-key-sequence"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let session = MarkdownSemanticSession(parser, first_revision_key=41)
  let publication = session.publish()
  assert_eq(publication.top_level_revision_keys(), [41, 42][:])
  assert_eq(session.next_revision_key(), 43)
}

///|
test "semantic session preserves task-list semantics and revision keys" {
  let source = "- [ ] first task\n\nParagraph alpha.\n\nTail omega.\n"
  let extensions = MarkdownExtensions::task_list()
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("semantic-session-task-list"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let session = MarkdownSemanticSession(parser, extensions~)
  let initial = session.publish()
  assert_semantic_publication_matches_direct(parser, initial, extensions)
  let initial_keys = initial.top_level_revision_keys().to_array()
  let repeated = session.publish()
  assert_eq(repeated.document(), initial.document())
  assert_eq(repeated.top_level_revision_keys(), initial_keys[:])

  let task_position = source.find("[ ]").unwrap() + 1
  let checked_source = semantic_session_replace(source, task_position, 1, "x")
  parser.apply_edit(
    @core.Edit::replace(task_position, task_position + 1, task_position + 1),
    checked_source,
  )
  let checked = session.publish()
  assert_semantic_publication_matches_direct(parser, checked, extensions)
  let checked_keys = checked.top_level_revision_keys()
  assert_true(checked_keys[0] != initial_keys[0])
  assert_eq(checked_keys[1], initial_keys[1])
  assert_eq(checked_keys[2], initial_keys[2])

  let insertion_position = checked_source.find("alpha").unwrap() + 5
  let inserted_source = semantic_session_replace(
    checked_source, insertion_position, 0, " extended",
  )
  parser.apply_edit(@core.Edit::insert(insertion_position, 9), inserted_source)
  let inserted = session.publish()
  assert_semantic_publication_matches_direct(parser, inserted, extensions)
  let inserted_keys = inserted.top_level_revision_keys()
  assert_eq(inserted_keys[0], checked_keys[0])
  assert_true(inserted_keys[1] != checked_keys[1])
  assert_eq(inserted_keys[2], checked_keys[2])
}

///|
test "semantic session definition changes fall back and seed the next edit" {
  let source = "[ref]: /a \"title\"\n\nParagraph [x][ref].\n\nTail text.\n"
  let extensions = MarkdownExtensions::none()
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("semantic-session-definition"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let session = MarkdownSemanticSession(parser, extensions~)
  let initial = session.publish()
  assert_semantic_publication_matches_direct(parser, initial, extensions)
  let initial_keys = initial.top_level_revision_keys().to_array()

  let definition_position = source.find("/a").unwrap() + 1
  let changed = semantic_session_replace(source, definition_position, 1, "b")
  parser.apply_edit(
    @core.Edit::replace(
      definition_position,
      definition_position + 1,
      definition_position + 1,
    ),
    changed,
  )
  let fallback = session.publish()
  assert_semantic_publication_matches_direct(parser, fallback, extensions)
  let fallback_keys = fallback.top_level_revision_keys().to_array()
  for index, key in fallback_keys {
    assert_true(key != initial_keys[index])
  }

  let tail_position = changed.find("Tail").unwrap()
  let recovered = semantic_session_replace(changed, tail_position, 1, "S")
  parser.apply_edit(
    @core.Edit::replace(tail_position, tail_position + 1, tail_position + 1),
    recovered,
  )
  let next = session.publish()
  assert_semantic_publication_matches_direct(parser, next, extensions)
  let next_keys = next.top_level_revision_keys()
  assert_eq(next_keys[0], fallback_keys[0])
  assert_true(next_keys[next_keys.length() - 1] != fallback_keys[fallback_keys.length() - 1])
}

///|
test "semantic session diagnostics force conservative direct publications" {
  let source = "Alpha text.\n\nBeta text.\n"
  let extensions = MarkdownExtensions::none()
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("semantic-session-diagnostics"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let session = MarkdownSemanticSession(parser, extensions~)
  let initial = session.publish()
  let initial_keys = initial.top_level_revision_keys().to_array()
  let snapshot = parser.snapshot().read_or_abort()
  snapshot.diagnostics.push(
    @core.lexer_diagnostic_at(
      parser.source_id(),
      "synthetic diagnostic",
      0,
      1,
      "semantic-session-test.dirty",
    ),
  )
  let dirty = session.publish()
  let dirty_keys = dirty.top_level_revision_keys()
  for index, key in dirty_keys {
    assert_true(key != initial_keys[index])
  }
}

///|
test "semantic session direct fallback immediately seeds recovery" {
  let source = "Alpha text.\n\nBeta text.\n\nGamma text.\n"
  let extensions = MarkdownExtensions::none()
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("semantic-session-fallback-recovery"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let session = MarkdownSemanticSession(parser, extensions~)
  let initial = session.publish()
  assert_semantic_publication_matches_direct(parser, initial, extensions)

  let beta = source.find("Beta").unwrap()
  let merged_source = semantic_session_replace(source, beta - 2, 2, "")
  parser.apply_edit(@core.Edit::delete(beta - 2, beta), merged_source)
  let fallback = session.publish()
  assert_semantic_publication_matches_direct(parser, fallback, extensions)

  let gamma = merged_source.find("Gamma").unwrap()
  let recovered_source = semantic_session_replace(merged_source, gamma, 1, "K")
  parser.apply_edit(
    @core.Edit::replace(gamma, gamma + 1, gamma + 1),
    recovered_source,
  )
  let recovered = session.publish()
  assert_semantic_publication_matches_direct(parser, recovered, extensions)
}
