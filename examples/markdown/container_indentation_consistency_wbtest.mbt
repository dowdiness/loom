///|
priv struct ContainerIndentationCase {
  label : String
  source : String
  expected_code_values : Array[String]
  expected_html : String
}

///|
fn collect_syntax_code_block_values(
  node : @seam.SyntaxNode,
  values : Array[String],
) -> Unit {
  if node.kind() == CodeBlockNode.to_raw() {
    values.push(code_block_value(node))
  }
  for child in node.children() {
    collect_syntax_code_block_values(child, values)
  }
}

///|
fn collect_ir_code_block_facts(
  ir : MarkdownIR,
  values : Array[String],
  content_origins : Array[MarkdownIROrigin?],
) -> Unit {
  match ir.node {
    CodeBlock(_, value, content_origin) => {
      values.push(value)
      content_origins.push(content_origin)
    }
    _ =>
      for child in ir.children() {
        collect_ir_code_block_facts(child, values, content_origins)
      }
  }
}

///|
fn assert_container_indentation_case(
  case : ContainerIndentationCase,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-container-indentation-" + case.label)
  let (cst, diagnostics) = try! parse_cst(source_id, case.source)
  assert_eq(diagnostics.is_empty(), true)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let syntax_values : Array[String] = []
  collect_syntax_code_block_values(syntax, syntax_values)
  assert_eq(syntax_values, case.expected_code_values)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, syntax, diagnostics,
  )
  let ir_values : Array[String] = []
  let ir_content_origins : Array[MarkdownIROrigin?] = []
  collect_ir_code_block_facts(ir, ir_values, ir_content_origins)
  assert_eq(ir_values, syntax_values)
  assert_eq(ir_content_origins, ir_values.map(_ => None))
  assert_eq(experimental_markdown_ir_to_commonmark_html(ir), case.expected_html)
}

///|
test "container indentation: list-owned fences preserve close and content columns" {
  let cases : Array[(String, Array[String], String)] = [
    (
      "- a\n  - b\n      ~~~~\n      code\n      ~~~~\n",
      ["code"],
      "<ul>\n<li>a\n<ul>\n<li>b\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n</li>\n</ul>\n",
    ),
    (
      "- item\n    ```\n      code\n    ```\n",
      ["  code"],
      "<ul>\n<li>item\n<pre><code>  code\n</code></pre>\n</li>\n</ul>\n",
    ),
  ]
  for index, case in cases {
    let (source, expected_values, expected_html) = case
    let source_id = @core.SourceId(
      "markdown-list-owned-fence-regression-" + index.to_string(),
    )
    let (cst, diagnostics) = try! parse_cst(source_id, source)
    assert_true(diagnostics.is_empty())
    let syntax = @seam.SyntaxNode::from_cst(cst)
    let syntax_values : Array[String] = []
    collect_syntax_code_block_values(syntax, syntax_values)
    assert_eq(syntax_values, expected_values)
    let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id, syntax, diagnostics,
    )
    let ir_values : Array[String] = []
    collect_ir_code_block_facts(ir, ir_values, [])
    assert_eq(ir_values, expected_values)
    assert_eq(experimental_markdown_ir_to_commonmark_html(ir), expected_html)
  }
}

///|
test "container indentation: parser classification and MarkdownIR deindent share effective columns" {
  let cases : Array[ContainerIndentationCase] = [
    {
      label: "tab-list-continuation-below-code-threshold",
      source: "- foo\n\n\tbar\n",
      expected_code_values: [],
      expected_html: "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n",
    },
    {
      label: "tab-list-continuation",
      source: "- foo\n\n\t\tbar\n",
      expected_code_values: ["  bar"],
      expected_html: "<ul>\n<li>\n<p>foo</p>\n<pre><code>  bar\n</code></pre>\n</li>\n</ul>\n",
    },
    {
      label: "tab-block-quote-below-code-threshold",
      source: ">\tfoo\n",
      expected_code_values: [],
      expected_html: "<blockquote>\n<p>foo</p>\n</blockquote>\n",
    },
    {
      label: "tab-block-quote",
      source: ">\t\tfoo\n",
      expected_code_values: ["  foo"],
      expected_html: "<blockquote>\n<pre><code>  foo\n</code></pre>\n</blockquote>\n",
    },
    {
      label: "tab-list-initial-line-below-code-threshold",
      source: "-\tfoo\n",
      expected_code_values: [],
      expected_html: "<ul>\n<li>foo</li>\n</ul>\n",
    },
    {
      label: "tab-list-initial-line",
      source: "-\t\tfoo\n",
      expected_code_values: ["  foo"],
      expected_html: "<ul>\n<li>\n<pre><code>  foo\n</code></pre>\n</li>\n</ul>\n",
    },
    {
      label: "blank-marker-tail-below-code-threshold",
      source: "-   \n     code\n",
      expected_code_values: [],
      expected_html: "<ul>\n<li>code</li>\n</ul>\n",
    },
    {
      label: "blank-marker-tail-boundary",
      source: "-   \n      code\n",
      expected_code_values: ["code"],
      expected_html: "<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n",
    },
    {
      label: "blank-marker-tail-extra-code-indent",
      source: "-   \n        code\n",
      expected_code_values: ["  code"],
      expected_html: "<ul>\n<li>\n<pre><code>  code\n</code></pre>\n</li>\n</ul>\n",
    },
    {
      label: "empty-list-item-below-code-threshold",
      source: "-\n     code\n",
      expected_code_values: [],
      expected_html: "<ul>\n<li>code</li>\n</ul>\n",
    },
    {
      label: "empty-list-item",
      source: "-\n      code\n",
      expected_code_values: ["code"],
      expected_html: "<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n",
    },
    {
      label: "indented-code-continuation-below-threshold",
      source: "- foo\n\n     code\n",
      expected_code_values: [],
      expected_html: "<ul>\n<li>\n<p>foo</p>\n<p>code</p>\n</li>\n</ul>\n",
    },
    {
      label: "indented-code-continuation",
      source: "- foo\n\n      code\n",
      expected_code_values: ["code"],
      expected_html: "<ul>\n<li>\n<p>foo</p>\n<pre><code>code\n</code></pre>\n</li>\n</ul>\n",
    },
    {
      label: "quoted-tab-marker",
      source: "> \t- foo\n",
      expected_code_values: [],
      expected_html: "<blockquote>\n<ul>\n<li>foo</li>\n</ul>\n</blockquote>\n",
    },
  ]
  for case in cases {
    try! assert_container_indentation_case(case)
  }
}
