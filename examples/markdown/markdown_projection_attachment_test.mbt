///|
fn projection_attachment_test_parser(
  source_id : @core.SourceId,
  source : String,
) -> @loom.SyntaxParser {
  try! @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
}

///|
fn direct_block_from_syntax_parser(parser : @loom.SyntaxParser) -> Block {
  let snapshot = parser.snapshot().read_or_abort()
  experimental_markdown_ir_to_block(
    experimental_markdown_ir_from_syntax_with_diagnostics(
      parser.source_id(),
      snapshot.syntax,
      snapshot.diagnostics,
    ),
  )
}

///|
fn fresh_direct_block(source_id : @core.SourceId, source : String) -> Block {
  direct_block_from_syntax_parser(
    projection_attachment_test_parser(source_id, source),
  )
}

///|
test "markdown projection attachment matches the direct Block adapter" {
  let source_id = @core.SourceId("markdown-projection-attachment-initial")
  let parser = projection_attachment_test_parser(
    source_id, "# heading [ref]\n\nparagraph\n\n[ref]: /url \"title\"\n",
  )
  let attachment = attach_markdown_projection(parser)
  assert_eq(attachment.projection(), direct_block_from_syntax_parser(parser))
  attachment.dispose()
}

///|
test "markdown projection attachment stays in parity across edit and reversal" {
  let source_id = @core.SourceId("markdown-projection-attachment-edit")
  let source = "alpha [x]\n\nbeta\n\n[x]: /one\n"
  let updated = "alpha [x]\n\nBETA\n\n[x]: /two\n"
  let parser = projection_attachment_test_parser(source_id, source)
  let attachment = attach_markdown_projection(parser)
  parser.apply_edit(
    @core.Edit::new(0, source.length(), updated.length()),
    updated,
  )
  assert_eq(attachment.projection(), direct_block_from_syntax_parser(parser))
  attachment.collect()
  assert_eq(attachment.projection(), direct_block_from_syntax_parser(parser))
  parser.apply_edit(
    @core.Edit::new(0, updated.length(), source.length()),
    source,
  )
  assert_eq(attachment.projection(), direct_block_from_syntax_parser(parser))
  attachment.dispose()
}

///|
test "markdown projection attachment matches fresh Block families and recovery" {
  let fixtures = [
    ("# heading [x]\n\n[x]: /one\n", "## heading [x]\n\n[x]: /two\n"),
    ("> quote\n\n- first\n- second\n", "> changed\n\n1. first\n2. second\n"),
    ("```mbt\nlet x = 1\n```\n", "~~~mbt\nlet answer = 42\n~~~\n"),
    ("# prefix\n\n[unclosed\n", "# prefix\n\n[changed!\n"),
  ]
  for index, fixture in fixtures {
    let (source, updated) = fixture
    let source_id = @core.SourceId(
      "markdown-projection-attachment-family-" + index.to_string(),
    )
    let parser = projection_attachment_test_parser(source_id, source)
    let attachment = attach_markdown_projection(parser)
    parser.apply_edit(
      @core.Edit::new(0, source.length(), updated.length()),
      updated,
    )
    assert_eq(attachment.projection(), fresh_direct_block(source_id, updated))
    parser.apply_edit(
      @core.Edit::new(0, updated.length(), source.length()),
      source,
    )
    assert_eq(attachment.projection(), fresh_direct_block(source_id, source))
    attachment.dispose()
  }
}

///|
test "markdown projection attachment disposal is idempotent" {
  let parser = projection_attachment_test_parser(
    @core.SourceId("markdown-projection-attachment-dispose"),
    "# heading\n",
  )
  let attachment = attach_markdown_projection(parser)
  ignore(attachment.projection())
  attachment.dispose()
  attachment.dispose()
  ignore(direct_block_from_syntax_parser(parser))
}

///|
test "markdown projection attachment returns detached Block values" {
  let parser = projection_attachment_test_parser(
    @core.SourceId("markdown-projection-attachment-detached"),
    "# heading\n\nparagraph\n",
  )
  let attachment = attach_markdown_projection(parser)
  match attachment.projection() {
    Document(children) => ignore(children.pop())
    _ => fail("expected a document projection")
  }
  assert_eq(attachment.projection(), direct_block_from_syntax_parser(parser))
  attachment.dispose()
}
