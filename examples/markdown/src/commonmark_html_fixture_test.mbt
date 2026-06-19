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
  let (cst, diagnostics) = parse_cst(self.source) catch {
    _ => abort("CommonMark HTML fixture parse failed for " + self.label())
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn CommonMarkHtmlFixture::actual_html(self : CommonMarkHtmlFixture) -> String {
  experimental_markdown_ir_to_commonmark_html(self.ir())
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
test "experimental MarkdownIR: CommonMark HTML fixture filters use CommonMark metadata" {
  debug_inspect(
    commonmark_html_fixture_cases_for_section("ATX headings").map(fixture => {
      fixture.example
    }),
    content="[62, 65]",
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
test "experimental MarkdownIR: CommonMark HTML renderer escapes text code and link attributes" {
  let source = "<>&\"\n\n```\n<>&\"\n```\n\n[<>&\"](https://example.com/?a=1&b=\"q\")\n"
  let (cst, diagnostics) = try! parse_cst(source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  inspect(
    experimental_markdown_ir_to_commonmark_html(ir),
    content=(
      #|<p>&lt;&gt;&amp;&quot;</p>
      #|<pre><code>&lt;&gt;&amp;&quot;
      #|</code></pre>
      #|<p><a href="https://example.com/?a=1&amp;b=&quot;q&quot;">&lt;&gt;&amp;&quot;</a></p>
      #|
    ),
  )
}

///|
test "experimental MarkdownIR: CommonMark HTML renderer uses loose list spread" {
  let source = "- one\n\n- two\n"
  let (cst, diagnostics) = try! parse_cst(source)
  let ir = experimental_markdown_ir_from_syntax_with_diagnostics(
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
