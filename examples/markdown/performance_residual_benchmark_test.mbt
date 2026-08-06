// Residual deployment-target performance envelope for #838.
//
// This file extends the stage profile with the still-unmeasured scenarios:
// a roughly 10,000-line mixed document, syntax-family controls, a checked-in
// snapshot of a real project document, and localized edits distributed across
// document positions and block kinds. Timings remain informational; stable
// operation-count guards live in normal tests.

///|
priv enum PerfResidualSyntaxFamily {
  HeadingFamily
  ParagraphFamily
  ListFamily
  FencedCodeFamily
}

///|
priv struct PerfResidualEditFixture {
  source : String
  edited : String
  edit : @core.Edit
}

///|
fn perf_residual_line_count(source : String) -> Int {
  let mut count = 1
  for ch in source {
    if ch == '\n' {
      count = count + 1
    }
  }
  count
}

///|
fn perf_residual_family_doc(
  family : PerfResidualSyntaxFamily,
  line_target : Int,
) -> String {
  let out = StringBuilder::StringBuilder()
  match family {
    HeadingFamily =>
      for i = 0; i < line_target; i = i + 1 {
        out.write_string("## Heading \{i} with plain text\n")
      }
    ParagraphFamily => {
      guard line_target % 2 == 0 else {
        abort("paragraph performance line target must be even")
      }
      for i = 0; i < line_target / 2; i = i + 1 {
        out.write_string(
          "Paragraph \{i} with *emphasis*, **strong**, `code`, and [link](/u).\n\n",
        )
      }
    }
    ListFamily =>
      for i = 0; i < line_target; i = i + 1 {
        out.write_string("- Item \{i} with *emphasis* and `code`\n")
      }
    FencedCodeFamily => {
      guard line_target % 4 == 0 else {
        abort("fenced-code performance line target must be divisible by four")
      }
      for i = 0; i < line_target / 4; i = i + 1 {
        out.write_string("```moonbit\n")
        out.write_string("fn item_\{i}() -> Int {\n")
        out.write_string("  \{i}\n")
        out.write_string("```\n")
      }
    }
  }
  out.to_string()
}

///|
fn perf_residual_mixed_doc(section_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  out.write_string("# Main Title\n\n")
  for i = 0; i < section_count; i = i + 1 {
    out.write_string("## Section \{i}\n\n")
    out.write_string(
      "This is paragraph \{i} with **bold** and *italic* and `code` and [link](/url).\n",
    )
    out.write_string("Continuation line for paragraph \{i}.\n\n")
    out.write_string("- Item \{i}a with **emphasis**\n")
    out.write_string("- Item \{i}b with `code`\n")
    out.write_string("- Item \{i}c plain\n\n")
    out.write_string("```lang\n")
    out.write_string("code_line_1_\{i}\n")
    out.write_string("code_line_2_\{i}\n")
    out.write_string("```\n\n")
  }
  out.to_string()
}

///|
fn perf_residual_find_from(
  source : String,
  target : String,
  start : Int,
) -> Int {
  for i = start; i < source.length() - target.length() + 1; i = i + 1 {
    if source[i:i + target.length()].to_owned() == target {
      return i
    }
  }
  -1
}

///|
fn perf_residual_edit_fixture(
  source : String,
  target : String,
  replacement : String,
) -> PerfResidualEditFixture {
  let pos = perf_residual_find_from(source, target, 0)
  guard pos >= 0 else { abort("residual performance edit target not found") }
  guard replacement.length() == 1 else {
    abort("residual performance edit replacement must be one code unit")
  }
  {
    source,
    edited: source[:pos].to_owned() + replacement + source[pos + 1:].to_owned(),
    edit: @core.Edit::replace(pos, pos + 1, pos + 1),
  }
}

///|
fn perf_residual_mixed_10k_edit(block_kind : String) -> PerfResidualEditFixture {
  let source = perf_residual_mixed_doc(714)
  match block_kind {
    "heading-start" => perf_residual_edit_fixture(source, "Main Title", "m")
    "list-first-third" => perf_residual_edit_fixture(source, "Item 238b", "i")
    "paragraph-middle" =>
      perf_residual_edit_fixture(source, "paragraph 400", "P")
    "code-end" => perf_residual_edit_fixture(source, "code_line_2_713", "C")
    _ => abort("unknown residual performance edit kind")
  }
}

///|
fn perf_residual_project_readme_excerpt() -> String {
  let excerpt =
    #|# `dowdiness/markdown`
    #|
    #|Markdown parser example for [`dowdiness/loom`](../../loom/).
    #|
    #|Demonstrates **mode-aware lexing** — `@core.ModeLexer[Token, Mode]` —
    #|the way to handle languages whose token grammar depends on the current
    #|context (line start vs inline vs inside a fenced code block).
    #|
    #|## Public API overview
    #|
    #|This section highlights the main entry points.
    #|
    #|```mbt nocheck
    #|pub let markdown_grammar : @loom.Grammar[Token, SyntaxKind, Block]
    #|pub let markdown_spec : @core.LanguageSpec[Token, SyntaxKind]
    #|pub let markdown_mode_lexer : @core.ModeLexer[Token, MarkdownLexMode]
    #|
    #|pub fn try! parse(@core.SourceId, String) -> Block
    #|pub fn parse_markdown(
    #|  @core.SourceId,
    #|  String,
    #|) -> (Block, @core.DiagnosticSet) raise @core.LexError
    #|pub fn parse_cst(
    #|  @core.SourceId,
    #|  String,
    #|) -> (@seam.CstNode, @core.DiagnosticSet) raise @core.LexError
    #|
    #|pub fn experimental_markdown_ir_from_syntax(
    #|  @core.SourceId,
    #|  @seam.SyntaxNode,
    #|) -> MarkdownIR
    #|pub fn experimental_markdown_ir_to_block(MarkdownIR) -> Block
    #|pub fn experimental_markdown_ir_to_mdast_json(MarkdownIR) -> Json
    #|```
    #|
    #|Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).
    #|
    #|### Emphasis token and CST compatibility
    #|
    #|CommonMark delimiter runs are resolved by the native inline parser. The
    #|public `Star` / `StarStar` token variants and their existing syntax-kind raw
    #|IDs remain available, while inline-text lexing emits one fact per marker.
    #|
    #|Characters consumed as bold or italic boundaries are
    #|`EmphasisDelimiterToken` leaves. Unmatched, escaped, or unused run portions
    #|are ordinary `TextToken` leaves.
    #|
    #|## Experimental MarkdownIR
    #|
    #|The MarkdownIR API is explicitly experimental. It covers documents,
    #|headings, paragraphs, lists, fenced code, text, emphasis, code spans, and
    #|links with UTF-16 source origins.
    #|
    #|- Use the CST when exact source structure matters.
    #|- Use `Block` for the established editor-facing semantic view.
    #|- Use MarkdownIR for source-aware export, rewrite, and HTML rendering.
    #|
    #|```moonbit nocheck
    #|let (cst, diagnostics) = parse_cst(source_id, source)
    #|let syntax = @seam.SyntaxNode::from_cst(cst)
    #|let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    #|  source_id,
    #|  syntax,
    #|  diagnostics,
    #|)
    #|```
    #|
    #|### Projection identity policy
    #|
    #|The private identity adapter extracts content-attached semantic leaves and
    #|previews the sequence through Loom's `ProjectionIdentityTracker`. It commits
    #|only after a successful projection and retains the last successful baseline
    #|through malformed intermediate input.
    #|
    #|Surface-only rewrites retain IDs when semantic payload is unchanged. Heading
    #|depth, list semantics, code language, payload text, and link destination
    #|changes receive fresh IDs.
    #|
  excerpt
}

///|
fn perf_residual_syntax(source : String) -> @seam.SyntaxNode {
  let (cst, _) = parse_cst(
    @core.SourceId("markdown-performance-residual"),
    source,
  ) catch {
    _ => abort("residual performance parse failed")
  }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn bench_perf_residual_tokenize(b : @bench.T, source : String) -> Unit {
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
fn bench_perf_residual_cst(b : @bench.T, source : String) -> Unit {
  b.bench(fn() {
    let (cst, diagnostics) = parse_cst(
      @core.SourceId("markdown-performance-residual"),
      source,
    ) catch {
      _ => abort("residual performance parse failed")
    }
    b.keep(cst)
    b.keep(diagnostics)
  })
}

///|
fn bench_perf_residual_ast(b : @bench.T, source : String) -> Unit {
  b.bench(fn() {
    b.keep(try! parse(@core.SourceId("markdown-performance-residual"), source))
  })
}

///|
fn bench_perf_residual_direct_block(b : @bench.T, source : String) -> Unit {
  let syntax = perf_residual_syntax(source)
  b.bench(fn() {
    let fold = @core.CstFold::new(markdown_fold_node)
    b.keep(fold.fold(syntax))
  })
}

///|
fn perf_residual_recursive_block(root : @seam.SyntaxNode) -> Block {
  fn lower(node : @seam.SyntaxNode) -> Block {
    markdown_fold_node(node, lower)
  }
  lower(root)
}

///|
fn bench_perf_residual_recursive_block(b : @bench.T, source : String) -> Unit {
  let syntax = perf_residual_syntax(source)
  b.bench(fn() { b.keep(perf_residual_recursive_block(syntax)) })
}

///|
fn bench_perf_residual_ir_construction(b : @bench.T, source : String) -> Unit {
  let syntax = perf_residual_syntax(source)
  b.bench(fn() {
    b.keep(
      experimental_markdown_ir_from_syntax(
        @core.SourceId("markdown-performance-residual"),
        syntax,
      ),
    )
  })
}

///|
fn bench_perf_residual_ir_adapter(b : @bench.T, source : String) -> Unit {
  let ir = experimental_markdown_ir_from_syntax(
    @core.SourceId("markdown-performance-residual"),
    perf_residual_syntax(source),
  )
  b.bench(fn() { b.keep(experimental_markdown_ir_to_block(ir)) })
}

///|
fn bench_perf_residual_ir_block(b : @bench.T, source : String) -> Unit {
  let syntax = perf_residual_syntax(source)
  b.bench(fn() {
    let ir = experimental_markdown_ir_from_syntax(
      @core.SourceId("markdown-performance-residual"),
      syntax,
    )
    b.keep(experimental_markdown_ir_to_block(ir))
  })
}

///|
fn bench_perf_residual_syntax_cycle(
  b : @bench.T,
  fixture : PerfResidualEditFixture,
) -> Unit {
  let parser = try! @loom.new_syntax_parser(
    @core.SourceId("markdown-performance-residual-edit"),
    fixture.source,
    markdown_grammar.to_syntax_grammar(),
  )
  let syntax = parser.syntax_tree()
  ignore(syntax.read_or_abort())
  b.bench(fn() {
    try! parser.apply_edit(fixture.edit, fixture.edited)
    b.keep(syntax.read_or_abort())
    try! parser.apply_edit(fixture.edit, fixture.source)
    b.keep(syntax.read_or_abort())
  })
}

///|
test "perf residual: corpus dimensions stay explicit" {
  let mixed_2k = perf_residual_mixed_doc(143)
  assert_eq(perf_residual_line_count(mixed_2k), 2005)
  assert_eq(mixed_2k.length(), 34884)
  assert_eq(perf_residual_line_count(perf_residual_mixed_doc(714)), 9999)
  for family in [HeadingFamily, ParagraphFamily, ListFamily, FencedCodeFamily] {
    assert_eq(
      perf_residual_line_count(perf_residual_family_doc(family, 2000)),
      2001,
    )
    assert_eq(
      perf_residual_line_count(perf_residual_family_doc(family, 10000)),
      10001,
    )
  }
  let readme = perf_residual_project_readme_excerpt()
  assert_true(perf_residual_line_count(readme) >= 70)
  assert_true(readme.contains("ProjectionIdentityTracker"))
}

///|
test "perf residual: 10k edit matrix covers position and block kind" {
  let cases = [
    perf_residual_mixed_10k_edit("heading-start"),
    perf_residual_mixed_10k_edit("list-first-third"),
    perf_residual_mixed_10k_edit("paragraph-middle"),
    perf_residual_mixed_10k_edit("code-end"),
  ]
  let source_length = cases[0].source.length()
  assert_true(cases[0].edit.start < source_length / 20)
  assert_true(cases[1].edit.start > source_length / 4)
  assert_true(cases[1].edit.start < source_length / 2)
  assert_true(cases[2].edit.start > source_length / 2)
  assert_true(cases[2].edit.start < source_length * 3 / 4)
  assert_true(cases[3].edit.start > source_length * 9 / 10)
  for fixture in cases {
    let incremental = try! @loom.new_syntax_parser(
      @core.SourceId("markdown-performance-residual-parity"),
      fixture.source,
      markdown_grammar.to_syntax_grammar(),
    )
    incremental.apply_edit(fixture.edit, fixture.edited)
    let fresh = try! @loom.new_syntax_parser(
      @core.SourceId("markdown-performance-residual-parity"),
      fixture.edited,
      markdown_grammar.to_syntax_grammar(),
    )
    assert_eq(
      incremental.syntax_tree().read_or_abort(),
      fresh.syntax_tree().read_or_abort(),
    )
  }
}

///|
test "perf residual: mixed 10k tokenize" (b : @bench.T) {
  bench_perf_residual_tokenize(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 10k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 2k CST plus AST" (b : @bench.T) {
  bench_perf_residual_ast(b, perf_residual_mixed_doc(143))
}

///|
test "perf residual: mixed 10k CST plus AST" (b : @bench.T) {
  bench_perf_residual_ast(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 2k direct Block lowering" (b : @bench.T) {
  bench_perf_residual_direct_block(b, perf_residual_mixed_doc(143))
}

///|
test "perf residual: mixed 10k direct Block lowering" (b : @bench.T) {
  bench_perf_residual_direct_block(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 2k recursive Block lowering" (b : @bench.T) {
  bench_perf_residual_recursive_block(b, perf_residual_mixed_doc(143))
}

///|
test "perf residual: mixed 10k recursive Block lowering" (b : @bench.T) {
  bench_perf_residual_recursive_block(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 2k MarkdownIR to Block" (b : @bench.T) {
  bench_perf_residual_ir_block(b, perf_residual_mixed_doc(143))
}

///|
test "perf residual: mixed 10k MarkdownIR to Block" (b : @bench.T) {
  bench_perf_residual_ir_block(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 2k MarkdownIR construction" (b : @bench.T) {
  bench_perf_residual_ir_construction(b, perf_residual_mixed_doc(143))
}

///|
test "perf residual: mixed 10k MarkdownIR construction" (b : @bench.T) {
  bench_perf_residual_ir_construction(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: mixed 2k MarkdownIR Block adapter" (b : @bench.T) {
  bench_perf_residual_ir_adapter(b, perf_residual_mixed_doc(143))
}

///|
test "perf residual: mixed 10k MarkdownIR Block adapter" (b : @bench.T) {
  bench_perf_residual_ir_adapter(b, perf_residual_mixed_doc(714))
}

///|
test "perf residual: heading 2k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(HeadingFamily, 2000))
}

///|
test "perf residual: heading 10k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(HeadingFamily, 10000))
}

///|
test "perf residual: paragraph 2k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(ParagraphFamily, 2000))
}

///|
test "perf residual: paragraph 10k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(ParagraphFamily, 10000))
}

///|
test "perf residual: list 2k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(ListFamily, 2000))
}

///|
test "perf residual: list 10k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(ListFamily, 10000))
}

///|
test "perf residual: fenced code 2k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(FencedCodeFamily, 2000))
}

///|
test "perf residual: fenced code 10k CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_family_doc(FencedCodeFamily, 10000))
}

///|
test "perf residual: heading 2k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(HeadingFamily, 2000),
  )
}

///|
test "perf residual: heading 10k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(HeadingFamily, 10000),
  )
}

///|
test "perf residual: paragraph 2k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(ParagraphFamily, 2000),
  )
}

///|
test "perf residual: paragraph 10k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(ParagraphFamily, 10000),
  )
}

///|
test "perf residual: list 2k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(ListFamily, 2000),
  )
}

///|
test "perf residual: list 10k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(ListFamily, 10000),
  )
}

///|
test "perf residual: fenced code 2k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(FencedCodeFamily, 2000),
  )
}

///|
test "perf residual: fenced code 10k recursive Block" (b : @bench.T) {
  bench_perf_residual_recursive_block(
    b,
    perf_residual_family_doc(FencedCodeFamily, 10000),
  )
}

///|
test "perf residual: real README excerpt CST" (b : @bench.T) {
  bench_perf_residual_cst(b, perf_residual_project_readme_excerpt())
}

///|
test "perf residual: real README excerpt CST plus AST" (b : @bench.T) {
  bench_perf_residual_ast(b, perf_residual_project_readme_excerpt())
}

///|
test "perf residual: real README excerpt direct Block lowering" (b : @bench.T) {
  bench_perf_residual_direct_block(b, perf_residual_project_readme_excerpt())
}

///|
test "perf residual: real README excerpt MarkdownIR to Block" (b : @bench.T) {
  bench_perf_residual_ir_block(b, perf_residual_project_readme_excerpt())
}

///|
test "perf residual: mixed 10k heading edit at start" (b : @bench.T) {
  bench_perf_residual_syntax_cycle(
    b,
    perf_residual_mixed_10k_edit("heading-start"),
  )
}

///|
test "perf residual: mixed 10k list edit in first third" (b : @bench.T) {
  bench_perf_residual_syntax_cycle(
    b,
    perf_residual_mixed_10k_edit("list-first-third"),
  )
}

///|
test "perf residual: mixed 10k paragraph edit in middle" (b : @bench.T) {
  bench_perf_residual_syntax_cycle(
    b,
    perf_residual_mixed_10k_edit("paragraph-middle"),
  )
}

///|
test "perf residual: mixed 10k code edit at end" (b : @bench.T) {
  bench_perf_residual_syntax_cycle(b, perf_residual_mixed_10k_edit("code-end"))
}
