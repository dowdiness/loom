///|
fn markdown_incremental_edit_reuse_count(
  label : String,
  source : String,
  edit : @core.Edit,
  new_source : String,
) -> Int {
  @loom.assert_incremental_edit_matches_full_parse(
    label,
    source,
    edit,
    new_source,
    markdown_grammar.to_syntax_grammar(),
  )
}

///|
fn assert_markdown_incremental_edit_matches_full_parse(
  label : String,
  source : String,
  edit : @core.Edit,
  new_source : String,
) -> Unit {
  ignore(markdown_incremental_edit_reuse_count(label, source, edit, new_source))
}

///|
test "incremental: paragraph text edit matches full parse" {
  let source = "Alpha beta\n\nNext paragraph\n"
  let new_source = "Alpha zeta\n\nNext paragraph\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown paragraph text edit",
    source,
    @core.Edit::new(6, 4, 4),
    new_source,
  )
  inspect(reuse_count, content="1")
}

///|
test "incremental: paragraph diagnostic text edit matches full parse" {
  let source = ")bad\n\n)tail\n"
  let new_source = ")good\n\n)tail\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown paragraph diagnostic text edit",
    source,
    @core.Edit::new(1, "bad".length(), "good".length()),
    new_source,
  )
  inspect(reuse_count, content="1")
}

///|
test "incremental: fenced code text edit matches full parse" {
  let prefix = "Intro\n\n```moonbit\nlet x = "
  let source = prefix + "1\n```\nAfter\n"
  let new_source = prefix + "2\n```\nAfter\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown fenced code text edit",
    source,
    @core.Edit::new(prefix.length(), 1, 1),
    new_source,
  )
  inspect(reuse_count, content="1")
}

///|
test "incremental: early closing fence edits match full parse" {
  let prefix = "```\nline one\n"
  let code_text_fence = "`` not close"
  let closing_fence = "```"
  let source = prefix + code_text_fence + "\nline two\n```\n"
  let new_source = prefix + closing_fence + "\nline two\n```\n"
  let introduce_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown introduce early closing fence",
    source,
    @core.Edit::new(
      prefix.length(),
      code_text_fence.length(),
      closing_fence.length(),
    ),
    new_source,
  )
  inspect(introduce_reuse_count != 1, content="true")
  let remove_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown remove early closing fence",
    new_source,
    @core.Edit::new(
      prefix.length(),
      closing_fence.length(),
      code_text_fence.length(),
    ),
    source,
  )
  inspect(remove_reuse_count != 1, content="true")
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
test "incremental: paragraph interior boundary edits match full parse" {
  let source = "Intro tail\nAfter\n"
  let new_source = "Intro\n# heading\nAfter\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown paragraph interior introduces heading boundary",
    source,
    @core.Edit::new("Intro".length(), " tail".length(), "\n# heading".length()),
    new_source,
  )
  inspect(reuse_count != 1, content="true")
}

///|
test "incremental: paragraph marker-sensitive prefix edits match full parse" {
  let source = "`` text\nTail\n"
  let new_source = "``` text\nTail\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown paragraph backtick prefix becomes fence",
    source,
    @core.Edit::insert("``".length(), "`".length()),
    new_source,
  )
  inspect(reuse_count != 1, content="true")
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
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown interior opening fence deletion",
    "```js\ncode\n```\nAfter\n",
    @core.Edit::new(1, 1, 0),
    "``js\ncode\n```\nAfter\n",
  )
  inspect(reuse_count != 1, content="true")
}
