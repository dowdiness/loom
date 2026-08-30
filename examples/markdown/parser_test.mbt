///|
fn heading_form_token_kinds(source : String) -> String {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  let kinds : Array[String] = []
  fn walk(node : @seam.SyntaxNode) -> Unit {
    let node_kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
    if node_kind is HeadingNode {
      let atx_kind : SyntaxKind = AtxHeadingMarkerToken
      let setext_kind : SyntaxKind = SetextHeadingUnderlineToken
      match node.direct_token_of_kind(atx_kind.to_raw()) {
        Some(_) => kinds.push(@debug.to_string(atx_kind))
        None => ()
      }
      match node.direct_token_of_kind(setext_kind.to_raw()) {
        Some(_) => kinds.push(@debug.to_string(setext_kind))
        None => ()
      }
    }
    for child in node.children() {
      walk(child)
    }
  }
  walk(@seam.SyntaxNode::from_cst(cst))
  kinds.join(",")
}

///|
fn inline_node_texts_of_kind(
  source : String,
  expected_kind : SyntaxKind,
) -> Array[String] {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  let texts : Array[String] = []
  fn walk(node : @seam.SyntaxNode) -> Unit {
    let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
    if kind == expected_kind {
      texts.push(node.text())
    }
    for child in node.children() {
      walk(child)
    }
  }
  walk(@seam.SyntaxNode::from_cst(cst))
  texts
}

///|
fn markdown_leaf_kind_signature(source : String) -> Array[String] {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  let signature : Array[String] = []
  fn walk(node : @seam.SyntaxNode) -> Unit {
    for element in node.direct_elements_iter() {
      match element {
        @seam.SyntaxElement::Node(child) => walk(child)
        @seam.SyntaxElement::Token(token) => {
          let kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
          signature.push(
            @debug.to_string(kind) + ":" + @debug.to_string(token.text()),
          )
        }
      }
    }
  }
  walk(@seam.SyntaxNode::from_cst(cst))
  signature
}

///|
test "parse cst: production autolinks use typed angle nodes" {
  debug_inspect(
    inline_node_texts_of_kind("<http://foo.bar.baz>\n", UriAutolinkNode),
    content="[\"<http://foo.bar.baz>\"]",
  )
  debug_inspect(
    inline_node_texts_of_kind("<foo@bar.example.com>\n", EmailAutolinkNode),
    content="[\"<foo@bar.example.com>\"]",
  )
}

///|
test "parse cst: underscore delimiter run emits italic node" {
  debug_inspect(
    inline_node_texts_of_kind("_italic_\n", ItalicNode),
    content="[\"_italic_\"]",
  )
}

///|
test "parse cst: non-CommonMark whitespace does not enable punctuation flanking" {
  for ch in ['\u{000B}', '\u{0085}', '\u{2028}', '\u{2029}'] {
    let source = "a" + ch.to_string() + "*!x*\n"
    debug_inspect(inline_node_texts_of_kind(source, ItalicNode), content="[]")
  }
  let form_feed = "a\u{000C}*!x*\n"
  debug_inspect(
    inline_node_texts_of_kind(form_feed, ItalicNode),
    content="[\"*!x*\"]",
  )
}

///|
test "parse cst: delimiter link scopes stay balanced across soft lines" {
  let slash = "\\"
  let source = slash +
    "* literal *unclosed\n[" +
    slash +
    "*literal*](/) " +
    slash +
    "*a " +
    slash +
    "*b***\n\n"
  let (cst, diagnostics) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  inspect(@seam.SyntaxNode::from_cst(cst).text(), content=source)
  inspect(diagnostics.is_empty(), content="true")
}

///|
test "parse cst: unconfirmed links cannot corrupt delimiter cursor stack" {
  let cases : Array[(String, SyntaxKind, String)] = [
    ("*[x*\n", ItalicNode, "*[x*"),
    ("**[x**\n", BoldNode, "**[x**"),
    ("_[x_\n", ItalicNode, "_[x_"),
  ]
  for case in cases {
    let (source, kind, expected) = case
    debug_inspect(
      inline_node_texts_of_kind(source, kind),
      content="[\"" + expected + "\"]",
    )
  }
}

///|
test "parse cst: CommonMark 512 uses the indexed nested-label closer" {
  debug_inspect(
    inline_node_texts_of_kind("[link [foo [bar]]](/uri)\n", LinkNode),
    content="[\"[link [foo [bar]]](/uri)\"]",
  )
}

///|
test "parse cst: indexed link labels preserve soft line continuations" {
  debug_inspect(
    inline_node_texts_of_kind("[link\ntext](target)\n", LinkNode),
    content="[\"[link\\ntext](target)\"]",
  )
  let emphasized = "[a *b\nc*](u)\n"
  debug_inspect(
    inline_node_texts_of_kind(emphasized, LinkNode),
    content="[\"[a *b\\nc*](u)\"]",
  )
  debug_inspect(
    inline_node_texts_of_kind(emphasized, ItalicNode),
    content="[\"*b\\nc*\"]",
  )
}

///|
test "parse cst: backticks do not hide unbalanced destination parentheses" {
  let source = "[x](`(`)\n"
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  inspect(@seam.SyntaxNode::from_cst(cst).text(), content=source)
  debug_inspect(inline_node_texts_of_kind(source, LinkNode), content="[]")

  let followed_by_emphasis = "[x](`(`)*a*)*b*\n"
  let (followed_cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    followed_by_emphasis,
  )
  inspect(
    @seam.SyntaxNode::from_cst(followed_cst).text(),
    content=followed_by_emphasis,
  )
  debug_inspect(
    inline_node_texts_of_kind(followed_by_emphasis, ItalicNode),
    content="[\"*b*\"]",
  )
}

///|
test "parse cst: heading forms have distinct marker token kinds" {
  let cases : Array[(String, String)] = [
    ("# Plain\n", "AtxHeadingMarkerToken"),
    ("Plain\n---\n", "SetextHeadingUnderlineToken"),
    ("   # Indented\n", "AtxHeadingMarkerToken"),
    ("   Indented\n   ---\n", "SetextHeadingUnderlineToken"),
    ("> # Quoted\n", "AtxHeadingMarkerToken"),
    ("> Quoted\n> ---\n", "SetextHeadingUnderlineToken"),
    ("- item\n  # Listed\n", "AtxHeadingMarkerToken"),
    ("- Listed\n  ---\n", "SetextHeadingUnderlineToken"),
  ]
  for case in cases {
    let (source, expected) = case
    inspect(heading_form_token_kinds(source), content=expected)
  }
}

///|
test "syntax kind: heading marker raw kinds remain stable and distinct" {
  let atx_kind : SyntaxKind = AtxHeadingMarkerToken
  let setext_kind : SyntaxKind = SetextHeadingUnderlineToken
  inspect(atx_kind.to_raw().0, content="0")
  inspect(setext_kind.to_raw().0, content="38")
  let atx : SyntaxKind = @seam.FromRawKind::from_raw(@seam.RawKind(0))
  let setext : SyntaxKind = @seam.FromRawKind::from_raw(@seam.RawKind(38))
  inspect(atx, content="AtxHeadingMarkerToken")
  inspect(setext, content="SetextHeadingUnderlineToken")
}

///|
test "syntax kind: emphasis CST shape uses append-only raw kinds" {
  let star : SyntaxKind = StarToken
  let star_star : SyntaxKind = StarStarToken
  let underscore : SyntaxKind = UnderscoreToken
  let delimiter : SyntaxKind = EmphasisDelimiterToken
  inspect(star.to_raw().0, content="5")
  inspect(star_star.to_raw().0, content="6")
  inspect(underscore.to_raw().0, content="39")
  inspect(delimiter.to_raw().0, content="40")
  inspect(SyntaxKind::from_raw(@seam.RawKind(39)), content="UnderscoreToken")
  inspect(
    SyntaxKind::from_raw(@seam.RawKind(40)),
    content="EmphasisDelimiterToken",
  )
  inspect(
    markdown_leaf_kind_signature("**bold**\n").join("|"),
    content="EmphasisDelimiterToken:\"*\"|EmphasisDelimiterToken:\"*\"|TextToken:\"bold\"|EmphasisDelimiterToken:\"*\"|EmphasisDelimiterToken:\"*\"|NewlineToken:\"\\n\"",
  )
  inspect(
    markdown_leaf_kind_signature("_italic_\n").join("|"),
    content="EmphasisDelimiterToken:\"_\"|TextToken:\"italic\"|EmphasisDelimiterToken:\"_\"|NewlineToken:\"\\n\"",
  )
}

///|
test "parse: heading" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "# Hello\n",
  )
  inspect(block, content="Document([Heading(1, [Text(\"Hello\")])])")
}

///|
test "parse: ATX heading keeps unmatched emphasis literal at line ending" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "# *foo\nbar*\n",
    ),
    content="Document([Heading(1, [Text(\"*foo\")]), Paragraph([Text(\"bar*\")])])",
  )
}

///|
test "parse: setext heading preserves legacy heading depth" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "Foo\n---\n",
    ),
    content="Document([Heading(2, [Text(\"Foo\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "Foo\n- \n",
    ),
    content="Document([Heading(2, [Text(\"Foo\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "Foo\n-  \n",
    ),
    content="Document([Heading(2, [Text(\"Foo\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "First\nsecond\n---\n",
    ),
    content="Document([Heading(2, [Text(\"First\"), Text(\"second\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "First\nsecond\n===\n",
    ),
    content="Document([Heading(1, [Text(\"First\"), Text(\"second\")])])",
  )
}

///|
test "parse: setext underline bounds literal unmatched emphasis" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "Foo *bar\n====\nbaz*\n",
    ),
    content="Document([Heading(1, [Text(\"Foo *bar\")]), Paragraph([Text(\"baz*\")])])",
  )
}

///|
test "parse: setext continuation bounds literal unmatched emphasis" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "Foo\nbar *baz\n====\nqux*\n",
    ),
    content=(
      #|Document(
      #|  [
      #|    Heading(1, [Text("Foo"), Text("bar *baz")]),
      #|    Paragraph([Text("qux*")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: ordered list item setext probe stops at ordered item boundary" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "1. Foo\n2. bar\n---\n",
    ),
    content=(
      #|Document(
      #|  [
      #|    OrderedList(
      #|      [
      #|        OrderedListItem([Text("Foo")], Some({ start: 1, delimiter: Period })),
      #|        OrderedListItem([Text("bar")], Some({ start: 2, delimiter: Period })),
      #|      ],
      #|      Some({ start: 1, delimiter: Period }),
      #|    ),
      #|    Paragraph([Text("---")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: paragraph" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "Hello world\n",
  )
  inspect(block, content="Document([Paragraph([Text(\"Hello world\")])])")
}

///|
test "parse: three-space-prefixed fence is code block" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "   ```\ncode\n   ```\n",
    ),
    content="Document([CodeBlock(\"\", \"code\")])",
  )
}

///|
test "parse: tilde fence is code block" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "~~~moonbit\nlet x = 1\n~~~\n",
    ),
    content="Document([CodeBlock(\"moonbit\", \"let x = 1\")])",
  )
}

///|
test "parse: tilde fence retains backticks in info string" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "~~~`moonbit\nlet x = 1\n~~~\n",
    ),
    content="Document([CodeBlock(\"`moonbit\", \"let x = 1\")])",
  )
}

///|
test "parse: indented fence interrupts root paragraph" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "foo\n  ```\ncode\n```\n",
    ),
    content="Document([Paragraph([Text(\"foo\")]), CodeBlock(\"\", \"code\")])",
  )
}

///|
test "parse: prefixed non-one ordered marker remains paragraph" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "foo\n  2. bar\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [paragraph] => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(paragraph.kind())
      inspect(kind, content="ParagraphNode")
    }
    _ => inspect(syntax.children().length(), content="one paragraph")
  }
}

///|
test "parse: prefixed lone list marker preserves setext heading" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "foo\n  -\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [heading] => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(heading.kind())
      inspect(kind, content="HeadingNode")
    }
    _ => inspect(syntax.children().length(), content="one heading")
  }
}

///|
test "parse: three-space-prefixed quote is block quote" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "   > quote\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      inspect(kind, content="BlockQuoteNode")
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: indented blockquote heading remains quoted CST child" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    ">   # heading\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [heading] => {
          let heading_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            heading.kind(),
          )
          inspect(heading_kind, content="HeadingNode")
        }
        _ => inspect(quote.children().length(), content="one heading")
      }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: indented blockquote fence remains quoted CST child" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    ">   ```\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [code] => {
          let code_kind : SyntaxKind = @seam.FromRawKind::from_raw(code.kind())
          inspect(code_kind, content="CodeBlockNode")
        }
        _ => inspect(quote.children().length(), content="one code block")
      }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: indented blockquote HTML remains quoted CST child" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    ">   <div>\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [html] => {
          let html_kind : SyntaxKind = @seam.FromRawKind::from_raw(html.kind())
          inspect(html_kind, content="HtmlBlockNode")
        }
        _ => inspect(quote.children().length(), content="one HTML block")
      }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: blockquote indented continuation remains one paragraph" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> item\n>     code\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [paragraph] => {
          let kind : SyntaxKind = @seam.FromRawKind::from_raw(paragraph.kind())
          inspect(kind, content="ParagraphNode")
        }
        _ => inspect(quote.children().length(), content="one paragraph")
      }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: blank-line blockquote indented code remains quoted child" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> item\n>\n>     code\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let mut has_code = false
      for child in quote.children() {
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
        if kind is CodeBlockNode {
          has_code = true
        }
      }
      inspect(has_code, content="true")
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: blockquote preserves legacy text projection" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "> quote\n",
  )
  inspect(block, content="Document([Paragraph([Text(\"> quote\")])])")
}

///|
test "parse: blockquote lazy continuation stays in quoted paragraph CST" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> bar\nbaz\n> foo\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      inspect(quote_kind, content="BlockQuoteNode")
      match quote.children() {
        [paragraph] => {
          let paragraph_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            paragraph.kind(),
          )
          inspect(paragraph_kind, content="ParagraphNode")
        }
        _ => inspect(quote.children().length(), content="one paragraph")
      }
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: blockquote lazy continuation preserves legacy text projection" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "> bar\nbaz\n",
  )
  inspect(block, content="Document([Paragraph([Text(\"> bar\\nbaz\")])])")
}

///|
test "parse: blockquote lazy continuation rejects thematic break line" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> foo\n---\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote, separator] => {
      let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      let separator_kind : SyntaxKind = @seam.FromRawKind::from_raw(
        separator.kind(),
      )
      inspect(quote_kind, content="BlockQuoteNode")
      inspect(separator_kind, content="ThematicBreakNode")
    }
    _ =>
      inspect(syntax.children().length(), content="blockquote then separator")
  }
}

///|
test "parse: thematic break preserves legacy text projection" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "---\n",
  )
  inspect(block, content="Document([Paragraph([Text(\"---\")])])")
}

///|
test "parse: list-item thematic break after marker is CST block child" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "- Foo\n- * * *\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [_, item] =>
          match item.children() {
            [separator] => {
              let separator_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                separator.kind(),
              )
              inspect(separator_kind, content="ThematicBreakNode")
            }
            _ => inspect(item.children().length(), content="one thematic break")
          }
        _ => inspect(list.children().length(), content="two list items")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
fn assert_list_item_prefixed_block_child(
  source : String,
  expected_kind : SyntaxKind,
) -> Unit raise {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [item] => {
          let mut found = false
          for child in item.children() {
            let kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
            if kind == expected_kind {
              found = true
            }
          }
          inspect(found, content="true")
        }
        _ => inspect(list.children().length(), content="one list item")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: list-item indented quote remains list child" {
  try! assert_list_item_prefixed_block_child(
    "- item\n  > quote\n",
    BlockQuoteNode,
  )
}

///|
test "parse: list-item indented fence remains list child" {
  try! assert_list_item_prefixed_block_child("- item\n  ```\n", CodeBlockNode)
}

///|
test "parse: list-item indented continuation remains paragraph" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "- item\n      code\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [item] => {
          inspect(item.text(), content="- item\n      code")
          inspect(item.children().length(), content="0")
        }
        _ => inspect(list.children().length(), content="one list item")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: blank-line list-item indented quote remains list child" {
  try! assert_list_item_prefixed_block_child(
    "- item\n\n  > quote\n",
    BlockQuoteNode,
  )
}

///|
test "parse: blank-line empty quote does not create phantom list paragraph" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "- item\n\n  >\n\n  body\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list, ..] =>
      match list.children() {
        [item, ..] => inspect(item.children().length(), content="0")
        _ => inspect(list.children().length(), content="one list item")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: blank-line list-item indented fence remains list child" {
  try! assert_list_item_prefixed_block_child("- item\n\n  ```\n", CodeBlockNode)
}

///|
test "parse: list-item blank-line indented code remains list child" {
  try! assert_list_item_prefixed_block_child(
    "- item\n\n      code\n",
    CodeBlockNode,
  )
}

///|
test "parse: list-item indented HTML remains list child" {
  try! assert_list_item_prefixed_block_child("- item\n  <div>\n", HtmlBlockNode)
}

///|
test "parse: list-item thematic break preserves legacy text projection" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- * * *\n",
  )
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"* * *\")])])])",
  )
}

///|
test "parse: empty list item does not promote indented underline to setext heading" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "- \n  ---\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list, ..] =>
      match list.children() {
        [item] => {
          for child in item.children() {
            let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(
              child.kind(),
            )
            if child_kind is HeadingNode {
              fail("empty list item must not contain a setext heading")
            }
          }
          inspect(item.children().length(), content="0")
        }
        _ => inspect(list.children().length(), content="one list item")
      }
    _ =>
      inspect(syntax.children().length(), content="list plus following block")
  }
}

///|
test "parse: list setext code span owns continuation indentation structurally" {
  let (cst, _) = parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "- x `a\n  b`\n  ---\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [item] =>
          match item.children() {
            [heading] => {
              let kind : SyntaxKind = @seam.FromRawKind::from_raw(
                heading.kind(),
              )
              inspect(kind, content="HeadingNode")
              let mut saw_structural_indentation = false
              for element in heading.all_children() {
                match element {
                  @seam.SyntaxElement::Node(inline) => {
                    let inline_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                      inline.kind(),
                    )
                    if inline_kind is InlineCodeNode {
                      for element in inline.all_children() {
                        match element {
                          @seam.SyntaxElement::Token(token) => {
                            let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                              token.kind(),
                            )
                            if token_kind is IndentationToken {
                              saw_structural_indentation = true
                            }
                          }
                          _ => ()
                        }
                      }
                    }
                  }
                  _ => ()
                }
              }
              inspect(saw_structural_indentation, content="true")
            }
            _ => inspect(item.children().length(), content="one heading")
          }
        _ => inspect(list.children().length(), content="one list item")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: blockquote lazy continuation accepts indented thematic text" {
  for source in ["> foo\n    ---\n", "> foo\n\t---\n"] {
    let (cst, _) = try! parse_cst(
      @core.SourceId("markdown-parser-test-document"),
      source,
    )
    let syntax = @seam.SyntaxNode::from_cst(cst)
    match syntax.children() {
      [quote] => {
        let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
        inspect(quote_kind, content="BlockQuoteNode")
        match quote.children() {
          [paragraph] => {
            let paragraph_kind : SyntaxKind = @seam.FromRawKind::from_raw(
              paragraph.kind(),
            )
            inspect(paragraph_kind, content="ParagraphNode")
          }
          _ => inspect(quote.children().length(), content="one paragraph")
        }
      }
      _ => inspect(syntax.children().length(), content="one blockquote")
    }
  }
}

///|
test "parse: blockquote setext heading has heading CST child" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> foo\n> ---\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] => {
      let quote_kind : SyntaxKind = @seam.FromRawKind::from_raw(quote.kind())
      inspect(quote_kind, content="BlockQuoteNode")
      match quote.children() {
        [heading] => {
          let heading_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            heading.kind(),
          )
          inspect(heading_kind, content="HeadingNode")
        }
        _ => inspect(quote.children().length(), content="one heading")
      }
    }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: quoted setext heading code span crosses soft-line continuation" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> ``a\n> b``\n> ---\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [heading] =>
          match heading.children() {
            [inline_code] => {
              let kind : SyntaxKind = @seam.FromRawKind::from_raw(
                inline_code.kind(),
              )
              inspect(kind, content="InlineCodeNode")
              inspect(inline_code.text(), content="``a\n> b``")
            }
            _ => inspect(heading.children().length(), content="one inline code")
          }
        _ => inspect(quote.children().length(), content="one heading")
      }
    _ => inspect(syntax.children().length(), content="one blockquote")
  }
}

///|
test "parse: multi-line paragraph" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "line one\nline two\n\n",
  )
  inspect(
    block,
    content="Document([Paragraph([Text(\"line one\"), Text(\" \"), Text(\"line two\")])])",
  )
}

///|
test "parse: multi-line paragraph unparse keeps soft break" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "line one\nline two\n\n",
  )
  inspect(@core.Renderable::unparse(block), content="line one line two")
}

///|
test "parse: code block" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "```python\nx = 1\n```\n",
  )
  inspect(block, content="Document([CodeBlock(\"python\", \"x = 1\")])")
}

///|
test "parse: list" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- one\n- two\n",
  )
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"one\")]), UnorderedListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: nested list stays editor-compatible" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- parent\n  - child\n",
  )
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"parent\")])])])",
  )
}

///|
fn assert_nested_list_cst_shape(
  source : String,
  top_level_item_count : Int,
  nested_item_count : Int,
) -> Unit raise {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    source,
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] => {
      let list_kind : SyntaxKind = @seam.FromRawKind::from_raw(list.kind())
      inspect(list_kind, content="UnorderedListNode")
      inspect(
        list.children().length(),
        content=top_level_item_count.to_string(),
      )
      match list.children() {
        [item, ..] => {
          let item_kind : SyntaxKind = @seam.FromRawKind::from_raw(item.kind())
          inspect(item_kind, content="ListItemNode")
          match item.children() {
            [nested] => {
              let nested_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                nested.kind(),
              )
              inspect(nested_kind, content="UnorderedListNode")
              inspect(
                nested.children().length(),
                content=nested_item_count.to_string(),
              )
            }
            _ => inspect(item.children().length(), content="one nested list")
          }
        }
        _ => inspect(list.children().length(), content="at least one item")
      }
    }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: nested list has nested CST container" {
  try! assert_nested_list_cst_shape("- parent\n  - child\n", 1, 1)
}

///|
test "parse: multi-item nested list stays in one CST container" {
  try! assert_nested_list_cst_shape("- a\n  - b\n  - c\n", 1, 2)
}

///|
test "parse: outdented marker resumes top-level list after nested CST container" {
  try! assert_nested_list_cst_shape("- a\n  - b\n- c\n", 2, 1)
}

///|
test "parse: indented non-one ordered marker starts nested ordered CST container" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "- a\n  2. b\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [list] =>
      match list.children() {
        [item] =>
          match item.children() {
            [nested] => {
              let nested_kind : SyntaxKind = @seam.FromRawKind::from_raw(
                nested.kind(),
              )
              inspect(nested_kind, content="OrderedListNode")
            }
            _ => inspect(item.children().length(), content="one nested list")
          }
        _ => inspect(list.children().length(), content="one item")
      }
    _ => inspect(syntax.children().length(), content="one list")
  }
}

///|
test "parse: loose list separated by blank line" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- one\n\n- two\n",
  )
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"one\")]), UnorderedListItem([Text(\"two\")])])])",
  )
}

///|
test "parse: list item lazy continuation stays in item" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- a\nb\n",
  )
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"a\"), Text(\"\\n\"), Text(\"b\")])])])",
  )
}

///|
test "parse: non-one ordered marker lazy continuation stays in item" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- a\n2. b\n",
  )
  inspect(
    block,
    content="Document([UnorderedList([UnorderedListItem([Text(\"a\"), Text(\"\\n\"), Text(\"2. \"), Text(\"b\")])])])",
  )
}

///|
test "parse: empty list item does not start lazy continuation paragraph" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "- \nfoo\n",
    ),
    content="Document([UnorderedList([UnorderedListItem([])]), Paragraph([Text(\"foo\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "-   \nfoo\n",
    ),
    content="Document([UnorderedList([UnorderedListItem([])]), Paragraph([Text(\"foo\")])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "- \n2. foo\n",
    ),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([UnorderedListItem([])]),
      #|    OrderedList(
      #|      [OrderedListItem([Text("foo")], Some({ start: 2, delimiter: Period }))],
      #|      Some({ start: 2, delimiter: Period }),
      #|    ),
      #|  ],
      #|)
    ),
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "-   \n2. foo\n",
    ),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([UnorderedListItem([])]),
      #|    OrderedList(
      #|      [OrderedListItem([Text("foo")], Some({ start: 2, delimiter: Period }))],
      #|      Some({ start: 2, delimiter: Period }),
      #|    ),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: list item preserves whitespace-only inline syntax" {
  inspect(
    parse_block_ast(@core.SourceId("markdown-parser-test-document"), "- ` `\n"),
    content="Document([UnorderedList([UnorderedListItem([InlineCode(\" \")])])])",
  )
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "- [](/)\n",
    ),
    content="Document([UnorderedList([UnorderedListItem([Link([], \"/\")])])])",
  )
}

///|
test "parse: blank-line-separated marker change starts a new list" {
  let same = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- one\n\n- two\n",
  )
  inspect(
    same,
    content="Document([UnorderedList([UnorderedListItem([Text(\"one\")]), UnorderedListItem([Text(\"two\")])])])",
  )
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "- one\n\n+ two\n",
  )
  match block {
    Document(
      [
        UnorderedList([UnorderedListItem([Text("one")])]),
        UnorderedList([UnorderedListItem([Text("two")])]),
      ]
    ) => inspect(true, content="true")
    _ => inspect(block, content="two separate lists")
  }
}

///|
test "parse: ordered list delimiter change starts a new editor-compatible list" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "1. one\n2. two\n3) three\n",
  )
  match block {
    Document(
      [
        OrderedList(
          [
            OrderedListItem([Text("one")], Some(first_item_marker)),
            OrderedListItem([Text("two")], Some(second_item_marker)),
          ],
          Some(first_list_marker)
        ),
        OrderedList(
          [OrderedListItem([Text("three")], Some(third_item_marker))],
          Some(second_list_marker)
        ),
      ]
    ) => {
      inspect(first_list_marker.text(), content="1.")
      inspect(first_item_marker.text(), content="1.")
      inspect(second_item_marker.text(), content="2.")
      inspect(second_list_marker.text(), content="3)")
      inspect(third_item_marker.text(), content="3)")
    }
    _ => inspect(block, content="ordered delimiter boundary")
  }
}

///|
test "parse: non-one ordered marker does not interrupt paragraph" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "The number of windows is\n14.  The doors are 6.\n",
  )
  match block {
    Document(
      [
        Paragraph(
          [
            Text("The number of windows is"),
            Text(" "),
            Text("14. "),
            Text(" The doors are 6."),
          ]
        ),
      ]
    ) => inspect(true, content="true")
    _ => inspect(block, content="single paragraph")
  }
}

///|
test "parse: one-start ordered marker interrupts paragraph" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "The number of windows is\n1.  The doors are 6.\n",
  )
  match block {
    Document(
      [
        Paragraph(_),
        OrderedList(
          [OrderedListItem([Text(" The doors are 6.")], Some(item_marker))],
          Some(list_marker)
        ),
      ]
    ) => {
      inspect(list_marker.text(), content="1.")
      inspect(item_marker.text(), content="1.")
    }
    _ => inspect(block, content="paragraph then ordered list")
  }
}

///|
test "parse: ordered list unparse preserves start and delimiter" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "3) three\n4) four\n",
  )
  inspect(@core.Renderable::unparse(block), content="3) three\n4) four")
}

///|
test "parse: mixed document" {
  let block = parse_block_ast(
    @core.SourceId("markdown-parser-test-document"),
    "# Title\n\nSome text\n\n- item\n",
  )
  match block {
    Document(blocks) => inspect(blocks.length(), content="3")
    _ => inspect(false, content="true")
  }
}

///|
test "parse: code span owns equal-length delimiters and unequal raw interior" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "`a``b`\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [paragraph] =>
      match paragraph.children() {
        [inline_code] => {
          let kind : SyntaxKind = @seam.FromRawKind::from_raw(
            inline_code.kind(),
          )
          inspect(kind, content="InlineCodeNode")
          inspect(inline_code.text(), content="`a``b`")
        }
        _ =>
          inspect(paragraph.children().length(), content="one inline code node")
      }
    _ => inspect(syntax.children().length(), content="one paragraph")
  }
}

///|
test "parse: code span crosses a paragraph soft-line continuation" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "`code\nmore`\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [paragraph] =>
      match paragraph.children() {
        [inline_code] => {
          let kind : SyntaxKind = @seam.FromRawKind::from_raw(
            inline_code.kind(),
          )
          inspect(kind, content="InlineCodeNode")
          inspect(inline_code.text(), content="`code\nmore`")
        }
        _ =>
          inspect(paragraph.children().length(), content="one inline code node")
      }
    _ => inspect(syntax.children().length(), content="one paragraph")
  }
}

///|
test "parse: blank line does not supply a code-span closer" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "`open\n\nclose`\n",
    ),
    content=(
      #|Document(
      #|  [
      #|    Paragraph([Text("`"), Text("open")]),
      #|    Paragraph([Text("close"), Text("`")]),
      #|  ],
      #|)
    ),
  )
}

///|
test "parse: code span crosses a block quote soft-line continuation" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> `code\n> more`\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [paragraph] =>
          match paragraph.children() {
            [inline_code] => {
              let kind : SyntaxKind = @seam.FromRawKind::from_raw(
                inline_code.kind(),
              )
              inspect(kind, content="InlineCodeNode")
              inspect(inline_code.text(), content="`code\n> more`")
            }
            _ =>
              inspect(paragraph.children().length(), content="one inline code")
          }
        _ => inspect(quote.children().length(), content="one quote paragraph")
      }
    _ => inspect(syntax.children().length(), content="one block quote")
  }
}

///|
test "parse: nested emphasis uses block quote code-span continuation" {
  let (cst, _) = try! parse_cst(
    @core.SourceId("markdown-parser-test-document"),
    "> *`code\n> more`*\n",
  )
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [paragraph] =>
          match paragraph.children() {
            [italic] =>
              match italic.children() {
                [inline_code] => {
                  let kind : SyntaxKind = @seam.FromRawKind::from_raw(
                    inline_code.kind(),
                  )
                  inspect(kind, content="InlineCodeNode")
                  inspect(inline_code.text(), content="`code\n> more`")
                }
                _ =>
                  inspect(italic.children().length(), content="one code node")
              }
            _ =>
              inspect(paragraph.children().length(), content="one italic node")
          }
        _ => inspect(quote.children().length(), content="one quote paragraph")
      }
    _ => inspect(syntax.children().length(), content="one block quote")
  }
}

///|
test "parse: ATX heading uses maximal code-span runs" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "# ``a`b``\n",
    ),
    content="Document([Heading(1, [InlineCode(\"a`b\")])])",
  )
}

///|
test "parse: setext heading uses maximal code-span runs" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "``a`b``\n---\n",
    ),
    content="Document([Heading(2, [InlineCode(\"a`b\")])])",
  )
}

///|
test "parse: setext heading code span crosses soft-line continuation" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "``a\nb``\n---\n",
    ),
    content="Document([Heading(2, [InlineCode(\"a b\")])])",
  )
}

///|
test "parse: code span crosses a list item lazy continuation" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "- `code\nmore`\n",
    ),
    content="Document([UnorderedList([UnorderedListItem([InlineCode(\"code more\")])])])",
  )
}

///|
test "parse: code span does not cross a list-item paragraph boundary" {
  inspect(
    parse_block_ast(
      @core.SourceId("markdown-parser-test-document"),
      "- `open\n\n`close\n",
    ),
    content=(
      #|Document(
      #|  [
      #|    UnorderedList([UnorderedListItem([Text("`"), Text("open")])]),
      #|    Paragraph([Text("`"), Text("close")]),
      #|  ],
      #|)
    ),
  )
}
