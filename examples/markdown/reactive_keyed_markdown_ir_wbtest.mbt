///|
fn reactive_keyed_markdown_test_parser(
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
fn direct_markdown_ir_from_syntax_parser(
  parser : @loom.SyntaxParser,
) -> MarkdownIR {
  let snapshot = parser.snapshot().read_or_abort()
  experimental_markdown_ir_from_syntax_with_diagnostics(
    parser.source_id(),
    snapshot.syntax,
    snapshot.diagnostics,
  )
}

///|
fn assert_reactive_keyed_full_replacement_matches_direct(
  source : String,
  updated : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-reactive-keyed-replacement")
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_reactive_keyed_markdown_ir(parser)
  parser.apply_edit(
    @core.Edit::new(0, source.length(), updated.length()),
    updated,
  )
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  parser.apply_edit(
    @core.Edit::new(0, updated.length(), source.length()),
    source,
  )
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: initial value matches direct lowering" {
  let source_id = @core.SourceId("markdown-reactive-keyed-initial")
  let parser = reactive_keyed_markdown_test_parser(
    source_id, "# heading [ref]\n\nparagraph\n\n[ref]: /url \"title\"\n",
  )
  let shell = attach_reactive_keyed_markdown_ir(parser)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: root CST discriminator preserves exact fallback" {
  let parser = reactive_keyed_markdown_test_parser(
    @core.SourceId("markdown-reactive-keyed-discriminator"),
    "paragraph\n",
  )
  let snapshot = parser.snapshot().read_or_abort()
  let root_cst = reactive_markdown_document_root(snapshot.syntax).cst
  let whole = MarkdownIROrigin::MarkdownIROrigin(start=0, end=10)
  let prefix = MarkdownIROrigin::MarkdownIROrigin(start=0, end=9)
  let whole_layout : ReactiveMarkdownDocumentLayout = {
    root_cst,
    origin: whole,
    blocks: [],
  }
  let prefix_layout : ReactiveMarkdownDocumentLayout = {
    root_cst,
    origin: prefix,
    blocks: [],
  }
  assert_false(whole_layout == prefix_layout)
  let whole_document : ReactiveMarkdownDocument = {
    root_cst,
    value: MarkdownIR::document([], whole),
  }
  let prefix_document : ReactiveMarkdownDocument = {
    root_cst,
    value: MarkdownIR::document([], prefix),
  }
  assert_false(whole_document == prefix_document)
}

///|
test "reactive keyed MarkdownIR: local edit recomputes one structural block" {
  let source_id = @core.SourceId("markdown-reactive-keyed-local-edit")
  let source = "alpha\n\nbeta\n\ngamma\n"
  let updated = "alpha\n\nBETA\n\ngamma\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  shell.reset_counters()
  parser.apply_edit(@core.Edit::new(7, 11, 11), updated)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 1,
    label_projection: 0,
    block_resolution: 1,
    placement: 3,
    contextual_fallback: 0,
  })
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: definition edit resolves only matching labels" {
  let source_id = @core.SourceId("markdown-reactive-keyed-definition-edit")
  let source = "[x]\n\n[y]\n\n[x]: /one\n[y]: /two\n"
  let updated = "[x]\n\n[y]\n\n[x]: /uno\n[y]: /two\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  shell.reset_counters()
  parser.apply_edit(@core.Edit::new(15, 19, 19), updated)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 0,
    label_projection: 2,
    block_resolution: 1,
    placement: 2,
    contextual_fallback: 0,
  })
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: definition add and remove reuse local plans" {
  let source_id = @core.SourceId(
    "markdown-reactive-keyed-definition-transition",
  )
  let source = "[target]\n"
  let updated = source + "\n[target]: /url\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  shell.reset_counters()
  parser.apply_edit(
    @core.Edit::new(source.length(), source.length(), updated.length()),
    updated,
  )
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 0,
    label_projection: 1,
    block_resolution: 1,
    placement: 1,
    contextual_fallback: 0,
  })
  shell.reset_counters()
  parser.apply_edit(
    @core.Edit::new(source.length(), updated.length(), source.length()),
    source,
  )
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 0,
    label_projection: 1,
    block_resolution: 1,
    placement: 1,
    contextual_fallback: 0,
  })
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: dense shared label resolves every dependent key" {
  let source_id = @core.SourceId("markdown-reactive-keyed-dense-label")
  let source = "first [x]\n\nsecond [x]\n\n[x]: /one\n"
  let updated = "first [x]\n\nsecond [x]\n\n[x]: /two\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  shell.reset_counters()
  parser.apply_edit(@core.Edit::new(28, 32, 32), updated)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 0,
    label_projection: 1,
    block_resolution: 2,
    placement: 2,
    contextual_fallback: 0,
  })
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: prepend reuses existing local plans" {
  let source_id = @core.SourceId("markdown-reactive-keyed-prepend")
  let source = "one\n\ntwo\n"
  let updated = "prep\n\none\n\ntwo\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  shell.reset_counters()
  parser.apply_edit(@core.Edit::new(0, 0, 6), updated)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 1,
    label_projection: 0,
    block_resolution: 1,
    placement: 3,
    contextual_fallback: 0,
  })
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: malformed edit takes live contextual fallback" {
  let source_id = @core.SourceId("markdown-reactive-keyed-contextual")
  let source = "# prefix\n\n[unclosed\n"
  let updated = "# prefix\n\n[changed!\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  shell.reset_counters()
  parser.apply_edit(@core.Edit::new(11, 19, 19), updated)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot(), {
    local_lowering: 1,
    label_projection: 0,
    block_resolution: 1,
    placement: 2,
    contextual_fallback: 1,
  })
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: contextual recovery remains available after gc" {
  let source_id = @core.SourceId("markdown-reactive-keyed-contextual-after-gc")
  let source = "ok\n"
  let updated = "[unclosed\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_instrumented_reactive_keyed_markdown_ir(parser)
  ignore(shell.collect_stale())
  shell.reset_counters()
  parser.apply_edit(
    @core.Edit::new(0, source.length(), updated.length()),
    updated,
  )
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.counter_snapshot().contextual_fallback, 1)
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: returned document survives later edit and gc" {
  let source_id = @core.SourceId("markdown-reactive-keyed-retained-document")
  let source = "alpha\n\nbeta\n"
  let updated = "alpha\n\nBETA\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_reactive_keyed_markdown_ir(parser)
  let retained = shell.read()
  let expected = direct_markdown_ir_from_syntax_parser(parser)
  parser.apply_edit(@core.Edit::new(7, 11, 11), updated)
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  ignore(shell.collect_stale())
  assert_eq(retained, expected)
  shell.dispose()
}

///|
test "reactive keyed MarkdownIR: block family replacements match direct lowering" {
  let fixtures = [
    ("> quote\n\n- first\n- second\n", "> changed\n\n1. first\n2. second\n"),
    ("```mbt\nlet x = 1\n```\n", "```mbt\nlet answer = 42\n```\n"),
    ("<div>before</div>\n", "<section>after</section>\n"),
    ("# prefix\n\n[unclosed\n", "# prefix\n\n[changed!\n"),
  ]
  for fixture in fixtures {
    let (source, updated) = fixture
    assert_reactive_keyed_full_replacement_matches_direct(source, updated)
  }
}

///|
test "reactive keyed MarkdownIR: gc and sweep retire dead keyed generations" {
  let source_id = @core.SourceId("markdown-reactive-keyed-sweep")
  let source = "keep [x]\n\n[x]: /x\n"
  let parser = reactive_keyed_markdown_test_parser(source_id, source)
  let shell = attach_reactive_keyed_markdown_ir(parser)
  for index = 0; index < 5; index = index + 1 {
    let label = "y" + index.to_string()
    let updated = source + "\ntemp [" + label + "]\n\n[" + label + "]: /y\n"
    parser.apply_edit(
      @core.Edit::new(source.length(), source.length(), updated.length()),
      updated,
    )
    ignore(shell.read())
    parser.apply_edit(
      @core.Edit::new(source.length(), updated.length(), source.length()),
      source,
    )
    ignore(shell.read())
  }
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  assert_eq(shell.collect_stale(), {
    resolved: { before: 6, removed: 5, after: 1 },
    plan: { before: 6, removed: 5, after: 1 },
    definition: { before: 6, removed: 5, after: 1 },
  })
  assert_eq(shell.read(), direct_markdown_ir_from_syntax_parser(parser))
  shell.dispose()
}
