///|
fn assert_markdown_ir_legacy_block_matches_direct_fold(
  source : String,
) -> Unit raise {
  let source_id = @core.SourceId("markdown-ir-legacy-block-test")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown parse failed for source: " + @debug.to_string(source))
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let direct = fold_markdown_syntax_with_source(syntax, source)
  let parsed = parse(source_id, source)
  let (parsed_markdown, parsed_diagnostics) = parse_markdown(source_id, source)
  assert_eq(parsed, direct)
  assert_eq(parsed_markdown, direct)
  assert_eq(parsed_diagnostics, diagnostics)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, syntax, diagnostics,
  )
  inspect(
    markdown_ir_to_block_with_source(ir, Some(source)),
    content=@debug.to_string(direct),
  )
}

///|
test "experimental MarkdownIR: legacy Block projection preserves block quotes" {
  assert_markdown_ir_legacy_block_matches_direct_fold("> quote\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("> bar\nbaz\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("> quote\r\n")
}

///|
test "experimental MarkdownIR: legacy Block projection preserves thematic breaks" {
  assert_markdown_ir_legacy_block_matches_direct_fold("---\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("  ---\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("---\r")
}

///|
test "experimental MarkdownIR: legacy Block projection preserves list-item text" {
  assert_markdown_ir_legacy_block_matches_direct_fold(
    "The number of windows is\n1.  The doors are 6.\n",
  )
  assert_markdown_ir_legacy_block_matches_direct_fold("- * * *\n")
}

///|
test "experimental MarkdownIR: legacy Block projection preserves source endings" {
  assert_markdown_ir_legacy_block_matches_direct_fold("a\nb")
  assert_markdown_ir_legacy_block_matches_direct_fold("a\r\nb\r\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("a\rb\r")
  assert_markdown_ir_legacy_block_matches_direct_fold(
    "```moonbit\r\nlet x = 1\r\n```\r\n",
  )
}

///|
test "experimental MarkdownIR: legacy Block projection preserves reference links" {
  assert_markdown_ir_legacy_block_matches_direct_fold(
    "[foo][bar]\n\n[bar]: /url\n",
  )
}

///|
test "experimental MarkdownIR: legacy Block projection preserves tab soft breaks" {
  assert_markdown_ir_legacy_block_matches_direct_fold("a\t\nb\n")
}

///|
test "experimental MarkdownIR: legacy Block projection preserves soft breaks and nested lists" {
  assert_markdown_ir_legacy_block_matches_direct_fold("a\nb\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("- outer\n  - inner\n")
  assert_markdown_ir_legacy_block_matches_direct_fold(
    "- outer\n\n  continuation\n",
  )
}

///|
test "experimental MarkdownIR: legacy Block projection preserves ordered markers and fenced indentation" {
  assert_markdown_ir_legacy_block_matches_direct_fold("3) item\n")
  assert_markdown_ir_legacy_block_matches_direct_fold(
    "- item\n\n  ```moonbit\n  let x = 1\n  ```\n",
  )
}

///|
test "experimental MarkdownIR: legacy Block projection preserves malformed links and escapes" {
  assert_markdown_ir_legacy_block_matches_direct_fold("[foo]\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("[foo][bar]\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("[[x]]\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("\\[foo]\n")
  assert_markdown_ir_legacy_block_matches_direct_fold(
    "[foo][ref[]\n\n[ref[]: /uri\n",
  )
  assert_markdown_ir_legacy_block_matches_direct_fold("[foo](\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("\\*a **b** c*\n")
}

///|
test "experimental MarkdownIR: legacy Block projection preserves image and raw link targets" {
  assert_markdown_ir_legacy_block_matches_direct_fold("![x](u)\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("foo![x](u)\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("foo\n![x](u)\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("foo  \n![x](u)\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("foo\nbar![x](u)\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("[x](/u \"t\")\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("[x](<u>)\n")
  assert_markdown_ir_legacy_block_matches_direct_fold("[x](  u  )\n")
}

///|
test "experimental MarkdownIR: legacy Block projection preserves recovered nodes" {
  assert_markdown_ir_legacy_block_matches_direct_fold("[unclosed\n")
}

///|
test "experimental MarkdownIR: public Block projection retains list paragraphs" {
  let source_id = @core.SourceId("markdown-ir-public-block-test")
  let source = "- first\n\n  second\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_block(ir),
    content="Document([UnorderedList([UnorderedListItem([" +
      "Text(\"first\"), Text(\"second\")])])])",
  )
}
