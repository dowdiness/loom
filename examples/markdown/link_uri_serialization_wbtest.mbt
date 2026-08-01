///|
fn link_uri_serialization_ir_from_source(source : String) -> MarkdownIR {
  let source_id = @core.SourceId("markdown-link-uri-serialization")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown link URI serialization parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn only_uri_serialization_inline(ir : MarkdownIR) -> MarkdownIR {
  match ir.node {
    Document([paragraph]) =>
      match paragraph.node {
        Paragraph([inline], _) => inline
        _ => abort("expected one link paragraph inline")
      }
    _ => abort("expected one link paragraph")
  }
}

///|
fn link_uri_json_string(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  buf.write_char('\"')
  for ch in value {
    match ch {
      '\\' => buf.write_string("\\\\")
      '\"' => buf.write_string("\\\"")
      _ => buf.write_char(ch)
    }
  }
  buf.write_char('\"')
  buf.to_string()
}

///|
fn assert_link_uri_serialization(
  source : String,
  expected_destination : String,
  expected_title : String?,
  expected_destination_source : String,
  expected_title_source : String?,
  expected_html : String,
) -> Unit raise {
  let ir = link_uri_serialization_ir_from_source(source)
  let inline = only_uri_serialization_inline(ir)
  match inline.node {
    Link(_, destination, title, surface) => {
      assert_eq(destination, expected_destination)
      assert_eq(title, expected_title)
      match surface.destination_origin {
        Some(origin) =>
          assert_eq(
            source[origin.start():origin.end()],
            expected_destination_source,
          )
        None => fail("expected link destination origin")
      }
      match (surface.title_origin, expected_title_source) {
        (Some(origin), Some(expected)) =>
          assert_eq(source[origin.start():origin.end()], expected)
        (None, None) => ()
        _ => fail("unexpected link title origin")
      }
    }
    _ => abort("expected typed MarkdownIR Link")
  }
  let mdast = experimental_markdown_ir_to_mdast_json(ir).stringify()
  assert_true(
    mdast.contains("\"url\":" + link_uri_json_string(expected_destination)),
  )
  match expected_title {
    Some(title) =>
      assert_true(mdast.contains("\"title\":" + link_uri_json_string(title)))
    None => assert_false(mdast.contains("\"title\":"))
  }
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=expected_html,
  )
}

///|
test "link URI serialization keeps MarkdownIR and mdast semantic" {
  // CommonMark examples 489, 502, 503, 504, and 507.
  assert_link_uri_serialization(
    "[link](</my uri>)\n",
    "/my uri",
    None,
    "/my uri",
    None,
    "<p><a href=\"/my%20uri\">link</a></p>\n",
  )
  assert_link_uri_serialization(
    "[link](foo\\bar)\n",
    "foo\\bar",
    None,
    "foo\\bar",
    None,
    "<p><a href=\"foo%5Cbar\">link</a></p>\n",
  )
  assert_link_uri_serialization(
    "[link](foo%20b&auml;)\n",
    "foo%20bä",
    None,
    "foo%20b&auml;",
    None,
    "<p><a href=\"foo%20b%C3%A4\">link</a></p>\n",
  )
  assert_link_uri_serialization(
    "[link](\"title\")\n",
    "\"title\"",
    None,
    "\"title\"",
    None,
    "<p><a href=\"%22title%22\">link</a></p>\n",
  )
  assert_link_uri_serialization(
    "[link](/url \"title\")\n",
    "/url \"title\"",
    None,
    "/url \"title\"",
    None,
    "<p><a href=\"/url%C2%A0%22title%22\">link</a></p>\n",
  )
}

///|
test "link titles remain semantic at CommonMark title boundaries" {
  // CommonMark examples 505 and 506.
  assert_link_uri_serialization(
    "[link](/url \"title\")\n",
    "/url",
    Some("title"),
    "/url",
    Some("title"),
    "<p><a href=\"/url\" title=\"title\">link</a></p>\n",
  )
  assert_link_uri_serialization(
    "[link](/url \"title \\\"&quot;\")\n",
    "/url",
    Some("title \"\""),
    "/url",
    Some("title \\\"&quot;"),
    "<p><a href=\"/url\" title=\"title &quot;&quot;\">link</a></p>\n",
  )
}

///|
test "image URI serialization reuses the semantic destination" {
  let source = "![alt](<image uri>)\n"
  let ir = link_uri_serialization_ir_from_source(source)
  let inline = only_uri_serialization_inline(ir)
  match inline.node {
    Image(_, destination, title, surface) => {
      assert_eq(destination, "image uri")
      assert_eq(title, None)
      match surface.destination_origin {
        Some(origin) =>
          assert_eq(source[origin.start():origin.end()], "image uri")
        None => fail("expected image destination origin")
      }
    }
    _ => abort("expected typed MarkdownIR Image")
  }
  let mdast = experimental_markdown_ir_to_mdast_json(ir).stringify()
  assert_true(mdast.contains("\"url\":\"image uri\""))
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p><img src=\"image%20uri\" alt=\"alt\" /></p>\n",
  )
}

///|
test "reference destinations retain decoded values and definition origins" {
  // CommonMark examples 202 and 206.
  assert_link_uri_serialization(
    "[foo]: /url\\bar\\*baz \"foo\\\"bar\\baz\"\n[foo]\n",
    "/url\\bar*baz",
    Some("foo\"bar\\baz"),
    "/url\\bar\\*baz",
    Some("foo\\\"bar\\baz"),
    "<p><a href=\"/url%5Cbar*baz\" title=\"foo&quot;bar\\baz\">foo</a></p>\n",
  )
  assert_link_uri_serialization(
    "[ΑΓΩ]: /φου\n[αγω]\n",
    "/φου",
    None,
    "/φου",
    None,
    "<p><a href=\"/%CF%86%CE%BF%CF%85\">αγω</a></p>\n",
  )
}
