///|
fn unterminated_inline_comment_workload(repeat_count : Int) -> String {
  let builder = StringBuilder::StringBuilder()
  builder.write_string("x ")
  for i = 0; i < repeat_count; i = i + 1 {
    builder.write_string("<!--x")
  }
  builder.write_char('\n')
  builder.to_string()
}

///|
fn benchmark_unterminated_inline_comment_tokenize(
  b : @bench.T,
  repeat_count : Int,
) -> Unit {
  let source = unterminated_inline_comment_workload(repeat_count)
  b.bench(() => {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
test "unterminated inline comment index has one bounded lookup per candidate" {
  for repeat_count in [64, 256] {
    let source = unterminated_inline_comment_workload(repeat_count)
    let index = build_inline_angle_delimiter_index(source)
    let mut checks = 0
    for candidate = 0; candidate < repeat_count; candidate = candidate + 1 {
      let start = 2 + candidate * "<!--x".length()
      match index.angle_delimiters.get(start) {
        Some(snapshot) => {
          assert_eq(snapshot.comment_end, None)
          checks = checks + 1
        }
        None => fail("expected an indexed inline comment candidate")
      }
    }
    assert_eq(checks, repeat_count)
  }
}

///|
test "production inline angle lexing matches the stateless reference" {
  let cases = [
    "x <!--a--> y\n", "x <![CDATA[a<b]]> y\n", "x <?target a?> y\n", "x <!DOCTYPE html> y\n",
    "x <a title='a<b'>y</a>\n", "x <a title=\"line one\nline two\">y</a>\n", "<a title=\"a lot\n---\nof dashes\"/>\n",
    "`<a href=\"`\">`\n", "<a href=\"`\">`\n", "x <!--x<!--x\n",
  ]
  for source in cases {
    let production = tokenize(source) catch {
      _ => fail("production lex failed")
    }
    let (reference, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => fail("stateless reference lex failed")
    }
    assert_eq(production, reference)
  }
}

///|
test "markdown unterminated inline comments 1024x tokenize" (b : @bench.T) {
  benchmark_unterminated_inline_comment_tokenize(b, 1024)
}

///|
test "markdown unterminated inline comments 4096x tokenize" (b : @bench.T) {
  benchmark_unterminated_inline_comment_tokenize(b, 4096)
}

///|
fn angle_free_inline_workload(repeat_count : Int) -> String {
  let builder = StringBuilder::StringBuilder()
  for i = 0; i < repeat_count; i = i + 1 {
    builder.write_string("plain *emphasis* and [link](url) ")
  }
  builder.write_char('\n')
  builder.to_string()
}

///|
test "markdown angle-free 4096x production tokenize" (b : @bench.T) {
  let source = angle_free_inline_workload(4096)
  b.bench(() => {
    let tokens = tokenize(source) catch { _ => abort("production lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown angle-free 4096x stateless tokenize" (b : @bench.T) {
  let source = angle_free_inline_workload(4096)
  b.bench(() => {
    let (tokens, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => abort("stateless lex failed")
    }
    b.keep(tokens)
  })
}

///|
fn greater_than_heavy_inline_workload(repeat_count : Int) -> String {
  let builder = StringBuilder::StringBuilder()
  for i = 0; i < repeat_count; i = i + 1 {
    builder.write_string("plain text > with a marker and >> more >> ")
  }
  builder.write_char('\n')
  builder.to_string()
}

///|
// A `>`-heavy, `<`-free control: every `>` becomes a one-character Text token
// boundary while no angle index or autolink plan is constructed. This measures
// the unavoidable `>` boundary cost separately from semantic angle planning.
test "markdown greater-than-heavy 4096x production tokenize" (b : @bench.T) {
  let source = greater_than_heavy_inline_workload(4096)
  b.bench(() => {
    let tokens = tokenize(source) catch { _ => abort("production lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown greater-than-heavy 4096x stateless tokenize" (b : @bench.T) {
  let source = greater_than_heavy_inline_workload(4096)
  b.bench(() => {
    let (tokens, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => abort("stateless lex failed")
    }
    b.keep(tokens)
  })
}

///|
fn successful_single_line_inline_html_workload(repeat_count : Int) -> String {
  let builder = StringBuilder::StringBuilder()
  for i = 0; i < repeat_count; i = i + 1 {
    builder.write_string(
      "prefix <a data-i=\"\{i}\" title=\"a deliberately long attribute value\">suffix</a>\n",
    )
  }
  builder.to_string()
}

///|
test "markdown successful single-line inline HTML 512x production tokenize" (
  b : @bench.T,
) {
  let source = successful_single_line_inline_html_workload(512)
  b.bench(() => {
    let tokens = tokenize(source) catch { _ => abort("production lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown successful single-line inline HTML 512x stateless tokenize" (
  b : @bench.T,
) {
  let source = successful_single_line_inline_html_workload(512)
  b.bench(() => {
    let (tokens, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => abort("stateless lex failed")
    }
    b.keep(tokens)
  })
}

///|
fn successful_multiline_inline_html_workload(repeat_count : Int) -> String {
  let builder = StringBuilder::StringBuilder()
  for i = 0; i < repeat_count; i = i + 1 {
    builder.write_string(
      "prefix <a data-i=\"\{i}\" title=\"line one\nline two\nline three\">suffix</a>\n",
    )
  }
  builder.to_string()
}

///|
test "markdown successful multiline inline HTML 512x production tokenize" (
  b : @bench.T,
) {
  let source = successful_multiline_inline_html_workload(512)
  b.bench(() => {
    let tokens = tokenize(source) catch { _ => abort("production lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown successful multiline inline HTML 512x stateless tokenize" (
  b : @bench.T,
) {
  let source = successful_multiline_inline_html_workload(512)
  b.bench(() => {
    let (tokens, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => abort("stateless lex failed")
    }
    b.keep(tokens)
  })
}

///|
fn benchmark_inline_html_cst(
  b : @bench.T,
  source_id : @core.SourceId,
  source : String,
) -> Unit {
  b.bench(() => {
    let (cst, diagnostics) = parse_cst(source_id, source) catch {
      _ => abort("inline HTML CST benchmark parse failed")
    }
    b.keep(cst)
    b.keep(diagnostics)
  })
}

///|
test "markdown successful single-line inline HTML 512x CST" (b : @bench.T) {
  benchmark_inline_html_cst(
    b,
    @core.SourceId("markdown-inline-html-single-line-cst"),
    successful_single_line_inline_html_workload(512),
  )
}

///|
test "markdown successful multiline inline HTML 512x CST" (b : @bench.T) {
  benchmark_inline_html_cst(
    b,
    @core.SourceId("markdown-inline-html-multiline-cst"),
    successful_multiline_inline_html_workload(512),
  )
}

///|
test "markdown backtick-bearing inline HTML 512x CST" (b : @bench.T) {
  benchmark_inline_html_cst(
    b,
    @core.SourceId("markdown-inline-html-backtick-cst"),
    "prefix <a title=\"`\">` suffix\n".repeat(512),
  )
}

///|
fn benchmark_inline_html_cst_ir(
  b : @bench.T,
  source_id : @core.SourceId,
  source : String,
) -> Unit {
  b.bench(() => {
    let (cst, diagnostics) = parse_cst(source_id, source) catch {
      _ => abort("inline HTML CST plus IR benchmark parse failed")
    }
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
test "markdown successful single-line inline HTML 512x CST plus IR" (
  b : @bench.T,
) {
  benchmark_inline_html_cst_ir(
    b,
    @core.SourceId("markdown-inline-html-single-line-cst-ir"),
    successful_single_line_inline_html_workload(512),
  )
}

///|
test "markdown successful multiline inline HTML 512x CST plus IR" (b : @bench.T) {
  benchmark_inline_html_cst_ir(
    b,
    @core.SourceId("markdown-inline-html-multiline-cst-ir"),
    successful_multiline_inline_html_workload(512),
  )
}

///|
test "markdown backtick-bearing inline HTML 512x CST plus IR" (b : @bench.T) {
  benchmark_inline_html_cst_ir(
    b,
    @core.SourceId("markdown-inline-html-backtick-cst-ir"),
    "prefix <a title=\"`\">` suffix\n".repeat(512),
  )
}
