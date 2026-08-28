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
fn markdown_document_test_find_image(
  node : MarkdownSemanticReadNode,
) -> MarkdownSemanticReadNode? {
  match node.view() {
    Image(..) => Some(node)
    _ => {
      for child in node.children() {
        match markdown_document_test_find_image(child) {
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
fn markdown_document_test_collect_task_states(
  node : MarkdownSemanticReadNode,
  states : Array[Bool?],
) -> Unit {
  match node.view() {
    ListItem(task~, ..) | OrderedListItem(task~, ..) =>
      states.push(task.map(task => task.checked()))
    _ => ()
  }
  for child in node.children() {
    markdown_document_test_collect_task_states(child, states)
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
test "MarkdownDocument keeps GFM task syntax literal by default" {
  let source_id = @core.SourceId("markdown-commonmark-task-list-literal")
  let document = parse_document(source_id, "- [ ] todo\n")
  assert_eq(document.diagnostics().length(), 0)
  let read = document.semantic_read()
  match read.root().children() {
    [list] =>
      match list.children() {
        [item] => {
          match item.view() {
            ListItem(task=None, ..) => ()
            _ => fail("expected CommonMark list item without task semantics")
          }
          match item.children() {
            [paragraph] => {
              let literal = paragraph
                .children()
                .map(child => {
                  match child.view() {
                    Text(value~) => value
                    _ => fail("expected literal CommonMark task-like text")
                  }
                })
                .join("")
              assert_eq(literal, "[ ] todo")
            }
            _ => fail("expected one literal paragraph")
          }
        }
        _ => fail("expected one CommonMark list item")
      }
    _ => fail("expected one CommonMark list")
  }
  let html = experimental_markdown_ir_to_commonmark_html(read.ir())
  assert_false(html.contains("type=\"checkbox\""))
  assert_true(html.contains("[ ] todo"))
}

///|
test "direct MarkdownIR lowering opts in to task-list semantics" {
  let source_id = @core.SourceId("markdown-direct-task-list-extension")
  let (cst, diagnostics) = try! parse_cst(source_id, "- [x] done\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let commonmark = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    syntax,
    diagnostics.copy(),
  )
  let task_list_without_diagnostics = experimental_markdown_ir_from_syntax(
    source_id,
    syntax,
    extensions=MarkdownExtensions::task_list(),
  )
  let task_list = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    syntax,
    diagnostics,
    extensions=MarkdownExtensions::task_list(),
  )
  assert_false(
    experimental_markdown_ir_to_mdast_json(commonmark)
    .stringify()
    .contains("\"checked\":"),
  )
  assert_true(
    experimental_markdown_ir_to_mdast_json(task_list_without_diagnostics)
    .stringify()
    .contains("\"checked\":true"),
  )
  assert_true(
    experimental_markdown_ir_to_mdast_json(task_list)
    .stringify()
    .contains("\"checked\":true"),
  )
  assert_eq(
    experimental_markdown_ir_canonical_format_checked(source_id, task_list),
    Ok("- [x] done"),
  )
}

///|
test "MarkdownSemanticRead exposes an unchecked GFM task list item" {
  let source_id = @core.SourceId("markdown-semantic-read-task-list")
  let document = parse_document(
    source_id,
    "- [ ] todo\n",
    extensions=MarkdownExtensions::task_list(),
  )
  let read = document.semantic_read()
  match read.root().children() {
    [list] =>
      match list.children() {
        [item] => {
          match item.view() {
            ListItem(task=Some(task), ..) => {
              assert_false(task.checked())
              assert_eq(task.marker_origin().start(), 2)
              assert_eq(task.marker_origin().end(), 5)
            }
            _ => fail("expected an unchecked task list item")
          }
          match item.children() {
            [paragraph] =>
              match paragraph.children() {
                [text] =>
                  match text.view() {
                    Text(value="todo") => ()
                    _ => fail("expected the task marker to be removed")
                  }
                _ => fail("expected one task paragraph text child")
              }
            _ => fail("expected one task paragraph")
          }
        }
        _ => fail("expected one task list item")
      }
    _ => fail("expected one task list")
  }
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(read.ir()),
    "<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> todo</li>\n</ul>\n",
  )
  assert_eq(
    experimental_markdown_ir_canonical_format(source_id, read.ir()),
    "- [ ] todo",
  )
  assert_eq(
    experimental_markdown_ir_canonical_format_checked(source_id, read.ir()),
    Ok("- [ ] todo"),
  )
}

///|
test "MarkdownSemanticRead recognizes a task marker before continued content" {
  let read = parse_document(
    @core.SourceId("markdown-semantic-read-continued-task"),
    "- [x]\n  continued\n",
    extensions=MarkdownExtensions::task_list(),
  ).semantic_read()
  match read.root().children() {
    [list] =>
      match list.children() {
        [item] => {
          match item.view() {
            ListItem(task=Some(task), ..) => assert_true(task.checked())
            _ => fail("expected a checked task list item")
          }
          match item.children() {
            [paragraph] =>
              match paragraph.children() {
                [text] =>
                  match text.view() {
                    Text(value="continued") => ()
                    _ => fail("expected continued task content")
                  }
                _ => fail("expected one continued task text child")
              }
            _ => fail("expected one continued task paragraph")
          }
        }
        _ => fail("expected one continued task item")
      }
    _ => fail("expected one continued task list")
  }
}

///|
test "MarkdownSemanticRead follows the GFM task marker boundary" {
  let source =
    #|- [ ] todo
    #|- [x] done
    #|- [X] uppercase
    #|* [ ] star
    #|+ [x] plus
    #|-   [ ] spaced
    #|1. [	] ordered
    #|- [y] ordinary
    #|- [x]no-separator
    #|
  let read = parse_document(
    @core.SourceId("markdown-semantic-read-task-boundary"),
    source,
    extensions=MarkdownExtensions::task_list(),
  ).semantic_read()
  let states : Array[Bool?] = []
  markdown_document_test_collect_task_states(read.root(), states)
  assert_eq(states, [
    Some(false),
    Some(true),
    Some(true),
    Some(false),
    Some(true),
    Some(false),
    Some(false),
    None,
    None,
  ])
  let mdast = experimental_markdown_ir_to_mdast_json(read.ir()).stringify()
  assert_true(mdast.contains("\"checked\":false"))
  assert_true(mdast.contains("\"checked\":true"))
  assert_true(
    experimental_markdown_ir_to_commonmark_html(read.ir()).contains(
      "disabled=\"\" checked=\"\"",
    ),
  )
}

///|
test "MarkdownSemanticRead permits definitions before the first task paragraph" {
  let read = parse_document(
    @core.SourceId("markdown-semantic-read-task-after-definition"),
    "- [ref]: /url\n  [x] task\n",
    extensions=MarkdownExtensions::task_list(),
  ).semantic_read()
  let states : Array[Bool?] = []
  let root = read.root()
  markdown_document_test_collect_task_states(root, states)
  assert_eq(states, [Some(true)])
  match root.children() {
    [list] =>
      match list.children() {
        [item] =>
          match item.children() {
            [paragraph] =>
              match paragraph.children() {
                [text] =>
                  match text.view() {
                    Text(value="task") => ()
                    _ => fail("expected task content without its marker")
                  }
                _ => fail("expected one task text child")
              }
            _ => fail("expected definitions to precede one task paragraph")
          }
        _ => fail("expected one task item after definitions")
      }
    _ => fail("expected one task list after definitions")
  }
}

///|
test "MarkdownSemanticRead does not promote a later paragraph task marker" {
  let source_id = @core.SourceId("markdown-semantic-read-later-task-marker")
  let read = parse_document(
    source_id,
    "- first\n\n  [x] second\n",
    extensions=MarkdownExtensions::task_list(),
  ).semantic_read()
  match read.root().children() {
    [list] =>
      match list.children() {
        [item] => {
          match item.view() {
            ListItem(task=None, ..) => ()
            _ => fail("expected an ordinary list item")
          }
          match item.children() {
            [_, later] =>
              match later.children() {
                [marker, ..] =>
                  match marker.view() {
                    Text(value="[x]") => ()
                    _ => fail("expected the later marker to remain literal")
                  }
                _ => fail("expected later paragraph content")
              }
            _ => fail("expected two ordinary paragraphs")
          }
        }
        _ => fail("expected one ordinary list item")
      }
    _ => fail("expected one ordinary list")
  }
}

///|
test "MarkdownSemanticRead requires the first content block to be a paragraph" {
  let read = parse_document(
    @core.SourceId("markdown-semantic-read-task-after-heading"),
    "- # heading\n\n  [x] later\n",
    extensions=MarkdownExtensions::task_list(),
  ).semantic_read()
  let states : Array[Bool?] = []
  markdown_document_test_collect_task_states(read.root(), states)
  assert_eq(states, [None])
}

///|
test "MarkdownSemanticRead keeps an unresolved bracket as ordinary text" {
  let document = parse_document(
    @core.SourceId("markdown-semantic-read-unresolved-bracket"),
    "[unclosed\n",
  )
  assert_eq(document.diagnostics().length(), 0)
  let read = document.semantic_read()
  let mdast = markdown_semantic_read_to_mdast_json_with_positions(read).stringify()
  assert_false(mdast.contains("mdastRecovered"))
  match read.ir().children() {
    [paragraph] =>
      match paragraph.children() {
        [opener, text] => {
          match opener.view() {
            Text(value~) => assert_eq(value, "[")
            _ => fail("expected literal opener text")
          }
          match text.view() {
            Text(value~) => assert_eq(value, "unclosed")
            _ => fail("expected literal trailing text")
          }
          assert_eq(opener.diagnostics().length(), 0)
        }
        _ => fail("expected literal paragraph content")
      }
    _ => fail("expected one paragraph")
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
    link.selection(kind=MarkdownSemanticSelectionKind::Content) is Some(_),
  )
  assert_true(
    link.selection(kind=MarkdownSemanticSelectionKind::AutolinkDisplay) is None,
  )
}

///|
test "MarkdownSemanticRead content selections rewrite link and image labels" {
  let source = "[link label](https://example.test)\n\n![image alt](https://image.test)\n"
  let read = parse_document(
    @core.SourceId("markdown-semantic-read-content-selections"),
    source,
  ).semantic_read()
  let root = read.root()
  let link = markdown_document_test_expect_node(
    markdown_document_test_find_link(root),
    "expected link",
  )
  let image = markdown_document_test_expect_node(
    markdown_document_test_find_image(root),
    "expected image",
  )
  let link_content = markdown_document_test_expect_selection(
    link.selection(kind=MarkdownSemanticSelectionKind::Content),
    "expected link content selection",
  )
  let image_content = markdown_document_test_expect_selection(
    image.selection(kind=MarkdownSemanticSelectionKind::Content),
    "expected image content selection",
  )
  assert_eq(
    markdown_semantic_read_local_transform_rewrite(
      link_content,
      replacement_text="new link",
    ),
    "[new link](https://example.test)\n\n![image alt](https://image.test)\n",
  )
  assert_eq(
    markdown_semantic_read_local_transform_rewrite(
      image_content,
      replacement_text="new alt",
    ),
    "[link label](https://example.test)\n\n![new alt](https://image.test)\n",
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
