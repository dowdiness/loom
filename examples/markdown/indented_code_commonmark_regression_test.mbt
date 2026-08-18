///|
fn assert_commonmark_indented_code_regression(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-commonmark-indented-code-" + example.to_string(),
  )
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  assert_true(diagnostics.is_empty())
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => html
    Err(_) => abort("Passthrough raw HTML policy cannot reject valid HTML")
  }
  guard actual == expected_html else {
    fail(
      "CommonMark indented-code regression " +
      example.to_string() +
      "\nexpected: " +
      @debug.to_string(expected_html) +
      "\nactual:   " +
      @debug.to_string(actual) +
      "\nir:       " +
      ir.kind_tag(),
    )
  }
}

///|
test "CommonMark indented code 107-118 and fence-looking 134" {
  let cases : Array[(Int, String, String)] = [
    (
      107, "    a simple\n      indented code block\n", "<pre><code>a simple\n  indented code block\n</code></pre>\n",
    ),
    (
      108, "  - foo\n\n    bar\n", "<ul>\n<li>\n<p>foo</p>\n<p>bar</p>\n</li>\n</ul>\n",
    ),
    (
      109, "1.  foo\n\n    - bar\n", "<ol>\n<li>\n<p>foo</p>\n<ul>\n<li>bar</li>\n</ul>\n</li>\n</ol>\n",
    ),
    (
      110, "    <a/>\n    *hi*\n\n    - one\n", "<pre><code>&lt;a/&gt;\n*hi*\n\n- one\n</code></pre>\n",
    ),
    (
      111, "    chunk1\n\n    chunk2\n  \n \n \n    chunk3\n", "<pre><code>chunk1\n\nchunk2\n\n\n\nchunk3\n</code></pre>\n",
    ),
    (
      112, "    chunk1\n      \n      chunk2\n", "<pre><code>chunk1\n  \n  chunk2\n</code></pre>\n",
    ),
    (113, "Foo\n    bar\n\n", "<p>Foo\nbar</p>\n"),
    (114, "    foo\nbar\n", "<pre><code>foo\n</code></pre>\n<p>bar</p>\n"),
    (
      115, "# Heading\n    foo\nHeading\n------\n    foo\n----\n", "<h1>Heading</h1>\n<pre><code>foo\n</code></pre>\n<h2>Heading</h2>\n<pre><code>foo\n</code></pre>\n<hr />\n",
    ),
    (116, "        foo\n    bar\n", "<pre><code>    foo\nbar\n</code></pre>\n"),
    (117, "\n    \n    foo\n    \n\n", "<pre><code>foo\n</code></pre>\n"),
    (118, "    foo  \n", "<pre><code>foo  \n</code></pre>\n"),
    (
      134, "    ```\n    aaa\n    ```\n", "<pre><code>```\naaa\n```\n</code></pre>\n",
    ),
  ]
  for case in cases {
    let (example, source, expected_html) = case
    assert_commonmark_indented_code_regression(example, source, expected_html)
  }
}

///|
test "indented code stops at an unindented line after a fence-looking opener" {
  assert_commonmark_indented_code_regression(
    39201, "    ```\nbar\n", "<pre><code>```\n</code></pre>\n<p>bar</p>\n",
  )
}

///|
test "indented code stops at an unindented line after an HTML-looking opener" {
  assert_commonmark_indented_code_regression(
    39202, "    <div>\nbar\n", "<pre><code>&lt;div&gt;\n</code></pre>\n<p>bar</p>\n",
  )
}

///|
test "incremental: indented code content edit matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code content edit",
      "    foo\n",
      @core.Edit::new("    ".length(), "foo".length(), "bar".length()),
      "    bar\n",
    ),
  )
}

///|
test "incremental: indented code indent boundary matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code indent boundary three to four spaces",
      "   foo\n",
      @core.Edit::insert(0, " ".length()),
      "    foo\n",
    ),
  )
}

///|
test "incremental: indented code construction matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code construct four-space prefix",
      "foo\n",
      @core.Edit::insert(0, "    ".length()),
      "    foo\n",
    ),
  )
}

///|
test "incremental: indented code destruction matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code destroy four-space prefix",
      "    foo\n",
      @core.Edit::delete(0, "    ".length()),
      "foo\n",
    ),
  )
}

///|
test "incremental: indented code html continuation matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code html literal continuation",
      "    <a/>\n",
      @core.Edit::insert("    <a/>\n".length(), "    *hi*\n".length()),
      "    <a/>\n    *hi*\n",
    ),
  )
}

///|
test "incremental: indented code extra content line matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code insert interior content line",
      "    foo\n    baz\n",
      @core.Edit::insert("    foo\n".length(), "    bar\n".length()),
      "    foo\n    bar\n    baz\n",
    ),
  )
}

///|
/// Fence-looking indented closer: detached relex may emit CodeText instead of
/// CodeFenceClose, so CST/role `tree_diff` is skipped (`require_cst=false`).
/// Diagnostics, AST, IR, and HTML still match a full parse.
test "incremental: fence-looking indented closer matches full parse" {
  ignore(
    assert_block_container_incremental_parity(
      "indented-code 134 closer",
      "    ```\n    aaa\n",
      @core.Edit::insert("    ```\n    aaa\n".length(), "    ```\n".length()),
      "    ```\n    aaa\n    ```\n",
      require_cst=false,
    ),
  )
}

///|
test "incremental: list-item fence at document column four stays fenced" {
  ignore(
    assert_block_container_incremental_parity(
      "list-item fence closer at column four",
      "- item\n    ```\n    aaa\n",
      @core.Edit::insert(
        "- item\n    ```\n    aaa\n".length(),
        "    ```\n".length(),
      ),
      "- item\n    ```\n    aaa\n    ```\n",
    ),
  )
}

///|
test "list-item fence at document column four stays fenced" {
  assert_commonmark_indented_code_regression(
    39203, "- item\n    ```\n    aaa\n    ```\n", "<ul>\n<li>item\n<pre><code>aaa\n</code></pre>\n</li>\n</ul>\n",
  )
}
