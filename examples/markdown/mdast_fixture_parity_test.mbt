///|
struct MdastFixture {
  name : String
  source : String
  expected : String
  status : MdastFixtureStatus
}

///|
enum MdastFixtureStatus {
  Pass
  Xfail(String)
  Skip(String)
}

///|
fn MdastFixture::ir(self : MdastFixture) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(self.source) catch {
    _ =>
      abort(
        "Markdown mdast fixture parse failed for " +
        self.name +
        ": " +
        @debug.to_string(self.source),
      )
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn canonical_mdast_fixture_json(json : Json) -> Json {
  json.transform(@json.Replacer::exclude(["position"]))
}

///|
fn MdastFixture::actual_json(self : MdastFixture) -> Json {
  canonical_mdast_fixture_json(
    experimental_markdown_ir_to_mdast_json(self.ir()),
  )
}

///|
fn MdastFixture::expected_json(self : MdastFixture) -> Json {
  canonical_mdast_fixture_json(try! @json.parse(self.expected))
}

///|
fn MdastFixture::assert_pass(self : MdastFixture) -> Unit raise {
  let expected = self.expected_json()
  let actual = self.actual_json()
  guard actual == expected else {
    fail(
      "mdast fixture mismatch: " +
      self.name +
      "\nexpected: " +
      expected.stringify() +
      "\nactual:   " +
      actual.stringify(),
    )
  }
}

///|
fn MdastFixture::assert_xfail(
  self : MdastFixture,
  reason : String,
) -> Unit raise {
  let expected = self.expected_json()
  let actual = self.actual_json()
  guard actual != expected else {
    fail(
      "mdast xfail fixture now passes; promote to pass: " +
      self.name +
      "\nreason: " +
      reason,
    )
  }
}

///|
fn mdast_fixture_actual_status_counts() -> (Int, Int, Int) {
  for fixture in mdast_fixture_cases(); pass = 0, xfail = 0, skip = 0 {
    match fixture.status {
      Pass => continue pass + 1, xfail, skip
      Xfail(_) => continue pass, xfail + 1, skip
      Skip(_) => continue pass, xfail, skip + 1
    }
  } nobreak {
    (pass, xfail, skip)
  }
}

///|
test "experimental MarkdownIR: mdast fixture status metadata supports xfail and skip" {
  let examples : Array[MdastFixtureStatus] = [
    Xfail("documented expected mismatch"),
    Skip("documented skip"),
  ]
  for status in examples {
    match status {
      Xfail(reason) | Skip(reason) => assert_true(reason.length() > 0)
      Pass => ()
    }
  }
}

///|
test "experimental MarkdownIR: mdast fixture parity baseline counts stay explicit" {
  let actual = mdast_fixture_actual_status_counts()
  let expected = mdast_fixture_expected_status_counts()
  guard actual == expected else {
    fail(
      "mdast fixture status counts changed; update generated baseline" +
      "\nexpected: " +
      @debug.to_string(expected) +
      "\nactual:   " +
      @debug.to_string(actual),
    )
  }
}

///|
test "experimental MarkdownIR: mdast fixture parity pass fixtures" {
  for fixture in mdast_fixture_cases() {
    match fixture.status {
      Pass => fixture.assert_pass()
      Xfail(_) | Skip(_) => ()
    }
  }
}

///|
test "experimental MarkdownIR: mdast fixture parity xfail fixtures" {
  for fixture in mdast_fixture_cases() {
    match fixture.status {
      Xfail(reason) => fixture.assert_xfail(reason)
      Pass | Skip(_) => ()
    }
  }
}
