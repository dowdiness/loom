// Differential scenarios for the throwaway LocalRawBlock prototype.

///|
fn local_raw_block_prototype_syntax(
  source_id : @core.SourceId,
  source : String,
) -> @seam.SyntaxNode {
  let (cst, _) = parse_cst(source_id, source) catch {
    _ => abort("LocalRawBlock prototype source failed to parse")
  }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn assert_local_raw_block_prototype_matches(
  label : String,
  source : String,
) -> Unit {
  let source_id = @core.SourceId("markdown-local-raw-block-prototype:" + label)
  let syntax = local_raw_block_prototype_syntax(source_id, source)
  let expected = experimental_markdown_ir_from_syntax(source_id, syntax)
  let actual = prototype_markdown_ir_from_syntax(source_id, syntax)
  guard actual == expected else {
    abort(
      "LocalRawBlock prototype mismatch for " +
      label +
      "\nexpected: " +
      @debug.to_string(expected) +
      "\nactual: " +
      @debug.to_string(actual),
    )
  }
}

///|
test "LocalRawBlock prototype: independent blocks and prepend preserve exact IR" {
  let source =
    #|Paragraph zero with *emphasis*.
    #|
    #|Paragraph one with **strong text** and `code`.
    #|
  assert_local_raw_block_prototype_matches("independent", source)
  assert_local_raw_block_prototype_matches(
    "prepend",
    "# Prepended heading\n\n" + source,
  )
}

///|
test "LocalRawBlock prototype: inline links and images preserve local origins" {
  assert_local_raw_block_prototype_matches(
    "inline-links",
    (
      #|Before [link](/destination "title") and ![image](/image.png).
      #|
      #|<https://example.com> and <user@example.com>
      #|
    ),
  )
}

///|
test "LocalRawBlock prototype: references retain document-owned target origins" {
  let source =
    #|[target]: /destination "title"
    #|
    #|Use [target], [full][target], [collapsed][], and ![image][target].
    #|
    #|[collapsed]: /collapsed
    #|
  assert_local_raw_block_prototype_matches("references", source)
  assert_local_raw_block_prototype_matches(
    "references-after-prepend",
    "# Prefix\n\n" + source,
  )
  assert_local_raw_block_prototype_matches(
    "references-after-definition-change",
    source.replace(
      old="/destination \"title\"".view(),
      new="/updated \"next\"".view(),
    ),
  )
}

///|
test "LocalRawBlock prototype: identical blocks may share relative semantics" {
  let repeated = "Same *content* and [inline](/target).\n\n"
  assert_local_raw_block_prototype_matches(
    "duplicate-blocks",
    repeated + repeated + repeated,
  )
  assert_local_raw_block_prototype_matches(
    "duplicate-blocks-after-prepend",
    "# Prefix\n\n" + repeated + repeated + repeated,
  )
}

///|
test "LocalRawBlock prototype: containers and code preserve exact IR" {
  assert_local_raw_block_prototype_matches(
    "containers",
    (
      #|> Quote with *emphasis*.
      #|>
      #|> - nested item
      #|
      #|1. ordered item
      #|2. second item
      #|
      #|```moonbit
      #|let answer = 42
      #|```
      #|
      #|<div>
      #|html
      #|</div>
      #|
    ),
  )
}
