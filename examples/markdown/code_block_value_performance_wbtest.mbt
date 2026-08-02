///|
fn collect_code_block_nodes(
  node : @seam.SyntaxNode,
  code_blocks : Array[@seam.SyntaxNode],
) -> Unit {
  if node.kind() == CodeBlockNode.to_raw() {
    code_blocks.push(node)
  }
  for child in node.children() {
    collect_code_block_nodes(child, code_blocks)
  }
}

///|
fn code_block_value_test_syntax(source : String) -> @seam.SyntaxNode {
  let (cst, diagnostics) = try! parse_cst(
    @core.SourceId("markdown-code-block-value-performance"),
    source,
  )
  guard diagnostics.is_empty() else {
    abort("code-block performance fixture must parse without diagnostics")
  }
  @seam.SyntaxNode::from_cst(cst)
}

///|
test "code block value: fenced corpus performs zero source reconstructions" {
  let source = StringBuilder::StringBuilder()
  for i = 0; i < 128; i = i + 1 {
    source.write_string("```moonbit\n")
    source.write_string("fn item_\{i}() -> Int { \{i} }\n")
    source.write_string("```\n")
  }
  let syntax = code_block_value_test_syntax(source.to_string())
  let code_blocks : Array[@seam.SyntaxNode] = []
  collect_code_block_nodes(syntax, code_blocks)
  let mut source_reconstructions = 0
  for code_block in code_blocks {
    let value = code_block_value_with_source_loader(code_block, fn() {
      source_reconstructions = source_reconstructions + 1
      syntax.text()
    })
    assert_true(value.has_prefix("fn item_"))
  }
  assert_eq(code_blocks.length(), 128)
  assert_eq(source_reconstructions, 0)
}

///|
test "code block value: source-aware top-level fold preserves indented blocks" {
  let source = "    first\n\nparagraph\n\n    second\n"
  let syntax = code_block_value_test_syntax(source)
  assert_eq(
    fold_markdown_syntax_with_source(syntax, source),
    Block::Document([
      Block::CodeBlock("", "first"),
      Block::Paragraph([Inline::Text("paragraph")]),
      Block::CodeBlock("", "second"),
    ]),
  )
}

///|
test "code block value: compatibility loader is demand-driven" {
  let source = "    code\n"
  let syntax = code_block_value_test_syntax(source)
  let code_blocks : Array[@seam.SyntaxNode] = []
  collect_code_block_nodes(syntax, code_blocks)
  let mut source_reconstructions = 0
  let value = code_block_value_with_source_loader(code_blocks[0], fn() {
    source_reconstructions = source_reconstructions + 1
    source
  })
  assert_eq(value, "code")
  assert_eq(source_reconstructions, 1)
}
