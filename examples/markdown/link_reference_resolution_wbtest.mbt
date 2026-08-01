///|
fn link_reference_ir_from_source(source : String) -> MarkdownIR {
  let source_id = @core.SourceId("markdown-link-reference-surface")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown link/reference surface parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn only_inline_node(ir : MarkdownIR) -> MarkdownIR {
  match ir.node {
    Document([paragraph]) =>
      match paragraph.node {
        Paragraph([inline], _) => inline
        _ => abort("expected one inline node")
      }
    _ => abort("expected one paragraph")
  }
}

///|
fn assert_link_surface(
  source : String,
  expected_form : LinkReferenceForm,
  expected_origin : MarkdownIROrigin,
  expected_label_origin : MarkdownIROrigin,
  expected_reference_label_origin : MarkdownIROrigin?,
  expected_destination_origin : MarkdownIROrigin,
  expected_title_origin : MarkdownIROrigin,
) -> Unit raise {
  let inline = only_inline_node(link_reference_ir_from_source(source))
  match inline.node {
    Link(children, destination, title, surface) => {
      assert_eq(markdown_ir_plain_text(children), "foo")
      assert_eq(destination, "/url")
      assert_eq(title, Some("title"))
      assert_eq(inline.origin, expected_origin)
      assert_eq(surface.form, expected_form)
      assert_eq(surface.label_origin, Some(expected_label_origin))
      assert_eq(surface.reference_label_origin, expected_reference_label_origin)
      assert_eq(surface.destination_origin, Some(expected_destination_origin))
      assert_eq(surface.title_origin, Some(expected_title_origin))
    }
    _ => abort("expected a typed MarkdownIR Link")
  }
}

///|
test "link resolution retains form, title, and source origins" {
  assert_link_surface(
    "[foo](/url \"title\")\n",
    InlineLinkForm,
    MarkdownIROrigin(start=0, end=19),
    MarkdownIROrigin(start=1, end=4),
    None,
    MarkdownIROrigin(start=6, end=10),
    MarkdownIROrigin(start=12, end=17),
  )
  assert_link_surface(
    "[foo][ref]\n\n[ref]: /url \"title\"\n",
    FullReferenceLinkForm,
    MarkdownIROrigin(start=0, end=10),
    MarkdownIROrigin(start=1, end=4),
    Some(MarkdownIROrigin(start=6, end=9)),
    MarkdownIROrigin(start=19, end=23),
    MarkdownIROrigin(start=25, end=30),
  )
  assert_link_surface(
    "[foo][]\n\n[foo]: /url \"title\"\n",
    CollapsedReferenceLinkForm,
    MarkdownIROrigin(start=0, end=7),
    MarkdownIROrigin(start=1, end=4),
    Some(MarkdownIROrigin(start=6, end=6)),
    MarkdownIROrigin(start=16, end=20),
    MarkdownIROrigin(start=22, end=27),
  )
  assert_link_surface(
    "[foo]\n\n[foo]: /url \"title\"\n",
    ShortcutReferenceLinkForm,
    MarkdownIROrigin(start=0, end=5),
    MarkdownIROrigin(start=1, end=4),
    None,
    MarkdownIROrigin(start=14, end=18),
    MarkdownIROrigin(start=20, end=25),
  )
}

///|
test "image resolution remains distinct and retains link reference surface" {
  let source = "![foo][ref]\n\n[ref]: /url \"title\"\n"
  let inline = only_inline_node(link_reference_ir_from_source(source))
  match inline.node {
    Image(children, destination, title, surface) => {
      assert_eq(markdown_ir_plain_text(children), "foo")
      assert_eq(destination, "/url")
      assert_eq(title, Some("title"))
      assert_eq(inline.origin, MarkdownIROrigin(start=0, end=11))
      assert_eq(surface.form, FullReferenceLinkForm)
      assert_eq(surface.label_origin, Some(MarkdownIROrigin(start=2, end=5)))
      assert_eq(
        surface.reference_label_origin,
        Some(MarkdownIROrigin(start=7, end=10)),
      )
      assert_eq(
        surface.destination_origin,
        Some(MarkdownIROrigin(start=20, end=24)),
      )
      assert_eq(surface.title_origin, Some(MarkdownIROrigin(start=26, end=31)))
    }
    _ => abort("expected a distinct typed MarkdownIR Image")
  }
}
