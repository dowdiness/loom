///|
fn reference_definition_ir_from_source(source : String) -> MarkdownIR {
  let source_id = @core.SourceId("markdown-reference-definition-basic")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown reference-definition parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn reference_definition_syntax_from_source(source : String) -> @seam.SyntaxNode {
  let source_id = @core.SourceId("markdown-reference-definition-table")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown reference-definition syntax parse failed")
  }
  guard diagnostics.length() == 0 else {
    abort("reference-definition syntax unexpectedly produced diagnostics")
  }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn reference_definition_node_texts(source : String) -> Array[String] {
  let texts : Array[String] = []
  fn walk(node : @seam.SyntaxNode) -> Unit {
    let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
    if kind is LinkReferenceDefinitionNode {
      texts.push(node.text())
    }
    for child in node.children() {
      walk(child)
    }
  }
  walk(reference_definition_syntax_from_source(source))
  texts
}

///|
fn reference_definition_equality_fixture(
  normalized_label? : String = "foo",
  destination_value? : String = "/url",
  title_value? : String? = Some("title"),
  definition_origin? : MarkdownIROrigin = MarkdownIROrigin(start=0, end=20),
  label_value_origin? : MarkdownIROrigin = MarkdownIROrigin(start=1, end=4),
  destination_value_origin? : MarkdownIROrigin = MarkdownIROrigin(
    start=7,
    end=11,
  ),
  title_value_origin? : MarkdownIROrigin? = Some(
    MarkdownIROrigin(start=12, end=19),
  ),
) -> LinkReferenceDefinition {
  {
    normalized_label,
    destination_value,
    title_value,
    definition_origin,
    label_value_origin,
    destination_value_origin,
    title_value_origin,
  }
}

///|
test "reference definition: complete block is omitted from semantic flow" {
  let ir = reference_definition_ir_from_source("[foo]: /url\n")
  inspect(ir.kind_tag(), content="Document")
  assert_eq(ir.children().length(), 0)
  let mdast = experimental_markdown_ir_to_mdast_json(ir).stringify()
  assert_true(mdast.contains("\"type\":\"root\",\"children\":[]"))
  assert_false(mdast.contains("definition"))
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => inspect(html, content="")
    Err(_) => fail("valid reference definition must render as empty flow")
  }
}

///|
test "reference definition: typed CST is lossless and keeps duplicates" {
  let source = "[foo]: /first\n[FOO]: /second\n"
  debug_inspect(
    reference_definition_node_texts(source),
    content="[\"[foo]: /first\\n\", \"[FOO]: /second\\n\"]",
  )
  assert_eq(
    collect_link_reference_definitions(
      reference_definition_syntax_from_source(source),
    ).length(),
    1,
  )
}

///|
test "reference definition: quoted title remains part of the definition block" {
  let ir = reference_definition_ir_from_source("[foo]: /url \"title\"\n")
  assert_eq(ir.children().length(), 0)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => inspect(html, content="")
    Err(_) => fail("reference definition with title must render as empty flow")
  }
}

///|
test "reference definition: destination may continue on the next line" {
  let ir = reference_definition_ir_from_source("[foo]:\n/url\n")
  assert_eq(ir.children().length(), 0)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => inspect(html, content="")
    Err(_) => fail("multiline reference definition must render as empty flow")
  }
}

///|
test "reference definition table normalizes labels and keeps the first definition" {
  let root = reference_definition_syntax_from_source(
    "[FOO]: /first \"one\"\n[foo]: /second\n",
  )
  let table = collect_link_reference_definitions(root)
  assert_eq(table.length(), 1)
  match table.lookup("foo") {
    Some(definition) => {
      inspect(definition.destination_value, content="/first")
      assert_eq(definition.title_value, Some("one"))
      assert_eq(definition.label_value_origin, MarkdownIROrigin(start=1, end=4))
      assert_eq(
        definition.destination_value_origin,
        MarkdownIROrigin(start=7, end=13),
      )
      assert_eq(
        definition.title_value_origin,
        Some(MarkdownIROrigin(start=15, end=18)),
      )
      assert_eq(definition.definition_origin, MarkdownIROrigin(start=0, end=20))
    }
    None => fail("normalized first definition must be collected")
  }
}

///|
test "reference definition equality contains values and every owned origin" {
  let base = reference_definition_equality_fixture()
  assert_false(
    base == reference_definition_equality_fixture(normalized_label="bar"),
  )
  assert_false(
    base == reference_definition_equality_fixture(destination_value="/alt"),
  )
  assert_false(
    base == reference_definition_equality_fixture(title_value=Some("other")),
  )
  assert_false(
    base ==
    reference_definition_equality_fixture(
      definition_origin=MarkdownIROrigin(start=0, end=21),
    ),
  )
  assert_false(
    base ==
    reference_definition_equality_fixture(
      label_value_origin=MarkdownIROrigin(start=2, end=4),
    ),
  )
  assert_false(
    base ==
    reference_definition_equality_fixture(
      destination_value_origin=MarkdownIROrigin(start=8, end=11),
    ),
  )
  assert_false(
    base ==
    reference_definition_equality_fixture(
      title_value_origin=Some(MarkdownIROrigin(start=13, end=19)),
    ),
  )
}

///|
test "reference definition table equality ignores map construction order" {
  let definitions = collect_link_reference_definitions(
    reference_definition_syntax_from_source("[a]: /a\n[b]: /b\n"),
  )
  let a = definitions.lookup("a").unwrap()
  let b = definitions.lookup("b").unwrap()
  let left = LinkReferenceDefinitionTable::empty()
    .insert_first(a)
    .insert_first(b)
  let right = LinkReferenceDefinitionTable::empty()
    .insert_first(b)
    .insert_first(a)
  assert_true(left == right)
}

///|
test "reference definition table equality ignores normalized duplicates after the first" {
  let left = collect_link_reference_definitions(
    reference_definition_syntax_from_source("[FOO]: /first\n[foo]: /ignored\n"),
  )
  let right = collect_link_reference_definitions(
    reference_definition_syntax_from_source("[foo]: /first\n[FOO]: /another\n"),
  )
  assert_true(left == right)
}

///|
test "reference definition table normalizes raw labels without decoding escapes" {
  let root = reference_definition_syntax_from_source(
    "[foo\\!]: /escaped\n[foo!]: /plain\n",
  )
  let table = collect_link_reference_definitions(root)
  assert_eq(table.length(), 2)
  match table.lookup("foo\\!") {
    Some(definition) =>
      inspect(definition.destination_value, content="/escaped")
    None => fail("escaped raw label must retain a distinct normalized key")
  }
  match table.lookup("foo!") {
    Some(definition) => inspect(definition.destination_value, content="/plain")
    None => fail("plain raw label must retain a distinct normalized key")
  }
}

///|
test "reference definition: label may span nonblank lines" {
  let ir = reference_definition_ir_from_source("[\nfoo\n]: /url\nbar\n")
  assert_eq(ir.children().length(), 1)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => inspect(html, content="<p>bar</p>\n")
    Err(_) => fail("multiline-label definition must leave following flow")
  }
}

///|
test "reference definition: angle destination may be empty" {
  let ir = reference_definition_ir_from_source("[foo]: <>\n")
  assert_eq(ir.children().length(), 0)
  let table = collect_link_reference_definitions(
    reference_definition_syntax_from_source("[foo]: <>\n"),
  )
  match table.lookup("foo") {
    Some(definition) => {
      inspect(definition.destination_value, content="")
      assert_eq(
        definition.destination_value_origin,
        MarkdownIROrigin(start=8, end=8),
      )
    }
    None => fail("empty angle destination must be collected")
  }
}

///|
test "reference definition: block quote definition is collected but not rendered" {
  let source = "> [foo]: /url\n"
  let ir = reference_definition_ir_from_source(source)
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      ir,
      Passthrough,
    ) {
    Ok(html) => inspect(html, content="<blockquote>\n</blockquote>\n")
    Err(_) => fail("block quote definition must leave an empty container")
  }
  let table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(source),
  )
  assert_eq(table.length(), 1)
}

///|
test "reference definition: list-contained definitions enter the document table" {
  let direct = "- [foo]: /direct\n"
  let continuation = "- item\n\n  [bar]: /continuation\n"
  debug_inspect(
    reference_definition_node_texts(direct),
    content="[\"[foo]: /direct\\n\"]",
  )
  debug_inspect(
    reference_definition_node_texts(continuation),
    content="[\"  [bar]: /continuation\\n\"]",
  )
  let direct_table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(direct),
  )
  let continuation_table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(continuation),
  )
  match direct_table.lookup("foo") {
    Some(definition) => inspect(definition.destination_value, content="/direct")
    None => fail("direct list definition must be collected")
  }
  match continuation_table.lookup("bar") {
    Some(definition) =>
      inspect(definition.destination_value, content="/continuation")
    None => fail("continued list definition must be collected")
  }
}

///|
test "reference definition: cannot interrupt a list-item paragraph" {
  let source = "- text\n  [foo]: /url\n"
  debug_inspect(reference_definition_node_texts(source), content="[]")
  assert_eq(
    collect_link_reference_definitions(
      reference_definition_syntax_from_source(source),
    ).length(),
    0,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(source),
    ),
    content="<ul>\n<li>text\n[foo]: /url</li>\n</ul>\n",
  )
}

///|
test "reference definition: list continuation does not create an empty flow item" {
  let source = "- a\n- b\n\n  [ref]: /url\n- d\n"
  let ir = reference_definition_ir_from_source(source)
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n",
  )
  let table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(source),
  )
  match table.lookup("ref") {
    Some(definition) => inspect(definition.destination_value, content="/url")
    None => fail("CommonMark example 317 definition must be collected")
  }
}

///|
test "reference definition classifier follows CommonMark valid boundaries" {
  let valid = [
    "[foo]: /url \"title\"\n", "   [foo]: \n      /url  \n           'the title'  \n",
    "[Foo*bar\\]]:my_(url) 'title (with parens)'\n", "[Foo bar]:\n<my url>\n'title'\n",
    "[foo]: /url '\ntitle\nline1\nline2\n'\n", "[foo]:\n/url\n", "[foo]: <>\n", "[foo]: /url\\bar\\*baz \"foo\\\"bar\\baz\"\n",
    "[foo]: /url (a\\(b\\))\n", "[\nfoo\n]: /url\n",
  ]
  for source in valid {
    guard classify_link_reference_definition(source) is Some(definition) &&
      definition.end == source.length() else {
      fail("expected valid reference definition: " + @debug.to_string(source))
    }
  }
}

///|
test "reference definition classifier rejects malformed boundaries" {
  let invalid = [
    "[foo]:\n", "[foo]: <bar>(baz)\n", "[foo]: /url \"title\" ok\n", "    [foo]: /url \"title\"\n",
    "[]: /url\n", "[   ]: /url\n", "[foo]: /url 'title\n\nwith blank line'\n", "[foo]: /url)\n",
    "[foo]: <a\\\nb>\n", "[foo\\\n\nbar]: /url\n", "[foo]: /url 'title\\\n\nblank'\n",
    "[foo]: /u\u{000B}rl\n", "\t[foo]: /url\n", "[foo]: /url (a(b)\n",
  ]
  for source in invalid {
    guard classify_link_reference_definition(source) is None else {
      fail("expected invalid reference definition: " + @debug.to_string(source))
    }
  }
}

///|
test "reference definition: malformed candidate remains paragraph CST" {
  let source = "[foo]: /url \"title\" ok\n"
  debug_inspect(reference_definition_node_texts(source), content="[]")
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(source),
    ),
    content="<p>[foo]: /url &quot;title&quot; ok</p>\n",
  )
}

///|
test "reference definition: unescaped nested parenthesized title remains paragraph" {
  let source = "[foo]: /url (a(b)\n"
  debug_inspect(reference_definition_node_texts(source), content="[]")
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(source),
    ),
    content="<p>[foo]: /url (a(b)</p>\n",
  )
}

///|
test "reference definition: CommonMark 201 invalid angle destination remains diagnostic-free paragraph" {
  let source = "[foo]: <bar>(baz)\n\n[foo]\n"
  let source_id = @core.SourceId("markdown-reference-definition-commonmark-201")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("CommonMark 201 parse failed")
  }
  assert_true(diagnostics.is_empty())
  let syntax = @seam.SyntaxNode::from_cst(cst)
  debug_inspect(reference_definition_node_texts(source), content="[]")
  match syntax.children() {
    [paragraph, ..] => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(paragraph.kind())
      assert_eq(kind, ParagraphNode)
      for element in paragraph.all_children() {
        match element {
          @seam.SyntaxElement::Token(token) => {
            let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(
              token.kind(),
            )
            assert_true(token_kind is TextToken || token_kind is NewlineToken)
          }
          _ =>
            fail("CommonMark 201 literal paragraph must contain direct tokens")
        }
      }
    }
    _ => fail("CommonMark 201 must begin with a paragraph")
  }
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, syntax, diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content="<p>[foo]: &lt;bar&gt;(baz)</p>\n<p>[foo]</p>\n",
  )
}

///|
test "reference definition: malformed angle literal detection stays line-local" {
  assert_true(
    scan_link_reference_definition("[   ]: <bar>(baz)\n")
    is InvalidAngleDestinationLiteral,
  )
  assert_true(
    scan_link_reference_definition("[foo]:\n<bar>(baz)\n")
    is NoReferenceDefinition,
  )
}

///|
test "reference definition: escaped angle and punctuation remain inside angle destinations" {
  let escaped_angle = "[foo]: <bar\\>baz>\n\n[foo]\n"
  let angle_table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(escaped_angle),
  )
  match angle_table.lookup("foo") {
    Some(definition) => inspect(definition.destination_value, content="bar>baz")
    None => fail("escaped closing angle must remain inside the destination")
  }
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(escaped_angle),
    ),
    content="<p><a href=\"bar%3Ebaz\">foo</a></p>\n",
  )
  let escaped_punctuation = "[foo]: <bar\\*baz>\n\n[foo]\n"
  let punctuation_table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(escaped_punctuation),
  )
  match punctuation_table.lookup("foo") {
    Some(definition) => inspect(definition.destination_value, content="bar*baz")
    None => fail("escaped punctuation must remain a valid angle destination")
  }
}

///|
test "reference definition: malformed angle candidate keeps lazy paragraph continuation" {
  let source = "[foo]: <bar>(baz)\ncontinued\n"
  let syntax = reference_definition_syntax_from_source(source)
  debug_inspect(reference_definition_node_texts(source), content="[]")
  match syntax.children() {
    [paragraph] => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(paragraph.kind())
      assert_eq(kind, ParagraphNode)
      inspect(paragraph.text(), content=source)
    }
    _ => fail("malformed candidate continuation must remain one paragraph")
  }
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(source),
    ),
    content="<p>[foo]: &lt;bar&gt;(baz)\ncontinued</p>\n",
  )
}

///|
test "reference definition: CommonMark 211 indented candidate remains code" {
  let source = "    [foo]: /url \"title\"\n\n[foo]\n"
  let source_id = @core.SourceId("markdown-reference-definition-commonmark-211")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("CommonMark 211 parse failed")
  }
  assert_true(diagnostics.is_empty())
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      experimental_markdown_ir_from_syntax_with_diagnostics(
        source_id,
        @seam.SyntaxNode::from_cst(cst),
        diagnostics,
      ),
    ),
    content="<pre><code>[foo]: /url &quot;title&quot;\n</code></pre>\n<p>[foo]</p>\n",
  )
}

///|
test "reference definition: CommonMark 195 multiline title remains semantic" {
  let source = "[Foo bar]:\n<my url>\n'title'\n\n[Foo bar]\n"
  let source_id = @core.SourceId("markdown-reference-definition-commonmark-195")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("CommonMark 195 parse failed")
  }
  assert_true(diagnostics.is_empty())
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      experimental_markdown_ir_from_syntax_with_diagnostics(
        source_id,
        @seam.SyntaxNode::from_cst(cst),
        diagnostics,
      ),
    ),
    content="<p><a href=\"my%20url\" title=\"title\">Foo bar</a></p>\n",
  )
}

///|
test "reference definition: cannot interrupt a paragraph" {
  let source = "Foo\n[bar]: /baz\n\n[bar]\n"
  debug_inspect(reference_definition_node_texts(source), content="[]")
  assert_eq(
    collect_link_reference_definitions(
      reference_definition_syntax_from_source(source),
    ).length(),
    0,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(source),
    ),
    content="<p>Foo\n[bar]: /baz</p>\n<p>[bar]</p>\n",
  )
}

///|
test "reference definition: invalid next-line title does not extend the block" {
  let source = "[foo]: /url\n\"title\" ok\n"
  debug_inspect(
    reference_definition_node_texts(source),
    content="[\"[foo]: /url\\n\"]",
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(
      reference_definition_ir_from_source(source),
    ),
    content="<p>&quot;title&quot; ok</p>\n",
  )
}

///|
test "reference definition: label length boundary is 999 characters" {
  let valid = "[" + "a".repeat(999) + "]: /url\n"
  let invalid = "[" + "a".repeat(1000) + "]: /url\n"
  guard classify_link_reference_definition(valid) is Some(_) else {
    fail("999-character label must be accepted")
  }
  guard classify_link_reference_definition(invalid) is None else {
    fail("1000-character label must be rejected")
  }
}

///|
test "reference definition: label length counts Unicode characters" {
  let valid = "[" + "😈".repeat(999) + "]: /url\n"
  let invalid = "[" + "😈".repeat(1000) + "]: /url\n"
  guard classify_link_reference_definition(valid) is Some(_) else {
    fail("999 non-BMP characters must be accepted")
  }
  guard classify_link_reference_definition(invalid) is None else {
    fail("1000 non-BMP characters must be rejected")
  }
}

///|
test "reference definition: bare destination parentheses are balanced and bounded" {
  let depth32 = "/url" + "(".repeat(32) + "x" + ")".repeat(32)
  let depth33 = "/url" + "(".repeat(33) + "x" + ")".repeat(33)
  guard classify_link_reference_definition("[foo]: " + depth32 + "\n")
    is Some(_) else {
    fail("32 nested destination parentheses must be accepted")
  }
  guard classify_link_reference_definition("[foo]: " + depth33 + "\n") is None else {
    fail("33 nested destination parentheses must be rejected")
  }
}

///|
test "reference definition table uses Unicode lowercase and collapsed whitespace" {
  let source = "[ΑΓΩ]: /greek\n[Foo\n bar]: /spaced\n"
  let table = collect_link_reference_definitions(
    reference_definition_syntax_from_source(source),
  )
  match table.lookup("αγω") {
    Some(definition) => inspect(definition.destination_value, content="/greek")
    None => fail("Greek label must normalize to lowercase")
  }
  match table.lookup("foo bar") {
    Some(definition) => inspect(definition.destination_value, content="/spaced")
    None => fail("multiline label whitespace must collapse")
  }
}
