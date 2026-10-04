///|
struct DependencyTestSnapshot {
  source : String
  tree : @seam.CstNode
  dependencies : ReuseDependencies?
  reused : Int
}

///|
fn dependency_test_spec(
  parse_root : (ParserContext[TestTok, TestKind]) -> Unit,
  tracking? : Bool = true,
) -> LanguageSpec[TestTok, TestKind] {
  LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TokEof,
    incomplete_kind=KIncomplete,
    parse_root~,
    reuse_size_threshold=0,
    track_reuse_dependencies=tracking,
  )
}

///|
fn dependency_parse(
  source : String,
  spec : LanguageSpec[TestTok, TestKind],
  previous? : DependencyTestSnapshot,
  edit? : Edit,
) -> DependencyTestSnapshot raise {
  let (tokens, starts) = test_tokenize_with_starts(source)
  let cursor = previous.map(old => {
    ReuseCursor::new_with_edit(
      old.tree,
      edit.unwrap(),
      tokens.length(),
      i => tokens[i].token,
      i => starts[i],
      i => {
        source.view(
          start_offset=starts[i],
          end_offset=starts[i] + tokens[i].len,
        )
      },
      spec,
      dependencies=old.dependencies,
    )
  })
  let mut dependencies = None
  let (tree, diagnostics, reused) = parse_tokens_indexed(
    SourceId("reuse-dependency-source"),
    source,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    spec,
    cursor~,
    on_reuse_dependencies=found => dependencies = Some(found),
  )
  assert_true(diagnostics.is_empty())
  assert_eq(@seam.SyntaxNode::from_cst(tree).text(), source)
  { source, tree, dependencies, reused, }
}

///|
fn dependency_drain(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  while !ctx.at_eof() {
    match ctx.peek() {
      Plus => ctx.emit_token(KPlus)
      _ => ctx.emit_token(KNum)
    }
  }
}

///|
test "reuse dependencies preserve failed lookahead across reuse and undo" {
  let mut executions = 0
  let spec = dependency_test_spec(ctx => {
    ctx.node(KExpr, () => {
      executions += 1
      let continues = ctx.lookahead(() => {
        ctx.emit_token(KNum)
        ctx.emit_token(KPlus)
        ctx.peek() == Num(2)
      })
      ctx.emit_token(KNum)
      if continues {
        ctx.emit_token(KPlus)
        ctx.emit_token(KNum)
      }
    })
    dependency_drain(ctx)
  })
  let initial = dependency_parse("1+3+5", spec)
  executions = 0
  let middle = dependency_parse(
    "1+3+6",
    spec,
    previous=initial,
    edit=Edit::new(4, 1, 1),
  )
  assert_eq(executions, 0)
  assert_eq(middle.reused, 1)
  assert_eq(middle.tree, dependency_parse(middle.source, spec).tree)
  executions = 0
  let extended = dependency_parse(
    "1+2+6",
    spec,
    previous=middle,
    edit=Edit::new(2, 1, 1),
  )
  assert_eq(executions, 1)
  assert_eq(extended.tree.children()[0].text_len(), 3)
  assert_eq(extended.tree, dependency_parse(extended.source, spec).tree)
  let undone = dependency_parse(
    middle.source,
    spec,
    previous=extended,
    edit=Edit::new(2, 1, 1),
  )
  assert_eq(undone.tree, middle.tree)
}

///|
test "reuse context compares the complete inherited key and restores outer scope" {
  let mut special = false
  let mut executions = 0
  let outer = ReuseContext::new(7, 0)
  let spec = dependency_test_spec(ctx => {
    ctx.with_reuse_context(outer, () => {
      let parent = ReuseContext::new(
        8,
        if special {
          1
        } else {
          0
        },
        parent=ctx.current_reuse_context(),
      )
      ctx.with_reuse_context(parent, () => {
        let child = ReuseContext::new(9, 0, parent=ctx.current_reuse_context())
        ctx.with_reuse_context(child, () => {
          ctx.node(KExpr, () => {
            executions += 1
            if special {
              ctx.start_node(KComment)
            }
            ctx.emit_token(KNum)
            if special {
              ctx.finish_node()
            }
          })
        })
      })
      ctx.emit_token(KPlus)
      // This node is back in the unchanged outer context.
      ctx.node(KExpr, () => ctx.emit_token(KNum))
    })
    dependency_drain(ctx)
  })
  let initial = dependency_parse("1+2+3", spec)
  executions = 0
  let unchanged = dependency_parse(
    initial.source,
    spec,
    previous=initial,
    edit=Edit::new(5, 0, 0),
  )
  assert_eq(executions, 0)
  assert_eq(unchanged.reused, 2)
  special = true
  executions = 0
  let changed = dependency_parse(
    initial.source,
    spec,
    previous=unchanged,
    edit=Edit::new(5, 0, 0),
  )
  assert_eq(executions, 1)
  assert_eq(changed.reused, 1)
  assert_true(changed.tree.children()[0] != initial.tree.children()[0])
  assert_eq(changed.tree, dependency_parse(changed.source, spec).tree)
}

///|
test "retroactive parent retains the dependencies of a reused child" {
  let mut reuse_parent = false
  let mut child_executions = 0
  let mut parent_executions = 0
  let spec = dependency_test_spec(ctx => {
    if !reuse_parent || !ctx.try_reuse_current_node(KComment) {
      parent_executions += 1
      let mark = ctx.mark()
      ctx.node(KExpr, () => {
        child_executions += 1
        let special = ctx.peek_nth(4) == Num(5)
        if special {
          ctx.start_node(KRoot)
        }
        ctx.emit_token(KNum)
        if special {
          ctx.finish_node()
        }
      })
      ctx.emit_token(KPlus)
      ctx.start_at(mark, KComment)
      ctx.finish_node()
    }
    dependency_drain(ctx)
  })
  let initial = dependency_parse("1+3+5+7+9", spec)
  child_executions = 0
  parent_executions = 0
  let middle = dependency_parse(
    "1+3+5+7+8",
    spec,
    previous=initial,
    edit=Edit::new(8, 1, 1),
  )
  assert_eq(child_executions, 0)
  assert_eq(parent_executions, 1)
  assert_eq(middle.reused, 1)
  reuse_parent = true
  child_executions = 0
  parent_executions = 0
  let changed = dependency_parse(
    "1+3+6+7+8",
    spec,
    previous=middle,
    edit=Edit::new(4, 1, 1),
  )
  assert_eq(parent_executions, 1)
  assert_eq(child_executions, 1)
  assert_true(changed.tree.children()[0] != middle.tree.children()[0])
  assert_eq(changed.tree, dependency_parse(changed.source, spec).tree)
}

///|
test "observed EOF invalidates an earlier node with an unchanged following token" {
  let spec = dependency_test_spec(ctx => {
    ctx.node(KExpr, () => {
      let ends_after_plus = ctx.peek_nth(2) == TokEof
      if ends_after_plus {
        ctx.start_node(KComment)
      }
      ctx.emit_token(KNum)
      if ends_after_plus {
        ctx.finish_node()
      }
    })
    dependency_drain(ctx)
  })
  let initial = dependency_parse("1+", spec)
  let extended = dependency_parse(
    "1+2",
    spec,
    previous=initial,
    edit=Edit::insert(2, 1),
  )
  assert_true(extended.tree.children()[0] != initial.tree.children()[0])
  assert_eq(extended.tree, dependency_parse(extended.source, spec).tree)
}

///|
test "declared backing-source observations invalidate otherwise unchanged nodes" {
  let spec = dependency_test_spec(ctx => {
    ctx.node(KExpr, () => {
      let source = ctx.current_token_text().data()
      ctx.observe_source_range(4, 5)
      let special = source[4] == '5'
      if special {
        ctx.start_node(KComment)
      }
      ctx.emit_token(KNum)
      if special {
        ctx.finish_node()
      }
    })
    dependency_drain(ctx)
  })
  let initial = dependency_parse("1+3+5", spec)
  let changed = dependency_parse(
    "1+3+6",
    spec,
    previous=initial,
    edit=Edit::new(4, 1, 1),
  )
  assert_true(changed.tree.children()[0] != initial.tree.children()[0])
  assert_eq(changed.tree, dependency_parse(changed.source, spec).tree)
}

///|
test "missing dependency metadata fails closed without changing legacy reuse" {
  for tracking in [true, false] {
    let mut executions = 0
    let spec = dependency_test_spec(
      ctx => {
        ctx.node(KExpr, () => {
          executions += 1
          ctx.emit_token(KNum)
        })
        dependency_drain(ctx)
      },
      tracking~,
    )
    let initial = dependency_parse("1+2+3", spec)
    let without_metadata = { ..initial, dependencies: None, }
    executions = 0
    let unchanged = dependency_parse(
      initial.source,
      spec,
      previous=without_metadata,
      edit=Edit::new(5, 0, 0),
    )
    assert_eq(executions, if tracking { 1 } else { 0 })
    assert_eq(unchanged.reused, if tracking { 0 } else { 1 })
    assert_eq(unchanged.tree, initial.tree)
  }
}

///|
test "block-splice history rebases unaffected occurrences without mutating old snapshots" {
  let mut executions = 0
  let spec = dependency_test_spec(ctx => {
    while !ctx.at_eof() {
      ctx.node(KExpr, () => {
        executions += 1
        ctx.emit_token(KNum)
      })
      if ctx.at(Plus) {
        ctx.emit_token(KPlus)
      }
    }
  })
  let initial = dependency_parse("1+2+3+4+5+6", spec)
  let spliced = dependency_parse("1+22+33+4+5+6", spec)
  let history = initial.dependencies
    .unwrap()
    .after_edit(Edit::new(2, 1, 2))
    .after_edit(Edit::new(5, 1, 2))
  let previous = { ..spliced, dependencies: Some(history), }
  executions = 0
  let changed = dependency_parse(
    "1+22+33+4+9+6",
    spec,
    previous~,
    edit=Edit::new(10, 1, 1),
  )
  assert_eq(changed.reused, 2)
  assert_eq(executions, 4)
  assert_eq(changed.tree, dependency_parse(changed.source, spec).tree)
  executions = 0
  let original_branch = dependency_parse(
    "1+2+3+4+5+7",
    spec,
    previous=initial,
    edit=Edit::new(10, 1, 1),
  )
  assert_eq(original_branch.reused, 5)
  assert_eq(executions, 1)
  assert_eq(
    original_branch.tree,
    dependency_parse(original_branch.source, spec).tree,
  )
}

///|
test "reuse dependencies distinguish nested same-kind occurrences at one span" {
  let spec = dependency_test_spec(ctx => {
    ctx.start_node(KExpr)
    ctx.node(KExpr, () => ctx.emit_token(KNum))
    ctx.finish_node()
    dependency_drain(ctx)
  })
  let initial = dependency_parse("1+2+3", spec)
  let incremental = dependency_parse(
    "1+2+4",
    spec,
    previous=initial,
    edit=Edit::new(4, 1, 1),
  )
  assert_eq(incremental.tree, dependency_parse(incremental.source, spec).tree)
}
