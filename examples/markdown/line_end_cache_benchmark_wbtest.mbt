// Reproducible before/after benchmark for quote-line physical-end reuse.

///|
// Recreate the production lexer shell without its line-end hint so this
// benchmark isolates physical-line-end reuse from inline-angle ownership.
fn line_end_cache_uncached_lexer() -> @core.ModeLexer[Token, MarkdownLexMode] {
  let lex_step = fn(input : String, pos : Int, mode : MarkdownLexMode) {
    markdown_lex_step_inner(input, pos, mode, None)
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
        line_end_cache_uncached_lexer(),
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
test "line-end cache: depth 1 uncached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 1, false)
}

///|
test "line-end cache: depth 1 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 1, true)
}

///|
test "line-end cache: depth 8 uncached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 8, false)
}

///|
test "line-end cache: depth 8 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 8, true)
}

///|
test "line-end cache: depth 32 uncached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 32, false)
}

///|
test "line-end cache: depth 32 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 32, true)
}

///|
test "line-end cache: depth 128 uncached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 128, false)
}

///|
test "line-end cache: depth 128 cached" (b : @bench.T) {
  bench_line_end_cache_nested_quotes(b, 128, true)
}
