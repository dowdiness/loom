///|
fn root_plan_handler(
  ctx : @core.ParserContext[Token, SyntaxKind],
) -> ContinuationHandler[RootContinuationKind] {
  {
    decide: () => decide_root_paragraph_continuation(ctx),
    consume: action => consume_root_continuation(ctx, action),
    speculate: action => consume_root_continuation(ctx, action),
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => advance_root_continuation(ctx, offset, action),
  }
}

///|
test "container fact plan: line-bound plan stops at newline" {
  let source = "alpha\nbeta"
  let ctx = continuation_context(source)
  let plan : ContainerFactPlan[Unit] =
    build_container_fact_plan(ctx, InlineParsePolicy::paragraph(), None)
  inspect(plan.actions.length(), content="0")
  inspect(plan.end_offset, content="5")
}

///|
test "container fact plan: root continuation records typed action" {
  let source = "alpha\nbeta\n"
  let ctx = continuation_context(source)
  let plan = build_container_fact_plan(
    ctx,
    InlineParsePolicy::paragraph(),
    Some(root_plan_handler(ctx)),
  )
  match plan.actions.get(5) {
    Some(RootContinuationKind::NoPrefix) => ()
    _ => abort("expected planned root NoPrefix action")
  }
  inspect(plan.end_offset, content="10")
}

///|
test "container fact plan: delimiters retain equal-length successors" {
  let ctx = continuation_context("a `x` b")
  let plan : ContainerFactPlan[Unit] =
    build_container_fact_plan(ctx, InlineParsePolicy::paragraph(), None)
  inspect(plan.delimiters.eligible_openers.get(2), content="Some(true)")
  inspect(plan.delimiters.successors.get(2), content="Some(4)")
}

///|
test "container fact plan: continuation resets escaped-text state" {
  let ctx = continuation_context("a\\\n`x`")
  let plan = build_container_fact_plan(
    ctx,
    InlineParsePolicy::paragraph(),
    Some(root_plan_handler(ctx)),
  )
  inspect(plan.delimiters.eligible_openers.get(3), content="Some(true)")
  inspect(plan.delimiters.successors.get(3), content="Some(5)")
}
