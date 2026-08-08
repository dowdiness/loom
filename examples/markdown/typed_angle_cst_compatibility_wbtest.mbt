///|
fn typed_angle_fixture_policy() -> @seam.CstMetadataPolicy {
  @seam.CstMetadataPolicy::new(
    [ErrorToken.to_raw()],
    error_kind=Some(ErrorNode.to_raw()),
    incomplete_kind=Some(ErrorNode.to_raw()),
  )
}

///|
fn typed_angle_fixture_node(
  source : String,
  kind : SyntaxKind,
  pieces : Array[(Int, Int)],
  policy : @seam.CstMetadataPolicy,
) -> @seam.CstNode {
  let children : Array[@seam.CstElement] = []
  for piece in pieces {
    let (start, end) = piece
    children.push(
      @seam.CstElement::Token(
        @seam.CstToken::CstToken(
          TextToken.to_raw(),
          source.view(start_offset=start, end_offset=end),
        ),
      ),
    )
  }
  @seam.CstNode::new(kind.to_raw(), children, policy~) catch {
    _ => abort("typed angle fixture node construction failed")
  }
}

///|
fn typed_angle_fixture(
  source : String,
  kind : SyntaxKind,
  pieces : Array[(Int, Int)],
) -> @seam.SyntaxNode {
  let policy = typed_angle_fixture_policy()
  let typed = typed_angle_fixture_node(source, kind, pieces, policy)
  let paragraph = @seam.CstNode::new(
    ParagraphNode.to_raw(),
    [@seam.CstElement::Node(typed)],
    policy~,
  ) catch {
    _ => abort("typed angle fixture paragraph construction failed")
  }
  let document = @seam.CstNode::new(
    DocumentNode.to_raw(),
    [@seam.CstElement::Node(paragraph)],
    policy~,
  ) catch {
    _ => abort("typed angle fixture document construction failed")
  }
  @seam.SyntaxNode::from_cst(document)
}

///|
fn typed_angle_fixture_document(
  source : String,
  parts : Array[(SyntaxKind, Int, Int)],
) -> @seam.SyntaxNode {
  let policy = typed_angle_fixture_policy()
  let children : Array[@seam.CstElement] = []
  let mut previous_end = 0
  for part in parts {
    let (kind, start, end) = part
    if start > previous_end {
      children.push(
        @seam.CstElement::Token(
          @seam.CstToken::CstToken(
            TextToken.to_raw(),
            source.view(start_offset=previous_end, end_offset=start),
          ),
        ),
      )
    }
    let typed = typed_angle_fixture_node(source, kind, [(start, end)], policy)
    children.push(@seam.CstElement::Node(typed))
    previous_end = end
  }
  if previous_end < source.length() {
    children.push(
      @seam.CstElement::Token(
        @seam.CstToken::CstToken(
          TextToken.to_raw(),
          source.view(start_offset=previous_end, end_offset=source.length()),
        ),
      ),
    )
  }
  let paragraph = @seam.CstNode::new(ParagraphNode.to_raw(), children, policy~) catch {
    _ => abort("typed angle fixture paragraph construction failed")
  }
  let document = @seam.CstNode::new(
    DocumentNode.to_raw(),
    [@seam.CstElement::Node(paragraph)],
    policy~,
  ) catch {
    _ => abort("typed angle fixture document construction failed")
  }
  @seam.SyntaxNode::from_cst(document)
}

///|
test "typed angle nodes use append-only raw kinds" {
  assert_eq(InlineCodeNode.to_raw(), @seam.RawKind(26))
  assert_eq(LinkReferenceDefinitionNode.to_raw(), @seam.RawKind(41))
  assert_eq(UriAutolinkNode.to_raw(), @seam.RawKind(42))
  assert_eq(EmailAutolinkNode.to_raw(), @seam.RawKind(43))
  assert_eq(InlineHtmlNode.to_raw(), @seam.RawKind(44))
  assert_eq(@seam.FromRawKind::from_raw(@seam.RawKind(42)), UriAutolinkNode)
  assert_eq(@seam.FromRawKind::from_raw(@seam.RawKind(43)), EmailAutolinkNode)
  assert_eq(@seam.FromRawKind::from_raw(@seam.RawKind(44)), InlineHtmlNode)
  assert_true(!UriAutolinkNode.is_token())
  assert_true(!EmailAutolinkNode.is_token())
  assert_true(!InlineHtmlNode.is_token())
}

///|
test "typed angle fixture nodes compose under the markdown_spec metadata domain" {
  let source = "<http://example.test>"
  let policy = typed_angle_fixture_policy()
  let typed = typed_angle_fixture_node(
    source,
    UriAutolinkNode,
    [(0, 1), (1, source.length() - 1), (source.length() - 1, source.length())],
    policy,
  )
  let paragraph = @seam.CstNode::new(
    ParagraphNode.to_raw(),
    [@seam.CstElement::Node(typed)],
    policy~,
  )
  let document = @seam.CstNode::new(
    DocumentNode.to_raw(),
    [@seam.CstElement::Node(paragraph)],
    policy~,
  )
  let syntax = @seam.SyntaxNode::from_cst(document)
  assert_eq(syntax.text(), source)
  assert_eq(syntax.children().length(), 1)
}

///|
test "typed angle CST remains structurally reusable under the generic CST contract" {
  let source = "<http://example.test>"
  let first = typed_angle_fixture(source, UriAutolinkNode, [
    (0, 1),
    (1, source.length() - 1),
    (source.length() - 1, source.length()),
  ])
  let second = typed_angle_fixture(source, UriAutolinkNode, [
    (0, 1),
    (1, source.length() - 1),
    (source.length() - 1, source.length()),
  ])
  assert_eq(first.cst_node(), second.cst_node())
  assert_eq(first.text(), source)
}

///|
test "typed angle CST lowers at the MarkdownIR seam with source origins" {
  let source = "<https://example.test/a\\b> <foo@bar.example> <i>"
  let uri_start = 0
  let uri_end = 26
  let email_start = 27
  let email_end = 44
  let html_start = 45
  let html_end = source.length()
  let syntax = typed_angle_fixture_document(source, [
    (UriAutolinkNode, uri_start, uri_end),
    (EmailAutolinkNode, email_start, email_end),
    (InlineHtmlNode, html_start, html_end),
  ])
  assert_eq(syntax.text(), source)
  let fidelity_syntax = typed_angle_fixture(
    source[uri_start:uri_end].to_owned(),
    UriAutolinkNode,
    [(0, 1), (1, uri_end - 1), (uri_end - 1, uri_end)],
  )
  let typed_uri = fidelity_syntax.children()[0].children()[0]
  assert_eq(
    typed_uri
    .direct_elements_iter()
    .filter_map(element => {
      match element {
        @seam.SyntaxElement::Token(token) => Some((token.start(), token.end()))
        @seam.SyntaxElement::Node(_) => None
      }
    })
    .to_array(),
    [
      (uri_start, uri_start + 1),
      (uri_start + 1, uri_end - 1),
      (uri_end - 1, uri_end),
    ],
  )
  let source_id = @core.SourceId("typed-angle-cst-fixture")
  let ir = experimental_markdown_ir_from_syntax(source_id, syntax)
  match ir.children() {
    [paragraph] =>
      match paragraph.children() {
        [uri, space1, email, space2, html] => {
          match uri.node {
            Autolink(
              UriAutolinkKind,
              "https://example.test/a\\b",
              "https://example.test/a%5Cb",
              Some(label_origin),
              Some(destination_origin)
            ) => {
              assert_eq(label_origin, destination_origin)
              assert_eq(
                uri.origin(),
                MarkdownIROrigin(start=uri_start, end=uri_end),
              )
              assert_eq(
                label_origin,
                MarkdownIROrigin(start=uri_start + 1, end=uri_end - 1),
              )
            }
            _ => fail("typed URI did not lower as an autolink")
          }
          assert_eq(space1.text_value(), Some(" "))
          match email.node {
            Autolink(
              EmailAutolinkKind,
              "foo@bar.example",
              "mailto:foo@bar.example",
              Some(label_origin),
              None
            ) => {
              assert_eq(
                label_origin,
                MarkdownIROrigin(start=email_start + 1, end=email_end - 1),
              )
              assert_eq(
                email.origin(),
                MarkdownIROrigin(start=email_start, end=email_end),
              )
            }
            _ => fail("typed email did not lower as an autolink")
          }
          assert_eq(space2.text_value(), Some(" "))
          match html.node {
            InlineHtml("<i>", Some(origin)) =>
              assert_eq(
                origin,
                MarkdownIROrigin(start=html_start, end=html_end),
              )
            _ => fail("typed HTML did not lower as inline HTML")
          }
        }
        _ => fail("typed angle fixture changed paragraph child shape")
      }
    _ => fail("typed angle fixture did not lower as one paragraph")
  }
  assert_eq(
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ),
    Ok(
      "<p><a href=\"https://example.test/a%5Cb\">https://example.test/a\\b</a> <a href=\"mailto:foo@bar.example\">foo@bar.example</a> <i></p>\n",
    ),
  )
}

///|
test "generic text does not rediscover typed angle semantics" {
  let cases = [
    ("<https://example.test>", "&lt;https://example.test&gt;"),
    ("<foo@bar.example>", "&lt;foo@bar.example&gt;"),
    ("<i>", "&lt;i&gt;"),
  ]
  for angle_case in cases {
    let (source, escaped) = angle_case
    let syntax = typed_angle_fixture_document(source, [])
    let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
      @core.SourceId("issue-894-generic-angle-text"),
      syntax,
      @core.DiagnosticSet::empty(),
    )
    match ir.children() {
      [paragraph] =>
        match paragraph.children() {
          [text] => assert_eq(text.text_value(), Some(source))
          _ => fail("generic angle text changed inline shape")
        }
      _ => fail("generic angle text changed paragraph shape")
    }
    assert_eq(
      experimental_markdown_ir_to_commonmark_html(ir),
      "<p>" + escaped + "</p>\n",
    )
  }
}

///|
test "typed angle fixture preserves legacy roles and editor adapter shape" {
  let source = "<http://example.test>"
  let syntax = typed_angle_fixture(source, UriAutolinkNode, [
    (0, 1),
    (1, source.length() - 1),
    (source.length() - 1, source.length()),
  ])
  assert_eq(project_markdown_roles(syntax), [])
  let ir = experimental_markdown_ir_from_syntax(
    @core.SourceId("typed-angle-adapter-fixture"),
    syntax,
  )
  assert_eq(ir, inline_angle_ir_from_source(source))
  assert_eq(
    experimental_markdown_ir_to_block(ir),
    Block::Document([
      Block::Paragraph([
        Inline::Link(
          [Inline::Text("http://example.test")],
          "http://example.test",
        ),
      ]),
    ]),
  )
  assert_eq(
    experimental_markdown_ir_canonical_format(
      @core.SourceId("typed-angle-canonical-fixture"),
      ir,
    ),
    source,
  )
  assert_eq(
    @debug.to_string(markdown_ir_identity_leaves(ir)),
    @debug.to_string([
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=0, end=source.length()),
        MarkdownSemanticKey::Paragraph,
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=1, end=source.length() - 1),
        MarkdownSemanticKey::LinkLabel,
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=1, end=source.length() - 1),
        MarkdownSemanticKey::LinkDestination("http://example.test"),
      ),
    ]),
  )
}
