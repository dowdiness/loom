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
test "incremental: heading text edit uses block reparse" {
  let prefix = "# Alpha "
  let source = prefix + "beta\n\nTail\n"
  let new_source = prefix + "zeta\n\nTail\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown heading text edit",
    source,
    @core.Edit::new(prefix.length(), "beta".length(), "zeta".length()),
    new_source,
  )
  inspect(reuse_count, content="1")
}

///|
test "incremental: heading boundary edits match full parse" {
  let marker_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown heading marker edit falls back",
    "# Title\n",
    @core.Edit::insert(1, "#".length()),
    "## Title\n",
  )
  inspect(marker_reuse_count != 1, content="true")
  let prefix = "# Alpha"
  let newline_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown heading newline edit falls back",
    prefix + " beta\nTail\n",
    @core.Edit::insert(prefix.length(), "\n".length()),
    prefix + "\n beta\nTail\n",
  )
  inspect(newline_reuse_count != 1, content="true")
}

///|
test "incremental: list item text edit uses block reparse" {
  let prefix = "- item "
  let source = prefix + "one\n- item two\n"
  let new_source = prefix + "ONE\n- item two\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown list item text edit",
    source,
    @core.Edit::new(prefix.length(), "one".length(), "ONE".length()),
    new_source,
  )
  inspect(reuse_count, content="1")
}

///|
test "incremental: list item boundary edits match full parse" {
  let marker_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown list marker edit falls back",
    "- item\n",
    @core.Edit::delete(1, 1 + " ".length()),
    "-item\n",
  )
  inspect(marker_reuse_count != 1, content="true")
  let prefix = "- item"
  let newline_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown list item newline edit falls back",
    prefix + " one\n",
    @core.Edit::insert(prefix.length(), "\n".length()),
    prefix + "\n one\n",
  )
  inspect(newline_reuse_count != 1, content="true")
  let split_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown list item marker-line split falls back",
    prefix + " one\n",
    @core.Edit::insert(prefix.length(), "\n- new".length()),
    prefix + "\n- new one\n",
  )
  inspect(split_reuse_count != 1, content="true")
}

///|
test "incremental: unordered list middle item edits use block reparse" {
  let first_item = "- one\n"
  let middle_item = "- two\n"
  let last_item = "- three\n"
  let insert_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list inserts middle item",
    first_item + last_item,
    @core.Edit::insert(first_item.length(), middle_item.length()),
    first_item + middle_item + last_item,
  )
  inspect(insert_reuse_count, content="1")
  let delete_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list deletes middle item",
    first_item + middle_item + last_item,
    @core.Edit::delete(
      first_item.length(),
      first_item.length() + middle_item.length(),
    ),
    first_item + last_item,
  )
  inspect(delete_reuse_count, content="1")
}

///|
test "incremental: unordered list explicit marker metadata edits match full parse" {
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown loose list second marker changes to boundary",
    "- one\n\n- two\n",
    @core.Edit::new("- one\n\n".length(), "-".length(), "+".length()),
    "- one\n\n+ two\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown adjacent list marker changes to continuation",
    "- one\n+ two\n",
    @core.Edit::new("- one\n".length(), "+".length(), "-".length()),
    "- one\n- two\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown loose list opening marker changes boundary",
    "- one\n\n- two\n",
    @core.Edit::new(0, "-".length(), "+".length()),
    "+ one\n\n- two\n",
  )
}

///|
test "incremental: unordered list marker spelling boundary edits match full parse" {
  let dash_to_star_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list changes middle marker from dash to star",
    "- one\n- two\n- three\n",
    @core.Edit::new("- one\n".length(), "-".length(), "*".length()),
    "- one\n* two\n- three\n",
  )
  inspect(dash_to_star_reuse_count != 1, content="true")
  let star_to_plus_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list changes middle marker from star to plus",
    "* one\n* two\n* three\n",
    @core.Edit::new("* one\n".length(), "*".length(), "+".length()),
    "* one\n+ two\n* three\n",
  )
  inspect(star_to_plus_reuse_count != 1, content="true")
  let plus_to_dash_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list changes middle marker from plus to dash",
    "+ one\n+ two\n+ three\n",
    @core.Edit::new("+ one\n".length(), "+".length(), "-".length()),
    "+ one\n- two\n+ three\n",
  )
  inspect(plus_to_dash_reuse_count != 1, content="true")
}

///|
test "incremental: ordered list marker boundary edits match full parse" {
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown ordered list delimiter changes to boundary",
    "1. one\n2. two\n",
    @core.Edit::new("1. one\n2".length(), ".".length(), ")".length()),
    "1. one\n2) two\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown ordered list opening start changes",
    "1. one\n2. two\n",
    @core.Edit::new(0, "1".length(), "3".length()),
    "3. one\n2. two\n",
  )
  let interruption_delete_start = "The number of windows is\n1".length()
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown ordered list interruption start changes",
    "The number of windows is\n14.  The doors are 6.\n",
    @core.Edit::delete(
      interruption_delete_start,
      interruption_delete_start + "4".length(),
    ),
    "The number of windows is\n1.  The doors are 6.\n",
  )
}

///|
test "incremental: unordered list blank separator edits match full parse" {
  let first_item = "- one\n"
  let middle_item = "- two\n"
  let last_item = "- three\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered list inserts loose-list blank separator",
    first_item + middle_item + last_item,
    @core.Edit::insert(first_item.length(), "\n".length()),
    first_item + "\n" + middle_item + last_item,
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered list removes loose-list blank separator",
    first_item + "\n" + middle_item + last_item,
    @core.Edit::delete(first_item.length(), first_item.length() + "\n".length()),
    first_item + middle_item + last_item,
  )
  let changed_marker_item = "+ two\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered list inserts mixed-marker blank separator",
    first_item + changed_marker_item + last_item,
    @core.Edit::insert(first_item.length(), "\n".length()),
    first_item + "\n" + changed_marker_item + last_item,
  )
  let marker_changed_prefix = "- one\n+ two\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered list inserts blank after marker-change boundary",
    marker_changed_prefix + "+ three\n",
    @core.Edit::insert(marker_changed_prefix.length(), "\n".length()),
    marker_changed_prefix + "\n+ three\n",
  )
}

///|
test "incremental: unordered list boundary-breaking edits fall back" {
  let first_item = "- one\n"
  let middle_item = "- two\n"
  let last_item = "- three\n"
  let list_source = first_item + middle_item + last_item
  let blank_line_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list inserts unsafe blank line",
    list_source,
    @core.Edit::insert(first_item.length(), "\n".length()),
    first_item + "\n" + middle_item + last_item,
  )
  inspect(blank_line_reuse_count != 1, content="true")
  let heading_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list inserts unsafe heading",
    first_item + middle_item,
    @core.Edit::insert(first_item.length(), "# heading\n".length()),
    first_item + "# heading\n" + middle_item,
  )
  inspect(heading_reuse_count != 1, content="true")
  let fence_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list inserts unsafe fence",
    first_item + middle_item,
    @core.Edit::insert(first_item.length(), "```\ncode\n```\n".length()),
    first_item + "```\ncode\n```\n" + middle_item,
  )
  inspect(fence_reuse_count != 1, content="true")
  let marker_delete_start = first_item.length()
  let marker_delete_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list deletes unsafe middle marker",
    list_source,
    @core.Edit::delete(marker_delete_start, marker_delete_start + "- ".length()),
    first_item + "two\n" + last_item,
  )
  inspect(marker_delete_reuse_count != 1, content="true")
}

///|
test "incremental: unordered list separator newline delete uses block reparse" {
  let first_item = "- one\n"
  let middle_item = "- two\n"
  let last_item = "- three\n"
  let list_source = first_item + middle_item + last_item
  let newline_delete_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list deletes separator newline",
    list_source,
    @core.Edit::delete("- one".length(), first_item.length()),
    "- one" + middle_item + last_item,
  )
  inspect(newline_delete_reuse_count, content="1")
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
