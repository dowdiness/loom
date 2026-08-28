///|
fn markdown_semantic_attachment_test_parser(
  source_id : @core.SourceId,
  source : String,
) -> @loom.Parser[Block] {
  try! @loom.new_parser(source_id, source, markdown_grammar)
}

///|
fn markdown_semantic_attachment_test_fresh_document(
  parser : @loom.Parser[Block],
) -> MarkdownIR {
  let snapshot = parser.snapshot().read_or_abort()
  experimental_markdown_ir_from_syntax_with_diagnostics(
    parser.source_id(),
    snapshot.syntax,
    snapshot.diagnostics,
  )
}

///|
fn markdown_semantic_attachment_test_fresh_source(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  markdown_semantic_attachment_test_fresh_document(
    markdown_semantic_attachment_test_parser(source_id, source),
  )
}

///|
fn markdown_semantic_attachment_test_replace_all(
  parser : @loom.Parser[Block],
  current : String,
  updated : String,
) -> Unit {
  try! parser.apply_edit(
    @core.Edit::new(0, current.length(), updated.length()),
    updated,
  )
}

///|
fn markdown_semantic_attachment_test_first_diagnostic_node(
  node : MarkdownIR,
) -> MarkdownIR? {
  if node.diagnostics().length() > 0 {
    return Some(node)
  }
  for child in node.children() {
    match markdown_semantic_attachment_test_first_diagnostic_node(child) {
      Some(found) => return Some(found)
      None => ()
    }
  }
  None
}

///|
test "Markdown semantic attachment initially matches fresh lowering" {
  let parser = markdown_semantic_attachment_test_parser(
    @core.SourceId("markdown-semantic-attachment-initial"),
    "# heading [ref]\n\nparagraph\n\n[ref]: /url \"title\"\n",
  )
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  assert_eq(
    attachment.document(),
    markdown_semantic_attachment_test_fresh_document(parser),
  )
  attachment.dispose()
}

///|
test "Markdown semantic attachment follows edits and fresh semantic lowering" {
  let source_id = @core.SourceId("markdown-semantic-attachment-edits")
  let initial = "alpha [x]\n\nbeta\n\n[x]: /one\n"
  let local_edit_source = "alpha [x]\n\nBETA\n\n[x]: /one\n"
  let structural = "> quote\n\n1. first\n2. second\n"
  let prepended = "# prefix\n\n> quote\n\n1. first\n2. second\n"
  let reference_added = "[target]\n\n[target]: /one \"title\"\n"
  let reference_changed = "[target]\n\n[target]: /two \"changed\"\n"
  let reference_duplicated = "[target]\n\n[target]: /two \"changed\"\n[target]: /ignored\n"
  let reference_removed = "[target]\n"
  let malformed = "# prefix\n\n[unclosed\n"
  let parser = markdown_semantic_attachment_test_parser(source_id, initial)
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  parser.apply_edit(@core.Edit::replace(11, 15, 15), local_edit_source)
  assert_eq(
    attachment.document(),
    markdown_semantic_attachment_test_fresh_source(source_id, local_edit_source),
  )
  markdown_semantic_attachment_test_replace_all(
    parser, local_edit_source, structural,
  )
  assert_eq(
    attachment.document(),
    markdown_semantic_attachment_test_fresh_source(source_id, structural),
  )
  parser.apply_edit(@core.Edit::new(0, 0, 10), prepended)
  assert_eq(
    attachment.document(),
    markdown_semantic_attachment_test_fresh_source(source_id, prepended),
  )
  let updates = [
    reference_added, reference_changed, reference_duplicated, reference_removed,
    malformed, initial,
  ]
  let mut current = prepended
  for updated in updates {
    markdown_semantic_attachment_test_replace_all(parser, current, updated)
    assert_eq(
      attachment.document(),
      markdown_semantic_attachment_test_fresh_source(source_id, updated),
    )
    current = updated
  }
  attachment.dispose()
}

///|
test "Markdown semantic attachment keeps opaque diagnostic arrays defensive" {
  let source_id = @core.SourceId("markdown-semantic-attachment-diagnostics")
  let source = "[text](\n"
  let parser = markdown_semantic_attachment_test_parser(source_id, source)
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  let document = attachment.document()
  let recovered = markdown_semantic_attachment_test_first_diagnostic_node(
    document,
  ).unwrap()
  let diagnostic_count = recovered.diagnostics().length()
  assert_true(diagnostic_count > 0)
  let diagnostics = recovered.diagnostics()
  ignore(diagnostics.pop())
  assert_eq(recovered.diagnostics().length(), diagnostic_count)
  assert_eq(
    attachment.document(),
    markdown_semantic_attachment_test_fresh_source(source_id, source),
  )
  attachment.dispose()
}

///|
test "Markdown semantic attachment returns retained owning documents" {
  let source_id = @core.SourceId("markdown-semantic-attachment-retained")
  let source = "# old\n\nparagraph [x]\n\n[x]: /one\n"
  let updated = "> new\n\n![image](/image \"title\")\n"
  let parser = markdown_semantic_attachment_test_parser(source_id, source)
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  let retained = attachment.document()
  let expected_retained = markdown_semantic_attachment_test_fresh_source(
    source_id, source,
  )
  let retained_children = retained.children()
  ignore(retained_children.pop())
  assert_eq(retained, expected_retained)

  markdown_semantic_attachment_test_replace_all(parser, source, updated)
  assert_eq(
    attachment.document(),
    markdown_semantic_attachment_test_fresh_source(source_id, updated),
  )
  attachment.dispose()
  attachment.dispose()

  assert_eq(retained, expected_retained)
  assert_true(retained.view() is Document)
  assert_true(retained.children().length() > 0)
  parser.set_source(source)
  assert_eq(
    markdown_semantic_attachment_test_fresh_document(parser),
    expected_retained,
  )
}

///|
test "Markdown semantic attachment source_document reads are independent" {
  let source_id = @core.SourceId("markdown-semantic-attachment-source-reads")
  let source = "# old\n\nparagraph\n"
  let updated = "> new\n\nparagraph\n"
  let parser = markdown_semantic_attachment_test_parser(source_id, source)
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  let initial_ir = attachment.document()
  let initial_source = attachment.source_document()
  let repeated_source = attachment.source_document()
  assert_eq(
    initial_ir,
    markdown_semantic_attachment_test_fresh_source(source_id, source),
  )
  assert_eq(initial_source.source(), source)
  assert_eq(repeated_source.source(), source)
  parser.set_source(updated)
  let updated_source = attachment.source_document()
  let updated_ir = attachment.document()
  assert_eq(updated_source.source(), updated)
  assert_eq(
    updated_ir,
    markdown_semantic_attachment_test_fresh_source(source_id, updated),
  )
  assert_eq(initial_source.source(), source)
  attachment.dispose()
  parser.set_source("after-disposal\n")
  assert_eq(initial_source.source(), source)
  assert_eq(repeated_source.source(), source)
  assert_eq(updated_source.source(), updated)
}

///|
test "Markdown semantic attachment disposal before first read is safe" {
  let source_id = @core.SourceId("markdown-semantic-attachment-early-dispose")
  let source = "# heading\n"
  let parser = markdown_semantic_attachment_test_parser(source_id, source)
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  attachment.dispose()
  attachment.dispose()
  parser.set_source("paragraph\n")
  assert_eq(
    markdown_semantic_attachment_test_fresh_document(parser),
    markdown_semantic_attachment_test_fresh_source(source_id, "paragraph\n"),
  )
}

///|
test "panic Markdown semantic attachment rejects reads after disposal" {
  let parser = markdown_semantic_attachment_test_parser(
    @core.SourceId("markdown-semantic-attachment-disposed-read"),
    "paragraph\n",
  )
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  attachment.dispose()
  ignore(attachment.document())
}

///|
test "panic Markdown semantic attachment rejects source_document after disposal" {
  let parser = markdown_semantic_attachment_test_parser(
    @core.SourceId("markdown-semantic-attachment-disposed-source-document"),
    "paragraph\n",
  )
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  attachment.dispose()
  ignore(attachment.source_document())
}
