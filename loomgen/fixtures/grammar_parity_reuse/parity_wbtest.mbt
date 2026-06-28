///|
fn indexed_parse(
  source : String,
  parse : (@core.ParserContext[ReuseToken, ReuseKind]) -> Unit,
  cursor? : @core.ReuseCursor[ReuseToken, ReuseKind]? = None,
  prev_diagnostics? : @core.DiagnosticSet? = None,
) -> (@seam.CstNode, @core.DiagnosticSet, Int) {
  let tokens = repeat_tokens()
  let starts = repeat_starts()
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    reuse_spec(parse),
    cursor~,
    prev_diagnostics~,
  )
}

///|
fn reuse_cursor(
  old_tree : @seam.CstNode,
  new_source : String,
  parse : (@core.ParserContext[ReuseToken, ReuseKind]) -> Unit,
) -> @core.ReuseCursor[ReuseToken, ReuseKind] {
  let tokens = repeat_tokens()
  let starts = repeat_starts()
  let edit = @core.Edit::replace(2, 3, 3)
  @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => {
      new_source.view(
        start_offset=starts[i],
        end_offset=starts[i] + tokens[i].len,
      )
    },
    reuse_spec(parse),
    reuse_size_threshold=0,
  )
}

///|
test "generated parser matches interpreter reuse behavior for repeat groups" {
  let interpreted = @grammar.interpret(repeat_ir())
  let old_source = "xsx"
  let new_source = "xsy"
  let (interp_old_tree, interp_old_diags, _) = indexed_parse(
    old_source, interpreted,
  )
  let (gen_old_tree, gen_old_diags, _) = indexed_parse(old_source, parse_root)
  inspect(@core.tree_diff(interp_old_tree, gen_old_tree).length(), content="0")
  inspect(gen_old_diags == interp_old_diags, content="true")
  let (interp_new_tree, interp_new_diags, interp_reuse) = indexed_parse(
    new_source,
    interpreted,
    cursor=Some(reuse_cursor(interp_old_tree, new_source, interpreted)),
    prev_diagnostics=Some(interp_old_diags),
  )
  let (gen_new_tree, gen_new_diags, gen_reuse) = indexed_parse(
    new_source,
    parse_root,
    cursor=Some(reuse_cursor(gen_old_tree, new_source, parse_root)),
    prev_diagnostics=Some(gen_old_diags),
  )
  inspect(@core.tree_diff(interp_new_tree, gen_new_tree).length(), content="0")
  inspect(gen_new_diags == interp_new_diags, content="true")
  inspect(gen_reuse == interp_reuse, content="true")
}
