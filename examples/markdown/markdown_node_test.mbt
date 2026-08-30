///|
fn markdown_node_test_first_inline(
  source : String,
) -> MarkdownNode raise Failure {
  let root = parse(source).root()
  guard root.children() is [block, ..] else { fail("expected one block") }
  guard block.children() is [inline, ..] else {
    fail("expected one inline node")
  }
  inline
}

///|
test "MarkdownNode preserves link reference forms" {
  let cases = [
    ("[foo](/url)\n", MarkdownReferenceForm::Inline),
    ("[foo][bar]\n\n[bar]: /url\n", MarkdownReferenceForm::FullReference),
    ("[foo][]\n\n[foo]: /url\n", MarkdownReferenceForm::CollapsedReference),
    ("[foo]\n\n[foo]: /url\n", MarkdownReferenceForm::ShortcutReference),
  ]
  cases.each(case => {
    let (source, expected) = case
    match markdown_node_test_first_inline(source).view() {
      Link(destination="/url", reference_form~, ..) =>
        assert_eq(reference_form, expected)
      other => fail("expected link, got " + @debug.to_string(other))
    }
  })
}

///|
test "MarkdownNode preserves image reference forms" {
  let cases = [
    ("![foo](/image)\n", MarkdownReferenceForm::Inline),
    ("![foo][bar]\n\n[bar]: /image\n", MarkdownReferenceForm::FullReference),
    ("![foo][]\n\n[foo]: /image\n", MarkdownReferenceForm::CollapsedReference),
    ("![foo]\n\n[foo]: /image\n", MarkdownReferenceForm::ShortcutReference),
  ]
  cases.each(case => {
    let (source, expected) = case
    match markdown_node_test_first_inline(source).view() {
      Image(destination="/image", reference_form~, ..) =>
        assert_eq(reference_form, expected)
      other => fail("expected image, got " + @debug.to_string(other))
    }
  })
}

///|
test "MarkdownNode preserves autolink hard-break and task metadata" {
  match markdown_node_test_first_inline("<https://example.test>\n").view() {
    Autolink(kind=Uri, display="https://example.test", ..) => ()
    other => fail("expected URI autolink, got " + @debug.to_string(other))
  }
  let paragraph = parse("a  \nb\\\nc\n").root().children()[0]
  let forms = paragraph
    .children()
    .filter_map(node => {
      match node.view() {
        HardBreak(form~) => Some(form)
        _ => None
      }
    })
  assert_eq(forms, [TrailingSpaces(2), Backslash])
  let item = parse("- [x] task\n", extensions=MarkdownExtensions::task_list())
    .root()
    .children()[0].children()[0]
  match item.view() {
    ListItem(task_checked=Some(true), ..) => ()
    other => fail("expected checked task item, got " + @debug.to_string(other))
  }
}

///|
test "MarkdownNode remains valid after its document goes out of scope" {
  let root = {
    let document = parse("detached\n")
    document.root()
  }
  assert_eq(root.view(), MarkdownNodeView::Document)
  match root.children()[0].children()[0].view() {
    Text(value="detached") => ()
    other => fail("expected detached text, got " + @debug.to_string(other))
  }
}
