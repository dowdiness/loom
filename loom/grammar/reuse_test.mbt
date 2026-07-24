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
fn pratt_parse(
  source : String,
  tokens : Array[@core.TokenInfo[TestToken]],
  starts : Array[Int],
  spec : @core.LanguageSpec[TestToken, TestToken],
  cursor? : @core.ReuseCursor[TestToken, TestToken]? = None,
  prev_diagnostics? : @core.DiagnosticSet? = None,
) -> (@seam.CstNode, @core.DiagnosticSet, Int) {
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    spec,
    cursor~,
    prev_diagnostics~,
  )
}

///|
fn binary_growth_tokens() -> Array[@core.TokenInfo[TestToken]] {
  [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
}

///|
fn binary_growth_starts() -> Array[Int] {
  [0, 1, 2, 3, 4, 5]
}

///|
fn binary_growth_rules() -> Map[RuleName, Expr[TestToken, TestToken]] {
  {
    "source": Expr::Ref("binary"),
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
fn app_old_tokens() -> Array[@core.TokenInfo[TestToken]] {
  [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
}

///|
fn app_old_starts() -> Array[Int] {
  [0, 1, 2]
}

///|
fn app_growth_rules() -> Map[RuleName, Expr[TestToken, TestToken]] {
  {
    "source": Expr::Ref("application"),
    "application": Expr::PrattApp(
      "atom",
      TestToken::Word,
      Pred::IsToken(TestToken::Int),
    ),
    "atom": Expr::Emit(TestToken::Int, TestToken::Int),
  }
}

///|
fn app_growth_tokens() -> Array[@core.TokenInfo[TestToken]] {
  [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
}

///|
fn app_growth_starts() -> Array[Int] {
  [0, 1, 2, 3]
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
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    spec,
  )
  inspect(old_diags.is_empty(), content="true")
  match old_tree.children[0] {
    @seam.CstElement::Node(node) =>
      if node.kind != @seam.ToRawKind::to_raw(TestToken::Word) ||
        node.text_len != 3 {
        abort("expected first Pratt wrapper to span '1+2'")
      }
    @seam.CstElement::Token(_) => abort("expected first Pratt wrapper node")
  }
  let edit = @core.Edit::replace(6, 7, 7)
  let cursor = @core.ReuseCursor::new_with_edit(
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
    spec,
    reuse_size_threshold=0,
  )
  inspect(
    @debug.to_string(
      cursor.explain_reuse_rejection(
        @seam.ToRawKind::to_raw(TestToken::Word),
        0,
        0,
      ),
    ),
    content="None",
  )
  let (_, new_diags, reuse_count) = @core.parse_tokens_indexed(
    new_source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    spec,
    cursor=Some(cursor),
    prev_diagnostics=Some(old_diags),
  )
  inspect(new_diags.is_empty(), content="true")
  inspect(reuse_count, content="1")
}

///|
test "PrattBinary growth matches fresh full parse after suffix append" {
  let parse_root = interpret(
    GrammarIr::GrammarIr(binary_growth_rules(), root="source"),
  )
  let spec = pratt_reuse_spec(parse_root)
  let old_tokens = [
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::Word, 1),
    @core.TokenInfo::new(TestToken::Int, 1),
    @core.TokenInfo::new(TestToken::EOF, 0),
  ]
  let old_starts = [0, 1, 2, 3]
  let old_source = "1+2"
  let new_tokens = binary_growth_tokens()
  let new_starts = binary_growth_starts()
  let new_source = "1+2+3"
  let (old_tree, old_diags, _) = pratt_parse(
    old_source, old_tokens, old_starts, spec,
  )
  inspect(old_diags.is_empty(), content="true")
  let edit = @core.Edit::insert(3, 2)
  let cursor = @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_tokens.length(),
    i => new_tokens[i].token,
    i => new_starts[i],
    i => {
      new_source.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_tokens[i].len,
      )
    },
    spec,
    reuse_size_threshold=0,
  )
  let (incremental_tree, incremental_diags, incremental_reuse) = pratt_parse(
    new_source,
    new_tokens,
    new_starts,
    spec,
    cursor=Some(cursor),
    prev_diagnostics=Some(old_diags),
  )
  let (full_tree, full_diags, _) = pratt_parse(
    new_source, new_tokens, new_starts, spec,
  )
  inspect(incremental_diags == full_diags, content="true")
  inspect(@core.tree_diff(incremental_tree, full_tree).length(), content="0")
  inspect(incremental_reuse, content="0")
  ignore(())
}

///|
test "PrattApp growth matches fresh full parse after suffix append" {
  let parse_root = interpret(
    GrammarIr::GrammarIr(app_growth_rules(), root="source"),
  )
  let spec = pratt_reuse_spec(parse_root)
  let old_tokens = app_old_tokens()
  let old_starts = app_old_starts()
  let old_source = "12"
  let new_tokens = app_growth_tokens()
  let new_starts = app_growth_starts()
  let new_source = "123"
  let (old_tree, old_diags, _) = pratt_parse(
    old_source, old_tokens, old_starts, spec,
  )
  inspect(old_diags.is_empty(), content="true")
  let edit = @core.Edit::insert(2, 1)
  let cursor = @core.ReuseCursor::new_with_edit(
    old_tree,
    edit,
    new_tokens.length(),
    i => new_tokens[i].token,
    i => new_starts[i],
    i => {
      new_source.view(
        start_offset=new_starts[i],
        end_offset=new_starts[i] + new_tokens[i].len,
      )
    },
    spec,
    reuse_size_threshold=0,
  )
  let (incremental_tree, incremental_diags, incremental_reuse) = pratt_parse(
    new_source,
    new_tokens,
    new_starts,
    spec,
    cursor=Some(cursor),
    prev_diagnostics=Some(old_diags),
  )
  let (full_tree, full_diags, _) = pratt_parse(
    new_source, new_tokens, new_starts, spec,
  )
  inspect(incremental_diags == full_diags, content="true")
  inspect(@core.tree_diff(incremental_tree, full_tree).length(), content="0")
  inspect(incremental_reuse, content="0")
  ignore(())
}
