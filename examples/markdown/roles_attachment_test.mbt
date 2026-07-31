///|
test "markdown role attachment matches pure initial projection" {
  let source_id = @core.SourceId("markdown-role-attachment-initial")
  let source = "# Hello\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  let expected = project_markdown_roles(parser.syntax_tree().read_or_abort())
  guard attachment.spans() == expected else {
    fail("expected attached spans to match pure projection")
  }
  attachment.dispose()
}

///|
test "markdown role attachment updates after syntax parser edit" {
  let source_id = @core.SourceId("markdown-role-attachment-edit")
  let source = "# Hello\n"
  let updated = "# World\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  parser.apply_edit(@core.Edit::new(2, 5, 5), updated)
  let fresh_parser = @loom.new_syntax_parser(
    source_id,
    updated,
    markdown_grammar.to_syntax_grammar(),
  )
  let expected = project_markdown_roles(
    fresh_parser.syntax_tree().read_or_abort(),
  )
  guard attachment.spans() == expected else {
    fail("expected attached spans to update after parser edit")
  }
  attachment.dispose()
}

///|
test "markdown role attachment survives parser runtime gc" {
  let source_id = @core.SourceId("markdown-role-attachment-gc")
  let source = "`code`\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  parser.runtime().gc()
  let expected = project_markdown_roles(parser.syntax_tree().read_or_abort())
  guard attachment.spans() == expected else {
    fail("expected attached spans to remain reachable after runtime gc")
  }
  attachment.dispose()
}

///|
test "markdown role attachment exports pure spans" {
  let source_id = @core.SourceId("markdown-role-attachment-export")
  let source = "[text](page_(C).html)\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  let expected = export_markdown_role_spans(
    project_markdown_roles(parser.syntax_tree().read_or_abort()),
  )
  guard export_markdown_role_spans(attachment.spans()) == expected else {
    fail("expected attachment exports to match pure projection")
  }
  attachment.dispose()
}

///|
test "markdown role attachment leaves unmatched emphasis as ordinary text" {
  let source_id = @core.SourceId("markdown-role-attachment-unmatched-emphasis")
  let source = "**unclosed\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  let expected : Array[(MarkdownRole, Int, Int)] = []
  guard markdown_test_observations(attachment.spans()) == expected else {
    fail("expected no attached recovery role for literal unmatched emphasis")
  }
  attachment.dispose()
}

///|
test "markdown role attachment leaves diagnostics parser-owned" {
  let source_id = @core.SourceId("markdown-role-attachment-parser-diagnostics")
  let source = "**unclosed\n"
  let updated = "**changed\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let before = parser.diagnostics().read_or_abort().format()
  let attachment = attach_markdown_role_spans(parser)
  ignore(attachment.spans())
  ignore(export_markdown_role_spans(attachment.spans()))
  let after_attach = parser.diagnostics().read_or_abort().format()
  guard before == after_attach else {
    fail("expected role attachment reads not to change diagnostics")
  }
  parser.apply_edit(@core.Edit::new(2, 8, 7), updated)
  let fresh_parser = @loom.new_syntax_parser(
    source_id,
    updated,
    markdown_grammar.to_syntax_grammar(),
  )
  let edited = parser.diagnostics().read_or_abort().format()
  let fresh = fresh_parser.diagnostics().read_or_abort().format()
  guard edited == fresh else {
    fail("expected edited diagnostics to match a fresh parser")
  }
  attachment.dispose()
}

///|
test "markdown role attachment returns defensive span copies" {
  let source_id = @core.SourceId("markdown-role-attachment-defensive-copy")
  let source = "# Hello\n"
  let parser = @loom.new_syntax_parser(
    source_id,
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  let copy = attachment.spans()
  ignore(copy.pop())
  let expected = project_markdown_roles(parser.syntax_tree().read_or_abort())
  guard attachment.spans() == expected else {
    fail("expected attachment spans to be defensive copies")
  }
  attachment.dispose()
}

///|
test "markdown role attachment disposal is idempotent" {
  let source_id = @core.SourceId("markdown-role-attachment-dispose")
  let parser = @loom.new_syntax_parser(
    source_id,
    "# Hello\n",
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_role_spans(parser)
  attachment.dispose()
  attachment.dispose()
}
