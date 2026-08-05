// Reproducible before/after benchmark for quote-line physical-end reuse.

///|
// Recreate the indexed lexer shell immediately before #873: preserve source
// identity and angle-delimiter indexing, but always omit the line-end hint.
fn line_end_cache_uncached_indexed_lexer() -> @core.ModeLexer[
  Token,
  MarkdownLexMode,
] {
  let source_ref : Ref[String?] = Ref(None)
  let delimiter_index_ref : Ref[InlineAngleDelimiterIndex?] = Ref(None)
  let lex_step = fn(input : String, pos : Int, mode : MarkdownLexMode) {
    let same_source = match source_ref.val {
      Some(source) => physical_equal(source, input)
      None => false
    }
    if !same_source {
      source_ref.val = Some(input)
      delimiter_index_ref.val = None
    }
    if delimiter_index_ref.val is None && char_at(input, pos) == Some('<') {
      delimiter_index_ref.val = Some(build_inline_angle_delimiter_index(input))
    }
    markdown_lex_step_with_angle_index(
      input,
      pos,
      mode,
      delimiter_index_ref.val,
      None,
    )
  }
  { lex_step, initial_mode: LineStart }
}

///|
fn bench_line_end_cache_nested_quotes(
  b : @bench.T,
  depth : Int,
  cached : Bool,
) -> Unit {
  let source = line_end_cache_nested_quote_doc(depth, 100)
  b.bench(() => {
    let tokens = if cached {
      tokenize(source) catch {
        _ => abort("cached nested-quote benchmark failed")
      }
    } else {
      let (tokens, _) = @core.tokenize_with_modes(
        line_end_cache_uncached_indexed_lexer(),
        source,
        EOF,
      ) catch {
        _ => abort("uncached nested-quote benchmark failed")
      }
      tokens
    }
    b.keep(tokens)
  })
}

///|
test "line-end cache: depth 1 uncached indexed" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 1, false)
}

///|
test "line-end cache: depth 1 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 1, true)
}

///|
test "line-end cache: depth 8 uncached indexed" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 8, false)
}

///|
test "line-end cache: depth 8 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 8, true)
}

///|
test "line-end cache: depth 32 uncached indexed" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 32, false)
}

///|
test "line-end cache: depth 32 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 32, true)
}

///|
test "line-end cache: depth 128 uncached indexed" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 128, false)
}

///|
test "line-end cache: depth 128 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 128, true)
}
