// Regression coverage for #875: repeated nested blockquote lines must not grow
// the parser call stack or CST container depth with physical line count.

///|
fn nested_blockquote_stack_doc(
  depth : Int,
  line_count : Int,
  terminator : String,
  terminate_last_line : Bool,
) -> String {
  let out = StringBuilder::new()
  for line = 0; line < line_count; line = line + 1 {
    for marker = 0; marker < depth; marker = marker + 1 {
      out.write_string("> ")
    }
    out.write_string("payload \{line}")
    if terminate_last_line || line + 1 < line_count {
      out.write_string(terminator)
    }
  }
  out.to_string()
}

///|
fn nested_blockquote_stack_max_quote_depth(cst : @seam.CstNode) -> Int {
  let pending : Array[(@seam.SyntaxNode, Int)] = [
    (@seam.SyntaxNode::from_cst(cst), 0),
  ]
  let mut max_quote_depth = 0
  while pending.pop() is Some((node, parent_quote_depth)) {
    let quote_depth = if node.kind() == BlockQuoteNode.to_raw() {
      parent_quote_depth + 1
    } else {
      parent_quote_depth
    }
    max_quote_depth = max_quote_depth.max(quote_depth)
    for child in node.children() {
      pending.push((child, quote_depth))
    }
  }
  max_quote_depth
}

///|
fn assert_nested_blockquote_stack_parse(
  label : String,
  source : String,
  expected_depth : Int,
) -> Unit {
  let (cst, diagnostics) = parse_cst(
    @core.SourceId("markdown-nested-blockquote-stack:" + label),
    source,
  ) catch {
    _ => abort("nested blockquote stack regression failed to lex: " + label)
  }
  guard diagnostics.length() == 0 else {
    abort("nested blockquote stack regression produced diagnostics: " + label)
  }
  guard @seam.SyntaxNode::from_cst(cst).text() == source else {
    abort("nested blockquote stack regression lost source text: " + label)
  }
  guard nested_blockquote_stack_max_quote_depth(cst) == expected_depth else {
    abort(
      "nested blockquote stack regression changed syntactic depth: " + label,
    )
  }
}

///|
test "nested blockquote stack: depth and line count remain independent" {
  for depth in [1, 8, 32, 128] {
    for line_count in [64, 128, 256] {
      assert_nested_blockquote_stack_parse(
        "depth=\{depth},lines=\{line_count}",
        line_end_cache_nested_quote_doc(depth, line_count),
        depth,
      )
    }
  }
}

///|
test "nested blockquote stack: line terminators and EOF preserve source" {
  for terminator in ["\n", "\r\n", "\r"] {
    for terminate_last_line in [false, true] {
      assert_nested_blockquote_stack_parse(
        "terminator=\{terminator.length()},eof=\{!terminate_last_line}",
        nested_blockquote_stack_doc(8, 256, terminator, terminate_last_line),
        8,
      )
    }
  }
}

///|
test "nested blockquote stack: repeated empty lines stay bounded" {
  assert_nested_blockquote_stack_parse(
    "empty-lines",
    "> > > > > > > >\n".repeat(256),
    8,
  )
}

///|
test "nested blockquote stack: marker spacing and indentation stay bounded" {
  for
    source in [
      "> > first\n> > second", ">>first\n>>second\n", "  > > first\r\n  > > second\r\n",
      ">  > first\r>  > second\r",
    ] {
    assert_nested_blockquote_stack_parse("marker-form", source, 2)
  }
}

///|
test "nested blockquote stack: lazy marker omission retains syntactic depth" {
  let source_id = @core.SourceId("markdown-nested-blockquote-stack-lazy")
  let source = "> > > alpha\n> > beta\n> gamma\nlazy\n"
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("nested blockquote lazy continuation failed to lex")
  }
  assert_eq(nested_blockquote_stack_max_quote_depth(cst), 3)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<blockquote>
      #|<blockquote>
      #|<p>alpha
      #|beta
      #|gamma
      #|lazy</p>
      #|</blockquote>
      #|</blockquote>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "nested blockquote stack: inline content keeps CommonMark semantics" {
  let source = "> > alpha *one*\n> > beta [two](/two)\n"
  let (cst, diagnostics) = parse_cst(
    @core.SourceId("markdown-nested-blockquote-stack-html"),
    source,
  ) catch {
    _ => abort("nested blockquote CommonMark regression failed to lex")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    @core.SourceId("markdown-nested-blockquote-stack-html"),
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<blockquote>
      #|<p>alpha <em>one</em>
      #|beta <a href="/two">two</a></p>
      #|</blockquote>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "nested blockquote stack: repeated depth owns following block transitions" {
  let source_id = @core.SourceId("markdown-nested-blockquote-stack-blocks")
  let source = "> > alpha\n> > # heading\n"
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("nested blockquote block transition failed to lex")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<blockquote>
      #|<p>alpha</p>
      #|<h1>heading</h1>
      #|</blockquote>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "nested blockquote stack: shallower block transition retains outer quotes" {
  let source_id = @core.SourceId("markdown-nested-blockquote-stack-shallower")
  let source = "> > > alpha\n> > # beta\n"
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("shallower nested blockquote transition failed to lex")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<blockquote>
      #|<blockquote>
      #|<p>alpha</p>
      #|</blockquote>
      #|<h1>beta</h1>
      #|</blockquote>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "nested blockquote stack: setext and list blocks retain repeated depth" {
  let source_id = @core.SourceId(
    "markdown-nested-blockquote-stack-block-matrix",
  )
  let source = "> > alpha\n> > ---\n> > - item\n"
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("nested blockquote block matrix failed to lex")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<blockquote>
      #|<h2>alpha</h2>
      #|<ul>
      #|<li>item</li>
      #|</ul>
      #|</blockquote>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "nested blockquote stack: shallower block forms preserve source and incremental parity" {
  for
    source in [
      "> > > alpha\n> > ---\n", "> > > alpha\n> > - item\n", "> > > alpha\n> > ```\n> > code\n> > ```\n",
      "> > > alpha\n> > <div>\n> > raw\n> > </div>\n", "> > > alpha\n> > [foo]: /url\n",
    ] {
    assert_nested_blockquote_stack_parse("shallower-block-form", source, 3)
    let edit_start = perf_work_find_from(source, "alpha", 0)
    guard edit_start >= 0 else {
      abort("shallower nested blockquote edit target not found")
    }
    let updated = source[:edit_start].to_owned() +
      "omega" +
      source[edit_start + "alpha".length():].to_owned()
    ignore(
      @loom.assert_incremental_edit_matches_full_parse(
        @core.SourceId("markdown-nested-blockquote-shallower-incremental"),
        "shallower nested blockquote block form",
        source,
        @core.Edit::replace(
          edit_start,
          edit_start + "alpha".length(),
          edit_start + "omega".length(),
        ),
        updated,
        markdown_grammar.to_syntax_grammar(),
      ),
    )
  }
}

///|
test "nested blockquote stack: list-owned indentation retains repeated quote" {
  let source_id = @core.SourceId("markdown-nested-blockquote-stack-list-owned")
  let source = "- item\n    > > one\n    > > two\n"
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("list-owned nested blockquote failed to lex")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>item
      #|<blockquote>
      #|<blockquote>
      #|<p>one
      #|two</p>
      #|</blockquote>
      #|</blockquote>
      #|</li>
      #|</ul>
      #|
    ),
  )
  assert_nested_blockquote_stack_parse(
    "list-owned-stress",
    "- item\n" + "    > > > > > > > > payload\n".repeat(256),
    8,
  )
}

///|
test "nested blockquote stack: list-owned indentation accepts its column range" {
  let source_id = @core.SourceId("markdown-nested-blockquote-stack-list-range")
  let source = "- item\n    > > one\n     > > two\n\t> > three\n"
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("list-owned range nested blockquote failed to lex")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>item
      #|<blockquote>
      #|<blockquote>
      #|<p>one
      #|two
      #|three</p>
      #|</blockquote>
      #|</blockquote>
      #|</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "nested blockquote stack: incremental edit and restore match fresh parse" {
  let source_id = @core.SourceId("markdown-nested-blockquote-stack-incremental")
  let source = line_end_cache_nested_quote_doc(8, 128) + "\nTail\n"
  let edit_start = perf_work_find_from(source, "payload 64", 0)
  guard edit_start >= 0 else {
    abort("nested blockquote edit target not found")
  }
  let edited = source[:edit_start].to_owned() +
    "changed" +
    source[edit_start + "payload".length():].to_owned()
  let edit = @core.Edit::replace(
    edit_start,
    edit_start + "payload".length(),
    edit_start + "changed".length(),
  )
  let reuse_count = @loom.assert_incremental_edit_matches_full_parse(
    source_id,
    "nested blockquote stack edit preserves trailing sibling reuse",
    source,
    edit,
    edited,
    markdown_grammar.to_syntax_grammar(),
  )
  assert_true(reuse_count > 0)
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  parser.apply_edit(edit, edited)
  let edited_fresh = @loom.new_parser(source_id, edited, markdown_grammar)
  assert_eq(
    parser.syntax_tree().read_or_abort().cst_node(),
    edited_fresh.syntax_tree().read_or_abort().cst_node(),
  )
  assert_eq(
    parser.diagnostics().read_or_abort(),
    edited_fresh.diagnostics().read_or_abort(),
  )
  assert_eq(parser.ast().read_or_abort(), edited_fresh.ast().read_or_abort())

  parser.apply_edit(edit, source)
  let restored_fresh = @loom.new_parser(source_id, source, markdown_grammar)
  assert_eq(
    parser.syntax_tree().read_or_abort().cst_node(),
    restored_fresh.syntax_tree().read_or_abort().cst_node(),
  )
  assert_eq(
    parser.diagnostics().read_or_abort(),
    restored_fresh.diagnostics().read_or_abort(),
  )
  assert_eq(parser.ast().read_or_abort(), restored_fresh.ast().read_or_abort())
  assert_eq(parser.syntax_tree().read_or_abort().text(), source)
}
