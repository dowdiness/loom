// PROTOTYPE benchmark — exact placed MarkdownIR materialization.
//
// Unlike `reactive_lowering_benchmark_test.mbt`, the keyed full path returns
// the complete MarkdownIR with absolute origins. Reference definitions are an
// explicit whole-table dependency: ordinary edits can backdate an unchanged
// snapshot, while a definition edit conservatively invalidates every block.

///|
priv enum PrototypeIrObservation {
  PrototypeIrCoarseFull
  PrototypeIrKeyedFull
}

///|
priv enum PrototypeIrEditKind {
  PrototypeIrSameLengthEdit
  PrototypeIrPrependBlock
  PrototypeIrReferenceDefinitionEdit
}

///|
priv struct PrototypeIrEditCycle {
  source : String
  edited : String
  forward : @core.Edit
  reverse : @core.Edit
}

///|
priv struct PrototypeBlockPlacement {
  cst : @seam.CstNode
  start : Int
} derive(Eq)

///|
priv struct PrototypeDocumentLayout {
  placements : Array[PrototypeBlockPlacement]
  origin : MarkdownIROrigin
} derive(Eq)

///|
priv struct PrototypeReactiveIrFixture {
  parser : @loom.SyntaxParser
  scope : @incr.Scope
  watch : @incr.Watch[MarkdownIR]
  cycle : PrototypeIrEditCycle
}

///|
priv struct PrototypeSemanticDefinitionFixture {
  scope : @incr.Scope
  definitions : @incr.Input[PrototypeDefinitionSnapshot]
  before : PrototypeDefinitionSnapshot
  after : PrototypeDefinitionSnapshot
  watch : @incr.Watch[MarkdownIR]
  expected_before : MarkdownIR
  expected_after : MarkdownIR
}

///|
fn prototype_ir_benchmark_document(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for i = 0; i < block_count; i = i + 1 {
    out.write_string(
      "Paragraph \{i} contains marker_\{i}, *emphasis*, **strong text**, and `code`.\n\n",
    )
  }
  out.to_string()
}

///|
fn prototype_ir_reference_document(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  out.write_string("[target]: /before\n\n")
  for i = 0; i < block_count; i = i + 1 {
    out.write_string("Paragraph \{i} uses [target].\n\n")
  }
  out.to_string()
}

///|
fn prototype_ir_benchmark_find(source : String, target : String) -> Int {
  for i = 0; i < source.length() - target.length() + 1; i = i + 1 {
    if source[i:i + target.length()].to_owned() == target {
      return i
    }
  }
  -1
}

///|
fn prototype_ir_edit_cycle(
  block_count : Int,
  edit_kind : PrototypeIrEditKind,
) -> PrototypeIrEditCycle {
  match edit_kind {
    PrototypeIrSameLengthEdit => {
      let source = prototype_ir_benchmark_document(block_count)
      let selected = block_count / 2
      let position = prototype_ir_benchmark_find(source, "marker_\{selected}")
      guard position >= 0 else { abort("prototype edit target not found") }
      let edit = @core.Edit::replace(position, position + 1, position + 1)
      {
        source,
        edited: source[:position].to_owned() +
        "M" +
        source[position + 1:].to_owned(),
        forward: edit,
        reverse: edit,
      }
    }
    PrototypeIrPrependBlock => {
      let source = prototype_ir_benchmark_document(block_count)
      let prefix = "# Prepended heading\n\n"
      {
        source,
        edited: prefix + source,
        forward: @core.Edit::replace(0, 0, prefix.length()),
        reverse: @core.Edit::replace(0, prefix.length(), 0),
      }
    }
    PrototypeIrReferenceDefinitionEdit => {
      let source = prototype_ir_reference_document(block_count)
      let before = "/before"
      let after = "/afterx"
      let position = prototype_ir_benchmark_find(source, before)
      guard position >= 0 else {
        abort("prototype reference definition edit target not found")
      }
      let edit = @core.Edit::replace(
        position,
        position + before.length(),
        position + after.length(),
      )
      {
        source,
        edited: source[:position].to_owned() +
        after +
        source[position + before.length():].to_owned(),
        forward: edit,
        reverse: edit,
      }
    }
  }
}

///|
fn prototype_document_layout(
  syntax : @seam.SyntaxNode,
) -> PrototypeDocumentLayout {
  let root = syntax_root(syntax)
  let placements : Array[PrototypeBlockPlacement] = []
  for child in root.children() {
    if prototype_is_document_block(child) {
      placements.push({ cst: child.cst_node(), start: child.start() })
    }
  }
  { placements, origin: origin_from_node(root) }
}

///|
fn prototype_ir_coarse_terminal(
  scope : @incr.Scope,
  syntax : @incr.Derived[@seam.SyntaxNode],
) -> @incr.Derived[MarkdownIR] {
  scope.derived(
    () => {
      experimental_markdown_ir_from_syntax(
        @core.SourceId("markdown-local-raw-block-benchmark"),
        syntax.get_or_abort(),
      )
    },
    label="markdown.prototype_ir.coarse_full",
  )
}

///|
fn prototype_ir_keyed_terminal(
  scope : @incr.Scope,
  syntax : @incr.Derived[@seam.SyntaxNode],
) -> @incr.Derived[MarkdownIR] {
  let layout = scope.derived(
    () => prototype_document_layout(syntax.get_or_abort()),
    label="markdown.prototype_ir.layout",
  )
  let definitions = scope.derived(
    () => prototype_definition_snapshot(syntax.get_or_abort()),
    label="markdown.prototype_ir.reference_definitions",
  )
  let lowered = scope.derived_map(
    (cst : @seam.CstNode) => {
      let current_definitions = definitions.get_or_abort()
      prototype_lower_local_raw_block(
        @core.SourceId("markdown-local-raw-block-benchmark"),
        cst,
        current_definitions.table,
      )
    },
    label="markdown.prototype_ir.local_raw_by_block",
  )
  scope.derived(
    () => {
      let current = layout.get_or_abort()
      let children = current.placements.map(placement => {
        let raw_block = lowered.get_or_abort(placement.cst)
        prototype_place_markdown_ir(raw_block.ir, placement.start)
      })
      MarkdownIR::document(children, current.origin)
    },
    label="markdown.prototype_ir.keyed_full",
  )
}

///|
fn prototype_ir_coarse_fixed_terminal(
  scope : @incr.Scope,
  layout : PrototypeDocumentLayout,
  definitions : @incr.Input[PrototypeDefinitionSnapshot],
) -> @incr.Derived[MarkdownIR] {
  scope.derived(
    () => {
      let current_definitions = definitions.get()
      let children = layout.placements.map(placement => {
        let raw_block = prototype_lower_local_raw_block(
          @core.SourceId("markdown-local-raw-block-benchmark"),
          placement.cst,
          current_definitions.table,
        )
        prototype_place_markdown_ir(raw_block.ir, placement.start)
      })
      MarkdownIR::document(children, layout.origin)
    },
    label="markdown.prototype_ir.coarse_fixed_definitions",
  )
}

///|
fn prototype_ir_keyed_fixed_terminal(
  scope : @incr.Scope,
  layout : PrototypeDocumentLayout,
  definitions : @incr.Input[PrototypeDefinitionSnapshot],
) -> @incr.Derived[MarkdownIR] {
  let lowered = scope.derived_map(
    (cst : @seam.CstNode) => {
      let current_definitions = definitions.get()
      prototype_lower_local_raw_block(
        @core.SourceId("markdown-local-raw-block-benchmark"),
        cst,
        current_definitions.table,
      )
    },
    label="markdown.prototype_ir.fixed_local_raw_by_block",
  )
  scope.derived(
    () => {
      let children = layout.placements.map(placement => {
        let raw_block = lowered.get_or_abort(placement.cst)
        prototype_place_markdown_ir(raw_block.ir, placement.start)
      })
      MarkdownIR::document(children, layout.origin)
    },
    label="markdown.prototype_ir.keyed_fixed_definitions",
  )
}

///|
fn prototype_semantic_definition_fixture(
  block_count : Int,
  observation : PrototypeIrObservation,
) -> PrototypeSemanticDefinitionFixture {
  let cycle = prototype_ir_edit_cycle(
    block_count,
    PrototypeIrReferenceDefinitionEdit,
  )
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-local-raw-block-benchmark"),
    cycle.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let edited_parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-local-raw-block-benchmark"),
    cycle.edited,
    markdown_grammar.to_syntax_grammar(),
  )
  let syntax = parser.syntax_tree().read_or_abort()
  let edited_syntax = edited_parser.syntax_tree().read_or_abort()
  let before = prototype_definition_snapshot(syntax)
  let after = prototype_definition_snapshot(edited_syntax)
  guard before != after else {
    abort("prototype definition snapshots must differ")
  }
  let layout = prototype_document_layout(syntax)
  let scope = @incr.Scope::new(parser.runtime())
  let definitions = @incr.Input::Input(
    parser.runtime(),
    before,
    label="markdown.prototype_ir.definition_input",
  )
  let terminal = match observation {
    PrototypeIrCoarseFull =>
      prototype_ir_coarse_fixed_terminal(scope, layout, definitions)
    PrototypeIrKeyedFull =>
      prototype_ir_keyed_fixed_terminal(scope, layout, definitions)
  }
  let watch = scope.add_watch(terminal.watch())
  let expected_before = experimental_markdown_ir_from_syntax(
    @core.SourceId("markdown-local-raw-block-benchmark"),
    syntax,
  )
  let expected_after = experimental_markdown_ir_from_syntax(
    @core.SourceId("markdown-local-raw-block-benchmark"),
    edited_syntax,
  )
  ignore(watch.read_or_abort())
  parser.runtime().gc()
  { scope, definitions, before, after, watch, expected_before, expected_after }
}

///|
fn PrototypeSemanticDefinitionFixture::read(
  self : PrototypeSemanticDefinitionFixture,
) -> MarkdownIR {
  self.watch.read_or_abort()
}

///|
fn PrototypeSemanticDefinitionFixture::apply_after(
  self : PrototypeSemanticDefinitionFixture,
) -> Unit {
  self.definitions.set(self.after)
}

///|
fn PrototypeSemanticDefinitionFixture::apply_before(
  self : PrototypeSemanticDefinitionFixture,
) -> Unit {
  self.definitions.set(self.before)
}

///|
fn PrototypeSemanticDefinitionFixture::dispose(
  self : PrototypeSemanticDefinitionFixture,
) -> Unit {
  self.scope.dispose()
  self.definitions.dispose()
}

///|
fn prototype_reactive_ir_fixture(
  block_count : Int,
  edit_kind : PrototypeIrEditKind,
  observation : PrototypeIrObservation,
) -> PrototypeReactiveIrFixture {
  let cycle = prototype_ir_edit_cycle(block_count, edit_kind)
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-local-raw-block-benchmark"),
    cycle.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let scope = @incr.Scope::new(parser.runtime())
  let terminal = match observation {
    PrototypeIrCoarseFull =>
      prototype_ir_coarse_terminal(scope, parser.syntax_tree())
    PrototypeIrKeyedFull =>
      prototype_ir_keyed_terminal(scope, parser.syntax_tree())
  }
  let watch = scope.add_watch(terminal.watch())
  ignore(watch.read_or_abort())
  parser.runtime().gc()
  { parser, scope, watch, cycle }
}

///|
fn PrototypeReactiveIrFixture::read(
  self : PrototypeReactiveIrFixture,
) -> MarkdownIR {
  self.watch.read_or_abort()
}

///|
fn PrototypeReactiveIrFixture::apply_forward(
  self : PrototypeReactiveIrFixture,
) -> Unit {
  self.parser.apply_edit(self.cycle.forward, self.cycle.edited)
}

///|
fn PrototypeReactiveIrFixture::apply_reverse(
  self : PrototypeReactiveIrFixture,
) -> Unit {
  self.parser.apply_edit(self.cycle.reverse, self.cycle.source)
}

///|
fn PrototypeReactiveIrFixture::dispose(
  self : PrototypeReactiveIrFixture,
) -> Unit {
  self.scope.dispose()
}

///|
fn assert_prototype_reactive_ir_matches(
  edit_kind : PrototypeIrEditKind,
) -> Unit {
  let coarse = prototype_reactive_ir_fixture(
    100,
    edit_kind,
    PrototypeIrCoarseFull,
  )
  let keyed = prototype_reactive_ir_fixture(
    100,
    edit_kind,
    PrototypeIrKeyedFull,
  )
  guard keyed.read() == coarse.read() else {
    abort("LocalRawBlock reactive prototype initial IR mismatch")
  }
  coarse.apply_forward()
  keyed.apply_forward()
  guard keyed.read() == coarse.read() else {
    abort("LocalRawBlock reactive prototype forward IR mismatch")
  }
  coarse.apply_reverse()
  keyed.apply_reverse()
  guard keyed.read() == coarse.read() else {
    abort("LocalRawBlock reactive prototype reverse IR mismatch")
  }
  coarse.dispose()
  keyed.dispose()
}

///|
fn bench_prototype_reactive_ir(
  b : @bench.T,
  edit_kind : PrototypeIrEditKind,
  observation : PrototypeIrObservation,
) -> Unit {
  let fixture = prototype_reactive_ir_fixture(2500, edit_kind, observation)
  b.bench(() => {
    fixture.apply_forward()
    b.keep(fixture.read())
    fixture.apply_reverse()
    b.keep(fixture.read())
  })
  fixture.dispose()
}

///|
fn bench_prototype_syntax_cycle(
  b : @bench.T,
  edit_kind : PrototypeIrEditKind,
) -> Unit {
  let cycle = prototype_ir_edit_cycle(2500, edit_kind)
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-local-raw-block-benchmark"),
    cycle.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let scope = @incr.Scope::new(parser.runtime())
  let watch = scope.add_watch(parser.syntax_tree().watch())
  ignore(watch.read_or_abort())
  parser.runtime().gc()
  b.bench(() => {
    parser.apply_edit(cycle.forward, cycle.edited)
    b.keep(watch.read_or_abort())
    parser.apply_edit(cycle.reverse, cycle.source)
    b.keep(watch.read_or_abort())
  })
  scope.dispose()
}

///|
fn assert_prototype_semantic_definition_matches(
  observation : PrototypeIrObservation,
) -> Unit {
  let fixture = prototype_semantic_definition_fixture(100, observation)
  guard fixture.read() == fixture.expected_before else {
    abort("semantic-only definition prototype initial IR mismatch")
  }
  fixture.apply_after()
  guard fixture.read() == fixture.expected_after else {
    abort("semantic-only definition prototype changed IR mismatch")
  }
  fixture.apply_before()
  guard fixture.read() == fixture.expected_before else {
    abort("semantic-only definition prototype restored IR mismatch")
  }
  fixture.dispose()
}

///|
fn bench_prototype_semantic_definition_cycle(
  b : @bench.T,
  observation : PrototypeIrObservation,
) -> Unit {
  let fixture = prototype_semantic_definition_fixture(2500, observation)
  b.bench(() => {
    fixture.apply_after()
    b.keep(fixture.read())
    fixture.apply_before()
    b.keep(fixture.read())
  })
  fixture.dispose()
}

///|
test "LocalRawBlock reactive prototype: same-length edit matches full IR" {
  assert_prototype_reactive_ir_matches(PrototypeIrSameLengthEdit)
}

///|
test "LocalRawBlock reactive prototype: prepend matches full IR" {
  assert_prototype_reactive_ir_matches(PrototypeIrPrependBlock)
}

///|
test "LocalRawBlock reactive prototype: reference definition edit matches full IR" {
  assert_prototype_reactive_ir_matches(PrototypeIrReferenceDefinitionEdit)
}

///|
test "LocalRawBlock semantic-only prototype: coarse definition dependency matches full IR" {
  assert_prototype_semantic_definition_matches(PrototypeIrCoarseFull)
}

///|
test "LocalRawBlock semantic-only prototype: keyed definition dependency matches full IR" {
  assert_prototype_semantic_definition_matches(PrototypeIrKeyedFull)
}

///|
test "LocalRawBlock reactive prototype: syntax same-length cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_syntax_cycle(b, PrototypeIrSameLengthEdit)
}

///|
test "LocalRawBlock reactive prototype: syntax prepend cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_syntax_cycle(b, PrototypeIrPrependBlock)
}

///|
test "LocalRawBlock reactive prototype: syntax reference definition cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_syntax_cycle(b, PrototypeIrReferenceDefinitionEdit)
}

///|
test "LocalRawBlock reactive prototype: coarse same-length cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_reactive_ir(
    b,
    PrototypeIrSameLengthEdit,
    PrototypeIrCoarseFull,
  )
}

///|
test "LocalRawBlock reactive prototype: keyed same-length cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_reactive_ir(
    b,
    PrototypeIrSameLengthEdit,
    PrototypeIrKeyedFull,
  )
}

///|
test "LocalRawBlock reactive prototype: coarse prepend cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_reactive_ir(b, PrototypeIrPrependBlock, PrototypeIrCoarseFull)
}

///|
test "LocalRawBlock reactive prototype: keyed prepend cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_reactive_ir(b, PrototypeIrPrependBlock, PrototypeIrKeyedFull)
}

///|
test "LocalRawBlock reactive prototype: coarse reference definition cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_reactive_ir(
    b,
    PrototypeIrReferenceDefinitionEdit,
    PrototypeIrCoarseFull,
  )
}

///|
test "LocalRawBlock reactive prototype: keyed reference definition cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_reactive_ir(
    b,
    PrototypeIrReferenceDefinitionEdit,
    PrototypeIrKeyedFull,
  )
}

///|
test "LocalRawBlock semantic-only prototype: coarse definition cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_semantic_definition_cycle(b, PrototypeIrCoarseFull)
}

///|
test "LocalRawBlock semantic-only prototype: keyed definition cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_prototype_semantic_definition_cycle(b, PrototypeIrKeyedFull)
}
