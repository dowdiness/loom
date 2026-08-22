///|
/// Indented list markers cannot interrupt a paragraph. After an open
/// blockquote paragraph, `    - bar` is lazy continuation text (CommonMark
/// 238), not a root list or indented code block.
test "CommonMark example 238: indented list is blockquote lazy continuation" {
  assert_commonmark_blockquote_html_regression(
    "lazy-list-continuation", "238", "> foo\n    - bar\n", "<blockquote>\n<p>foo\n- bar</p>\n</blockquote>\n",
  )
}

///|
/// List item content indent for `10.` is four columns. Stripping that prefix
/// leaves CommonMark example 238, so the indented list marker must stay inside
/// the quoted paragraph rather than starting a sibling list in the item.
test "list-owned indent: indented list is blockquote lazy continuation" {
  assert_commonmark_blockquote_html_regression(
    "lazy-list-continuation", "238-in-list-10", "10. > foo\n        - bar\n", "<ol start=\"10\">\n<li>\n<blockquote>\n<p>foo\n- bar</p>\n</blockquote>\n</li>\n</ol>\n",
  )
}
