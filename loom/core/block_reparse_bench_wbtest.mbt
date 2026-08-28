// Direct phase benchmark for isolated block parsing.
//
// Run: NEW_MOON_MOD=0 moon bench --release --target js loom/core \
//   -f block_reparse_bench_wbtest.mbt

///|
fn block_reparse_bench_parse_nested_expr(
  ctx : ParserContext[TestTok, TestKind],
) -> Unit {
  ctx.node(KExpr, () => {
    ctx.emit_token(KNum)
    ctx.emit_token(KPlus)
    ctx.node(KExpr, () => {
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.emit_token(KNum)
      ctx.emit_token(KPlus)
      ctx.emit_token(KNum)
    })
  })
}

///|
test "block reparse: direct isolated parse and diagnostics" (b : @bench.T) {
  let fixtures = Array::makei(16, i => {
    let source = (i % 10).to_string() + "+2+3+4"
    let (tokens, starts) = test_tokenize_with_starts(source)
    (source, tokens, starts)
  })
  let (first_source, first_tokens, first_starts) = fixtures[0]
  guard parse_block_isolated(
      SourceId("block-reparse-direct-phase"),
      first_source,
      test_kind_raw(KExpr),
      first_tokens,
      first_starts,
      block_reparse_bench_parse_nested_expr,
      test_spec,
    )
    is Some(_) else {
    abort("direct isolated parse benchmark fixture must be valid")
  }
  let slot = [0]
  b.bench(() => {
    let index = slot[0]
    slot[0] = (index + 7) % fixtures.length()
    let (source, tokens, starts) = fixtures[index]
    let parsed = try
      parse_block_isolated(
        SourceId("block-reparse-direct-phase"),
        source,
        test_kind_raw(KExpr),
        tokens,
        starts,
        block_reparse_bench_parse_nested_expr,
        test_spec,
      )
    catch {
      _ => abort("direct isolated parse benchmark failed")
    } noraise {
      result => result
    }
    b.keep(parsed)
  })
}
