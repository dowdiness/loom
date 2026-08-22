///|
test "CommonMark example 252: blank line splits blockquote after indented code" {
  assert_commonmark_blockquote_html_regression(
    "blank-line-split", "252", ">     code\n\n>    not code\n", "<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n<blockquote>\n<p>not code</p>\n</blockquote>\n",
  )
}

///|
test "CommonMark example 242: blank line splits consecutive blockquotes" {
  assert_commonmark_blockquote_html_regression(
    "blank-line-split", "242", "> foo\n\n> bar\n", "<blockquote>\n<p>foo</p>\n</blockquote>\n<blockquote>\n<p>bar</p>\n</blockquote>\n",
  )
}

///|
/// List item content indent for `10.` is four columns (W+N). Stripping that
/// prefix leaves CommonMark example 252, so the item must contain two sibling
/// blockquotes rather than absorbing the second quote into indented code.
test "list-owned indent: blank line splits blockquote after indented code" {
  assert_commonmark_blockquote_html_regression(
    "blank-line-split", "252-in-list-10", "10. >     code\n\n    >    not code\n",
    "<ol start=\"10\">\n<li>\n<blockquote>\n<pre><code>code\n</code></pre>\n</blockquote>\n<blockquote>\n<p>not code</p>\n</blockquote>\n</li>\n</ol>\n",
  )
}
