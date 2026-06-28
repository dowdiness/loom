///|
/// Renders a built CST element for separated_list assertions: tokens as
/// `t<kind>:<text>` (`t<kind>ø` when zero-width), nodes as `n<kind>(children)`.
fn render_cst_element(elem : @seam.CstElement) -> String {
  match elem {
    Token(t) => {
      let @seam.RawKind(k) = t.kind
      if t.text_len() == 0 {
        "t\{k}ø"
      } else {
        "t\{k}:\{t.text()}"
      }
    }
    Node(n) => {
      let @seam.RawKind(k) = n.kind
      "n\{k}(" + n.children.map(render_cst_element).join(" ") + ")"
    }
  }
}

///|
/// Builds the root tree from a finished context and renders its children.
fn render_list_tree(ctx : ParserContext[TestTok, TestKind]) -> String {
  ctx.flush_trivia()
  let tree = ctx.events.build_tree_interned(
    test_spec.root_kind.to_raw(),
    @seam.Interner::new(),
    trivia_kinds=Some([test_spec.whitespace_kind.to_raw()]),
    error_kind=Some(test_spec.error_kind.to_raw()),
    incomplete_kind=Some(test_spec.incomplete_kind.to_raw()),
  ) catch {
    _ => abort("expected separated_list tree to build")
  }
  tree.children.map(render_cst_element).join(" ")
}

///|
/// Standard element parser for separated_list tests: one Num token or nothing.
fn parse_num_element(ctx : ParserContext[TestTok, TestKind]) -> () -> Bool {
  () => {
    match ctx.peek() {
      Num(_) => {
        ctx.emit_token(KNum)
        true
      }
      _ => false
    }
  }
}

///|
fn is_num_element_start(ctx : ParserContext[TestTok, TestKind]) -> () -> Bool {
  () => ctx.peek() is Num(_)
}

///|
/// Element parser that owns its node wrapper, used for wrapper-free list mode.
fn parse_wrapped_num_element(
  ctx : ParserContext[TestTok, TestKind],
) -> () -> Bool {
  () => {
    match ctx.peek() {
      Num(_) => {
        ctx.node(KExpr, fn() { ctx.emit_token(KNum) })
        true
      }
      _ => false
    }
  }
}

///|
test "separated_list parses a,b,c shape with wrapped elements" {
  let src = "1+2+3"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="3")
  inspect(render_list_tree(ctx), content="n2(t0:1) t1:+ n2(t0:2) t1:+ n2(t0:3)")
  inspect(ctx.diagnostics.items().length(), content="0")
}

///|
test "separated_list trailing separator emits empty error element" {
  let src = "1+2+"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="3")
  inspect(render_list_tree(ctx), content="n2(t0:1) t1:+ n2(t0:2) t1:+ n2(t5ø)")
  inspect(
    has_diagnostic_message(ctx.diagnostics, "expected element"),
    content="true",
  )
}

///|
test "separated_list leading separator emits empty error element in slot 0" {
  let src = "+1"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="2")
  inspect(render_list_tree(ctx), content="n2(t5ø) t1:+ n2(t0:1)")
  inspect(
    has_diagnostic_message(ctx.diagnostics, "expected element"),
    content="true",
  )
}

///|
test "separated_list doubled separator emits empty error element in middle slot" {
  let src = "1++2"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="3")
  inspect(render_list_tree(ctx), content="n2(t0:1) t1:+ n2(t5ø) t1:+ n2(t0:2)")
  inspect(
    has_diagnostic_message(ctx.diagnostics, "expected element"),
    content="true",
  )
}

///|
test "separated_list on empty input emits nothing and returns 0" {
  let ctx = ParserContext::new([], "", test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="0")
  inspect(render_list_tree(ctx), content="")
  inspect(ctx.diagnostics.items().length(), content="0")
}

///|
test "separated_list does not consume past the list end" {
  let src = "1+2 9"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="2")
  // Next non-trivia token (9) is still available to the caller.
  inspect(ctx.at(TestTok::Num(9)), content="true")
}

///|
test "separated_list missing separator recovers element start as next slot" {
  let src = "1 2"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(
    KExpr,
    TestTok::Plus,
    parse_num_element(ctx),
    element_start=is_num_element_start(ctx),
  )
  inspect(count, content="2")
  inspect(render_list_tree(ctx), content="n2(t0:1) t5ø n2(t4:  t0:2)")
  inspect(
    has_diagnostic_message(ctx.diagnostics, "expected separator"),
    content="true",
  )
}

///|
test "separated_list wrapper-free mode keeps parser-owned element nodes" {
  let src = "1 2"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(
    KExpr,
    TestTok::Plus,
    parse_wrapped_num_element(ctx),
    element_start=is_num_element_start(ctx),
    wrap_element=false,
  )
  inspect(count, content="2")
  inspect(render_list_tree(ctx), content="n2(t0:1) t5ø n2(t4:  t0:2)")
  inspect(
    has_diagnostic_message(ctx.diagnostics, "expected separator"),
    content="true",
  )
}

///|
test "separated_list wrapper-free trailing separator emits direct placeholder" {
  let src = "1+"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(
    KExpr,
    TestTok::Plus,
    parse_wrapped_num_element(ctx),
    wrap_element=false,
  )
  inspect(count, content="2")
  inspect(render_list_tree(ctx), content="n2(t0:1) t1:+ t5ø")
  inspect(
    has_diagnostic_message(ctx.diagnostics, "expected element"),
    content="true",
  )
}

///|
test "separated_list element wrap includes leading trivia like node()" {
  let src = "1+ 2"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  inspect(count, content="2")
  inspect(render_list_tree(ctx), content="n2(t0:1) t1:+ n2(t4:  t0:2)")
}

///|
test "separated_list no-progress success terminates without counting" {
  let src = "1"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  // Contract violation on purpose: claims success, never consumes.
  let count = ctx.separated_list(KExpr, TestTok::Plus, () => true)
  inspect(count, content="0")
  inspect(render_list_tree(ctx), content="")
}

///|
test "separated_list element slots hit incremental reuse like node()" {
  let src = "1+2+3"
  let (toks, starts) = test_tokenize_with_starts(src)
  let old_ctx = ParserContext::new(toks, src, test_spec)
  let old_count = old_ctx.separated_list(
    KExpr,
    TestTok::Plus,
    parse_num_element(old_ctx),
  )
  inspect(old_count, content="3")
  old_ctx.flush_trivia()
  let old_tree = old_ctx.events.build_tree_interned(
    test_spec.root_kind.to_raw(),
    @seam.Interner::new(),
    trivia_kinds=Some([test_spec.whitespace_kind.to_raw()]),
    error_kind=Some(test_spec.error_kind.to_raw()),
    incomplete_kind=Some(test_spec.incomplete_kind.to_raw()),
  ) catch {
    _ => abort("expected interned old tree")
  }
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  let count = ctx.separated_list(KExpr, TestTok::Plus, () => {
    abort("element body must not run on reuse hit")
  })
  inspect(count, content="3")
  inspect(ctx.reuse_count, content="3")
  inspect(render_list_tree(ctx), content="n2(t0:1) t1:+ n2(t0:2) t1:+ n2(t0:3)")
}

///|
test "separated_list missing separator still recovers after element reuse" {
  let src = "1 2"
  let (toks, starts) = test_tokenize_with_starts(src)
  let old_ctx = ParserContext::new(toks, src, test_spec)
  let old_count = old_ctx.separated_list(
    KExpr,
    TestTok::Plus,
    parse_num_element(old_ctx),
    element_start=is_num_element_start(old_ctx),
  )
  inspect(old_count, content="2")
  old_ctx.flush_trivia()
  let old_tree = old_ctx.events.build_tree_interned(
    test_spec.root_kind.to_raw(),
    @seam.Interner::new(),
    trivia_kinds=Some([test_spec.whitespace_kind.to_raw()]),
    error_kind=Some(test_spec.error_kind.to_raw()),
    incomplete_kind=Some(test_spec.incomplete_kind.to_raw()),
  ) catch {
    _ => abort("expected interned old tree")
  }
  let cursor : ReuseCursor[TestTok, TestKind] = ReuseCursor::new(
    old_tree,
    99,
    99,
    toks.length(),
    fn(i) { toks[i].token },
    fn(i) { starts[i] },
    fn(i) {
      src.view(start_offset=starts[i], end_offset=starts[i] + toks[i].len)
    },
    test_spec,
  )
  let ctx = ParserContext::new(toks, src, test_spec)
  ctx.set_reuse_cursor(cursor)
  let count = ctx.separated_list(
    KExpr,
    TestTok::Plus,
    () => abort("element body must not run on reuse hit"),
    element_start=is_num_element_start(ctx),
  )
  inspect(count, content="2")
  inspect(ctx.reuse_count, content="2")
  inspect(render_list_tree(ctx), content="n2(t0:1) t5ø n2(t4:  t0:2)")
}

///|
test "separated_list lone separator emits leading and trailing empty elements" {
  let src = "+"
  let ctx = ParserContext::new(test_tokenize(src), src, test_spec)
  let count = ctx.separated_list(KExpr, TestTok::Plus, parse_num_element(ctx))
  // One separator, two slots: both empty error elements.
  inspect(count, content="2")
  inspect(render_list_tree(ctx), content="n2(t5ø) t1:+ n2(t5ø)")
  inspect(ctx.diagnostics.items().length(), content="2")
}
