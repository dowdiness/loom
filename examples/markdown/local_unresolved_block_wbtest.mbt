///|
fn local_unresolved_test_syntax(
  source_id : @core.SourceId,
  source : String,
) -> (@seam.SyntaxNode, @core.DiagnosticSet) {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("Markdown local unresolved block parse failed")
  }
  (@seam.SyntaxNode::from_cst(cst), diagnostics)
}

///|
fn first_local_unresolved_test_block(
  syntax : @seam.SyntaxNode,
) -> @seam.SyntaxNode {
  let root = syntax_root(syntax)
  for child in root.children() {
    let kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    if kind is HeadingNode || kind is ParagraphNode {
      return child
    }
  }
  abort("Markdown local unresolved block fixture has no flow block")
}

///|
fn is_local_unresolved_flow_block(node : @seam.SyntaxNode) -> Bool {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    HeadingNode
    | ParagraphNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode
    | ErrorNode => true
    _ => false
  }
}

///|
fn assert_local_unresolved_blocks_match_direct(source : String) -> Unit raise {
  let source_id = @core.SourceId("markdown-local-unresolved-differential")
  let (syntax, diagnostics) = local_unresolved_test_syntax(source_id, source)
  guard diagnostics.length() == 0 else {
    abort("valid local unresolved block differential produced diagnostics")
  }
  let root = syntax_root(syntax)
  let definitions = collect_link_reference_definitions(root)
  let expected = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, syntax, diagnostics,
  ).children()
  let actual : Array[MarkdownIR] = []
  for block in root.children() {
    if is_local_unresolved_flow_block(block) {
      let plan = lower_local_unresolved_block(source_id, block.cst_node())
      let locally_resolved = resolve_local_block(plan, label => {
        definitions.lookup(label)
      })
      let resolved = if resolved_local_block_requires_context(locally_resolved) {
        resolve_local_block(
          lower_contextual_local_block(
            source_id,
            block,
            root.text(),
            label => definitions.lookup(label),
            origin => diagnostics_in_origin(source_id, diagnostics, origin),
          ),
          label => definitions.lookup(label),
        )
      } else {
        locally_resolved
      }
      actual.push(place_resolved_local_block(resolved, block.start()))
    }
  }
  assert_eq(actual, expected)
}

///|
test "local unresolved block: shortcut reference resolves after local lowering" {
  let source_id = @core.SourceId("markdown-local-unresolved-shortcut")
  let source = "[target]: /docs \"Docs\"\n\nRead [target].\n"
  let (syntax, diagnostics) = local_unresolved_test_syntax(source_id, source)
  guard diagnostics.length() == 0 else {
    abort("valid local unresolved block fixture produced diagnostics")
  }
  let root = syntax_root(syntax)
  let block = first_local_unresolved_test_block(syntax)
  let definitions = collect_link_reference_definitions(root)
  let plan = lower_local_unresolved_block(source_id, block.cst_node())
  let resolved = resolve_local_block(plan, label => definitions.lookup(label))
  let actual = place_resolved_local_block(resolved, block.start())
  let expected = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id, syntax, diagnostics,
    ).children()[0]
  assert_eq(actual, expected)
}

///|
test "local unresolved block: reference forms and image match direct lowering" {
  assert_local_unresolved_blocks_match_direct(
    "[full][target] [collapsed][] [shortcut] ![image][target]\n\n" +
    "[target]: /target \"Target\"\n" +
    "[collapsed]: /collapsed\n" +
    "[shortcut]: /shortcut\n",
  )
}

///|
test "local unresolved block: nested link and image precedence matches direct lowering" {
  let fixtures = [
    "[foo **bar *[baz][ref]* qux**][ref]\n\n[ref]: /uri\n", "![foo ![bar](/url)](/url2)\n",
    "![foo [bar](/url)](/url2)\n", "![[foo]]\n\n[[foo]]: /url \"title\"\n",
  ]
  for source in fixtures {
    assert_local_unresolved_blocks_match_direct(source)
  }
}

///|
test "local unresolved block: one plan supports unresolved and resolved transitions" {
  let source_id = @core.SourceId("markdown-local-unresolved-transition")
  let block_source = "[target] and ![image][target]\n"
  let defined_source = block_source + "\n[target]: /after \"After\"\n"
  let (unresolved_syntax, unresolved_diagnostics) = local_unresolved_test_syntax(
    source_id, block_source,
  )
  let (defined_syntax, defined_diagnostics) = local_unresolved_test_syntax(
    source_id, defined_source,
  )
  let block = first_local_unresolved_test_block(unresolved_syntax)
  let plan = lower_local_unresolved_block(source_id, block.cst_node())
  let unresolved = place_resolved_local_block(
    resolve_local_block(plan, _ => None),
    0,
  )
  let definitions = collect_link_reference_definitions(defined_syntax)
  let resolved = place_resolved_local_block(
    resolve_local_block(plan, label => definitions.lookup(label)),
    0,
  )
  let expected_unresolved = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id, unresolved_syntax, unresolved_diagnostics,
    ).children()[0]
  let expected_resolved = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id, defined_syntax, defined_diagnostics,
    ).children()[0]
  assert_eq(unresolved, expected_unresolved)
  assert_eq(resolved, expected_resolved)
}

///|
test "local unresolved block: placement preserves local and definition origin owners" {
  assert_local_unresolved_blocks_match_direct(
    "[ref]: /definition \"Definition\"\n\n" +
    "> [inline](/local \"Local\") and [reference][ref]\n\n" +
    "- ![image][ref]\n" +
    "- `code` and **strong**\n",
  )
}

///|
test "local unresolved block: unresolved and bounded labels match direct lowering" {
  let accepted = "a".repeat(999)
  let rejected = "b".repeat(1000)
  let fixtures = [
    "[missing] [missing][] [text][missing] ![image][missing]\n",
    "[] [] []\n\n[]: /empty\n",
    "\\[escaped][target] and [target]\\[literal]\n\n[target]: /url\n",
    "[" + accepted + "]\n\n[" + accepted + "]: /accepted\n",
    "[" + rejected + "]\n\n[" + rejected + "]: /rejected\n",
  ]
  for source in fixtures {
    assert_local_unresolved_blocks_match_direct(source)
  }
}

///|
test "local unresolved block: malformed block takes exact contextual fallback" {
  let source_id = @core.SourceId("markdown-local-unresolved-contextual")
  let source = "# prefix\n\n[unclosed\n"
  let (syntax, _) = local_unresolved_test_syntax(source_id, source)
  let diagnostics = @core.DiagnosticSet::single(
    @core.lexer_diagnostic_at(
      source_id, "synthetic local recovery diagnostic", 10, 11, "synthetic-local-recovery",
    ),
  )
  let root = syntax_root(syntax)
  let block = root.children().last().unwrap()
  let definitions = collect_link_reference_definitions(root)
  let local_result = resolve_local_block(
    lower_local_unresolved_block(source_id, block.cst_node()),
    label => definitions.lookup(label),
  )
  assert_true(resolved_local_block_requires_context(local_result))
  let plan = lower_contextual_local_block(
    source_id,
    block,
    root.text(),
    label => definitions.lookup(label),
    origin => diagnostics_in_origin(source_id, diagnostics, origin),
  )
  let actual = place_resolved_local_block(
    resolve_local_block(plan, label => definitions.lookup(label)),
    block.start(),
  )
  let expected = experimental_markdown_ir_from_syntax_with_diagnostics(
      source_id, syntax, diagnostics,
    )
    .children()
    .last()
    .unwrap()
  assert_eq(actual, expected)
}

///|
test "local unresolved block: normalized duplicate definitions keep first value" {
  assert_local_unresolved_blocks_match_direct(
    "[A  B] [a b][] [A B][a b]\n\n" +
    "[A B]: /first \"First\"\n" +
    "[a  b]: /second \"Second\"\n",
  )
}

///|
test "local unresolved block: equal structural blocks share one relative plan" {
  let source_id = @core.SourceId("markdown-local-unresolved-duplicates")
  let source = "same [ref]\n\nsame [ref]\n\n[ref]: /url\n"
  let (syntax, diagnostics) = local_unresolved_test_syntax(source_id, source)
  let root = syntax_root(syntax)
  let definitions = collect_link_reference_definitions(root)
  let blocks : Array[@seam.SyntaxNode] = []
  for child in root.children() {
    let kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    if kind is ParagraphNode {
      blocks.push(child)
    }
  }
  guard blocks.length() == 2 else { abort("expected duplicate paragraphs") }
  let first_plan = lower_local_unresolved_block(source_id, blocks[0].cst_node())
  let second_plan = lower_local_unresolved_block(
    source_id,
    blocks[1].cst_node(),
  )
  assert_true(first_plan == second_plan)
  let expected = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, syntax, diagnostics,
  ).children()
  let first = place_resolved_local_block(
    resolve_local_block(first_plan, label => definitions.lookup(label)),
    blocks[0].start(),
  )
  let second = place_resolved_local_block(
    resolve_local_block(second_plan, label => definitions.lookup(label)),
    blocks[1].start(),
  )
  assert_eq([first, second], expected)
}

///|
test "local unresolved block: position shifts and block families match direct lowering" {
  let fixtures = [
    "# heading [ref]\n\n[ref]: /url\n", "prep\n\n# heading [ref]\n\n[ref]: /url\n",
    "> quote [ref]\n\n- list [ref]\n\n[ref]: /url\n", "```mbt\nlet x = 1\n```\n\n<div>html</div>\n\n---\n",
    "before marker\n\nafter [ref]\n\n[ref]: /url\n", "before Marker\n\nafter [ref]\n\n[ref]: /url\n",
  ]
  for source in fixtures {
    assert_local_unresolved_blocks_match_direct(source)
  }
}
