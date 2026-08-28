///|
/// Full-parse differential oracle for boundary-reparse investigation cases.
/// It checks source, CST/token coverage, diagnostics, compatibility AST, direct
/// MarkdownIR, and rendered semantic output. The returned count is one only
/// when the block-reparse fast path was admitted.
fn assert_block_boundary_reparse_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
) -> Int raise {
  let source_id = @core.SourceId("markdown-block-boundary-reparse")
  let incremental = @loom.new_parser(source_id, source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(source_id, updated, markdown_grammar)
  let incremental_source = incremental.source().read_or_abort()
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()

  assert_eq(incremental_source, updated)
  assert_eq(incremental_syntax.text(), updated)
  assert_eq(fresh_syntax.text(), updated)
  assert_eq(
    @core.tree_diff(incremental_syntax.cst_node(), fresh_syntax.cst_node()).is_empty(),
    true,
  )
  assert_eq(incremental_diagnostics, fresh_diagnostics)
  assert_eq(incremental.ast().read_or_abort(), fresh.ast().read_or_abort())

  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id, fresh_syntax, fresh_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  assert_eq(
    experimental_markdown_ir_to_commonmark_html(incremental_ir),
    experimental_markdown_ir_to_commonmark_html(fresh_ir),
  )
  let reuse_count = incremental.snapshot().read_or_abort().reuse_count
  ignore(label)
  reuse_count
}

///|
fn block_boundary_candidate_is_admitted(
  source : String,
  edit : @core.Edit,
  updated : String,
) -> Bool raise {
  let source_id = @core.SourceId("markdown-block-boundary-admission")
  let (old_cst, old_diagnostics) = try! parse_cst(source_id, source)
  @core.reparse_block(
    source_id,
    @seam.SyntaxNode::from_cst(old_cst),
    updated,
    edit,
    lex_for_grammar,
    markdown_spec,
    markdown_block_reparse_spec,
    old_diagnostics,
  )
  is Some(_)
}

///|
test "boundary reparse: paragraph exact-start replacement is admitted" {
  let prefix = "Prelude\n\n"
  let source = prefix + "Alpha beta\n\nTail\n"
  let updated = prefix + "Omega beta\n\nTail\n"
  let reuse_count = assert_block_boundary_reparse_parity(
    "paragraph exact-start same-length replacement",
    source,
    @core.Edit::replace(
      prefix.length(),
      prefix.length() + "Alpha".length(),
      prefix.length() + "Omega".length(),
    ),
    updated,
  )
  inspect(reuse_count, content="1")
}

///|
test "boundary reparse: adversarial exact-start prefix sweep preserves parity" {
  let probes : Array[(String, String)] = [
    ("A Heading\n\nTail\n", "# Heading\n\nTail\n"),
    ("A item\n\nTail\n", "- item\n\nTail\n"),
    ("A item\n\nTail\n", "* item\n\nTail\n"),
    ("A item\n\nTail\n", "+ item\n\nTail\n"),
    ("A quote\n\nTail\n", "> quote\n\nTail\n"),
    ("A``\ncode\n```\n", "```\ncode\n```\n"),
    ("A~~\ncode\n~~~\n", "~~~\ncode\n~~~\n"),
    ("Ascript>body</script>\n", "<script>body</script>\n"),
    ("A. item\n\nTail\n", "1. item\n\nTail\n"),
    ("A) item\n\nTail\n", "1) item\n\nTail\n"),
    ("Alabel]: /url\n\nTail\n", "[label]: /url\n\nTail\n"),
    ("A--\n\nTail\n", "---\n\nTail\n"),
    ("A**\n\nTail\n", "***\n\nTail\n"),
    ("A _ _\n\nTail\n", "_ _ _\n\nTail\n"),
    ("Alpha <tag\n\nTail\n", "Ωlpha <tag\n\nTail\n"),
    ("Alpha [broken\n\nTail\n", "文lpha [broken\n\nTail\n"),
  ]
  let mut admitted = 0
  let mut rejected = 0
  for probe in probes {
    let (old_source, updated) = probe
    let edit = @core.Edit::replace(0, 1, 1)
    if block_boundary_candidate_is_admitted(old_source, edit, updated) {
      admitted = admitted + 1
      ignore(
        assert_block_boundary_reparse_parity(
          "adversarial exact-start prefix", old_source, edit, updated,
        ),
      )
    } else {
      rejected = rejected + 1
    }
  }
  assert_true(admitted > 0)
  assert_true(rejected > 0)
}

///|
priv struct BlockBoundaryReparseCase {
  label : String
  source : String
  edit : @core.Edit
  updated : String
  admitted : Bool
}

///|
test "boundary reparse: accepted paragraph ownership matrix" {
  let lf_prefix = "Prelude\n\n"
  let crlf_prefix = "Prelude\r\n\r\n"
  let cr_prefix = "Prelude\r\r"
  let cases : Array[BlockBoundaryReparseCase] = [
    {
      label: "first-token interior insertion LF",
      source: lf_prefix + "Alpha beta\n\nTail\n",
      edit: @core.Edit::insert(lf_prefix.length() + 2, "X".length()),
      updated: lf_prefix + "AlXpha beta\n\nTail\n",
      admitted: true,
    },
    {
      label: "exact start length-changing replacement CRLF",
      source: crlf_prefix + "Alpha beta\r\n\r\nTail\r\n",
      edit: @core.Edit::replace(
        crlf_prefix.length(),
        crlf_prefix.length() + "Alpha".length(),
        crlf_prefix.length() + "A".length(),
      ),
      updated: crlf_prefix + "A beta\r\n\r\nTail\r\n",
      admitted: true,
    },
    {
      label: "exact start deletion CR",
      source: cr_prefix + "XAlpha beta\r\rTail\r",
      edit: @core.Edit::delete(cr_prefix.length(), cr_prefix.length() + 1),
      updated: cr_prefix + "Alpha beta\r\rTail\r",
      admitted: true,
    },
    {
      label: "exact start replacement at EOF",
      source: lf_prefix + "Alpha beta",
      edit: @core.Edit::replace(
        lf_prefix.length(),
        lf_prefix.length() + "Alpha".length(),
        lf_prefix.length() + "Omega".length(),
      ),
      updated: lf_prefix + "Omega beta",
      admitted: true,
    },
    {
      label: "exact start after adjacent ATX block",
      source: "# Head\nAlpha beta\n",
      edit: @core.Edit::replace(
        "# Head\n".length(),
        "# Head\nAlpha".length(),
        "# Head\nOmega".length(),
      ),
      updated: "# Head\nOmega beta\n",
      admitted: true,
    },
    {
      label: "exact paragraph-content start in list container",
      source: "- Alpha beta\n- Tail\n",
      edit: @core.Edit::replace(2, 7, 7),
      updated: "- Omega beta\n- Tail\n",
      admitted: true,
    },
    {
      label: "exact paragraph-content start in block quote",
      source: "> Alpha beta\n\nTail\n",
      edit: @core.Edit::replace(2, 7, 7),
      updated: "> Omega beta\n\nTail\n",
      admitted: true,
    },
    {
      label: "malformed paragraph exact start",
      source: "[broken](\n\nTail\n",
      edit: @core.Edit::replace(0, 1, 1),
      updated: "Xbroken](\n\nTail\n",
      admitted: true,
    },
    {
      label: "insertion immediately before LF terminator",
      source: "Alpha\n\nTail\n",
      edit: @core.Edit::insert("Alpha".length(), "!".length()),
      updated: "Alpha!\n\nTail\n",
      admitted: true,
    },
  ]
  for case in cases {
    ignore(
      assert_block_boundary_reparse_parity(
        case.label,
        case.source,
        case.edit,
        case.updated,
      ),
    )
    let admitted = block_boundary_candidate_is_admitted(
      case.source,
      case.edit,
      case.updated,
    )
    if admitted != case.admitted {
      println(
        case.label +
        ": expected admitted=" +
        case.admitted.to_string() +
        ", actual=" +
        admitted.to_string(),
      )
      abort("boundary matrix path mismatch")
    }
  }
}

///|
test "boundary reparse: ambiguous and ownership-changing matrix falls back" {
  let cases : Array[BlockBoundaryReparseCase] = [
    {
      label: "exact start insertion is shared with previous block",
      source: "Prelude\n\nAlpha\n",
      edit: @core.Edit::insert("Prelude\n\n".length(), "X".length()),
      updated: "Prelude\n\nXAlpha\n",
      admitted: false,
    },
    {
      label: "paragraph start becomes ATX marker",
      source: "Alpha\n\nTail\n",
      edit: @core.Edit::replace(0, 1, 1),
      updated: "#lpha\n\nTail\n",
      admitted: false,
    },
    {
      label: "newline insertion changes paragraph ownership",
      source: "Alpha beta\n\nTail\n",
      edit: @core.Edit::insert("Alpha".length(), "\n# heading".length()),
      updated: "Alpha\n# heading beta\n\nTail\n",
      admitted: false,
    },
    {
      label: "LF terminator removal reaches exact new block end",
      source: "Alpha\n\nTail\n",
      edit: @core.Edit::delete("Alpha".length(), "Alpha\n".length()),
      updated: "Alpha\nTail\n",
      admitted: false,
    },
    {
      label: "CRLF terminator replacement reaches exact new block end",
      source: "Alpha\r\n\r\nTail\r\n",
      edit: @core.Edit::replace(
        "Alpha".length(),
        "Alpha\r\n".length(),
        "Alpha\n".length(),
      ),
      updated: "Alpha\n\r\nTail\r\n",
      admitted: false,
    },
    {
      label: "insertion immediately after terminator",
      source: "Alpha\n\nTail\n",
      edit: @core.Edit::insert("Alpha\n".length(), "X".length()),
      updated: "Alpha\nX\nTail\n",
      admitted: false,
    },
    {
      label: "EOF insertion at block end",
      source: "Alpha",
      edit: @core.Edit::insert("Alpha".length(), " beta".length()),
      updated: "Alpha beta",
      admitted: false,
    },
    {
      label: "ATX heading exact start",
      source: "# Alpha\n\nTail\n",
      edit: @core.Edit::replace(0, 1, 2),
      updated: "## Alpha\n\nTail\n",
      admitted: false,
    },
    {
      label: "Setext heading exact start",
      source: "Alpha\n---\n\nTail\n",
      edit: @core.Edit::replace(0, "Alpha".length(), "Omega".length()),
      updated: "Omega\n---\n\nTail\n",
      admitted: false,
    },
    {
      label: "list item marker exact start",
      source: "- Alpha\n- Tail\n",
      edit: @core.Edit::replace(0, 1, 1),
      updated: "+ Alpha\n- Tail\n",
      admitted: false,
    },
    {
      label: "block quote marker exact start",
      source: "> Alpha\n\nTail\n",
      edit: @core.Edit::delete(0, 2),
      updated: "Alpha\n\nTail\n",
      admitted: false,
    },
    {
      label: "fenced code exact start",
      source: "```\ncode\n```\n\nTail\n",
      edit: @core.Edit::insert(0, "`".length()),
      updated: "````\ncode\n```\n\nTail\n",
      admitted: false,
    },
    {
      label: "indented code exact start",
      source: "    code\n\nTail\n",
      edit: @core.Edit::delete(0, 1),
      updated: "   code\n\nTail\n",
      admitted: false,
    },
    {
      label: "thematic break marker edit",
      source: "---\n\nTail\n",
      edit: @core.Edit::replace(0, 1, 1),
      updated: "*--\n\nTail\n",
      admitted: false,
    },
    {
      label: "exact-start deletion empties old paragraph",
      source: "Alpha\n\nTail\n",
      edit: @core.Edit::delete(0, "Alpha".length()),
      updated: "\n\nTail\n",
      admitted: false,
    },
    {
      label: "newly created empty block has no old owner",
      source: "Alpha\n",
      edit: @core.Edit::insert("Alpha\n".length(), "\n".length()),
      updated: "Alpha\n\n",
      admitted: false,
    },
  ]
  for case in cases {
    ignore(
      assert_block_boundary_reparse_parity(
        case.label,
        case.source,
        case.edit,
        case.updated,
      ),
    )
    let admitted = block_boundary_candidate_is_admitted(
      case.source,
      case.edit,
      case.updated,
    )
    if admitted != case.admitted {
      println(
        case.label +
        ": expected admitted=" +
        case.admitted.to_string() +
        ", actual=" +
        admitted.to_string(),
      )
      abort("boundary matrix path mismatch")
    }
  }
}

///|
test "boundary reparse: unaffected following sibling stays structurally shared" {
  let source_id = @core.SourceId("markdown-block-boundary-sibling-reuse")
  let prefix = "Prelude\n\n"
  let source = prefix + "Alpha beta\n\nTail\n"
  let updated = prefix + "Omega beta\n\nTail\n"
  let parser = @loom.new_parser(source_id, source, markdown_grammar)
  let before = parser.syntax_tree().read_or_abort()
  let old_tail = before.find_at(source.length() - "Tail\n".length())
  parser.apply_edit(
    @core.Edit::replace(
      prefix.length(),
      prefix.length() + "Alpha".length(),
      prefix.length() + "Omega".length(),
    ),
    updated,
  )
  let after = parser.syntax_tree().read_or_abort()
  let new_tail = after.find_at(updated.length() - "Tail\n".length())
  assert_true(physical_equal(old_tail.cst_node(), new_tail.cst_node()))
}
