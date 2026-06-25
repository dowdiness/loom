// Incremental-node interpreter tests. TestToken / TestKind / test_spec are
// defined in interpreter_test.mbt (shared blackbox compilation unit).

///|
/// A wired WrapIfNext emits no diagnostic; the Task-4 placeholder would, so
/// this asserts the incremental node is actually interpreted (red → green).
test "WrapIfNext wraps a matching prefix without spurious diagnostics" {
  let expr : Expr[TestToken, TestKind] = Expr::WrapIfNext(
    TestKind::Root,
    Pred::IsToken(TestToken::Int),
    Expr::Emit(TestToken::Int, TestKind::IntToken),
  )
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = { "source": expr }
  let parse_root = interpret(GrammarIr::GrammarIr(rules, root="source"))
  let spec = test_spec(parse_root)
  let lex = _src => {
    [
      @core.TokenInfo::new(TestToken::Int, 1),
      @core.TokenInfo::new(TestToken::EOF, 0),
    ]
  }
  let (_, diagnostics) = @core.parse_with("1", spec, lex, parse_root)
  inspect(diagnostics.is_empty(), content="true")
}

///|
fn pratt_reuse_tokens() -> Array[@core.TokenInfo[TestToken]] {
  [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Skip, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
}

///|
fn pratt_reuse_starts() -> Array[Int] {
  [0, 1, 2, 3, 4, 5, 6, 7]
}

///|
fn pratt_reuse_rules() -> Map[RuleName, Expr[TestToken, TestToken]] {
  {
    "source": Expr::Seq([
      Expr::Ref("binary"),
      Expr::Emit(TestToken::Skip, TestToken::Skip),
      Expr::Ref("binary"),
    ]),
    "binary": Expr::PrattBinary(
      "atom",
      TestToken::Word,
      [(TestToken::Word, TestToken::Word)],
      skip=None,
    ),
    "atom": Expr::Emit(TestToken::Int, TestToken::Int),
  }
}

///|
fn pratt_reuse_spec(
  parse_root : (@core.ParserContext[TestToken, TestToken]) -> Unit,
) -> @core.LanguageSpec[TestToken, TestToken] {
  @core.LanguageSpec::new(
    TestToken::Expected,
    TestToken::EOF,
    TestToken::Expected,
    TestToken::EOF,
    parse_root~,
  )
}

///|
test "PrattBinary reuses unchanged retroactive wrapper before later edit" {
  let parse_root = interpret(
    GrammarIr::GrammarIr(pratt_reuse_rules(), root="source"),
  )
  let spec = pratt_reuse_spec(parse_root)
  let tokens = pratt_reuse_tokens()
  let starts = pratt_reuse_starts()
  let old_source = "1+2 3+4"
  let new_source = "1+2 3+5"
  let (old_tree, old_diags, _) = @core.parse_tokens_indexed(
    old_source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + tokens[i].len },
    spec,
  )
  inspect(old_diags.is_empty(), content="true")
  match old_tree.children[0] {
    @seam.CstElement::Node(node) =>
      if node.kind != TestToken::Word.to_raw() || node.text_len != 3 {
        abort("expected first Pratt wrapper to span '1+2'")
      }
    @seam.CstElement::Token(_) => abort("expected first Pratt wrapper node")
  }
  let edit = @core.Edit::replace(6, 7, 7)
  let cursor = @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) {
      new_source.view(
        start_offset=starts[i],
        end_offset=starts[i] + tokens[i].len,
      )
    },
    spec,
    reuse_size_threshold=0,
  )
  inspect(
    @debug.to_string(
      cursor.explain_reuse_rejection(TestToken::Word.to_raw(), 0, 0),
    ),
    content="None",
  )
  let (_, new_diags, reuse_count) = @core.parse_tokens_indexed(
    new_source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + tokens[i].len },
    spec,
    cursor=Some(cursor),
    prev_diagnostics=Some(old_diags),
  )
  inspect(new_diags.is_empty(), content="true")
  inspect(reuse_count, content="1")
}
