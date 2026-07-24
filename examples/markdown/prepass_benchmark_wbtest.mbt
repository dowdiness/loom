// Isolated benchmark for the speculative code-span delimiter prepass.
//
// Each fixture is one realistic multi-line inline container. The prepass helper
// mirrors the current ParserContext::lookahead body and discards its index after
// lookahead restores parser state. It is test-only evidence for the Task 1
// stop/go gate; it does not change production parsing.

///|
fn prepass_context(source : String) -> @core.ParserContext[Token, SyntaxKind] {
  let tokens = tokenize(source) catch {
    _ => abort("prepass benchmark lex failed")
  }
  @core.ParserContext::new(tokens, source, markdown_spec)
}

///|
fn benchmark_root_source() -> String {
  "alpha `matched` ``two ticks`` \\`escaped` `unmatched\ncontinuation `again` ``second pair`` \\`escaped again` `trailing"
}

///|
fn benchmark_block_quote_source() -> String {
  "> alpha `matched` ``two ticks`` \\`escaped` `unmatched\n> continuation `again` ``second pair`` \\`escaped again` `trailing"
}

///|
fn benchmark_list_item_source() -> String {
  "- alpha `matched` ``two ticks`` \\`escaped` `unmatched\n  continuation `again` ``second pair`` \\`escaped again` `trailing"
}

///|
fn benchmark_indexed_prepass(
  ctx : @core.ParserContext[Token, SyntaxKind],
  policy : InlineParsePolicy,
  continue_line : () -> Bool,
) -> CodeSpanDelimiterIndex {
  ctx.lookahead(() => {
    let index : CodeSpanDelimiterIndex = {
      eligible_openers: {},
      successors: {},
    }
    let previous_by_length : Map[Int, Int] = {}
    let mut preceding_text_ends_escaped = false
    while true {
      while !token_is_inline_end(ctx.peek(), policy) {
        match ctx.peek() {
          Text(_) =>
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              ctx.current_token_text(),
            )
          Backtick => {
            let range = ctx.current_token_range()
            let start = range.start
            let run_length = range.length()
            index_code_span_delimiter_run(
              index,
              previous_by_length,
              start,
              run_length,
              !preceding_text_ends_escaped,
            )
            preceding_text_ends_escaped = false
          }
          _ => preceding_text_ends_escaped = false
        }
        ctx.emit_current_token()
      }
      guard ctx.peek() is Newline && continue_line() else { break }
      preceding_text_ends_escaped = false
    }
    index
  })
}

///|
fn root_prepass_context() -> @core.ParserContext[Token, SyntaxKind] {
  prepass_context(benchmark_root_source())
}

///|
fn block_quote_prepass_context() -> @core.ParserContext[Token, SyntaxKind] {
  let ctx = prepass_context(benchmark_block_quote_source())
  ctx.emit_token(BlockQuoteMarkerToken)
  ctx
}

///|
fn list_item_prepass_context() -> @core.ParserContext[Token, SyntaxKind] {
  let ctx = prepass_context(benchmark_list_item_source())
  ctx.emit_token(ListMarkerToken)
  ctx
}

///|
fn root_prepass(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> CodeSpanDelimiterIndex {
  let handler : ContinuationHandler[RootContinuationKind] = {
    decide: () => decide_root_paragraph_continuation(ctx),
    consume: action => consume_root_continuation(ctx, action),
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => {
      advance_root_paragraph_continuation(ctx, offset, action)
    },
  }
  benchmark_indexed_prepass(
    ctx,
    InlineParsePolicy::paragraph(),
    continuation_step(handler),
  )
}

///|
fn block_quote_prepass(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> CodeSpanDelimiterIndex {
  let handler : ContinuationHandler[BlockQuoteContinuationKind] = {
    decide: () => decide_block_quote_paragraph_continuation(ctx),
    consume: action => consume_block_quote_continuation(ctx, action),
    observe: offset => observe_block_quote_paragraph_continuation(ctx, offset),
    advance: (offset, action) => {
      advance_block_quote_paragraph_continuation(ctx, offset, action)
    },
  }
  benchmark_indexed_prepass(
    ctx,
    InlineParsePolicy::paragraph(),
    continuation_step(handler),
  )
}

///|
fn list_item_prepass(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> CodeSpanDelimiterIndex {
  let handler : ContinuationHandler[ListItemContinuationKind] = {
    decide: () => {
      decide_list_item_continuation(
        ctx,
        2,
        allow_ordered_marker=false,
        has_paragraph_content=true,
      )
    },
    consume: action => consume_list_item_continuation(ctx, action),
    observe: offset => {
      observe_list_item_continuation(
        ctx,
        offset,
        2,
        allow_ordered_marker=false,
        has_paragraph_content=true,
      )
    },
    advance: (offset, action) => {
      advance_list_item_continuation(ctx, offset, action)
    },
  }
  benchmark_indexed_prepass(
    ctx,
    InlineParsePolicy::list_item(allow_ordered_marker=false),
    continuation_step(handler),
  )
}

///|
test "markdown prepass: root paragraph prepass-first" (b : @bench.T) {
  let source = benchmark_root_source()
  let ctx = root_prepass_context()
  b.bench(fn() {
    let index = root_prepass(ctx)
    b.keep(index)
  })
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("root parse failed") }
    b.keep(cst)
  })
}

///|
test "markdown prepass: root paragraph cst-first" (b : @bench.T) {
  let source = benchmark_root_source()
  let ctx = root_prepass_context()
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("root parse failed") }
    b.keep(cst)
  })
  b.bench(fn() {
    let index = root_prepass(ctx)
    b.keep(index)
  })
}

///|
test "markdown prepass: block quote paragraph prepass-first" (b : @bench.T) {
  let source = benchmark_block_quote_source()
  let ctx = block_quote_prepass_context()
  b.bench(fn() {
    let index = block_quote_prepass(ctx)
    b.keep(index)
  })
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch {
      _ => abort("block quote parse failed")
    }
    b.keep(cst)
  })
}

///|
test "markdown prepass: block quote paragraph cst-first" (b : @bench.T) {
  let source = benchmark_block_quote_source()
  let ctx = block_quote_prepass_context()
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch {
      _ => abort("block quote parse failed")
    }
    b.keep(cst)
  })
  b.bench(fn() {
    let index = block_quote_prepass(ctx)
    b.keep(index)
  })
}

///|
test "markdown prepass: list item paragraph prepass-first" (b : @bench.T) {
  let source = benchmark_list_item_source()
  let ctx = list_item_prepass_context()
  b.bench(fn() {
    let index = list_item_prepass(ctx)
    b.keep(index)
  })
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch {
      _ => abort("list item parse failed")
    }
    b.keep(cst)
  })
}

///|
test "markdown prepass: list item paragraph cst-first" (b : @bench.T) {
  let source = benchmark_list_item_source()
  let ctx = list_item_prepass_context()
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch {
      _ => abort("list item parse failed")
    }
    b.keep(cst)
  })
  b.bench(fn() {
    let index = list_item_prepass(ctx)
    b.keep(index)
  })
}
