///|
test "LanguageSpec retains one CST metadata policy instance" {
  let spec = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    trivia_kinds_spec=[KWs],
  )
  let retained = spec.cst_metadata_policy
  assert_true(physical_equal(retained, spec.cst_metadata_policy))
  let child = @seam.CstNode::new(@seam.RawKind(2), [], policy=retained)
  let parent = @seam.CstNode::new(
    @seam.RawKind(1),
    [@seam.CstElement::Node(child)],
    policy=spec.cst_metadata_policy,
  )
  assert_eq(parent.children().length(), 1)
}

///|
test "incremental policy mismatch reaches the caller as Failure" {
  let source = "1"
  let source_id = SourceId("policy-mismatch-integration")
  let (tokens, starts) = test_tokenize_with_starts(source)
  let target_spec = LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=fn(ctx) { ctx.node(KExpr, fn() { ctx.emit_token(KNum) }) },
    trivia_kinds_spec=[KWs],
  )
  let foreign_policy = @seam.CstMetadataPolicy::new(
    [test_kind_raw(KWs), @seam.RawKind(999)],
    error_kind=Some(test_kind_raw(KErr)),
    incomplete_kind=Some(test_kind_raw(KIncomplete)),
  )
  let old_tree = @seam.build_tree(
    [
      @seam.ParseEvent::StartNode(test_kind_raw(KExpr)),
      @seam.ParseEvent::Token(test_kind_raw(KNum), "1"),
      @seam.ParseEvent::FinishNode,
    ],
    test_kind_raw(KRoot),
    policy=foreign_policy,
  )
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => {
      source.view(start_offset=starts[i], end_offset=starts[i] + tokens[i].len)
    },
    target_spec,
  )
  try
    parse_tokens_indexed(
      source_id,
      source,
      tokens.length(),
      i => tokens[i].token,
      i => starts[i],
      i => starts[i] + tokens[i].len,
      target_spec,
      cursor=Some(cursor),
    )
  catch {
    Failure::Failure(_) => ()
  } noraise {
    _ => abort("policy mismatch must not produce a fallback tree")
  }
}
