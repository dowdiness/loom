///|
fn issue_892_ir(source : String) -> MarkdownIR raise {
  let source_id = @core.SourceId("markdown-issue-892")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Issue #892 parse failed: " + source)
  }
  assert_eq(diagnostics.length(), 0)
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn issue_892_html(source : String) -> String raise {
  experimental_markdown_ir_to_commonmark_html(issue_892_ir(source))
}

///|
fn issue_892_assert_no_recovery(node : MarkdownIR) -> Unit raise {
  guard !node.is_raw() else {
    fail("raw node: " + node.kind_tag() + " " + @debug.to_string(node))
  }
  guard !node.is_recovered() else { fail("recovered node: " + node.kind_tag()) }
  for child in node.children() {
    issue_892_assert_no_recovery(child)
  }
}

///|
test "issue 892: CommonMark 342, 516, and 525 stay structural" {
  let cases = [
    (342, "[not a `link](/foo`)\n", "<p>[not a <code>link](/foo</code>)</p>\n"),
    (
      516, "[link *foo **bar** `#`*](/uri)\n", "<p><a href=\"/uri\">link <em>foo <strong>bar</strong> <code>#</code></em></a></p>\n",
    ),
    (525, "[foo`](/uri)`\n", "<p>[foo<code>](/uri)</code></p>\n"),
  ]
  for case in cases {
    let (example, source, expected_html) = case
    let ir = issue_892_ir(source)
    issue_892_assert_no_recovery(ir)
    guard issue_892_html(source) == expected_html else {
      fail("CommonMark example " + example.to_string() + " mismatch")
    }
  }
}

///|
// The expected HTML is pinned to commonmark@0.31.2 (the issue's recorded
// package integrity hash), not to a local renderer shortcut.
test "issue 892: destination and title backticks remain owned by suffixes" {
  let cases = [
    ("[x](foo`bar`)\n", "<p><a href=\"foo%60bar%60\">x</a></p>\n"),
    (
      "[x](url \"`title`\")\n", "<p><a href=\"url\" title=\"`title`\">x</a></p>\n",
    ),
  ]
  for case in cases {
    let (source, expected_html) = case
    let ir = issue_892_ir(source)
    issue_892_assert_no_recovery(ir)
    assert_eq(issue_892_html(source), expected_html)
  }
}

///|
test "issue 892: link and image labels retain distinct nesting" {
  let link = issue_892_ir("[x `code`](url)\n")
  let image = issue_892_ir("![x `code`](url)\n")
  issue_892_assert_no_recovery(link)
  issue_892_assert_no_recovery(image)
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(link),
    "<p><a href=\"url\">x <code>code</code></a></p>\n",
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(image),
    "<p><img src=\"url\" alt=\"x code\" /></p>\n",
  )
}

///|
// Expected HTML is pinned to commonmark@0.31.2
// (sha512-2fRLTyb9r/2835k5cwcAwOj0DEc44FARnMp5veGsJ+mEAZdi52sNopLu07ZyElQUz058H43whzlERDIaaSw4rg==).
test "issue 892: conflicting bracket endpoints are literal without recovery" {
  let cases = [
    ("[a `x]` b]\n", "<p>[a <code>x]</code> b]</p>\n"),
    ("[[a `x]` b]\n", "<p>[[a <code>x]</code> b]</p>\n"),
    ("![a `x]` b]\n", "<p>![a <code>x]</code> b]</p>\n"),
    ("[a `x]\n` b]\n", "<p>[a <code>x] </code> b]</p>\n"),
    (
      "[a `x]` b] [c `y]` d]\n", "<p>[a <code>x]</code> b] [c <code>y]</code> d]</p>\n",
    ),
  ]
  for index, case in cases {
    let (source, expected_html) = case
    let ir = issue_892_ir(source)
    issue_892_assert_no_recovery(ir)
    assert_eq(experimental_markdown_ir_to_commonmark_html(ir), expected_html)
    assert_source_fidelity(
      @core.SourceId("markdown-issue-892-fresh-fidelity-" + index.to_string()),
      source,
    )
  }
}

///|
test "issue 892: conflicting pair does not hide a later valid link" {
  let source = "[[a `x]` b] [ok](url)\n"
  let ir = issue_892_ir(source)
  issue_892_assert_no_recovery(ir)
  assert_source_fidelity(
    @core.SourceId("markdown-issue-892-later-link-fidelity"),
    source,
  )
  assert_eq(
    issue_892_html(source),
    "<p>[[a <code>x]</code> b] <a href=\"url\">ok</a></p>\n",
  )
}

///|
test "issue 892: an active link owns its conflicting bracket pair" {
  let source = "[a `x]` b](url)\n"
  let ir = issue_892_ir(source)
  issue_892_assert_no_recovery(ir)
  assert_source_fidelity(
    @core.SourceId("markdown-issue-892-active-link-fidelity"),
    source,
  )
  assert_eq(
    issue_892_html(source),
    "<p><a href=\"url\">a <code>x]</code> b</a></p>\n",
  )
}

///|
fn issue_892_incremental_conflict_case(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-issue-892-incremental-" + label)
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  assert_eq(incremental_syntax, fresh_syntax)
  assert_eq(incremental_diagnostics, fresh_diagnostics)
  assert_eq(incremental_diagnostics.length(), 0)
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  issue_892_assert_no_recovery(incremental_ir)
  issue_892_assert_no_recovery(fresh_ir)
  assert_source_fidelity(
    @core.SourceId("markdown-issue-892-incremental-fidelity-" + label),
    updated,
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
    expected_html,
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(incremental_ir),
    expected_html,
  )
}

///|
fn issue_892_incremental_case(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-issue-892-" + label)
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  assert_eq(incremental_syntax, fresh_syntax)
  assert_eq(incremental_diagnostics, fresh_diagnostics)
  assert_eq(incremental_diagnostics.length(), 0)
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  issue_892_assert_no_recovery(incremental_ir)
  issue_892_assert_no_recovery(fresh_ir)
  assert_source_fidelity(
    @core.SourceId("markdown-issue-892-fidelity-" + label),
    updated,
  )
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(incremental_ir),
    expected_html,
  )
}

///|
test "issue 892: fresh and incremental conflict matrix agrees" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "plain",
      "[a `x] b]\n",
      @core.Edit::insert("[a `x]".length(), 1),
      "[a `x]` b]\n",
      "<p>[a <code>x]</code> b]</p>\n",
    ),
    (
      "nested",
      "[[a `x] b]\n",
      @core.Edit::insert("[[a `x]".length(), 1),
      "[[a `x]` b]\n",
      "<p>[[a <code>x]</code> b]</p>\n",
    ),
    (
      "image",
      "![a `x] b]\n",
      @core.Edit::insert("![a `x]".length(), 1),
      "![a `x]` b]\n",
      "<p>![a <code>x]</code> b]</p>\n",
    ),
    (
      "multiline",
      "[a `x]\n b]\n",
      @core.Edit::insert("[a `x]\n".length(), 1),
      "[a `x]\n` b]\n",
      "<p>[a <code>x] </code> b]</p>\n",
    ),
    (
      "multiple-spans",
      "[a `x]` b] [c `y] d]\n",
      @core.Edit::insert("[a `x]` b] [c `y]".length(), 1),
      "[a `x]` b] [c `y]` d]\n",
      "<p>[a <code>x]</code> b] [c <code>y]</code> d]</p>\n",
    ),
    (
      "later-link",
      "[[a `x] b] [ok](url)\n",
      @core.Edit::insert("[[a `x]".length(), 1),
      "[[a `x]` b] [ok](url)\n",
      "<p>[[a <code>x]</code> b] <a href=\"url\">ok</a></p>\n",
    ),
  ]
  for case in cases {
    let (label, source, edit, updated, expected_html) = case
    issue_892_incremental_conflict_case(
      label, source, edit, updated, expected_html,
    )
  }
}

///|
test "issue 892: fresh and incremental edits agree at label and suffix boundaries" {
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "insert-label-code-closer",
      "[link `code](/uri)\n",
      @core.Edit::insert("[link `code".length(), 1),
      "[link `code`](/uri)\n",
      "<p><a href=\"/uri\">link <code>code</code></a></p>\n",
    ),
    (
      "remove-label-code-opener",
      "[link `code`](/uri)\n",
      @core.Edit::delete("[link ".length(), "[link `".length()),
      "[link code`](/uri)\n",
      "<p><a href=\"/uri\">link code`</a></p>\n",
    ),
    (
      "lengthen-label-code-opener",
      "[link `code`](/uri)\n",
      @core.Edit::insert("[link ".length(), 1),
      "[link ``code`](/uri)\n",
      "<p><a href=\"/uri\">link ``code`</a></p>\n",
    ),
    (
      "restore-suffix-backtick",
      "[x](foobar)\n",
      @core.Edit::insert("[x](foo".length(), 1),
      "[x](foo`bar)\n",
      "<p><a href=\"foo%60bar\">x</a></p>\n",
    ),
    (
      "restore-shortened-suffix-run",
      "[x](foo``bar)\n",
      @core.Edit::delete("[x](foo`".length(), "[x](foo``".length()),
      "[x](foo`bar)\n",
      "<p><a href=\"foo%60bar\">x</a></p>\n",
    ),
  ]
  for case in cases {
    let (label, source, edit, updated, expected_html) = case
    issue_892_incremental_case(label, source, edit, updated, expected_html)
  }
}
