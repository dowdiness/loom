// Focused production-shell benchmark for #847.
//
// Each measured iteration applies one same-length edit in the middle of a
// 2,500-block document, observes the complete MarkdownIR, reverses the edit,
// and observes the complete MarkdownIR again. Parser construction, shell
// attachment, watch priming, and workload construction stay outside the timed
// body.

///|
priv struct ReactiveKeyedMarkdownIRBenchmarkInput {
  source : String
  edited : String
  edit : @core.Edit
}

///|
fn reactive_keyed_markdown_ir_benchmark_source(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for index = 0; index < block_count; index = index + 1 {
    out.write_string(
      "Paragraph \{index} contains marker_\{index}, *emphasis*, **strong text**, and `code`.\n\n",
    )
  }
  out.to_string()
}

///|
fn reactive_keyed_markdown_ir_benchmark_find(
  source : String,
  target : String,
) -> Int {
  for index = 0; index <= source.length() - target.length(); index = index + 1 {
    if source[index:index + target.length()].to_owned() == target {
      return index
    }
  }
  abort("reactive keyed MarkdownIR benchmark target not found")
}

///|
fn reactive_keyed_markdown_ir_benchmark_input(
  block_count : Int,
) -> ReactiveKeyedMarkdownIRBenchmarkInput {
  let source = reactive_keyed_markdown_ir_benchmark_source(block_count)
  let selected_block = block_count / 2
  let target = "marker_\{selected_block}"
  let position = reactive_keyed_markdown_ir_benchmark_find(source, target)
  let edited = source[:position].to_owned() +
    "M" +
    source[position + 1:].to_owned()
  {
    source,
    edited,
    edit: @core.Edit::replace(position, position + 1, position + 1),
  }
}

///|
fn reactive_keyed_markdown_ir_benchmark_loomark_input(
  unit_count : Int,
  selected_unit : Int,
) -> ReactiveKeyedMarkdownIRBenchmarkInput {
  let out = StringBuilder::StringBuilder()
  for index = 0; index < unit_count; index = index + 1 {
    out.write_string(
      "## Heading \{index}\n\nParagraph \{index} with **bold**, [link](https://example.com/\{index}), and 日本語 😀.\n\n",
    )
  }
  let source = out.to_string()
  let position = source.find("Paragraph \{selected_unit}").unwrap()
  let edited = source[:position].to_owned() +
    "Q" +
    source[position + 1:].to_owned()
  {
    source,
    edited,
    edit: @core.Edit::replace(position, position + 1, position + 1),
  }
}

///|
fn reactive_keyed_markdown_ir_benchmark_direct_read(
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
fn markdown_semantic_benchmark_direct_read(
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
fn reactive_keyed_markdown_ir_benchmark_direct_block_read(
  parser : @loom.SyntaxParser,
) -> Block {
  experimental_markdown_ir_to_block(
    reactive_keyed_markdown_ir_benchmark_direct_read(parser),
  )
}

///|
fn benchmark_reactive_keyed_markdown_ir_direct(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-reactive-keyed-benchmark-direct"),
    input.source,
    markdown_grammar.to_syntax_grammar(),
  )
  ignore(reactive_keyed_markdown_ir_benchmark_direct_read(parser))
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(reactive_keyed_markdown_ir_benchmark_direct_read(parser))
    try! parser.apply_edit(input.edit, input.source)
    b.keep(reactive_keyed_markdown_ir_benchmark_direct_read(parser))
  })
}

///|
fn benchmark_reactive_keyed_markdown_ir_shell(
  b : @bench.T,
  block_count : Int,
  instrumented : Bool,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-reactive-keyed-benchmark-shell"),
    input.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let shell = if instrumented {
    attach_instrumented_reactive_keyed_markdown_ir(parser)
  } else {
    attach_reactive_keyed_markdown_ir(parser)
  }
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(shell.read())
    try! parser.apply_edit(input.edit, input.source)
    b.keep(shell.read())
  })
  shell.dispose()
}

///|
fn benchmark_reactive_keyed_markdown_direct_block(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-reactive-keyed-benchmark-direct-block"),
    input.source,
    markdown_grammar.to_syntax_grammar(),
  )
  ignore(reactive_keyed_markdown_ir_benchmark_direct_block_read(parser))
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(reactive_keyed_markdown_ir_benchmark_direct_block_read(parser))
    try! parser.apply_edit(input.edit, input.source)
    b.keep(reactive_keyed_markdown_ir_benchmark_direct_block_read(parser))
  })
}

///|
fn benchmark_markdown_projection_attachment(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-projection-attachment-benchmark"),
    input.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let attachment = attach_markdown_projection(parser)
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(attachment.projection())
    try! parser.apply_edit(input.edit, input.source)
    b.keep(attachment.projection())
  })
  attachment.dispose()
}

///|
fn benchmark_markdown_semantic_attachment_input(
  b : @bench.T,
  input : ReactiveKeyedMarkdownIRBenchmarkInput,
  source_id : String,
) -> Unit {
  let parser = try! @loom.new_parser(
    @core.SourceId(source_id),
    input.source,
    markdown_grammar,
  )
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  ignore(attachment.document())
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(attachment.document())
    try! parser.apply_edit(input.edit, input.source)
    b.keep(attachment.document())
  })
  attachment.dispose()
}

///|
fn benchmark_markdown_semantic_attachment(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  benchmark_markdown_semantic_attachment_input(
    b,
    reactive_keyed_markdown_ir_benchmark_input(block_count),
    "markdown-semantic-attachment-benchmark",
  )
}

///|
fn benchmark_markdown_semantic_direct(b : @bench.T, block_count : Int) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_parser(
    @core.SourceId("markdown-semantic-direct-benchmark"),
    input.source,
    markdown_grammar,
  )
  ignore(markdown_semantic_benchmark_direct_read(parser))
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(markdown_semantic_benchmark_direct_read(parser))
    try! parser.apply_edit(input.edit, input.source)
    b.keep(markdown_semantic_benchmark_direct_read(parser))
  })
}

///|
fn benchmark_markdown_direct_initial_read(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_parser(
    @core.SourceId("markdown-direct-initial-read-benchmark"),
    input.source,
    markdown_grammar,
  )
  b.bench(() => b.keep(markdown_semantic_benchmark_direct_read(parser)))
}

///|
fn benchmark_markdown_syntax_direct_initial_read(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-syntax-direct-initial-read-benchmark"),
    input.source,
    markdown_grammar.to_syntax_grammar(),
  )
  b.bench(() => b.keep(reactive_keyed_markdown_ir_benchmark_direct_read(parser)))
}

///|
fn benchmark_markdown_semantic_initial_read(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_parser(
    @core.SourceId("markdown-semantic-initial-read-benchmark"),
    input.source,
    markdown_grammar,
  )
  b.bench(() => {
    let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
      parser,
    )
    b.keep(attachment.document())
    attachment.dispose()
  })
}

///|
fn benchmark_markdown_projection_initial_read(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-projection-initial-read-benchmark"),
    input.source,
    markdown_grammar.to_syntax_grammar(),
  )
  b.bench(() => {
    let attachment = attach_markdown_projection(parser)
    b.keep(attachment.projection())
    attachment.dispose()
  })
}

///|
fn benchmark_markdown_compatibility_block_parser(
  b : @bench.T,
  block_count : Int,
) -> Unit {
  let input = reactive_keyed_markdown_ir_benchmark_input(block_count)
  let parser = try! @loom.new_parser(
    @core.SourceId("markdown-compatibility-block-benchmark"),
    input.source,
    markdown_grammar,
  )
  ignore(parser.ast().read_or_abort())
  b.bench(() => {
    try! parser.apply_edit(input.edit, input.edited)
    b.keep(parser.ast().read_or_abort())
    try! parser.apply_edit(input.edit, input.source)
    b.keep(parser.ast().read_or_abort())
  })
}

///|
test "reactive keyed MarkdownIR: direct full cycle 2500 blocks" (b : @bench.T) {
  benchmark_reactive_keyed_markdown_ir_direct(b, 2500)
}

///|
test "reactive keyed MarkdownIR: shell full cycle 2500 blocks" (b : @bench.T) {
  benchmark_reactive_keyed_markdown_ir_shell(b, 2500, false)
}

///|
test "reactive keyed MarkdownIR: instrumented shell calibration 2500 blocks" (
  b : @bench.T,
) {
  benchmark_reactive_keyed_markdown_ir_shell(b, 2500, true)
}

///|
test "Markdown projection: direct IR to Block full cycle 2500 blocks" (
  b : @bench.T,
) {
  benchmark_reactive_keyed_markdown_direct_block(b, 2500)
}

///|
test "Markdown projection: keyed attachment full cycle 2500 blocks" (
  b : @bench.T,
) {
  benchmark_markdown_projection_attachment(b, 2500)
}

///|
test "Markdown projection: compatibility Block parser full cycle 2500 blocks" (
  b : @bench.T,
) {
  benchmark_markdown_compatibility_block_parser(b, 2500)
}

///|
test "Markdown semantic: keyed attachment full cycle 2500 blocks" (b : @bench.T) {
  benchmark_markdown_semantic_attachment(b, 2500)
}

///|
test "Markdown semantic: Loomark late replacement full cycle 500 blocks" (
  b : @bench.T,
) {
  benchmark_markdown_semantic_attachment_input(
    b,
    reactive_keyed_markdown_ir_benchmark_loomark_input(250, 248),
    "markdown-semantic-attachment-loomark-late-benchmark",
  )
}

///|
test "Markdown semantic: direct Parser Block full cycle 2500 blocks" (
  b : @bench.T,
) {
  benchmark_markdown_semantic_direct(b, 2500)
}

///|
test "Markdown semantic: direct initial read 2500 blocks" (b : @bench.T) {
  benchmark_markdown_direct_initial_read(b, 2500)
}

///|
test "Markdown semantic: syntax-only direct initial read 2500 blocks" (
  b : @bench.T,
) {
  benchmark_markdown_syntax_direct_initial_read(b, 2500)
}

///|
test "Markdown semantic: attachment initial read 2500 blocks" (b : @bench.T) {
  benchmark_markdown_semantic_initial_read(b, 2500)
}

///|
test "Markdown semantic: projection initial read 2500 blocks" (b : @bench.T) {
  benchmark_markdown_projection_initial_read(b, 2500)
}
