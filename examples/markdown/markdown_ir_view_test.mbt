///|
fn markdown_ir_view_test_document(source : String) -> MarkdownIR {
  let source_id = @core.SourceId("markdown-ir-public-view")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("MarkdownIR public-view fixture failed to parse")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn markdown_ir_view_test_single_inline(source : String) -> MarkdownIR {
  let document = markdown_ir_view_test_document(source)
  match document.children() {
    [paragraph] =>
      match paragraph.children() {
        [inline] => inline
        _ => abort("expected one inline node")
      }
    _ => abort("expected one paragraph")
  }
}

///|
fn markdown_ir_view_test_link_form_name(
  form : MarkdownIRLinkReferenceForm,
) -> String {
  match form {
    InlineLinkForm => "inline"
    FullReferenceLinkForm => "full-reference"
    CollapsedReferenceLinkForm => "collapsed-reference"
    ShortcutReferenceLinkForm => "shortcut-reference"
  }
}

///|
fn[T] markdown_ir_view_test_is_some(value : T?) -> Bool {
  value is Some(_)
}

///|
fn markdown_ir_view_test_collect_external_tags(
  node : MarkdownIR,
  tags : Array[String],
) -> Unit {
  ignore(node.origin())
  ignore(node.content_origin())
  ignore(node.diagnostics())
  let tag = match node.view() {
    Document => "Document"
    Heading(depth~) => "Heading:" + depth.to_string()
    Paragraph => "Paragraph"
    BlockQuote => "BlockQuote"
    UnorderedList(spread~, marker~) =>
      "UnorderedList:" +
      spread.to_string() +
      ":" +
      markdown_ir_view_test_is_some(marker).to_string()
    OrderedList(spread~, marker~) =>
      "OrderedList:" +
      spread.to_string() +
      ":" +
      markdown_ir_view_test_is_some(marker).to_string()
    ListItem(spread~, marker~, task~) =>
      "ListItem:" +
      spread.to_string() +
      ":" +
      markdown_ir_view_test_is_some(marker).to_string() +
      ":" +
      markdown_ir_view_test_is_some(task).to_string()
    OrderedListItem(spread~, marker~, task~) =>
      "OrderedListItem:" +
      spread.to_string() +
      ":" +
      markdown_ir_view_test_is_some(marker).to_string() +
      ":" +
      markdown_ir_view_test_is_some(task).to_string()
    CodeBlock(info~, value~) => "CodeBlock:" + info + ":" + value
    HtmlBlock(value~) => "HtmlBlock:" + value
    ThematicBreak => "ThematicBreak"
    Text(value~) => "Text:" + value
    Bold => "Bold"
    Italic => "Italic"
    InlineCode(value~) => "InlineCode:" + value
    Link(destination~, title~, surface~) =>
      "Link:" +
      destination +
      ":" +
      markdown_ir_view_test_is_some(title).to_string() +
      ":" +
      markdown_ir_view_test_link_form_name(surface.form)
    Image(destination~, title~, surface~) =>
      "Image:" +
      destination +
      ":" +
      markdown_ir_view_test_is_some(title).to_string() +
      ":" +
      markdown_ir_view_test_link_form_name(surface.form)
    Autolink(kind~, display~, destination~, label_origin~, destination_origin~) => {
      let kind_name = match kind {
        UriAutolink => "uri"
        EmailAutolink => "email"
      }
      "Autolink:" +
      kind_name +
      ":" +
      display +
      ":" +
      destination +
      ":" +
      markdown_ir_view_test_is_some(label_origin).to_string() +
      ":" +
      markdown_ir_view_test_is_some(destination_origin).to_string()
    }
    InlineHtml(value~) => "InlineHtml:" + value
    SoftBreak => "SoftBreak"
    HardBreak(surface~) =>
      match surface {
        TrailingSpaces(count) => "HardBreak:spaces:" + count.to_string()
        Backslash => "HardBreak:backslash"
      }
    Unsupported(message~) => "Unsupported:" + message
    Raw(value~) => "Raw:" + value
    Recovered(value~) => "Recovered:" + value
  }
  tags.push(tag)
  for child in node.children() {
    markdown_ir_view_test_collect_external_tags(child, tags)
  }
}

///|
fn markdown_ir_view_test_has_tag(
  tags : Array[String],
  expected : String,
) -> Bool {
  tags.search_by(tag => tag == expected) is Some(_)
}

///|
fn markdown_ir_view_test_first_recovered(node : MarkdownIR) -> MarkdownIR? {
  if node.view() is Recovered(_) {
    return Some(node)
  }
  for child in node.children() {
    match markdown_ir_view_test_first_recovered(child) {
      Some(recovered) => return Some(recovered)
      None => ()
    }
  }
  None
}

///|
test "MarkdownIR public view supports an exhaustive external adapter" {
  let source_builder = StringBuilder::StringBuilder()
  source_builder.write_string(
    (
      #|# heading
      #|
      #|> quote
      #|
      #|+ item
      #|
      #|3) ordered
      #|
      #|```mbt
      #|code
      #|```
      #|
      #|<div>
      #|
      #|---
      #|
      #|text **bold** *italic* `code` [inline](/url "title") ![image](/img "caption")
      #|
      #|soft
      #|break
      #|
    ),
  )
  source_builder.write_string("spaces  \nbreak\n\n")
  source_builder.write_string(
    (
      #|slash\
      #|break
      #|
      #|<http://example.com> <foo@bar.example.com> <i>x</i>
      #|
    ),
  )
  let source = source_builder.to_string()
  let document = markdown_ir_view_test_document(source)
  let tags : Array[String] = []
  markdown_ir_view_test_collect_external_tags(document, tags)
  for
    expected in [
      "Document", "Heading:1", "BlockQuote", "UnorderedList:false:true", "ListItem:false:true:false",
      "OrderedList:false:true", "OrderedListItem:false:true:false", "CodeBlock:mbt:code",
      "ThematicBreak", "Bold", "Italic", "InlineCode:code", "Link:/url:true:inline",
      "Image:/img:true:inline", "SoftBreak", "HardBreak:spaces:2", "HardBreak:backslash",
      "Autolink:uri:http://example.com:http://example.com:true:true", "Autolink:email:foo@bar.example.com:mailto:foo@bar.example.com:true:false",
      "InlineHtml:<i>",
    ] {
    assert_true(markdown_ir_view_test_has_tag(tags, expected))
  }
  assert_true(
    tags.search_by(tag => tag.has_prefix("HtmlBlock:<div>")) is Some(_),
  )

  let unordered = markdown_ir_view_test_document("+ item\n").children()[0]
  match unordered.view() {
    UnorderedList(marker=Some(Plus), ..) => ()
    _ => fail("expected a typed unordered-list marker")
  }
  let ordered = markdown_ir_view_test_document("3) item\n").children()[0]
  match ordered.view() {
    OrderedList(marker=Some(marker), ..) => {
      assert_eq(marker.start(), 3)
      assert_eq(marker.delimiter(), Paren)
    }
    _ => fail("expected a typed ordered-list marker")
  }
}

///|
test "MarkdownIR public view exposes link and image reference surfaces" {
  let fixtures : Array[(String, MarkdownIRLinkReferenceForm)] = [
    ("[foo](/url \"title\")\n", InlineLinkForm),
    ("[foo][ref]\n\n[ref]: /url \"title\"\n", FullReferenceLinkForm),
    ("[foo][]\n\n[foo]: /url \"title\"\n", CollapsedReferenceLinkForm),
    ("[foo]\n\n[foo]: /url \"title\"\n", ShortcutReferenceLinkForm),
  ]
  for fixture in fixtures {
    let (source, expected_form) = fixture
    match markdown_ir_view_test_single_inline(source).view() {
      Link(destination~, title~, surface~) => {
        assert_eq(destination, "/url")
        assert_eq(title, Some("title"))
        assert_eq(surface.form, expected_form)
        assert_true(markdown_ir_view_test_is_some(surface.label_origin))
        assert_true(markdown_ir_view_test_is_some(surface.destination_origin))
        assert_true(markdown_ir_view_test_is_some(surface.title_origin))
        match expected_form {
          FullReferenceLinkForm | CollapsedReferenceLinkForm =>
            assert_true(
              markdown_ir_view_test_is_some(surface.reference_label_origin),
            )
          InlineLinkForm | ShortcutReferenceLinkForm =>
            assert_eq(surface.reference_label_origin, None)
        }
      }
      _ => fail("expected a typed link view")
    }
  }

  match
    markdown_ir_view_test_single_inline(
      "![foo][ref]\n\n[ref]: /image \"caption\"\n",
    ).view() {
    Image(destination~, title~, surface~) => {
      assert_eq(destination, "/image")
      assert_eq(title, Some("caption"))
      assert_eq(surface.form, FullReferenceLinkForm)
      assert_true(markdown_ir_view_test_is_some(surface.label_origin))
      assert_true(markdown_ir_view_test_is_some(surface.reference_label_origin))
      assert_true(markdown_ir_view_test_is_some(surface.destination_origin))
      assert_true(markdown_ir_view_test_is_some(surface.title_origin))
    }
    _ => fail("expected a distinct typed image view")
  }
}

///|
test "MarkdownIR public view keeps genuine recovery and returned arrays detached" {
  let document = genuine_recovery_source_ir(
    @core.SourceId("markdown-ir-public-view-recovery"),
    "unexpected",
  )
  let recovered = markdown_ir_view_test_first_recovered(document).unwrap()
  match recovered.view() {
    Recovered(value~) => assert_true(value.length() > 0)
    _ => fail("expected recovered MarkdownIR")
  }
  let diagnostic_count = recovered.diagnostics().length()
  assert_true(diagnostic_count > 0)
  let diagnostics = recovered.diagnostics()
  ignore(diagnostics.pop())
  assert_eq(recovered.diagnostics().length(), diagnostic_count)

  let child_count = document.children().length()
  let children = document.children()
  ignore(children.pop())
  assert_eq(document.children().length(), child_count)

  let raw_document = markdown_ir_view_test_document("[text](url\n")
  let tags : Array[String] = []
  markdown_ir_view_test_collect_external_tags(raw_document, tags)
  assert_true(tags.search_by(tag => tag.has_prefix("Raw:")) is Some(_))
}
