// Reactive Markdown lowering observation benchmarks.
//
// These fixtures compare three consumers over the same syntax-only parser:
//
// - coarse/full: lower the complete document after each edit;
// - keyed/full: reuse per-block lowering, then materialize every block; and
// - keyed/sparse: lower and observe only the edited block.
//
// Each reported iteration contains a forward one-code-unit edit, an observed
// read, the reverse edit, and a second observed read.
//
// The MarkdownIR projection intentionally adapts each local IR block to the
// position-independent legacy `Block` result. It proves the cost opportunity
// for independent paragraph blocks; it does not claim that block-relative IR
// origins or document-wide reference definitions are production-correct.

///|
priv enum ReactiveLoweringObservation {
  CoarseFull
  KeyedFull
  KeyedSparse
}

///|
priv enum ReactiveLoweringProjection {
  DirectBlockProjection
  MarkdownIrToBlockProjection
}

///|
priv struct ReactiveLoweringFixture {
  parser : @loom.SyntaxParser
  scope : @incr.Scope
  watch : @incr.Watch[Block]
  source : String
  edited : String
  edit : @core.Edit
}

///|
fn reactive_lowering_document(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for i = 0; i < block_count; i = i + 1 {
    out.write_string(
      "Paragraph \{i} contains marker_\{i}, *emphasis*, **strong text**, and `code`.\n\n",
    )
  }
  out.to_string()
}

///|
fn reactive_lowering_find(source : String, target : String) -> Int {
  for i = 0; i < source.length() - target.length() + 1; i = i + 1 {
    if source[i:i + target.length()].to_owned() == target {
      return i
    }
  }
  -1
}

///|
fn reactive_lowering_replace_at(
  source : String,
  position : Int,
  replacement : String,
) -> String {
  source[:position].to_owned() + replacement + source[position + 1:].to_owned()
}

///|
fn reactive_lowering_edit_fixture(
  block_count : Int,
) -> (String, String, @core.Edit, Int) {
  let source = reactive_lowering_document(block_count)
  let selected_block = block_count / 2
  let target = "marker_\{selected_block}"
  let position = reactive_lowering_find(source, target)
  guard position >= 0 else { abort("reactive lowering edit target not found") }
  let edited = reactive_lowering_replace_at(source, position, "M")
  (
    source,
    edited,
    @core.Edit::replace(position, position + 1, position + 1),
    selected_block,
  )
}

///|
fn reactive_lowering_is_document_block(node : @seam.SyntaxNode) -> Bool {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    HeadingNode
    | ParagraphNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode
    | ErrorNode => true
    _ => false
  }
}

///|
fn reactive_lowering_block_keys(
  root : @seam.SyntaxNode,
) -> Array[@seam.CstNode] {
  root
  .children()
  .iter()
  .filter(node => reactive_lowering_is_document_block(node))
  .map(node => node.cst_node())
  .collect()
}

///|
fn reactive_lowering_coarse_terminal(
  scope : @incr.Scope,
  syntax : @incr.Derived[@seam.SyntaxNode],
  projection : ReactiveLoweringProjection,
) -> @incr.Derived[Block] {
  match projection {
    DirectBlockProjection => {
      // Match `@loom.Parser[Block]`: `build_imperative_language` constructs
      // one `CstFold` and preserves its cache across parser revisions.
      let fold = @core.CstFold::new(markdown_fold_node)
      scope.derived(
        () => fold.fold(syntax.get_or_abort()),
        label="markdown.reactive_lowering.block.coarse_full",
      )
    }
    MarkdownIrToBlockProjection =>
      scope.derived(
        () => {
          experimental_markdown_ir_to_block(
            experimental_markdown_ir_from_syntax(
              @core.SourceId("markdown-reactive-lowering-benchmark"),
              syntax.get_or_abort(),
            ),
          )
        },
        label="markdown.reactive_lowering.markdown_ir.coarse_full",
      )
  }
}

///|
fn reactive_lowering_keyed_terminal(
  scope : @incr.Scope,
  syntax : @incr.Derived[@seam.SyntaxNode],
  observation : ReactiveLoweringObservation,
  selected_block : Int,
  projection : ReactiveLoweringProjection,
) -> @incr.Derived[Block] {
  let keys = scope.derived(
    () => reactive_lowering_block_keys(syntax.get_or_abort()),
    label="markdown.reactive_lowering.block_keys",
  )
  let lowered = scope.derived_map(
    (key : @seam.CstNode) => {
      let local_root = @seam.SyntaxNode::from_cst(key)
      match projection {
        DirectBlockProjection => {
          let fold = @core.CstFold::new(markdown_fold_node)
          fold.fold(local_root)
        }
        MarkdownIrToBlockProjection =>
          experimental_markdown_ir_to_block(
            experimental_markdown_ir_from_syntax(
              @core.SourceId("markdown-reactive-lowering-benchmark"),
              local_root,
            ),
          )
      }
    },
    label="markdown.reactive_lowering.lowered_by_block",
  )
  match observation {
    KeyedFull =>
      scope.derived(
        () => {
          let blocks = keys.get_or_abort().map(key => lowered.get_or_abort(key))
          Block::Document(blocks)
        },
        label="markdown.reactive_lowering.keyed_full",
      )
    KeyedSparse =>
      scope.derived(
        () => {
          let current_keys = keys.get_or_abort()
          guard selected_block < current_keys.length() else {
            abort("reactive lowering selected block is out of range")
          }
          lowered.get_or_abort(current_keys[selected_block])
        },
        label="markdown.reactive_lowering.keyed_sparse",
      )
    CoarseFull => abort("coarse observation must use the coarse terminal")
  }
}

///|
fn reactive_lowering_fixture(
  block_count : Int,
  observation : ReactiveLoweringObservation,
  projection : ReactiveLoweringProjection,
) -> ReactiveLoweringFixture {
  let (source, edited, edit, selected_block) = reactive_lowering_edit_fixture(
    block_count,
  )
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-reactive-lowering-benchmark"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let scope = @incr.Scope::new(parser.runtime())
  let syntax = parser.syntax_tree()
  let terminal = match observation {
    CoarseFull => reactive_lowering_coarse_terminal(scope, syntax, projection)
    KeyedFull | KeyedSparse =>
      reactive_lowering_keyed_terminal(
        scope, syntax, observation, selected_block, projection,
      )
  }
  let watch = scope.add_watch(terminal.watch())
  ignore(watch.read_or_abort())
  parser.runtime().gc()
  { parser, scope, watch, source, edited, edit }
}

///|
fn ReactiveLoweringFixture::read(self : ReactiveLoweringFixture) -> Block {
  self.watch.read_or_abort()
}

///|
fn ReactiveLoweringFixture::apply_forward(
  self : ReactiveLoweringFixture,
) -> Unit {
  self.parser.apply_edit(self.edit, self.edited)
}

///|
fn ReactiveLoweringFixture::apply_reverse(
  self : ReactiveLoweringFixture,
) -> Unit {
  self.parser.apply_edit(self.edit, self.source)
}

///|
fn ReactiveLoweringFixture::dispose(self : ReactiveLoweringFixture) -> Unit {
  self.scope.dispose()
}

///|
fn bench_reactive_lowering_observation(
  b : @bench.T,
  block_count : Int,
  observation : ReactiveLoweringObservation,
  projection : ReactiveLoweringProjection,
) -> Unit {
  let fixture = reactive_lowering_fixture(block_count, observation, projection)
  b.bench(() => {
    fixture.apply_forward()
    b.keep(fixture.read())
    fixture.apply_reverse()
    b.keep(fixture.read())
  })
  fixture.dispose()
}

///|
test "reactive lowering: Block keyed full matches coarse full across an edit" {
  let coarse = reactive_lowering_fixture(100, CoarseFull, DirectBlockProjection)
  let keyed = reactive_lowering_fixture(100, KeyedFull, DirectBlockProjection)
  inspect(keyed.read() == coarse.read(), content="true")
  coarse.apply_forward()
  keyed.apply_forward()
  inspect(keyed.read() == coarse.read(), content="true")
  coarse.dispose()
  keyed.dispose()
}

///|
test "reactive lowering: MarkdownIR keyed full matches coarse full across an edit" {
  let coarse = reactive_lowering_fixture(
    100,
    CoarseFull,
    MarkdownIrToBlockProjection,
  )
  let keyed = reactive_lowering_fixture(
    100,
    KeyedFull,
    MarkdownIrToBlockProjection,
  )
  inspect(keyed.read() == coarse.read(), content="true")
  coarse.apply_forward()
  keyed.apply_forward()
  inspect(keyed.read() == coarse.read(), content="true")
  coarse.dispose()
  keyed.dispose()
}

///|
test "reactive lowering: Block CstFold coarse full cycle 100 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(b, 100, CoarseFull, DirectBlockProjection)
}

///|
test "reactive lowering: Block DerivedMap full cycle 100 blocks" (b : @bench.T) {
  bench_reactive_lowering_observation(b, 100, KeyedFull, DirectBlockProjection)
}

///|
test "reactive lowering: Block DerivedMap sparse cycle 100 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    100,
    KeyedSparse,
    DirectBlockProjection,
  )
}

///|
test "reactive lowering: Block CstFold coarse full cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    2500,
    CoarseFull,
    DirectBlockProjection,
  )
}

///|
test "reactive lowering: Block DerivedMap full cycle 2500 blocks" (b : @bench.T) {
  bench_reactive_lowering_observation(b, 2500, KeyedFull, DirectBlockProjection)
}

///|
test "reactive lowering: Block DerivedMap sparse cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    2500,
    KeyedSparse,
    DirectBlockProjection,
  )
}

///|
test "reactive lowering: MarkdownIR coarse full cycle 100 blocks" (b : @bench.T) {
  bench_reactive_lowering_observation(
    b,
    100,
    CoarseFull,
    MarkdownIrToBlockProjection,
  )
}

///|
test "reactive lowering: MarkdownIR DerivedMap full cycle 100 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    100,
    KeyedFull,
    MarkdownIrToBlockProjection,
  )
}

///|
test "reactive lowering: MarkdownIR DerivedMap sparse cycle 100 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    100,
    KeyedSparse,
    MarkdownIrToBlockProjection,
  )
}

///|
test "reactive lowering: MarkdownIR coarse full cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    2500,
    CoarseFull,
    MarkdownIrToBlockProjection,
  )
}

///|
test "reactive lowering: MarkdownIR DerivedMap full cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    2500,
    KeyedFull,
    MarkdownIrToBlockProjection,
  )
}

///|
test "reactive lowering: MarkdownIR DerivedMap sparse cycle 2500 blocks" (
  b : @bench.T,
) {
  bench_reactive_lowering_observation(
    b,
    2500,
    KeyedSparse,
    MarkdownIrToBlockProjection,
  )
}
