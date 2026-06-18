// Selected from CommonMark 0.31.2 spec.json.
// The embedded data keeps `moon test` hermetic: no Node/npm or network access is
// needed during normal MoonBit CI. Each fixture records the CommonMark section
// and example number so later work can filter or promote the baseline.
// Baseline: pass=7, xfail=2, skip=1.

///|
fn commonmark_html_fixture_expected_status_counts() -> (Int, Int, Int) {
  (7, 2, 1)
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
