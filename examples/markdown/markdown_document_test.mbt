///|
fn markdown_document_test_parser(
  source_id : @core.SourceId,
  source : String,
) -> @loom.Parser[Block] {
  try! @loom.new_parser(source_id, source, markdown_grammar)
}

///|
fn markdown_document_test_find_heading(
  node : MarkdownSemanticReadNode,
) -> MarkdownSemanticReadNode? {
  match node.view() {
    Heading(..) => Some(node)
    _ => {
      for child in node.children() {
        match markdown_document_test_find_heading(child) {
          Some(found) => return Some(found)
          None => continue
        }
      }
      None
    }
  }
}

///|
fn markdown_document_test_find_link(
  node : MarkdownSemanticReadNode,
) -> MarkdownSemanticReadNode? {
  match node.view() {
    Link(..) => Some(node)
    _ => {
      for child in node.children() {
        match markdown_document_test_find_link(child) {
          Some(found) => return Some(found)
          None => continue
        }
      }
      None
    }
  }
}

///|
fn markdown_document_test_find_autolink(
  node : MarkdownSemanticReadNode,
) -> MarkdownSemanticReadNode? {
  match node.view() {
    Autolink(..) => Some(node)
    _ => {
      for child in node.children() {
        match markdown_document_test_find_autolink(child) {
          Some(found) => return Some(found)
          None => continue
        }
      }
      None
    }
  }
}

///|
fn markdown_document_test_expect_node(
  node : MarkdownSemanticReadNode?,
  message : String,
) -> MarkdownSemanticReadNode {
  match node {
    Some(node) => node
    None => abort(message)
  }
}

///|
fn markdown_document_test_expect_selection(
  selection : MarkdownSemanticSelection?,
  message : String,
) -> MarkdownSemanticSelection {
  match selection {
    Some(selection) => selection
    None => abort(message)
  }
}

///|
test "MarkdownDocument owns one parser snapshot" {
  let source_id = @core.SourceId("markdown-document-snapshot")
  let source = "# heading\n\nparagraph\n"
  let document = parse_document(source_id, source)
  assert_eq(document.source_id(), source_id)
  assert_eq(document.source(), source)
  assert_eq(document.diagnostics().length(), 0)
  let read = document.semantic_read()
  match read.root().view() {
    Document => ()
    _ => fail("expected a document read root")
  }
}

///|
test "MarkdownSemanticRead preserves malformed recovery diagnostics" {
  let document = parse_document(
    @core.SourceId("markdown-semantic-read-recovery"),
    "[unclosed\n",
  )
  assert_eq(document.diagnostics().length(), 0)
  let read = document.semantic_read()
  let mdast = markdown_semantic_read_to_mdast_json_with_positions(read).stringify()
  assert_true(mdast.contains("mdastRecovered"))
  match read.ir().children() {
    [paragraph] =>
      match paragraph.children() {
        [recovered, ..] => {
          match recovered.view() {
            Recovered(..) => ()
            _ => fail("expected a recovered MarkdownIR node")
          }
          assert_true(recovered.diagnostics().length() > 0)
        }
        _ => fail("expected recovered paragraph content")
      }
    _ => fail("expected one recovered paragraph")
  }
}

///|
test "MarkdownSemanticRead adapters reuse captured source" {
  let source_id = @core.SourceId("markdown-semantic-read-adapters")
  let source = "[old](https://example.test \"title\")\n"
  let read = parse_document(source_id, source).semantic_read()
  assert_eq(markdown_semantic_read_preserve_rewrite(read), source)
  assert_eq(
    markdown_semantic_read_to_mdast_json_with_positions(read).stringify(),
    experimental_markdown_ir_to_mdast_json_with_positions(read.ir(), source).stringify(),
  )
  let direct = parse(source_id, source)
  assert_eq(markdown_semantic_read_to_block(read), direct)
}

///|
test "MarkdownSemanticRead selections rewrite only their read snapshot" {
  let source_id = @core.SourceId("markdown-semantic-read-selections")
  let source = "# old\n\n[link](https://example.test \"title\")\n\n<https://example.org>\n"
  let read = parse_document(source_id, source).semantic_read()
  let root = read.root()
  let heading = markdown_document_test_expect_node(
    markdown_document_test_find_heading(root),
    "expected heading",
  )
  let link = markdown_document_test_expect_node(
    markdown_document_test_find_link(root),
    "expected link",
  )
  let autolink = markdown_document_test_expect_node(
    markdown_document_test_find_autolink(root),
    "expected autolink",
  )
  let heading_selection = markdown_document_test_expect_selection(
    heading.selection(kind=MarkdownSemanticSelectionKind::Content),
    "expected heading content selection",
  )
  let destination_selection = markdown_document_test_expect_selection(
    link.selection(kind=MarkdownSemanticSelectionKind::Destination),
    "expected link destination selection",
  )
  let title_selection = markdown_document_test_expect_selection(
    link.selection(kind=MarkdownSemanticSelectionKind::Title),
    "expected link title selection",
  )
  let display_selection = markdown_document_test_expect_selection(
    autolink.selection(kind=MarkdownSemanticSelectionKind::AutolinkDisplay),
    "expected autolink display selection",
  )
  assert_eq(
    markdown_semantic_read_local_transform_rewrite(
      heading_selection,
      replacement_text="new",
    ),
    "# new\n\n[link](https://example.test \"title\")\n\n<https://example.org>\n",
  )
  assert_eq(
    markdown_semantic_read_local_transform_rewrite(
      destination_selection,
      replacement_text="https://changed.test",
    ),
    "# old\n\n[link](https://changed.test \"title\")\n\n<https://example.org>\n",
  )
  assert_eq(
    markdown_semantic_read_local_transform_rewrite(
      title_selection,
      replacement_text="new title",
    ),
    "# old\n\n[link](https://example.test \"new title\")\n\n<https://example.org>\n",
  )
  assert_eq(
    markdown_semantic_read_local_transform_rewrite(
      display_selection,
      replacement_text="changed.example",
    ),
    "# old\n\n[link](https://example.test \"title\")\n\n<changed.example>\n",
  )
}

///|
test "MarkdownSemanticRead selections cover whole nodes and missing targets" {
  let read = parse_document(
    @core.SourceId("markdown-semantic-read-selection-kinds"),
    "# heading\n\n[link](https://example.test)\n",
  ).semantic_read()
  let root = read.root()
  assert_true(
    root.selection(kind=MarkdownSemanticSelectionKind::WholeNode) is Some(_),
  )
  let heading = markdown_document_test_expect_node(
    markdown_document_test_find_heading(root),
    "expected heading",
  )
  let link = markdown_document_test_expect_node(
    markdown_document_test_find_link(root),
    "expected link",
  )
  assert_true(
    link.selection(kind=MarkdownSemanticSelectionKind::WholeNode) is Some(_),
  )
  assert_true(
    heading.selection(kind=MarkdownSemanticSelectionKind::Destination) is None,
  )
  assert_true(
    heading.selection(kind=MarkdownSemanticSelectionKind::Title) is None,
  )
  assert_true(
    heading.selection(kind=MarkdownSemanticSelectionKind::AutolinkDisplay)
    is None,
  )
  assert_true(
    link.selection(kind=MarkdownSemanticSelectionKind::Content) is None,
  )
  assert_true(
    link.selection(kind=MarkdownSemanticSelectionKind::AutolinkDisplay) is None,
  )
}

///|
test "MarkdownSemanticRead survives its source document" {
  let source_id = @core.SourceId("markdown-semantic-read-detached")
  let read = {
    let document = parse_document(source_id, "detached\n")
    document.semantic_read()
  }
  assert_eq(markdown_semantic_read_preserve_rewrite(read), "detached\n")
}

///|
test "MarkdownSemanticAttachment source_document tracks parser snapshots" {
  let source_id = @core.SourceId("markdown-semantic-attachment-source-document")
  let parser = markdown_document_test_parser(source_id, "first\n")
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  let first = attachment.source_document()
  assert_eq(first.source(), "first\n")
  parser.set_source("second\n")
  let second = attachment.source_document()
  assert_eq(second.source(), "second\n")
  assert_eq(first.source(), "first\n")
  let first_read = first.semantic_read()
  attachment.dispose()
  assert_eq(markdown_semantic_read_preserve_rewrite(first_read), "first\n")
}
