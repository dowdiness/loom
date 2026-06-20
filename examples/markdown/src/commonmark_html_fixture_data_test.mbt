// Selected from CommonMark 0.31.2 spec.json.
// The embedded data keeps `moon test` hermetic: no Node/npm or network access is
// needed during normal MoonBit CI. Each fixture records the CommonMark section
// and example number so later work can filter or promote the baseline. Example
// 0 denotes a CommonMark prose-rule guard without a minimal numbered fixture.
// Baseline: pass=16, xfail=2, skip=1.

///|
fn commonmark_html_fixture_expected_status_counts() -> (Int, Int, Int) {
  (16, 2, 1)
}

///|
fn commonmark_html_fixture_cases() -> Array[CommonMarkHtmlFixture] {
  [
    {
      example: 62,
      section: "ATX headings",
      name: "atx-heading-levels",
      source: "# foo\n## foo\n### foo\n#### foo\n##### foo\n###### foo\n",
      expected_html: "<h1>foo</h1>\n<h2>foo</h2>\n<h3>foo</h3>\n<h4>foo</h4>\n<h5>foo</h5>\n<h6>foo</h6>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 119,
      section: "Fenced code blocks",
      name: "fenced-code-escapes-html",
      source: "```\n<\n >\n```\n",
      expected_html: "<pre><code>&lt;\n &gt;\n</code></pre>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 219,
      section: "Paragraphs",
      name: "paragraphs-separated-by-blank-line",
      source: "aaa\n\nbbb\n",
      expected_html: "<p>aaa</p>\n<p>bbb</p>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 328,
      section: "Code spans",
      name: "inline-code",
      source: "`foo`\n",
      expected_html: "<p><code>foo</code></p>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 350,
      section: "Emphasis and strong emphasis",
      name: "emphasis",
      source: "*foo bar*\n",
      expected_html: "<p><em>foo bar</em></p>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 483,
      section: "Links",
      name: "inline-link",
      source: "[link](/uri)\n",
      expected_html: "<p><a href=\"/uri\">link</a></p>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 607,
      section: "Autolinks",
      name: "angle-brackets-as-text",
      source: "<>\n",
      expected_html: "<p>&lt;&gt;</p>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 301,
      section: "Lists",
      name: "mixed-unordered-markers-start-new-list",
      source: "- foo\n- bar\n+ baz\n",
      expected_html: "<ul>\n<li>foo</li>\n<li>bar</li>\n</ul>\n<ul>\n<li>baz</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 302,
      section: "Lists",
      name: "ordered-list-delimiter-change-starts-new-list",
      source: "1. foo\n2. bar\n3) baz\n",
      expected_html: "<ol>\n<li>foo</li>\n<li>bar</li>\n</ol>\n<ol start=\"3\">\n<li>baz</li>\n</ol>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 306,
      section: "Lists",
      name: "loose-unordered-list-multiple-blank-lines",
      source: "- foo\n\n- bar\n\n\n- baz\n",
      expected_html: "<ul>\n<li>\n<p>foo</p>\n</li>\n<li>\n<p>bar</p>\n</li>\n<li>\n<p>baz</p>\n</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 310,
      section: "Lists",
      name: "indented-unordered-markers-stay-same-list",
      source: "- a\n - b\n  - c\n   - d\n  - e\n - f\n- g\n",
      expected_html: "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n<li>d</li>\n<li>e</li>\n<li>f</li>\n<li>g</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 311,
      section: "Lists",
      name: "indented-ordered-markers-loose-list",
      source: "1. a\n\n  2. b\n\n   3. c\n",
      expected_html: "<ol>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ol>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 314,
      section: "Lists",
      name: "loose-unordered-list-blank-between-items",
      source: "- a\n- b\n\n- c\n",
      expected_html: "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 322,
      section: "Lists",
      name: "tight-unordered-list-item",
      source: "- a\n",
      expected_html: "<ul>\n<li>a</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 323,
      section: "Lists",
      name: "tight-nested-unordered-list",
      source: "- a\n  - b\n",
      expected_html: "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    // CommonMark 0.31.2 has numbered lazy-continuation coverage near this
    // rule (notably list-item examples 290 and 292), but those fixtures also
    // require ordered-list indentation plus indented-code/blockquote rendering
    // or nested blockquote containers outside this fixture slice. Keep this
    // minimal prose-rule guard until a narrow official fixture is available.
    {
      example: 0,
      section: "Lists",
      name: "lazy-unordered-list-item-continuation",
      source: "- a\nb\n",
      expected_html: "<ul>\n<li>a\nb</li>\n</ul>\n",
      status: CommonMarkHtmlPass,
    },
    {
      example: 65,
      section: "ATX headings",
      name: "backslash-escaped-heading-marker",
      source: "\\## foo\n",
      expected_html: "<p>## foo</p>\n",
      status: CommonMarkHtmlXfail(
        "Backslash escape semantics are tracked by #329.",
      ),
    },
    {
      example: 228,
      section: "Block quotes",
      name: "blockquote-container",
      source: "> # Foo\n> bar\n> baz\n",
      expected_html: "<blockquote>\n<h1>Foo</h1>\n<p>bar\nbaz</p>\n</blockquote>\n",
      status: CommonMarkHtmlXfail(
        "Block/container semantics are tracked by #327.",
      ),
    },
    {
      example: 159,
      section: "HTML blocks",
      name: "raw-html-block-passthrough",
      source: "<div><a href=\"bar\">*foo*</a></div>\n",
      expected_html: "<div><a href=\"bar\">*foo*</a></div>\n",
      status: CommonMarkHtmlSkip(
        "Raw HTML passthrough mode is not part of the initial #326 baseline.",
      ),
    },
  ]
}
