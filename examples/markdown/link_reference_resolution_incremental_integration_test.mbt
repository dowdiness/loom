///|
fn assert_link_reference_incremental_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-link-reference-" + label)
  ignore(
    @loom.assert_incremental_edit_matches_full_parse(
      source_id,
      label,
      source,
      edit,
      updated,
      markdown_grammar.to_syntax_grammar(),
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
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  assert_eq(
    project_markdown_roles(incremental_syntax),
    project_markdown_roles(fresh_syntax),
  )
  assert_eq(
    experimental_markdown_ir_to_mdast_json(incremental_ir),
    experimental_markdown_ir_to_mdast_json(fresh_ir),
  )
  let incremental_html = experimental_markdown_ir_to_commonmark_html(
    incremental_ir,
  )
  assert_eq(
    incremental_html,
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
  )
  inspect(incremental_html, content=expected_html)
}

///|
fn assert_image_incremental_completion_grade(node : MarkdownIR) -> Unit raise {
  assert_false(node.is_raw())
  assert_false(node.is_recovered())
  assert_false(node.is_unsupported())
  for child in node.children() {
    assert_image_incremental_completion_grade(child)
  }
}

///|
fn assert_image_incremental_completion_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Unit raise {
  assert_link_reference_incremental_parity(
    label, source, edit, updated, expected_html,
  )
  let source_id = @core.SourceId("markdown-image-incremental-" + label)
  let (cst, diagnostics) = parse_cst(source_id, updated) catch {
    _ => abort("Markdown image incremental completion parse failed")
  }
  assert_eq(diagnostics.length(), 0)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  assert_image_incremental_completion_grade(ir)
}

///|
test "incremental links and images: resolution, form, definition, and image edits match fresh" {
  let definition_prefix = "[foo][bar]\n\n[bar]"
  assert_link_reference_incremental_parity(
    "construct-definition",
    definition_prefix + " /url \"title\"\n",
    @core.Edit::insert(definition_prefix.length(), 1),
    definition_prefix + ": /url \"title\"\n",
    "<p><a href=\"/url\" title=\"title\">foo</a></p>\n",
  )
  assert_link_reference_incremental_parity(
    "destroy-definition",
    definition_prefix + ": /url \"title\"\n[other]: /x\n",
    @core.Edit::delete(
      definition_prefix.length(),
      definition_prefix.length() + 1,
    ),
    definition_prefix + " /url \"title\"\n[other]: /x\n",
    "<p>[foo][bar]</p>\n<p>[bar] /url &quot;title&quot;\n[other]: /x</p>\n",
  )
  let destination_prefix = "[foo][bar]\n\n[bar]: /"
  assert_link_reference_incremental_parity(
    "change-definition-destination",
    destination_prefix + "one \"title\"\n",
    @core.Edit::replace(
      destination_prefix.length(),
      destination_prefix.length() + 3,
      destination_prefix.length() + 3,
    ),
    destination_prefix + "url \"title\"\n",
    "<p><a href=\"/url\" title=\"title\">foo</a></p>\n",
  )
  let title_prefix = "[foo][bar]\n\n[bar]: /url \""
  assert_link_reference_incremental_parity(
    "change-definition-title",
    title_prefix + "title\"\n",
    @core.Edit::replace(
      title_prefix.length(),
      title_prefix.length() + "title".length(),
      title_prefix.length() + "other".length(),
    ),
    title_prefix + "other\"\n",
    "<p><a href=\"/url\" title=\"other\">foo</a></p>\n",
  )
  let label_source = "[foo][bar]\n\n[bar]: /old \"title\"\n[baz]: /new \"title\"\n"
  let label_start = "[foo][".length()
  assert_link_reference_incremental_parity(
    "change-reference-label",
    label_source,
    @core.Edit::replace(
      label_start,
      label_start + "bar".length(),
      label_start + "baz".length(),
    ),
    "[foo][baz]\n\n[bar]: /old \"title\"\n[baz]: /new \"title\"\n",
    "<p><a href=\"/new\" title=\"title\">foo</a></p>\n",
  )
  assert_link_reference_incremental_parity(
    "full-to-collapsed",
    "[foo][bar]\n\n[foo]: /url \"title\"\n",
    @core.Edit::delete("[foo][".length(), "[foo][bar".length()),
    "[foo][]\n\n[foo]: /url \"title\"\n",
    "<p><a href=\"/url\" title=\"title\">foo</a></p>\n",
  )
  let reference_source = "[foo][bar]\n\n[bar]: /url \"title\"\n"
  assert_link_reference_incremental_parity(
    "link-to-image",
    reference_source,
    @core.Edit::insert(0, 1),
    "!" + reference_source,
    "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>\n",
  )
}

///|
test "incremental nested images and nested reference boundaries match fresh" {
  let nested_image_source = "![foo ![bar](/url)](/url2)\n"
  assert_image_incremental_completion_parity(
    "nested-image-to-link",
    nested_image_source,
    @core.Edit::delete(6, 7),
    "![foo [bar](/url)](/url2)\n",
    "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n",
  )
  let nested_link_source = "![foo [bar](/url)](/url2)\n"
  assert_image_incremental_completion_parity(
    "nested-link-to-image",
    nested_link_source,
    @core.Edit::insert("![foo ".length(), 1),
    nested_image_source,
    "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n",
  )
  let incomplete_nested_label = "![[foo]\n\n[[foo]]: /url \"title\"\n"
  assert_image_incremental_completion_parity(
    "complete-literal-nested-reference-boundary",
    incomplete_nested_label,
    @core.Edit::insert("![[foo]".length(), 1),
    "![[foo]]\n\n[[foo]]: /url \"title\"\n",
    "<p>![[foo]]</p>\n<p>[[foo]]: /url &quot;title&quot;</p>\n",
  )
}

///|
test "incremental link URI serialization edits match fresh CommonMark projections" {
  let backslash_prefix = "[link](foo"
  assert_link_reference_incremental_parity(
    "introduce-backslash-destination",
    backslash_prefix + "bar)\n",
    @core.Edit::insert(backslash_prefix.length(), 1),
    backslash_prefix + "\\bar)\n",
    "<p><a href=\"foo%5Cbar\">link</a></p>\n",
  )
  let entity_prefix = "[link](foo%20b"
  assert_link_reference_incremental_parity(
    "remove-entity-decoded-non-ascii",
    entity_prefix + "&auml;)\n",
    @core.Edit::delete(
      entity_prefix.length(),
      entity_prefix.length() + "&auml;".length(),
    ),
    entity_prefix + ")\n",
    "<p><a href=\"foo%20b\">link</a></p>\n",
  )
  let unicode_prefix = "[link](/"
  assert_link_reference_incremental_parity(
    "introduce-raw-unicode-destination",
    unicode_prefix + "foo)\n",
    @core.Edit::replace(
      unicode_prefix.length(),
      unicode_prefix.length() + "foo".length(),
      unicode_prefix.length() + "φου".length(),
    ),
    unicode_prefix + "φου)\n",
    "<p><a href=\"/%CF%86%CE%BF%CF%85\">link</a></p>\n",
  )
  let title_boundary_source = "[link](/url \"title\")\n"
  let title_boundary = "[link](/url".length()
  assert_link_reference_incremental_parity(
    "replace-title-boundary-space-with-nbsp",
    title_boundary_source,
    @core.Edit::replace(title_boundary, title_boundary + 1, title_boundary + 1),
    "[link](/url \"title\")\n",
    "<p><a href=\"/url%C2%A0%22title%22\">link</a></p>\n",
  )
  assert_link_reference_incremental_parity(
    "remove-title-boundary-space",
    title_boundary_source,
    @core.Edit::delete(title_boundary, title_boundary + 1),
    "[link](/url\"title\")\n",
    "<p><a href=\"/url%22title%22\">link</a></p>\n",
  )
}

///|
test "link and image mdast adapters render only typed MarkdownIR data" {
  let source = "[foo][ref] ![bar][ref]\n\n[ref]: /url \"title\"\n"
  let source_id = @core.SourceId("markdown-link-image-mdast")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown link/image mdast parse failed")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let expected_mdast =
    #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"link","url":"/url","title":"title","children":[{"type":"text","value":"foo"}]},{"type":"text","value":" "},{"type":"image","url":"/url","title":"title","alt":"bar"}]}]}
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=expected_mdast,
  )
}

///|
test "unresolved shortcut and invalid direct link remain literal text" {
  let source = "[shortcut] [link](/my uri)\n"
  let source_id = @core.SourceId("markdown-unresolved-links-stay-literal")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown unresolved-link parse failed")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let expected_mdast =
    #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"[shortcut] [link](/my uri)"}]}]}
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=expected_mdast,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p>[shortcut] [link](/my uri)</p>\n",
  )
}

///|
test "malformed nested reference delimiters remain literal without recovery" {
  let source = "[foo][ref[]\n\n[ref[]: /uri\n"
  let source_id = @core.SourceId("markdown-invalid-reference-stays-literal")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown invalid-reference parse failed")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let expected_mdast =
    #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"[foo][ref[]"}]},{"type":"paragraph","children":[{"type":"text","value":"[ref[]: /uri"}]}]}
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=expected_mdast,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p>[foo][ref[]</p>\n<p>[ref[]: /uri</p>\n",
  )
}

///|
test "link indexing preserves an immediately following emphasis opener" {
  let cases = [
    ("[foo](/url)*bar*\n", "<p><a href=\"/url\">foo</a><em>bar</em></p>\n"),
    (
      "[foo][ref]*bar*\n\n[ref]: /url\n", "<p><a href=\"/url\">foo</a><em>bar</em></p>\n",
    ),
  ]
  for item in cases {
    let (source, expected) = item
    let source_id = @core.SourceId("markdown-link-followed-by-emphasis")
    let (cst, diagnostics) = parse_cst(source_id, source) catch {
      _ => abort("Markdown adjacent link/emphasis parse failed")
    }
    let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id,
      @seam.SyntaxNode::from_cst(cst),
      diagnostics,
    )
    inspect(experimental_markdown_ir_to_commonmark_html(ir), content=expected)
  }
}
