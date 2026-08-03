// Stage-isolation benchmarks for #838.
//
// The corpus is deliberately simple so the measurements expose framework and
// publication costs without mixing in container or delimiter adversaries.

///|
fn perf_paragraph_doc(count : Int) -> String {
  let out = StringBuilder::new()
  out.write_string("# Document Title\n\n")
  for i = 0; i < count; i = i + 1 {
    out.write_string(
      "Paragraph \{i + 1} with some content that needs parsing. ",
    )
    out.write_string("This is a *sample* paragraph with **formatting**.\n\n")
  }
  out.to_string()
}

///|
fn perf_find_from(source : String, target : String, start : Int) -> Int {
  for i = start; i < source.length() - target.length() + 1; i = i + 1 {
    if source[i:i + target.length()].to_owned() == target {
      return i
    }
  }
  -1
}

///|
fn perf_middle_edit(source : String) -> (String, @core.Edit) {
  let pos = perf_find_from(source, "sample", source.length() / 2)
  guard pos >= 0 else { abort("middle edit target not found") }
  (
    source[:pos].to_owned() + "S" + source[pos + 1:].to_owned(),
    @core.Edit::replace(pos, pos + 1, pos + 1),
  )
}

///|
fn perf_syntax(source : String) -> @seam.SyntaxNode {
  let (cst, _) = parse_cst(@core.SourceId("markdown-perf-envelope"), source) catch {
    _ => abort("parse failed")
  }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn bench_perf_tokenize(b : @bench.T, count : Int) -> Unit {
  let source = perf_paragraph_doc(count)
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
fn bench_perf_cst(b : @bench.T, count : Int) -> Unit {
  let source = perf_paragraph_doc(count)
  b.bench(fn() {
    let (cst, diagnostics) = parse_cst(
      @core.SourceId("markdown-perf-envelope"),
      source,
    ) catch {
      _ => abort("parse failed")
    }
    b.keep(cst)
    b.keep(diagnostics)
  })
}

///|
fn bench_perf_ast(b : @bench.T, count : Int) -> Unit {
  let source = perf_paragraph_doc(count)
  b.bench(fn() {
    b.keep(parse(@core.SourceId("markdown-perf-envelope"), source))
  })
}

///|
fn bench_perf_fold(b : @bench.T, count : Int) -> Unit {
  let syntax = perf_syntax(perf_paragraph_doc(count))
  b.bench(fn() {
    let fold = @core.CstFold::new(markdown_fold_node)
    b.keep(fold.fold(syntax))
  })
}

///|
fn bench_perf_ir(b : @bench.T, count : Int) -> Unit {
  let syntax = perf_syntax(perf_paragraph_doc(count))
  b.bench(fn() {
    b.keep(
      experimental_markdown_ir_from_syntax(
        @core.SourceId("markdown-perf-envelope"),
        syntax,
      ),
    )
  })
}

///|
fn bench_perf_imperative_ast_cycle(b : @bench.T, count : Int) -> Unit {
  let source = perf_paragraph_doc(count)
  let (edited, edit) = perf_middle_edit(source)
  let parser = @loom.new_imperative_parser(
    @core.SourceId("markdown-perf-envelope"),
    source,
    markdown_grammar,
  )
  let _ = parser.parse()
  b.bench(fn() {
    b.keep(parser.edit(edit, edited).ast)
    b.keep(parser.edit(edit, source).ast)
  })
}

///|
fn bench_perf_reactive_syntax_cycle(b : @bench.T, count : Int) -> Unit {
  let source = perf_paragraph_doc(count)
  let (edited, edit) = perf_middle_edit(source)
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-perf-envelope"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  let syntax = parser.syntax_tree()
  ignore(syntax.read_or_abort())
  b.bench(fn() {
    parser.apply_edit(edit, edited)
    b.keep(syntax.read_or_abort())
    parser.apply_edit(edit, source)
    b.keep(syntax.read_or_abort())
  })
}

///|
fn bench_perf_reactive_ast_cycle(b : @bench.T, count : Int) -> Unit {
  let source = perf_paragraph_doc(count)
  let (edited, edit) = perf_middle_edit(source)
  let parser = @loom.new_parser(
    @core.SourceId("markdown-perf-envelope"),
    source,
    markdown_grammar,
  )
  let ast = parser.ast()
  ignore(ast.read_or_abort())
  b.bench(fn() {
    parser.apply_edit(edit, edited)
    b.keep(ast.read_or_abort())
    parser.apply_edit(edit, source)
    b.keep(ast.read_or_abort())
  })
}

///|
test "perf envelope: tokenize 10 paragraphs" (b : @bench.T) {
  bench_perf_tokenize(b, 10)
}

///|
test "perf envelope: tokenize 100 paragraphs" (b : @bench.T) {
  bench_perf_tokenize(b, 100)
}

///|
test "perf envelope: tokenize 500 paragraphs" (b : @bench.T) {
  bench_perf_tokenize(b, 500)
}

///|
test "perf envelope: CST 10 paragraphs" (b : @bench.T) {
  bench_perf_cst(b, 10)
}

///|
test "perf envelope: CST 100 paragraphs" (b : @bench.T) {
  bench_perf_cst(b, 100)
}

///|
test "perf envelope: CST 500 paragraphs" (b : @bench.T) {
  bench_perf_cst(b, 500)
}

///|
test "perf envelope: CST plus AST 10 paragraphs" (b : @bench.T) {
  bench_perf_ast(b, 10)
}

///|
test "perf envelope: CST plus AST 100 paragraphs" (b : @bench.T) {
  bench_perf_ast(b, 100)
}

///|
test "perf envelope: CST plus AST 500 paragraphs" (b : @bench.T) {
  bench_perf_ast(b, 500)
}

///|
test "perf envelope: isolated AST fold 10 paragraphs" (b : @bench.T) {
  bench_perf_fold(b, 10)
}

///|
test "perf envelope: isolated AST fold 100 paragraphs" (b : @bench.T) {
  bench_perf_fold(b, 100)
}

///|
test "perf envelope: isolated AST fold 500 paragraphs" (b : @bench.T) {
  bench_perf_fold(b, 500)
}

///|
test "perf envelope: isolated MarkdownIR 100 paragraphs" (b : @bench.T) {
  bench_perf_ir(b, 100)
}

///|
test "perf envelope: isolated MarkdownIR 500 paragraphs" (b : @bench.T) {
  bench_perf_ir(b, 500)
}

///|
test "perf envelope: imperative AST cycle 10 paragraphs" (b : @bench.T) {
  bench_perf_imperative_ast_cycle(b, 10)
}

///|
test "perf envelope: imperative AST cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_imperative_ast_cycle(b, 100)
}

///|
test "perf envelope: imperative AST cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_imperative_ast_cycle(b, 500)
}

///|
test "perf envelope: reactive syntax cycle 10 paragraphs" (b : @bench.T) {
  bench_perf_reactive_syntax_cycle(b, 10)
}

///|
test "perf envelope: reactive syntax cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_reactive_syntax_cycle(b, 100)
}

///|
test "perf envelope: reactive syntax cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_reactive_syntax_cycle(b, 500)
}

///|
test "perf envelope: reactive AST cycle 10 paragraphs" (b : @bench.T) {
  bench_perf_reactive_ast_cycle(b, 10)
}

///|
test "perf envelope: reactive AST cycle 100 paragraphs" (b : @bench.T) {
  bench_perf_reactive_ast_cycle(b, 100)
}

///|
test "perf envelope: reactive AST cycle 500 paragraphs" (b : @bench.T) {
  bench_perf_reactive_ast_cycle(b, 500)
}
