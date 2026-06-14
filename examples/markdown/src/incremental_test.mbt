///|
fn assert_markdown_incremental_edit_matches_full_parse(
  label : String,
  source : String,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  ignore(
    @loom.assert_incremental_edit_matches_full_parse(
      label,
      source,
      edit,
      new_source,
      markdown_grammar.to_syntax_grammar(),
    ),
  )
}

///|
test "incremental: paragraph text edit matches full parse" {
  let source = "Alpha beta\n\nNext paragraph\n"
  let new_source = "Alpha zeta\n\nNext paragraph\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown paragraph text edit",
    source,
    @core.Edit::new(6, 4, 4),
    new_source,
  )
}

///|
test "incremental: fenced code text edit matches full parse" {
  let prefix = "Intro\n\n```moonbit\nlet x = "
  let source = prefix + "1\n```\nAfter\n"
  let new_source = prefix + "2\n```\nAfter\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown fenced code text edit",
    source,
    @core.Edit::new(prefix.length(), 1, 1),
    new_source,
  )
}

///|
test "incremental: early closing fence edits match full parse" {
  let prefix = "```\nline one\n"
  let code_text_fence = "`` not close"
  let closing_fence = "```"
  let source = prefix + code_text_fence + "\nline two\n```\n"
  let new_source = prefix + closing_fence + "\nline two\n```\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown introduce early closing fence",
    source,
    @core.Edit::new(
      prefix.length(),
      code_text_fence.length(),
      closing_fence.length(),
    ),
    new_source,
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown remove early closing fence",
    new_source,
    @core.Edit::new(
      prefix.length(),
      closing_fence.length(),
      code_text_fence.length(),
    ),
    source,
  )
}

///|
test "incremental: paragraph edits introducing block boundaries match full parse" {
  let prefix = "Intro\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown paragraph introduces heading boundary",
    prefix + "not a heading\nTail\n",
    @core.Edit::new(
      prefix.length(),
      "not a heading".length(),
      "# heading".length(),
    ),
    prefix + "# heading\nTail\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown paragraph introduces list boundary",
    prefix + "not a list\nTail\n",
    @core.Edit::new(prefix.length(), "not a list".length(), "- item".length()),
    prefix + "- item\nTail\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown paragraph introduces fence boundary",
    prefix + "not a fence\nTail\n",
    @core.Edit::new(
      prefix.length(),
      "not a fence".length(),
      "```\ncode\n```".length(),
    ),
    prefix + "```\ncode\n```\nTail\n",
  )
}

///|
test "incremental: fence length and info edits match full parse" {
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown fence info edit",
    "```js\ncode\n```\nAfter\n",
    @core.Edit::new("```".length(), "js".length(), "moonbit".length()),
    "```moonbit\ncode\n```\nAfter\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown opening fence length edit",
    "```js\ncode\n```\nAfter\n",
    @core.Edit::insert(0, 1),
    "````js\ncode\n```\nAfter\n",
  )
}
