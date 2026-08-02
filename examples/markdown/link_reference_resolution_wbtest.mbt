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
fn link_reference_has_recovered(node : MarkdownIR) -> Bool {
  if node.is_recovered() {
    return true
  }
  for child in node.children() {
    if link_reference_has_recovered(child) {
      return true
    }
  }
  false
}

///|
fn link_reference_has_link(node : MarkdownIR) -> Bool {
  if node.node is Link(_, _, _, _) {
    return true
  }
  for child in node.children() {
    if link_reference_has_link(child) {
      return true
    }
  }
  false
}

///|
fn link_reference_has_image(node : MarkdownIR) -> Bool {
  if node.node is Image(_, _, _, _) {
    return true
  }
  for child in node.children() {
    if link_reference_has_image(child) {
      return true
    }
  }
  false
}

///|
fn assert_link_reference_has_no_opaque(node : MarkdownIR) -> Unit raise {
  assert_false(node.is_recovered())
  for child in node.children() {
    assert_link_reference_has_no_opaque(child)
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

///|
fn assert_image_completion_grade(node : MarkdownIR) -> Unit raise {
  assert_false(node.is_raw())
  assert_false(node.is_recovered())
  assert_false(node.is_unsupported())
  for child in node.children() {
    assert_image_completion_grade(child)
  }
}

///|
fn image_completion_ir(source : String) -> MarkdownIR raise {
  let source_id = @core.SourceId("markdown-image-completion")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown image completion parse failed")
  }
  assert_eq(diagnostics.length(), 0)
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn assert_inline_image_surface(
  image : MarkdownIR,
  expected_origin : MarkdownIROrigin,
  expected_label_origin : MarkdownIROrigin,
  expected_destination_origin : MarkdownIROrigin,
  expected_destination : String,
) -> Array[MarkdownIR] raise {
  match image.node {
    Image(children, destination, title, surface) => {
      assert_eq(image.origin, expected_origin)
      assert_eq(destination, expected_destination)
      assert_eq(title, None)
      assert_eq(surface.form, InlineLinkForm)
      assert_eq(surface.label_origin, Some(expected_label_origin))
      assert_eq(surface.reference_label_origin, None)
      assert_eq(surface.destination_origin, Some(expected_destination_origin))
      assert_eq(surface.title_origin, None)
      children
    }
    _ => abort("expected a typed MarkdownIR Image")
  }
}

///|
test "CommonMark images 574 and 575 retain typed nested label semantics" {
  let cases : Array[
    (
      Int,
      String,
      MarkdownIROrigin,
      MarkdownIROrigin,
      MarkdownIROrigin,
      MarkdownIROrigin,
      MarkdownIROrigin,
      MarkdownIROrigin,
      Bool,
    ),
  ] = [
    (
      574,
      "![foo ![bar](/url)](/url2)\n",
      MarkdownIROrigin(start=0, end=26),
      MarkdownIROrigin(start=2, end=18),
      MarkdownIROrigin(start=20, end=25),
      MarkdownIROrigin(start=6, end=18),
      MarkdownIROrigin(start=8, end=11),
      MarkdownIROrigin(start=13, end=17),
      true,
    ),
    (
      575,
      "![foo [bar](/url)](/url2)\n",
      MarkdownIROrigin(start=0, end=25),
      MarkdownIROrigin(start=2, end=17),
      MarkdownIROrigin(start=19, end=24),
      MarkdownIROrigin(start=6, end=17),
      MarkdownIROrigin(start=7, end=10),
      MarkdownIROrigin(start=12, end=16),
      false,
    ),
  ]
  for image_case in cases {
    let (
      example,
      source,
      outer_origin,
      outer_label_origin,
      outer_destination_origin,
      nested_origin,
      nested_label_origin,
      nested_destination_origin,
      nested_is_image,
    ) = image_case
    let ir = image_completion_ir(source)
    assert_image_completion_grade(ir)
    let outer = only_inline_node(ir)
    let children = assert_inline_image_surface(
      outer, outer_origin, outer_label_origin, outer_destination_origin, "/url2",
    )
    match children {
      [first, nested] =>
        match first.node {
          Text("foo ") => {
            assert_eq(markdown_ir_plain_text(children), "foo bar")
            if nested_is_image {
              ignore(
                assert_inline_image_surface(
                  nested, nested_origin, nested_label_origin, nested_destination_origin,
                  "/url",
                ),
              )
            } else {
              match nested.node {
                Link(nested_children, destination, title, surface) => {
                  assert_eq(nested.origin, nested_origin)
                  assert_eq(markdown_ir_plain_text(nested_children), "bar")
                  assert_eq(destination, "/url")
                  assert_eq(title, None)
                  assert_eq(surface.form, InlineLinkForm)
                  assert_eq(surface.label_origin, Some(nested_label_origin))
                  assert_eq(surface.reference_label_origin, None)
                  assert_eq(
                    surface.destination_origin,
                    Some(nested_destination_origin),
                  )
                  assert_eq(surface.title_origin, None)
                }
                _ => abort("expected a nested typed MarkdownIR Link")
              }
            }
          }
          _ => abort("expected text before the nested image/link")
        }
      _ => abort("expected text followed by one nested image/link")
    }
    let expected_html = "<p><img src=\"/url2\" alt=\"foo bar\" /></p>\n"
    match
      experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
        ir,
        Passthrough,
      ) {
      Ok(html) => assert_eq(html, expected_html)
      Err(_) =>
        fail("raw policy rejected CommonMark image " + example.to_string())
    }
    let expected_mdast =
      #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"image","url":"/url2","alt":"foo bar"}]}]}
    inspect(
      experimental_markdown_ir_to_mdast_json(ir).stringify(),
      content=expected_mdast,
    )
  }
}

///|
test "CommonMark image 590 keeps the nested reference label literal" {
  let source = "![[foo]]\n\n[[foo]]: /url \"title\"\n"
  let ir = image_completion_ir(source)
  assert_image_completion_grade(ir)
  assert_false(link_reference_has_link(ir))
  assert_false(link_reference_has_image(ir))
  match ir.node {
    Document([first, second]) =>
      match (first.node, second.node) {
        (Paragraph(first_children, _), Paragraph(second_children, _)) => {
          assert_eq(markdown_ir_plain_text(first_children), "![[foo]]")
          assert_eq(
            markdown_ir_plain_text(second_children),
            "[[foo]]: /url \"title\"",
          )
        }
        _ => abort("expected two literal paragraphs")
      }
    _ => abort("expected two paragraphs for CommonMark image 590")
  }
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p>![[foo]]</p>\n<p>[[foo]]: /url &quot;title&quot;</p>\n",
  )
  let expected_mdast =
    #|{"type":"root","children":[{"type":"paragraph","children":[{"type":"text","value":"![[foo]]"}]},{"type":"paragraph","children":[{"type":"text","value":"[[foo]]: /url \"title\""}]}]}
  inspect(
    experimental_markdown_ir_to_mdast_json(ir).stringify(),
    content=expected_mdast,
  )
}

///|
fn assert_links_recovered_prefix_html(
  example : Int,
  source : String,
  expected : String,
) -> Unit raise {
  let ir = link_reference_ir_from_source(source)
  assert_link_reference_has_no_opaque(ir)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(actual) => assert_eq(actual, expected)
    Err(_) => fail("raw policy rejected CommonMark " + example.to_string())
  }
}

///|
test "link recovery prefixes become literal before typed inline siblings" {
  let cases : Array[(Int, String, String)] = [
    (514, "[link [bar](/uri)\n", "<p>[link <a href=\"/uri\">bar</a></p>\n"),
    (524, "[foo <bar attr=\"](baz)\">\n", "<p>[foo <bar attr=\"](baz)\"></p>\n"),
    (525, "[foo`](/uri)`\n", "<p>[foo<code>](/uri)</code></p>\n"),
    (
      526, "[foo<https://example.com/?search=](uri)>\n", "<p>[foo<a href=\"https://example.com/?search=%5D(uri)\">https://example.com/?search=](uri)</a></p>\n",
    ),
    (
      536, "[foo <bar attr=\"][ref]\">\n\n[ref]: /uri\n", "<p>[foo <bar attr=\"][ref]\"></p>\n",
    ),
    (537, "[foo`][ref]`\n\n[ref]: /uri\n", "<p>[foo<code>][ref]</code></p>\n"),
    (
      538, "[foo<https://example.com/?search=][ref]>\n\n[ref]: /uri\n", "<p>[foo<a href=\"https://example.com/?search=%5D%5Bref%5D\">https://example.com/?search=][ref]</a></p>\n",
    ),
    (
      560, "[[bar [foo]\n\n[foo]: /url\n", "<p>[[bar <a href=\"/url\">foo</a></p>\n",
    ),
  ]
  for link_case in cases {
    let (example, source, expected) = link_case
    assert_links_recovered_prefix_html(example, source, expected)
  }
}

///|
test "typed inline before an unclosed bracket preserves recovery" {
  let ir = link_reference_ir_from_source("`code` [unclosed\n")
  assert_true(link_reference_has_recovered(ir))
}

///|
fn deep_unclosed_shortcut_fixture(
  depth : Int,
) -> (Array[MarkdownIR], MarkdownIRLoweringContext) {
  let source_id = @core.SourceId("deep-unclosed-shortcut")
  let source = "[".repeat(depth) + "x"
  let children : Array[MarkdownIR] = []
  for offset = 0; offset < depth; offset = offset + 1 {
    children.push(
      MarkdownIR::recovered(
        source_id,
        "[",
        MarkdownIROrigin(start=offset, end=offset + 1),
        [],
      ),
    )
  }
  children.push(
    MarkdownIR::text("x", MarkdownIROrigin(start=depth, end=depth + 1)),
  )
  (
    children,
    {
      source_id,
      source,
      reference_definition_lookup: _ => None,
      diagnostics_in_origin: _ => [],
      defer_reference_resolution: false,
      deferred_reference_candidates: None,
    },
  )
}

///|
test "incomplete full-reference suffix preserves every atom at EOF" {
  let source_id = @core.SourceId("incomplete-full-reference-suffix")
  let source = "[foo][bar"
  let children : Array[MarkdownIR] = [
    MarkdownIR::recovered(source_id, "[", MarkdownIROrigin(start=0, end=1), []),
    MarkdownIR::text("foo", MarkdownIROrigin(start=1, end=4)),
    MarkdownIR::raw(source_id, "]", MarkdownIROrigin(start=4, end=5), []),
    MarkdownIR::recovered(source_id, "[", MarkdownIROrigin(start=5, end=6), []),
    MarkdownIR::text("bar", MarkdownIROrigin(start=6, end=9)),
  ]
  let resolved = resolve_shortcut_references(children, {
    source_id,
    source,
    reference_definition_lookup: _ => None,
    diagnostics_in_origin: _ => [],
    defer_reference_resolution: false,
    deferred_reference_candidates: None,
  })
  assert_eq(resolved.length(), 5)
  assert_eq(markdown_ir_plain_text(resolved), source)
  assert_true(resolved[0].node is Text("["))
  assert_true(resolved[1].node is Text("foo"))
  assert_true(resolved[2].node is Text("]"))
  assert_true(resolved[3].node is Recovered("[", _))
  assert_true(resolved[4].node is Text("bar"))
  assert_eq(resolved[0].origin(), MarkdownIROrigin(start=0, end=1))
  assert_eq(resolved[1].origin(), MarkdownIROrigin(start=1, end=4))
  assert_eq(resolved[2].origin(), MarkdownIROrigin(start=4, end=5))
  assert_eq(resolved[3].origin(), MarkdownIROrigin(start=5, end=6))
  assert_eq(resolved[4].origin(), MarkdownIROrigin(start=6, end=9))
}

///|
test "shortcut reference label limit counts Unicode characters" {
  for character in ["a", "😈"] {
    let valid = character.repeat(999)
    let invalid = character.repeat(1000)
    assert_true(
      link_reference_label_is_within_limit(
        valid,
        MarkdownIROrigin(start=0, end=valid.length()),
      ),
    )
    assert_false(
      link_reference_label_is_within_limit(
        invalid,
        MarkdownIROrigin(start=0, end=invalid.length()),
      ),
    )
  }
}

///|
test "final lowering enforces the reference label character boundary" {
  for character in ["a", "😈"] {
    let valid_label = character.repeat(999)
    let valid = link_reference_ir_from_source(
      "[" + valid_label + "]\n\n[" + valid_label + "]: /url\n",
    )
    match valid.node {
      Document([paragraph, ..]) =>
        match paragraph.node {
          Paragraph([inline], _) =>
            match inline.node {
              Link(_, destination, _, _) => assert_eq(destination, "/url")
              _ => fail("999-character reference label must resolve")
            }
          _ => fail("valid reference must remain one inline")
        }
      _ => fail("valid reference must produce a document")
    }
    let invalid_label = character.repeat(1000)
    let invalid = link_reference_ir_from_source(
      "[" + invalid_label + "]\n\n[" + invalid_label + "]: /url\n",
    )
    match invalid.node {
      Document([paragraph, ..]) =>
        match paragraph.node {
          Paragraph(children, _) => {
            assert_eq(
              markdown_ir_plain_text(children),
              "[" + invalid_label + "]",
            )
            for child in children {
              assert_false(child.node is Link(_, _, _, _))
            }
          }
          _ => fail("over-limit reference must remain a paragraph")
        }
      _ => fail("over-limit reference must produce a document")
    }
  }
}

///|
test "final lowering counts CRLF as one reference label character" {
  let prefix = "a".repeat(499)
  let suffix = "b".repeat(499)
  let normalized_label = prefix + " " + suffix
  let valid_label = prefix + "\r\n" + suffix
  let invalid_label = prefix + "\r\n\t" + suffix
  assert_true(
    link_reference_label_is_within_limit(
      valid_label,
      MarkdownIROrigin(start=0, end=valid_label.length()),
    ),
  )
  assert_false(
    link_reference_label_is_within_limit(
      invalid_label,
      MarkdownIROrigin(start=0, end=invalid_label.length()),
    ),
  )
  let definition = "[" + normalized_label + "]: /url\n"
  let cases : Array[(String, LinkReferenceForm)] = [
    ("[" + valid_label + "]\n\n" + definition, ShortcutReferenceLinkForm),
    ("[text][" + valid_label + "]\n\n" + definition, FullReferenceLinkForm),
  ]
  for link_case in cases {
    let (source, expected_form) = link_case
    let inline = only_inline_node(link_reference_ir_from_source(source))
    match inline.node {
      Link(_, destination, _, surface) => {
        assert_eq(destination, "/url")
        assert_eq(surface.form, expected_form)
      }
      _ => fail("999-character CRLF reference label must resolve")
    }
  }
  let invalid_cases : Array[String] = [
    "[" + invalid_label + "]\n\n" + definition,
    "[text][" + invalid_label + "]\n\n" + definition,
  ]
  for source in invalid_cases {
    let ir = link_reference_ir_from_source(source)
    assert_false(link_reference_has_link(ir))
  }
}

///|
fn deep_unclosed_parenthesis_fixture(depth : Int) -> Array[MarkdownIR] {
  let source_id = @core.SourceId("deep-unclosed-parenthesis")
  let children : Array[MarkdownIR] = []
  for offset = 0; offset < depth; offset = offset + 1 {
    children.push(
      MarkdownIR::raw(
        source_id,
        "(",
        MarkdownIROrigin(start=offset, end=offset + 1),
        [],
      ),
    )
  }
  children.push(
    MarkdownIR::text("x", MarkdownIROrigin(start=depth, end=depth + 1)),
  )
  children
}

///|
fn deep_balanced_shortcut_fixture(
  depth : Int,
) -> (Array[MarkdownIR], MarkdownIRLoweringContext) {
  let source_id = @core.SourceId("deep-balanced-shortcut")
  let source = "[".repeat(depth) + "x" + "]".repeat(depth)
  let children : Array[MarkdownIR] = []
  for offset = 0; offset < depth; offset = offset + 1 {
    children.push(
      MarkdownIR::recovered(
        source_id,
        "[",
        MarkdownIROrigin(start=offset, end=offset + 1),
        [],
      ),
    )
  }
  children.push(
    MarkdownIR::text("x", MarkdownIROrigin(start=depth, end=depth + 1)),
  )
  for offset = 0; offset < depth; offset = offset + 1 {
    let start = depth + 1 + offset
    children.push(
      MarkdownIR::raw(source_id, "]", MarkdownIROrigin(start~, end=start + 1), []),
    )
  }
  (
    children,
    {
      source_id,
      source,
      reference_definition_lookup: _ => None,
      diagnostics_in_origin: _ => [],
      defer_reference_resolution: false,
      deferred_reference_candidates: None,
    },
  )
}

///|
fn deep_balanced_parenthesis_fixture(depth : Int) -> Array[MarkdownIR] {
  let source_id = @core.SourceId("deep-balanced-parenthesis")
  let children : Array[MarkdownIR] = []
  for offset = 0; offset < depth; offset = offset + 1 {
    children.push(
      MarkdownIR::raw(
        source_id,
        "(",
        MarkdownIROrigin(start=offset, end=offset + 1),
        [],
      ),
    )
  }
  children.push(
    MarkdownIR::text("x", MarkdownIROrigin(start=depth, end=depth + 1)),
  )
  for offset = 0; offset < depth; offset = offset + 1 {
    let start = depth + 1 + offset
    children.push(
      MarkdownIR::raw(source_id, ")", MarkdownIROrigin(start~, end=start + 1), []),
    )
  }
  children
}

///|
test "deep unclosed shortcut and parenthesis frames flatten exactly once" {
  let depth = 2048
  let (shortcut_children, context) = deep_unclosed_shortcut_fixture(depth)
  let shortcuts = resolve_shortcut_references(shortcut_children, context)
  assert_eq(shortcuts.length(), depth + 1)
  for index = 0; index < depth; index = index + 1 {
    assert_true(shortcuts[index].node is Recovered("[", _))
    assert_eq(
      shortcuts[index].origin(),
      MarkdownIROrigin(start=index, end=index + 1),
    )
  }
  assert_true(shortcuts[depth].node is Text("x"))
  assert_eq(
    shortcuts[depth].origin(),
    MarkdownIROrigin(start=depth, end=depth + 1),
  )
  let parentheses = literalize_balanced_raw_parentheses(
    deep_unclosed_parenthesis_fixture(depth),
  )
  assert_eq(parentheses.length(), depth + 1)
  for index = 0; index < depth; index = index + 1 {
    assert_true(parentheses[index].node is Raw("(", _))
    assert_eq(
      parentheses[index].origin(),
      MarkdownIROrigin(start=index, end=index + 1),
    )
  }
  assert_true(parentheses[depth].node is Text("x"))
  assert_eq(
    parentheses[depth].origin(),
    MarkdownIROrigin(start=depth, end=depth + 1),
  )
}

///|
test "deep balanced shortcut and parenthesis frames project exactly once" {
  let depth = 2048
  let (shortcut_children, context) = deep_balanced_shortcut_fixture(depth)
  let shortcuts = resolve_shortcut_references(shortcut_children, context)
  assert_eq(shortcuts.length(), depth * 2 + 1)
  assert_eq(markdown_ir_plain_text(shortcuts), context.source)
  for index = 0; index < depth; index = index + 1 {
    assert_true(shortcuts[index].node is Text("["))
    assert_eq(
      shortcuts[index].origin(),
      MarkdownIROrigin(start=index, end=index + 1),
    )
  }
  assert_true(shortcuts[depth].node is Text("x"))
  for offset = 0; offset < depth; offset = offset + 1 {
    let index = depth + 1 + offset
    assert_true(shortcuts[index].node is Text("]"))
    assert_eq(
      shortcuts[index].origin(),
      MarkdownIROrigin(start=index, end=index + 1),
    )
  }
  let parentheses = literalize_balanced_raw_parentheses(
    deep_balanced_parenthesis_fixture(depth),
  )
  assert_eq(parentheses.length(), depth * 2 + 1)
  for index = 0; index < depth; index = index + 1 {
    assert_true(parentheses[index].node is Text("("))
  }
  assert_true(parentheses[depth].node is Text("x"))
  for offset = 0; offset < depth; offset = offset + 1 {
    assert_true(parentheses[depth + 1 + offset].node is Text(")"))
  }
  for index = 0; index < parentheses.length(); index = index + 1 {
    assert_eq(
      parentheses[index].origin(),
      MarkdownIROrigin(start=index, end=index + 1),
    )
  }
}

///|
test "literal outer link finds a nested link through two emphasis layers" {
  let source = "[foo **bar *[baz][ref]* qux**][ref]\n\n[ref]: /uri\n"
  let ir = link_reference_ir_from_source(source)
  assert_link_reference_has_no_opaque(ir)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(actual) =>
      assert_eq(
        actual, "<p>[foo <strong>bar <em><a href=\"/uri\">baz</a></em> qux</strong>]<a href=\"/uri\">ref</a></p>\n",
      )
    Err(_) => fail("raw policy rejected nested emphasis link regression")
  }
}

///|
fn benchmark_deep_unclosed_shortcut_unwind(b : @bench.T, depth : Int) -> Unit {
  let (children, context) = deep_unclosed_shortcut_fixture(depth)
  b.bench(() => b.keep(resolve_shortcut_references(children, context)))
}

///|
fn benchmark_deep_unclosed_parenthesis_unwind(
  b : @bench.T,
  depth : Int,
) -> Unit {
  let children = deep_unclosed_parenthesis_fixture(depth)
  b.bench(() => b.keep(literalize_balanced_raw_parentheses(children)))
}

///|
fn benchmark_deep_balanced_shortcut_resolution(
  b : @bench.T,
  depth : Int,
) -> Unit {
  let (children, context) = deep_balanced_shortcut_fixture(depth)
  b.bench(() => b.keep(resolve_shortcut_references(children, context)))
}

///|
fn benchmark_deep_balanced_parenthesis_projection(
  b : @bench.T,
  depth : Int,
) -> Unit {
  let children = deep_balanced_parenthesis_fixture(depth)
  b.bench(() => b.keep(literalize_balanced_raw_parentheses(children)))
}

///|
test "bench: deep unclosed shortcut unwind 512" (b : @bench.T) {
  benchmark_deep_unclosed_shortcut_unwind(b, 512)
}

///|
test "bench: deep unclosed shortcut unwind 2048" (b : @bench.T) {
  benchmark_deep_unclosed_shortcut_unwind(b, 2048)
}

///|
test "bench: deep unclosed parenthesis unwind 512" (b : @bench.T) {
  benchmark_deep_unclosed_parenthesis_unwind(b, 512)
}

///|
test "bench: deep unclosed parenthesis unwind 2048" (b : @bench.T) {
  benchmark_deep_unclosed_parenthesis_unwind(b, 2048)
}

///|
test "bench: deep balanced shortcut resolution 512" (b : @bench.T) {
  benchmark_deep_balanced_shortcut_resolution(b, 512)
}

///|
test "bench: deep balanced shortcut resolution 2048" (b : @bench.T) {
  benchmark_deep_balanced_shortcut_resolution(b, 2048)
}

///|
test "bench: deep balanced parenthesis projection 512" (b : @bench.T) {
  benchmark_deep_balanced_parenthesis_projection(b, 512)
}

///|
test "bench: deep balanced parenthesis projection 2048" (b : @bench.T) {
  benchmark_deep_balanced_parenthesis_projection(b, 2048)
}
