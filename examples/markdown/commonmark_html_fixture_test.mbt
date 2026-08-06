///|
struct CommonMarkHtmlFixture {
  example : Int
  section : String
  name : String
  source : String
  expected_html : String
  status : CommonMarkHtmlFixtureStatus
}

///|
enum CommonMarkHtmlFixtureStatus {
  CommonMarkHtmlPass
  CommonMarkHtmlXfail(String)
  CommonMarkHtmlSkip(String)
}

///|
fn CommonMarkHtmlFixture::label(self : CommonMarkHtmlFixture) -> String {
  "CommonMark example " +
  self.example.to_string() +
  " (" +
  self.section +
  "): " +
  self.name
}

///|
fn CommonMarkHtmlFixture::ir(self : CommonMarkHtmlFixture) -> MarkdownIR {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-fixture:" + self.example.to_string(),
  )
  let (cst, diagnostics) = parse_cst(source_id, self.source) catch {
    _ => abort("CommonMark HTML fixture parse failed for " + self.label())
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn CommonMarkHtmlFixture::actual_html(self : CommonMarkHtmlFixture) -> String {
  match
    experimental_markdown_ir_to_commonmark_html_with_raw_html_policy(
      self.ir(),
      Passthrough,
    ) {
    Ok(html) => html
    Err(_) => abort("Passthrough raw HTML policy cannot reject valid HTML")
  }
}

///|
fn CommonMarkHtmlFixture::assert_pass(
  self : CommonMarkHtmlFixture,
) -> Unit raise {
  let actual = self.actual_html()
  guard actual == self.expected_html else {
    fail(
      "CommonMark HTML fixture mismatch: " +
      self.label() +
      "\nexpected: " +
      @debug.to_string(self.expected_html) +
      "\nactual:   " +
      @debug.to_string(actual),
    )
  }
}

///|
fn CommonMarkHtmlFixture::assert_xfail(
  self : CommonMarkHtmlFixture,
  reason : String,
) -> Unit raise {
  let actual = self.actual_html()
  guard actual != self.expected_html else {
    fail(
      "CommonMark HTML xfail fixture now passes; promote to pass: " +
      self.label() +
      "\nreason: " +
      reason,
    )
  }
}

///|
fn commonmark_html_fixture_actual_status_counts() -> (Int, Int, Int) {
  for fixture in commonmark_html_fixture_cases(); pass = 0, xfail = 0, skip = 0 {
    match fixture.status {
      CommonMarkHtmlPass => continue pass + 1, xfail, skip
      CommonMarkHtmlXfail(_) => continue pass, xfail + 1, skip
      CommonMarkHtmlSkip(_) => continue pass, xfail, skip + 1
    }
  } nobreak {
    (pass, xfail, skip)
  }
}

///|
fn commonmark_html_fixture_cases_for_section(
  section : String,
) -> Array[CommonMarkHtmlFixture] {
  commonmark_html_fixture_cases()
  .iter()
  .filter(fixture => fixture.section == section)
  .collect()
}

///|
fn commonmark_html_fixture_case_by_example(
  example : Int,
) -> CommonMarkHtmlFixture? {
  commonmark_html_fixture_cases()
  .iter()
  .find_first(fixture => fixture.example == example)
}

///|
test "experimental MarkdownIR: CommonMark HTML fixture status metadata supports xfail and skip" {
  let examples : Array[CommonMarkHtmlFixtureStatus] = [
    CommonMarkHtmlXfail("documented expected mismatch"),
    CommonMarkHtmlSkip("documented skip"),
  ]
  for status in examples {
    match status {
      CommonMarkHtmlXfail(reason) | CommonMarkHtmlSkip(reason) =>
        assert_true(reason.length() > 0)
      CommonMarkHtmlPass => ()
    }
  }
}

///|
test "experimental MarkdownIR: CommonMark HTML fixture non-pass reasons stay explicit" {
  for fixture in commonmark_html_fixture_cases() {
    match fixture.status {
      CommonMarkHtmlXfail(reason) =>
        if reason.trim().is_empty() {
          fail("expected a nonempty xfail reason for " + fixture.label())
        }
      CommonMarkHtmlSkip(reason) =>
        if reason.trim().is_empty() {
          fail("expected a nonempty skip reason for " + fixture.label())
        }
      CommonMarkHtmlPass => ()
    }
  }
}

///|
test "experimental MarkdownIR: CommonMark emphasis fixture corpus is complete" {
  let fixtures = commonmark_html_fixture_cases_for_section(
    "Emphasis and strong emphasis",
  )
  guard fixtures.length() == 132 else {
    fail(
      "expected all 132 CommonMark emphasis examples, got " +
      fixtures.length().to_string(),
    )
  }
  for index, fixture in fixtures {
    let expected_example = 350 + index
    guard fixture.example == expected_example else {
      fail(
        "expected CommonMark emphasis example " +
        expected_example.to_string() +
        ", got " +
        fixture.example.to_string(),
      )
    }
  }
  let actual = for fixture in fixtures; pass = 0, xfail = 0, skip = 0 {
    match fixture.status {
      CommonMarkHtmlPass => continue pass + 1, xfail, skip
      CommonMarkHtmlXfail(_) => continue pass, xfail + 1, skip
      CommonMarkHtmlSkip(_) => continue pass, xfail, skip + 1
    }
  } nobreak {
    (pass, xfail, skip)
  }
  let expected = commonmark_emphasis_html_fixture_expected_status_counts()
  guard expected == (132, 0, 0) else {
    fail(
      "expected the generated CommonMark emphasis baseline to stay " +
      "(132, 0, 0), got " +
      @debug.to_string(expected),
    )
  }
  guard actual == expected else {
    fail(
      "expected CommonMark emphasis fixture counts " +
      @debug.to_string(expected) +
      ", got " +
      @debug.to_string(actual),
    )
  }
}

///|
test "experimental MarkdownIR: CommonMark HTML fixture filters use CommonMark metadata" {
  debug_inspect(
    commonmark_html_fixture_cases_for_section("ATX headings").map(fixture => {
      fixture.example
    }),
    content="[62, 65, 66, 69, 67, 68, 71, 72, 73, 79, 63, 64, 74, 75, 78]",
  )
  match commonmark_html_fixture_case_by_example(119) {
    Some(fixture) => inspect(fixture.section, content="Fenced code blocks")
    None => fail("expected CommonMark example 119 fixture")
  }
}

///|
test "experimental MarkdownIR: CommonMark HTML fixture baseline counts stay explicit" {
  let actual = commonmark_html_fixture_actual_status_counts()
  let expected = commonmark_html_fixture_expected_status_counts()
  guard actual == expected else {
    fail(
      "CommonMark HTML fixture status counts changed; update baseline" +
      "\nexpected: " +
      @debug.to_string(expected) +
      "\nactual:   " +
      @debug.to_string(actual),
    )
  }
}

///|
test "experimental MarkdownIR: CommonMark HTML fixture pass fixtures" {
  for fixture in commonmark_html_fixture_cases() {
    match fixture.status {
      CommonMarkHtmlPass => fixture.assert_pass()
      CommonMarkHtmlXfail(_) | CommonMarkHtmlSkip(_) => ()
    }
  }
}

///|
test "experimental MarkdownIR: CommonMark HTML fixture xfail fixtures" {
  for fixture in commonmark_html_fixture_cases() {
    match fixture.status {
      CommonMarkHtmlXfail(reason) => fixture.assert_xfail(reason)
      CommonMarkHtmlPass | CommonMarkHtmlSkip(_) => ()
    }
  }
}

///|
test "experimental MarkdownIR: example 91 angle boundary supports line endings and EOF" {
  let cases : Array[(String, String)] = [
    ("LF", "<a title=\"a lot\n---\nof dashes\"/>\n"),
    ("CRLF", "<a title=\"a lot\r\n---\r\nof dashes\"/>\r\n"),
    ("CR", "<a title=\"a lot\r---\rof dashes\"/>\r"),
    ("EOF", "<a title=\"a lot\n---\nof dashes\"/>"),
  ]
  for ending_case in cases {
    let (label, source) = ending_case
    let fixture : CommonMarkHtmlFixture = {
      example: 91,
      section: "Setext headings",
      name: "setext angle boundary " + label,
      source,
      expected_html: "<h2>&lt;a title=&quot;a lot</h2>\n<p>of dashes&quot;/&gt;</p>\n",
      status: CommonMarkHtmlPass,
    }
    fixture.assert_pass()
  }
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer supports setext headings in containers" {
  let source_id = @core.SourceId("markdown-commonmark-html-setext-containers")
  let blockquote = "> Foo\n> ---\n"
  let (blockquote_cst, blockquote_diagnostics) = try! parse_cst(
    source_id, blockquote,
  )
  let blockquote_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(blockquote_cst),
    blockquote_diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(blockquote_ir),
    content="<blockquote>\n<h2>Foo</h2>\n</blockquote>\n",
  )
  let list_item = "- Bar\n  ---\n"
  let (list_cst, list_diagnostics) = try! parse_cst(source_id, list_item)
  let list_ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(list_cst),
    list_diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(list_ir),
    content="<ul>\n<li>\n<h2>Bar</h2>\n</li>\n</ul>\n",
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer escapes text code and link attributes" {
  let source_id = @core.SourceId("markdown-commonmark-html-escaping")
  let source = "<>&\"\n\n```\n<>&\"\n```\n\n[<>&\"](https://example.com/?a=1&b=\"q\")\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<p>&lt;&gt;&amp;&quot;</p>
      #|<pre><code>&lt;&gt;&amp;&quot;
      #|</code></pre>
      #|<p><a href="https://example.com/?a=1&amp;b=%22q%22">&lt;&gt;&amp;&quot;</a></p>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer preserves whitespace-only list item inline syntax" {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-whitespace-list-item",
  )
  let source = "- ` `\n- [](/)\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li><code> </code></li>
      #|<li><a href="/"></a></li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps tab continuation inside empty list item" {
  let source_id = @core.SourceId("markdown-commonmark-html-empty-list-tab")
  let source = "-\n\tfoo\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>foo</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer stops list code block before paragraph continuation" {
  let source_id = @core.SourceId("markdown-commonmark-html-list-code-boundary")
  let source = "-\t\tfoo\n    bar\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>
      #|<pre><code>  foo
      #|</code></pre>
      #|bar</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps quoted tab-indented marker as list" {
  let source_id = @core.SourceId("markdown-commonmark-html-quoted-tab-list")
  let source = "> \t- foo\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<ul>
      #|<li>foo</li>
      #|</ul>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer preserves extra code indent after blank marker padding" {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-blank-marker-code-indent",
  )
  let source = "-   \n        code\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>
      #|<pre><code>  code
      #|</code></pre>
      #|</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps column-relative blockquote tab as paragraph" {
  let source_id = @core.SourceId("markdown-commonmark-html-blockquote-tab")
  let source = "> \tfoo\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<p>foo</p>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer normalizes tab paragraph continuation" {
  let source_id = @core.SourceId("markdown-commonmark-html-tab-paragraph")
  let source = "foo\n\tbar\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<p>foo
      #|bar</p>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps tab-indented marker as code block" {
  let source_id = @core.SourceId("markdown-commonmark-html-tab-code-block")
  let source = "\t- foo\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<pre><code>- foo
      #|</code></pre>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer uses loose list spread" {
  let source_id = @core.SourceId("markdown-commonmark-html-loose-list")
  let source = "- one\n\n- two\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>
      #|<p>one</p>
      #|</li>
      #|<li>
      #|<p>two</p>
      #|</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps multi-item nested list tight" {
  let source_id = @core.SourceId("markdown-commonmark-html-tight-nested-list")
  let source = "- a\n  - b\n  - c\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>a
      #|<ul>
      #|<li>b</li>
      #|<li>c</li>
      #|</ul>
      #|</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer resumes top-level list after nested flow" {
  let source_id = @core.SourceId("markdown-commonmark-html-resume-top-list")
  let source = "- a\n  - b\n- c\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>a
      #|<ul>
      #|<li>b</li>
      #|</ul>
      #|</li>
      #|<li>c</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps mixed-marker loose lists separate" {
  let source_id = @core.SourceId("markdown-commonmark-html-mixed-marker-lists")
  let source = "- one\n\n+ two\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>one</li>
      #|</ul>
      #|<ul>
      #|<li>two</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer preserves marker-change boundary before loose separator" {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-marker-change-boundary",
  )
  let source = "- one\n+ two\n\n+ three\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li>one</li>
      #|</ul>
      #|<ul>
      #|<li>
      #|<p>two</p>
      #|</li>
      #|<li>
      #|<p>three</p>
      #|</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer leaves empty loose list items paragraphless" {
  let source_id = @core.SourceId("markdown-commonmark-html-empty-loose-item")
  let source = "- \n\n- two\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<ul>
      #|<li></li>
      #|<li>
      #|<p>two</p>
      #|</li>
      #|</ul>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps quoted loose list in one blockquote" {
  let source_id = @core.SourceId("markdown-commonmark-html-quoted-loose-list")
  let source = "> - a\n>\n> - b\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<ul>
      #|<li>
      #|<p>a</p>
      #|</li>
      #|<li>
      #|<p>b</p>
      #|</li>
      #|</ul>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer keeps non-one quoted ordered markers in paragraphs" {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-non-one-ordered-marker",
  )
  let source = "> text\n> 14. still text\n"
  let (cst, diagnostics) = try! parse_cst(source_id, source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<blockquote>
      #|<p>text
      #|14. still text</p>
      #|</blockquote>
      #|
    ),
  )
}
