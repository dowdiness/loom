///|

///|
/// Incremental vs full-parse parity for block-container edits.
/// `require_cst=false` skips CST `tree_diff`, projection roles, and reuse
/// count when leftover fence-mode token kinds differ; diagnostics, AST, IR,
/// and HTML still match.
fn assert_block_container_incremental_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  require_cst? : Bool = true,
) -> Int raise {
  let source_id = @core.SourceId("markdown-block-container-decision-core")
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let (direct_cst, direct_diagnostics) = try! parse_cst(source_id, updated)
  let direct_syntax = @seam.SyntaxNode::from_cst(direct_cst)
  if require_cst {
    assert_eq(
      @core.tree_diff(incremental_syntax.cst_node(), direct_cst).is_empty(),
      true,
    )
    assert_eq(
      @core.tree_diff(fresh_syntax.cst_node(), direct_cst).is_empty(),
      true,
    )
    assert_eq(
      project_markdown_roles(incremental_syntax),
      project_markdown_roles(fresh_syntax),
    )
    assert_eq(
      project_markdown_roles(fresh_syntax),
      project_markdown_roles(direct_syntax),
    )
  }
  assert_eq(
    incremental.diagnostics().read_or_abort(),
    fresh.diagnostics().read_or_abort(),
  )
  assert_eq(fresh.diagnostics().read_or_abort(), direct_diagnostics)
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    incremental_syntax,
    incremental.diagnostics().read_or_abort(),
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    fresh_syntax,
    fresh.diagnostics().read_or_abort(),
  )
  let direct_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, direct_syntax, direct_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  assert_eq(fresh_ir, direct_ir)
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(incremental_ir),
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
    experimental_markdown_ir_to_commonmark_html(direct_ir),
  )
  if require_cst {
    markdown_incremental_edit_reuse_count(
      source_id, label, source, edit, updated,
    )
  } else {
    0
  }
}

///|
priv struct ContainerIndentationEditCase {
  label : String
  source : String
  edit : @core.Edit
  updated : String
  expected_before_html : String
  expected_html : String
  assert_nonlocal_reparse : Bool
}

///|
fn direct_commonmark_html(
  source_id : @core.SourceId,
  source : String,
) -> String {
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  experimental_markdown_ir_to_commonmark_html(ir)
}

///|
test "block container core: indentation boundary edits preserve fresh parser and lowering semantics" {
  let cases : Array[ContainerIndentationEditCase] = [
    {
      label: "empty item code threshold",
      source: "-\n     code\n",
      edit: @core.Edit::insert("-\n".length(), 1),
      updated: "-\n      code\n",
      expected_before_html: "<ul>\n<li>code</li>\n</ul>\n",
      expected_html: "<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n",
      assert_nonlocal_reparse: true,
    },
    {
      label: "tab-expanded list continuation",
      source: "- foo\n\n\tbar\n",
      edit: @core.Edit::insert("- foo\n\n\t".length(), 1),
      updated: "- foo\n\n\t\tbar\n",
      expected_before_html: "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n",
      expected_html: "<ul>\n<li>\n<p>foo</p>\n<pre><code>  bar\n</code></pre>\n</li>\n</ul>\n",
      assert_nonlocal_reparse: true,
    },
    {
      label: "tab-expanded block quote code",
      source: ">\tfoo\n",
      edit: @core.Edit::insert(">\t".length(), 1),
      updated: ">\t\tfoo\n",
      expected_before_html: "<blockquote>\n<p>foo</p>\n</blockquote>\n",
      expected_html: "<blockquote>\n<pre><code>  foo\n</code></pre>\n</blockquote>\n",
      assert_nonlocal_reparse: true,
    },
    {
      label: "tab-expanded initial code",
      source: "-\tfoo\n",
      edit: @core.Edit::insert("-\t".length(), 1),
      updated: "-\t\tfoo\n",
      expected_before_html: "<ul>\n<li>foo</li>\n</ul>\n",
      expected_html: "<ul>\n<li>\n<pre><code>  foo\n</code></pre>\n</li>\n</ul>\n",
      assert_nonlocal_reparse: false,
    },
    {
      label: "blank marker tail code threshold",
      source: "-   \n     code\n",
      edit: @core.Edit::insert("-   \n".length(), 1),
      updated: "-   \n      code\n",
      expected_before_html: "<ul>\n<li>code</li>\n</ul>\n",
      expected_html: "<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n",
      assert_nonlocal_reparse: true,
    },
    {
      label: "quoted tab marker",
      source: ">  - foo\n",
      edit: @core.Edit::new("> ".length(), 1, 1),
      updated: "> \t- foo\n",
      expected_before_html: "<blockquote>\n<ul>\n<li>foo</li>\n</ul>\n</blockquote>\n",
      expected_html: "<blockquote>\n<ul>\n<li>foo</li>\n</ul>\n</blockquote>\n",
      assert_nonlocal_reparse: false,
    },
    {
      label: "nonempty item code threshold",
      source: "- foo\n\n     code\n",
      edit: @core.Edit::insert("- foo\n\n".length(), 1),
      updated: "- foo\n\n      code\n",
      expected_before_html: "<ul>\n<li>\n<p>foo</p>\n<p>code</p>\n</li>\n</ul>\n",
      expected_html: "<ul>\n<li>\n<p>foo</p>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n",
      assert_nonlocal_reparse: true,
    },
  ]
  for case in cases {
    let source_id = @core.SourceId(
      "markdown-container-indentation-edit-" + case.label,
    )
    assert_eq(
      direct_commonmark_html(source_id, case.source),
      case.expected_before_html,
    )
    assert_eq(
      direct_commonmark_html(source_id, case.updated),
      case.expected_html,
    )
    let reuse_count = assert_block_container_incremental_parity(
      case.label,
      case.source,
      case.edit,
      case.updated,
    )
    if case.assert_nonlocal_reparse {
      inspect(reuse_count != 1, content="true")
    }
    let parser = @loom.new_parser(source_id, case.source, markdown_grammar)
    parser.apply_edit(case.edit, case.updated)
    let syntax = parser.syntax_tree().read_or_abort()
    let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id,
      syntax,
      parser.diagnostics().read_or_abort(),
    )
    assert_eq(
      experimental_markdown_ir_to_commonmark_html(ir),
      case.expected_html,
    )
  }
}

///|
test "block container core: migrated edit families match fresh semantic projections" {
  ignore(
    assert_block_container_incremental_parity(
      "block container indentation boundary",
      "paragraph\n   # heading\n",
      @core.Edit::insert("paragraph\n".length(), " ".length()),
      "paragraph\n    # heading\n",
    ),
  )
  let blank_line_reuse = assert_block_container_incremental_parity(
    "block container blank-line boundary",
    "- one\n- two\n",
    @core.Edit::insert("- one\n".length(), "\n".length()),
    "- one\n\n- two\n",
  )
  inspect(blank_line_reuse != 1, content="true")
  ignore(
    assert_block_container_incremental_parity(
      "block container blockquote lazy continuation",
      "> bar\n> baz\n",
      @core.Edit::delete("> bar\n".length(), "> bar\n> ".length()),
      "> bar\nbaz\n",
    ),
  )
  let marker_reuse = assert_block_container_incremental_parity(
    "block container marker boundary",
    "- one\n- two\n- three\n",
    @core.Edit::new("- one\n".length(), "-".length(), "*".length()),
    "- one\n* two\n- three\n",
  )
  inspect(marker_reuse != 1, content="true")
  let fence_reuse = assert_block_container_incremental_parity(
    "block container fence boundary",
    "`` text\nTail\n",
    @core.Edit::insert("``".length(), "`".length()),
    "``` text\nTail\n",
  )
  inspect(fence_reuse != 1, content="true")
}
