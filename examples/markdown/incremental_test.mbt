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
test "incremental: unordered list last item edit uses block reparse matches full parse" {
  let prefix = "- one\n- two\n- "
  let source = prefix + "three\n"
  let new_source = prefix + "THREE\n"
  let reuse_count = markdown_incremental_edit_reuse_count(
    "markdown unordered list last item text edit",
    source,
    @core.Edit::new(prefix.length(), "three".length(), "THREE".length()),
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
test "incremental: ordered marker delimiter relex matches detached tokenize" {
  let source = "1. one\n2. two\n"
  let new_source = "1. one\n2) two\n"
  let edit = @core.Edit::new("1. one\n2".length(), ".".length(), ")".length())
  let factory = @core.erase_mode_lexer(
    markdown_mode_lexer,
    Token::EOF,
    error_token=Token::Error("lex error"),
    error_token_from_message=Some(fn(msg) { Token::Error(msg) }),
  )
  let state = (factory.new_session)()
  let initial = (state.tokenize)(source)
  let buffer = @core.TokenBuffer::new_with_mode_relex(
    source,
    initial.tokens(),
    initial.starts(),
    Token::EOF,
    state,
  )
  buffer.update(edit, new_source)
  let full = (factory.tokenize)(new_source)
  inspect(buffer.get_tokens() == full.tokens(), content="true")
  inspect(buffer.get_starts() == full.starts(), content="true")
  for i in 0..<buffer.token_count() {
    let start = full.starts()[i]
    let end = start + full.tokens()[i].len
    inspect(buffer.get_view(i) == new_source.view(start_offset=start, end_offset=end), content="true")
  }
}


///|
test "incremental: list marker indentation edits match full parse" {
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered list marker gains allowed indentation",
    "- a\n- b\n",
    @core.Edit::insert("- a\n".length(), " ".length()),
    "- a\n - b\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered list marker becomes indented paragraph",
    "- a\n   - b\n",
    @core.Edit::insert("- a\n".length(), " ".length()),
    "- a\n    - b\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown ordered list marker gains allowed indentation",
    "1. a\n\n2. b\n",
    @core.Edit::insert("1. a\n\n".length(), "  ".length()),
    "1. a\n\n  2. b\n",
  )
}

///|
test "incremental: nested list indentation edits match full parse" {
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered child marker indents into nested list",
    "- parent\n- child\n",
    @core.Edit::insert("- parent\n".length(), "  ".length()),
    "- parent\n  - child\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered nested child outdents to sibling",
    "- parent\n  - child\n",
    @core.Edit::delete("- parent\n".length(), "- parent\n  ".length()),
    "- parent\n- child\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown tab-indented nested list text edit matches full parse",
    " - foo\n   - bar\n\t - baz\n",
    @core.Edit::new(
      " - foo\n   - bar\n\t - ".length(),
      "baz".length(),
      "BAZ".length(),
    ),
    " - foo\n   - bar\n\t - BAZ\n",
  )
  let nested_prefix = "- a\n  - b\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered top-level sibling joins existing nested list",
    nested_prefix + "- c\n",
    @core.Edit::insert(nested_prefix.length(), "  ".length()),
    nested_prefix + "  - c\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown unordered nested sibling outdents after existing nested list",
    nested_prefix + "  - c\n",
    @core.Edit::delete(
      nested_prefix.length(),
      nested_prefix.length() + "  ".length(),
    ),
    nested_prefix + "- c\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown over-indented nested marker matches full parse",
    "- parent\n  - child\n",
    @core.Edit::insert("- parent\n".length(), "    ".length()),
    "- parent\n      - child\n",
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
    "markdown unordered list deletes middle marker into lazy continuation",
    list_source,
    @core.Edit::delete(marker_delete_start, marker_delete_start + "- ".length()),
    first_item + "two\n" + last_item,
  )
  inspect(marker_delete_reuse_count, content="1")
}

///|
test "incremental: list item lazy continuation edits match full parse" {
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown lazy continuation text edit",
    "- a\nb\n",
    @core.Edit::new("- a\n".length(), "b".length(), "B".length()),
    "- a\nB\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown non-one ordered marker lazy continuation text edit",
    "- a\n2. b\n",
    @core.Edit::new("- a\n2. ".length(), "b".length(), "B".length()),
    "- a\n2. B\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown empty item rejects lazy paragraph continuation",
    "- a\nfoo\n",
    @core.Edit::delete("- ".length(), "- a".length()),
    "- \nfoo\n",
  )
  let whitespace_only_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown whitespace-only item rejects lazy paragraph continuation",
    "- a\nfoo\n",
    @core.Edit::new("- ".length(), "a".length(), "  ".length()),
    "-   \nfoo\n",
  )
  inspect(whitespace_only_reuse_count != 1, content="true")
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown empty item rejects ordered-marker lazy continuation",
    "- a\n2. foo\n",
    @core.Edit::delete("- ".length(), "- a".length()),
    "- \n2. foo\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown whitespace-only item rejects ordered-marker lazy continuation",
    "- a\n2. foo\n",
    @core.Edit::new("- ".length(), "a".length(), "  ".length()),
    "-   \n2. foo\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown indented ordered marker becomes nested list",
    "- a\n2. b\n",
    @core.Edit::insert("- a\n".length(), "  ".length()),
    "- a\n  2. b\n",
  )
  let marker_delete_reuse_count = markdown_incremental_edit_reuse_count(
    "markdown middle marker deletion becomes lazy continuation",
    "- one\n- two\n- three\n",
    @core.Edit::delete("- one\n".length(), "- one\n- ".length()),
    "- one\ntwo\n- three\n",
  )
  inspect(marker_delete_reuse_count, content="1")
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
test "incremental: blockquote list text edit preserves unquoted boundary" {
  let prefix = "> - "
  let quoted_item = prefix + "foo\n"
  let unquoted_item = "- bar\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown blockquote list text edit preserves unquoted list boundary",
    quoted_item + unquoted_item,
    @core.Edit::new(prefix.length(), "foo".length(), "FOO".length()),
    prefix + "FOO\n" + unquoted_item,
  )
}

///|
test "incremental: blockquote lazy continuation marker edits match full parse" {
  let first_line = "> bar\n"
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown blockquote removes paragraph continuation marker",
    first_line + "> baz\n",
    @core.Edit::delete(first_line.length(), first_line.length() + "> ".length()),
    first_line + "baz\n",
  )
  assert_markdown_incremental_edit_matches_full_parse(
    "markdown blockquote inserts paragraph continuation marker",
    first_line + "baz\n",
    @core.Edit::insert(first_line.length(), "> ".length()),
    first_line + "> baz\n",
  )
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


