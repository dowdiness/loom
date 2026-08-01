///|
fn link_delimiter_boundary_ir(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR raise {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("link delimiter boundary parse failed: " + source)
  }
  assert_eq(diagnostics.length(), 0)
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn link_delimiter_boundary_commonmark_html(ir : MarkdownIR) -> String {
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => html
    Err(_) => abort("Passthrough raw HTML policy rejected link delimiter IR")
  }
}

///|
fn assert_link_delimiter_boundary_has_no_raw_or_recovered(
  node : MarkdownIR,
) -> Unit raise {
  assert_false(node.is_raw())
  assert_false(node.is_recovered())
  for child in node.children() {
    assert_link_delimiter_boundary_has_no_raw_or_recovered(child)
  }
}

///|
fn assert_link_delimiter_boundary_official_case(
  example : Int,
  source : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId(
    "markdown-link-delimiter-boundary-official-" + example.to_string(),
  )
  let ir = link_delimiter_boundary_ir(source_id, source)
  assert_link_delimiter_boundary_has_no_raw_or_recovered(ir)
  assert_eq(link_delimiter_boundary_commonmark_html(ir), expected_html)
}

///|
test "link delimiter boundaries: Issue 827 official CommonMark cases" {
  // This is the bounded Issue #827 slice. The full-corpus audit remains the
  // exhaustive CommonMark fixture suite.
  let cases : Array[(Int, String, String)] = [
    (490, "[link](foo\nbar)\n", "<p>[link](foo\nbar)</p>\n"),
    (491, "[link](<foo\nbar>)\n", "<p>[link](<foo\nbar>)</p>\n"),
    (492, "[a](<b)c>)\n", "<p><a href=\"b)c\">a</a></p>\n"),
    (
      494, "[a](<b)c\n[a](<b)c>\n[a](<b>c)\n", "<p>[a](&lt;b)c\n[a](&lt;b)c&gt;\n[a](<b>c)</p>\n",
    ),
    (497, "[link](foo(and(bar))\n", "<p>[link](foo(and(bar))</p>\n"),
    (
      499, "[link](<foo(and(bar)>)\n", "<p><a href=\"foo(and(bar)\">link</a></p>\n",
    ),
    (
      510, "[link](   /uri\n  \"title\"  )\n", "<p><a href=\"/uri\" title=\"title\">link</a></p>\n",
    ),
    (511, "[link] (/uri)\n", "<p>[link] (/uri)</p>\n"),
    (513, "[link] bar](/uri)\n", "<p>[link] bar](/uri)</p>\n"),
    (
      517, "[![moon](moon.jpg)](/uri)\n", "<p><a href=\"/uri\"><img src=\"moon.jpg\" alt=\"moon\" /></a></p>\n",
    ),
    (
      518, "[foo [bar](/uri)](/uri)\n", "<p>[foo <a href=\"/uri\">bar</a>](/uri)</p>\n",
    ),
    (
      519, "[foo *[bar [baz](/uri)](/uri)*](/uri)\n", "<p>[foo <em>[bar <a href=\"/uri\">baz</a>](/uri)</em>](/uri)</p>\n",
    ),
    (
      520, "![[[foo](uri1)](uri2)](uri3)\n", "<p><img src=\"uri3\" alt=\"[foo](uri2)\" /></p>\n",
    ),
    (523, "*foo [bar* baz]\n", "<p><em>foo [bar</em> baz]</p>\n"),
    (
      531, "[![moon](moon.jpg)][ref]\n\n[ref]: /uri\n", "<p><a href=\"/uri\"><img src=\"moon.jpg\" alt=\"moon\" /></a></p>\n",
    ),
    (
      532, "[foo [bar](/uri)][ref]\n\n[ref]: /uri\n", "<p>[foo <a href=\"/uri\">bar</a>]<a href=\"/uri\">ref</a></p>\n",
    ),
    (
      533, "[foo *bar [baz][ref]*][ref]\n\n[ref]: /uri\n", "<p>[foo <em>bar <a href=\"/uri\">baz</a></em>]<a href=\"/uri\">ref</a></p>\n",
    ),
    (
      547, "[foo][ref[bar]]\n\n[ref[bar]]: /uri\n", "<p>[foo][ref[bar]]</p>\n<p>[ref[bar]]: /uri</p>\n",
    ),
    (
      548, "[[[foo]]]\n\n[[[foo]]]: /url\n", "<p>[[[foo]]]</p>\n<p>[[[foo]]]: /url</p>\n",
    ),
    (
      559, "[[*foo* bar]]\n\n[*foo* bar]: /url \"title\"\n", "<p>[<a href=\"/url\" title=\"title\"><em>foo</em> bar</a>]</p>\n",
    ),
    (564, "[foo*]: /url\n\n*[foo*]\n", "<p>*<a href=\"/url\">foo*</a></p>\n"),
    (
      568, "[foo](not a link)\n\n[foo]: /url1\n", "<p><a href=\"/url1\">foo</a>(not a link)</p>\n",
    ),
    (
      569, "[foo][bar][baz]\n\n[baz]: /url\n", "<p>[foo]<a href=\"/url\">bar</a></p>\n",
    ),
    (
      571, "[foo][bar][baz]\n\n[baz]: /url1\n[foo]: /url2\n", "<p>[foo]<a href=\"/url1\">bar</a></p>\n",
    ),
  ]
  assert_eq(cases.length(), 24)
  for link_case in cases {
    let (example, source, expected_html) = link_case
    assert_link_delimiter_boundary_official_case(example, source, expected_html)
  }
}

///|
fn assert_link_delimiter_boundary_incremental_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-link-delimiter-boundary-" + label)
  ignore(
    markdown_incremental_edit_reuse_count(
      source_id, label, source, edit, updated,
    ),
  )
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  assert_eq(incremental_diagnostics, fresh_diagnostics)
  assert_eq(incremental_diagnostics.length(), 0)
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  // MarkdownIR equality includes every node origin, so this checks source
  // origin parity as well as tree shape and values.
  assert_eq(incremental_ir, fresh_ir)
  assert_link_delimiter_boundary_has_no_raw_or_recovered(incremental_ir)
  assert_eq(
    project_markdown_roles(incremental_syntax),
    project_markdown_roles(fresh_syntax),
  )
  assert_eq(
    experimental_markdown_ir_to_mdast_json(incremental_ir),
    experimental_markdown_ir_to_mdast_json(fresh_ir),
  )
  assert_eq(
    link_delimiter_boundary_commonmark_html(incremental_ir),
    expected_html,
  )
}

///|
test "link delimiter boundaries: requested incremental forms match fresh origins" {
  let angle_prefix = "[a](<b)c>"
  let title_prefix = "[link](   /uri\n  \"title\"  "
  let outer_prefix = "[foo [bar](/uri)](/uri"
  let full_prefix = "[foo][bar"
  let collapsed_label_start = "[foo][".length()
  let shortcut_prefix = "[foo]"
  let cases : Array[(String, String, @core.Edit, String, String)] = [
    (
      "complete-angle-destination",
      angle_prefix + "\n",
      @core.Edit::insert(angle_prefix.length(), 1),
      angle_prefix + ")\n",
      "<p><a href=\"b)c\">a</a></p>\n",
    ),
    (
      "complete-multiline-title",
      title_prefix + "\n",
      @core.Edit::insert(title_prefix.length(), 1),
      title_prefix + ")\n",
      "<p><a href=\"/uri\" title=\"title\">link</a></p>\n",
    ),
    (
      "complete-disallowed-nested-link",
      outer_prefix + "\n",
      @core.Edit::insert(outer_prefix.length(), 1),
      outer_prefix + ")\n",
      "<p>[foo <a href=\"/uri\">bar</a>](/uri)</p>\n",
    ),
    (
      "complete-full-reference",
      full_prefix + "\n\n[bar]: /url\n",
      @core.Edit::insert(full_prefix.length(), 1),
      full_prefix + "]\n\n[bar]: /url\n",
      "<p><a href=\"/url\">foo</a></p>\n",
    ),
    (
      "full-to-collapsed-reference",
      "[foo][x]\n\n[foo]: /url\n",
      @core.Edit::delete(collapsed_label_start, collapsed_label_start + 1),
      "[foo][]\n\n[foo]: /url\n",
      "<p><a href=\"/url\">foo</a></p>\n",
    ),
    (
      "complete-shortcut-reference",
      shortcut_prefix + "x\n\n[foo]: /url\n",
      @core.Edit::delete(shortcut_prefix.length(), shortcut_prefix.length() + 1),
      shortcut_prefix + "\n\n[foo]: /url\n",
      "<p><a href=\"/url\">foo</a></p>\n",
    ),
    (
      "link-to-image",
      "[moon](moon.jpg)\n",
      @core.Edit::insert(0, 1),
      "![moon](moon.jpg)\n",
      "<p><img src=\"moon.jpg\" alt=\"moon\" /></p>\n",
    ),
  ]
  for incremental_case in cases {
    let (label, source, edit, updated, expected_html) = incremental_case
    assert_link_delimiter_boundary_incremental_parity(
      label, source, edit, updated, expected_html,
    )
  }
}

///|
test "link delimiter boundaries: long mixed delimiter input completes structurally" {
  let repetitions = 128
  let source_fragment = "[x](<a(b)c>) \\[literal\\] (paren) `code [ ] ( )` "
  let html_fragment = "<a href=\"a(b)c\">x</a> [literal] (paren) <code>code [ ] ( )</code> "
  let final_html_fragment = "<a href=\"a(b)c\">x</a> [literal] (paren) <code>code [ ] ( )</code>"
  let source = source_fragment.repeat(repetitions) + "\n"
  let expected_html = "<p>" +
    html_fragment.repeat(repetitions - 1) +
    final_html_fragment +
    "</p>\n"
  let ir = link_delimiter_boundary_ir(
    @core.SourceId("markdown-link-delimiter-boundary-long-mixed"),
    source,
  )
  assert_link_delimiter_boundary_has_no_raw_or_recovered(ir)
  assert_eq(link_delimiter_boundary_commonmark_html(ir), expected_html)
}
