///|
fn assert_html_block_incremental_projection_parity(
  label : String,
  source : String,
  edit : @core.Edit,
  updated : String,
  expected_html : String,
) -> Int raise {
  // Check CST and diagnostics before making any claim about reuse.
  let reuse_count = markdown_incremental_edit_reuse_count(
    label, source, edit, updated,
  )
  let incremental = @loom.new_parser(source, markdown_grammar)
  incremental.apply_edit(edit, updated)
  let fresh = @loom.new_parser(updated, markdown_grammar)
  let incremental_syntax = incremental.syntax_tree().read_or_abort()
  let fresh_syntax = fresh.syntax_tree().read_or_abort()
  let incremental_diagnostics = incremental.diagnostics().read_or_abort()
  let fresh_diagnostics = fresh.diagnostics().read_or_abort()
  let incremental_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    incremental_syntax, incremental_diagnostics,
  )
  let fresh_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    fresh_syntax, fresh_diagnostics,
  )
  assert_eq(incremental_ir, fresh_ir)
  let incremental_html = experimental_markdown_ir_to_commonmark_html(
    incremental_ir,
  )
  let fresh_html = experimental_markdown_ir_to_commonmark_html(fresh_ir)
  assert_eq(incremental_html, fresh_html)
  inspect(fresh_html, content=expected_html)
  reuse_count
}

///|
fn assert_html_closing_character_edit_falls_back(
  label : String,
  prefix : String,
  original : String,
  replacement : String,
  suffix : String,
) -> Unit raise {
  let source = prefix + original + suffix
  let updated = prefix + replacement + suffix
  let reuse_count = assert_html_block_incremental_projection_parity(
    label,
    source,
    @core.Edit::new(prefix.length(), original.length(), replacement.length()),
    updated,
    updated,
  )
  // A damaged terminator can extend the HTML block beyond the old splice range.
  inspect(reuse_count != 1, content="true")
}

///|
test "incremental HTML type-1 terminator edits fall back after projection parity" {
  let cases : Array[(String, String, String, String, String)] = [
    (
      "markdown pre closing angle edit falls back", "<pre>\nbody\n</pre", ">", "x",
      "\n\nTail\n",
    ),
    (
      "markdown script closing angle edit falls back", "<script>\nbody\n</script",
      ">", "x", "\n\nTail\n",
    ),
    (
      "markdown mixed-case style closing angle edit falls back", "<STYLE>\nbody\n</StYlE",
      ">", "x", "\n\nTail\n",
    ),
    (
      "markdown textarea closing angle edit falls back", "<textarea>\nbody\n</textarea",
      ">", "x", "\n\nTail\n",
    ),
    (
      "markdown script closing tag-name edit falls back", "<script>\nbody\n</scrip",
      "t", "x", ">\n\nTail\n",
    ),
  ]
  for case in cases {
    let (label, prefix, original, replacement, suffix) = case
    assert_html_closing_character_edit_falls_back(
      label, prefix, original, replacement, suffix,
    )
  }
}

///|
test "incremental HTML type-2 terminator edits fall back after projection parity" {
  let cases : Array[(String, String, String, String, String)] = [
    (
      "markdown comment terminator edit falls back", "<!--\nbody\n--", ">", "x",
      "\n\nTail\n",
    ),
    (
      "markdown processing-instruction terminator edit falls back", "<?pi\nbody\n?",
      ">", "x", "\n\nTail\n",
    ),
    (
      "markdown CDATA terminator edit falls back", "<![CDATA[\nbody\n]]", ">", "x",
      "\n\nTail\n",
    ),
    (
      "markdown declaration terminator edit falls back", "<!DOCTYPE html", ">", "x",
      "\n\nTail\n",
    ),
  ]
  for case in cases {
    let (label, prefix, original, replacement, suffix) = case
    assert_html_closing_character_edit_falls_back(
      label, prefix, original, replacement, suffix,
    )
  }
}
