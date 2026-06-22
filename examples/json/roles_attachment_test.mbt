///|
test "json role spans attachment matches pure initial projection" {
  let source = "{ \"name\": \"Alice\" }"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let attachment = attach_json_role_spans(parser)
  let expected = project_json_roles(parser.syntax_tree().read_or_abort())
  guard attachment.spans() == expected else {
    fail("expected attached role spans to match pure projection")
  }
  attachment.dispose()
}

///|
test "json role spans attachment updates after syntax parser edit" {
  let source = "{ \"name\": \"Alice\" }"
  let updated = "{ \"name\": \"Bob\" }"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let attachment = attach_json_role_spans(parser)
  parser.apply_edit(@core.Edit::new(11, 5, 3), updated)
  let fresh_parser = @loom.new_syntax_parser(
    updated,
    json_grammar.to_syntax_grammar(),
  )
  let expected = project_json_roles(fresh_parser.syntax_tree().read_or_abort())
  guard attachment.spans() == expected else {
    fail("expected attached role spans to update after SyntaxParser.apply_edit")
  }
  attachment.dispose()
}

///|
test "json role spans attachment survives parser runtime gc" {
  let source = "{ \"name\": \"Alice\" }"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let attachment = attach_json_role_spans(parser)
  parser.runtime().gc()
  let fresh_parser = @loom.new_syntax_parser(
    source,
    json_grammar.to_syntax_grammar(),
  )
  let expected = project_json_roles(fresh_parser.syntax_tree().read_or_abort())
  guard attachment.spans() == expected else {
    fail("expected attached role spans to remain reachable after runtime gc")
  }
  attachment.dispose()
}

///|
test "json role spans attachment exports editor-neutral spans" {
  let source = "{\"a\": [\"x\", 1]}"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let attachment = attach_json_role_spans(parser)
  let expected = export_json_role_spans(
    project_json_roles(parser.syntax_tree().read_or_abort()),
  )
  guard attachment.export_spans() == expected else {
    fail("expected attachment export spans to match exported pure projection")
  }
  inspect(parser.diagnostics().read_or_abort().is_empty(), content="true")
  attachment.dispose()
}

///|
test "json role spans attachment keeps diagnostics parser-owned" {
  let source = "{\"a\" 1}"
  let parser = @loom.new_syntax_parser(source, json_grammar.to_syntax_grammar())
  let attachment = attach_json_role_spans(parser)
  let spans = attachment.spans()
  let exported = attachment.export_spans()
  let diagnostics = parser.diagnostics().read_or_abort()
  guard diagnostics.length() > 0 else {
    fail("expected malformed JSON diagnostics to remain on parser")
  }
  guard spans.any(span => span.role() == Error) else {
    fail("expected attachment to surface recovered syntax as error role spans")
  }
  guard exported.any(span => span.role() == "error") else {
    fail("expected exported spans to surface recovered syntax as error role")
  }
  attachment.dispose()
}
