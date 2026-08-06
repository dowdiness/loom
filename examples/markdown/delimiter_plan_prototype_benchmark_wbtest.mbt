// Reusable adoption-gate benchmark matrix for Issue #883.
//
// The representative excerpt mixes ordinary README prose with CommonMark
// delimiter boundaries. Synthetic delimiter-heavy rows remain in
// delimiter_performance_wbtest.mbt and are not substituted for this corpus.
// The measured online-resolver candidate was rejected, so this file preserves
// only the production oracle and informational control workloads.

///|
fn delimiter_plan_representative_excerpt() -> String {
  let section =
    #|# Parser integration guide
    #|
    #|The *ordinary emphasis* path and the **strong emphasis** path should stay
    #|predictable when a [link label](/guide) appears in otherwise normal prose.
    #|Use `moon check` before committing, and keep \*escaped markers\* literal.
    #|
    #|Identifiers such as snake_case_value use intraword underscores. An
    #|unmatched *marker remains text, while *a***a* exercises the odd-match rule.
    #|The scoped form *outside [*inside*](/guide) tail* must not cross the label.
    #|
    #|- Parse the source and retain **diagnostics**.
    #|- Compare *syntax* and MarkdownIR after an incremental edit.
    #|- Leave `*opaque*` delimiters inside code spans untouched.
    #|
    #|```moonbit
    #|let value = "*not emphasis inside a fence*"
    #|```
    #|
    #|<span data-mode="example">Inline HTML control</span>
    #|
  section.repeat(16)
}

///|
fn delimiter_plan_plain_control(source : String) -> String {
  let out = StringBuilder::new()
  for character in source {
    match character {
      '*' | '_' | '`' | '[' | ']' | '(' | ')' | '/' => out.write_char('x')
      _ => out.write_char(character)
    }
  }
  out.to_string()
}

///|
fn delimiter_plan_mixed_control(section_count : Int) -> String {
  let out = StringBuilder::new()
  for i in 0..<section_count {
    out.write_string("## Section \{i}\n\n")
    out.write_string(
      "Paragraph with **bold**, *italic*, `code`, and [link](/url).\n\n",
    )
    out.write_string("- first item\n- second item\n\n")
    out.write_string("```moonbit\nfn item() -> Int { 1 }\n```\n\n")
  }
  out.to_string()
}

///|
fn delimiter_plan_fenced_control(block_count : Int) -> String {
  let out = StringBuilder::new()
  for i in 0..<block_count {
    out.write_string("```moonbit\n")
    out.write_string("fn item_\{i}() -> Int { \{i} }\n")
    out.write_string("```\n")
  }
  out.to_string()
}

///|
fn delimiter_plan_find(source : String, target : String) -> Int {
  for i = 0; i <= source.length() - target.length(); i = i + 1 {
    if source[i:i + target.length()].to_owned() == target {
      return i
    }
  }
  -1
}

///|
fn delimiter_plan_parse_cst(
  source_id : @core.SourceId,
  source : String,
) -> (@seam.CstNode, @core.DiagnosticSet) {
  parse_cst(source_id, source) catch {
    _ => abort("delimiter-plan representative parse failed")
  }
}

///|
fn benchmark_delimiter_plan_cst(
  b : @bench.T,
  source_id : @core.SourceId,
  source : String,
) -> Unit {
  b.bench(() => {
    let (cst, diagnostics) = delimiter_plan_parse_cst(source_id, source)
    b.keep(cst)
    b.keep(diagnostics)
  })
}

///|
fn benchmark_delimiter_plan_cst_ir(
  b : @bench.T,
  source_id : @core.SourceId,
  source : String,
) -> Unit {
  b.bench(() => {
    let (cst, diagnostics) = delimiter_plan_parse_cst(source_id, source)
    let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id,
      @seam.SyntaxNode::from_cst(cst),
      diagnostics,
    )
    b.keep(cst)
    b.keep(ir)
  })
}

///|
test "delimiter candidate: representative oracle is deterministic" {
  let source = delimiter_plan_representative_excerpt()
  let source_id = @core.SourceId("markdown-delimiter-candidate-oracle")
  let (first_cst, first_diagnostics) = delimiter_plan_parse_cst(
    source_id, source,
  )
  let (second_cst, second_diagnostics) = delimiter_plan_parse_cst(
    source_id, source,
  )
  assert_eq(first_cst, second_cst)
  assert_eq(first_diagnostics, second_diagnostics)
  assert_eq(first_diagnostics.length(), 0)
  let first_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(first_cst),
    first_diagnostics,
  )
  let second_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(second_cst),
    second_diagnostics,
  )
  assert_eq(first_ir, second_ir)
}

///|
test "delimiter candidate: representative CST" (b : @bench.T) {
  benchmark_delimiter_plan_cst(
    b,
    @core.SourceId("markdown-delimiter-candidate-representative"),
    delimiter_plan_representative_excerpt(),
  )
}

///|
test "delimiter candidate: representative CST and MarkdownIR" (b : @bench.T) {
  benchmark_delimiter_plan_cst_ir(
    b,
    @core.SourceId("markdown-delimiter-candidate-representative-ir"),
    delimiter_plan_representative_excerpt(),
  )
}

///|
test "delimiter candidate: matched plain CST" (b : @bench.T) {
  let source = delimiter_plan_representative_excerpt()
  benchmark_delimiter_plan_cst(
    b,
    @core.SourceId("markdown-delimiter-candidate-plain"),
    delimiter_plan_plain_control(source),
  )
}

///|
test "delimiter candidate: mixed Markdown CST" (b : @bench.T) {
  benchmark_delimiter_plan_cst(
    b,
    @core.SourceId("markdown-delimiter-candidate-mixed"),
    delimiter_plan_mixed_control(64),
  )
}

///|
test "delimiter candidate: HTML control CST" (b : @bench.T) {
  benchmark_delimiter_plan_cst(
    b,
    @core.SourceId("markdown-delimiter-candidate-html"),
    "<div>\nraw <span>payload</span>\n</div>\n\n".repeat(128),
  )
}

///|
test "delimiter candidate: fenced-code control CST" (b : @bench.T) {
  benchmark_delimiter_plan_cst(
    b,
    @core.SourceId("markdown-delimiter-candidate-fenced"),
    delimiter_plan_fenced_control(128),
  )
}

///|
test "delimiter candidate: representative tokenize only" (b : @bench.T) {
  let source = delimiter_plan_representative_excerpt()
  b.bench(() => {
    let tokens = tokenize(source) catch {
      _ => abort("delimiter-plan representative tokenize failed")
    }
    b.keep(tokens)
  })
}

///|
test "delimiter candidate: representative incremental edit and restore" (
  b : @bench.T,
) {
  let source = delimiter_plan_representative_excerpt()
  let start = delimiter_plan_find(source, "*ordinary emphasis*")
  guard start >= 0 else { abort("delimiter-plan edit target not found") }
  let edited = source[:start].to_owned() + "_" + source[start + 1:].to_owned()
  let edit = @core.Edit::new(start, 1, 1)
  let parser = @loom.new_syntax_parser(
    @core.SourceId("markdown-delimiter-candidate-incremental"),
    source,
    markdown_grammar.to_syntax_grammar(),
  )
  ignore(parser.syntax_tree().read_or_abort())
  b.bench(() => {
    parser.apply_edit(edit, edited)
    b.keep(parser.syntax_tree().read_or_abort())
    parser.apply_edit(edit, source)
    b.keep(parser.syntax_tree().read_or_abort())
  })
}
