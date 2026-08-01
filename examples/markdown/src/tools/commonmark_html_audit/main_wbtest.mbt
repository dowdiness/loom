///|
test "audit classification: recovery assistance outranks matching HTML" {
  let outcome = classify_audit(AuditSignals::{
    parser_diagnostics: false,
    unsupported: false,
    malformed_raw: false,
    recovered: true,
    adapter_policy_rejected: false,
    html_matches: true,
  })
  assert_eq(outcome, Recovered)
}

///|
test "audit classification: precedence assigns exactly one category" {
  let cases : Array[(AuditSignals, AuditOutcome)] = [
    (
      {
        parser_diagnostics: true,
        unsupported: true,
        malformed_raw: true,
        recovered: true,
        adapter_policy_rejected: true,
        html_matches: false,
      },
      ParserDiagnostics,
    ),
    (
      {
        parser_diagnostics: false,
        unsupported: true,
        malformed_raw: true,
        recovered: true,
        adapter_policy_rejected: true,
        html_matches: false,
      },
      Unsupported,
    ),
    (
      {
        parser_diagnostics: false,
        unsupported: false,
        malformed_raw: true,
        recovered: true,
        adapter_policy_rejected: true,
        html_matches: false,
      },
      MalformedRaw,
    ),
    (
      {
        parser_diagnostics: false,
        unsupported: false,
        malformed_raw: false,
        recovered: true,
        adapter_policy_rejected: true,
        html_matches: false,
      },
      Recovered,
    ),
    (
      {
        parser_diagnostics: false,
        unsupported: false,
        malformed_raw: false,
        recovered: false,
        adapter_policy_rejected: true,
        html_matches: true,
      },
      AdapterPolicyRejection,
    ),
    (
      {
        parser_diagnostics: false,
        unsupported: false,
        malformed_raw: false,
        recovered: false,
        adapter_policy_rejected: false,
        html_matches: false,
      },
      HtmlMismatch,
    ),
    (
      {
        parser_diagnostics: false,
        unsupported: false,
        malformed_raw: false,
        recovered: false,
        adapter_policy_rejected: false,
        html_matches: true,
      },
      Pass,
    ),
  ]
  for item in cases {
    let (signals, expected) = item
    assert_eq(classify_audit(signals), expected)
  }
}

///|
test "audit accounting: every category contributes exactly once" {
  let outcomes = [
    Pass,
    LexError,
    ParserDiagnostics,
    Unsupported,
    MalformedRaw,
    Recovered,
    AdapterPolicyRejection,
    HtmlMismatch,
  ]
  let mut counts = AuditCounts::empty()
  for outcome in outcomes {
    counts = counts.record(outcome)
  }
  assert_eq(counts.total(), 8)
  assert_eq(counts.pass, 1)
  assert_eq(counts.fail(), 7)
  assert_false(counts.is_complete(expected_total=8))
}

///|
test "audit accounting: render parity does not promote assisted output" {
  let counts = AuditCounts::empty().record_assessment(AuditAssessment::{
    outcome: MalformedRaw,
    html_matches: true,
  })
  assert_eq(counts.pass, 0)
  assert_eq(counts.render_match, 1)
  assert_eq(counts.malformed_raw, 1)
  assert_eq(counts.total(), 1)
}

///|
test "audit output: example rows follow the declared TSV columns" {
  let example = CommonMarkSpecExample::{
    markdown: "source",
    html: "<p>source</p>\n",
    section: "Example section",
    example: 7,
  }
  assert_eq(
    example_line(example, AuditAssessment::{
      outcome: MalformedRaw,
      html_matches: true,
    }),
    "example\tExample section\t7\tmalformed-raw\ttrue",
  )
}

///|
test "audit completion: only the pinned all-pass corpus is complete" {
  let complete = { ..AuditCounts::empty(), pass: 652, render_match: 652 }
  assert_true(complete.is_complete(expected_total=652))
  assert_false(
    { ..AuditCounts::empty(), pass: 652 }.is_complete(expected_total=652),
  )
  assert_false(complete.is_complete(expected_total=651))
  assert_false(
    complete.record(AdapterPolicyRejection).is_complete(expected_total=653),
  )
  assert_false({ ..complete, skip: 1 }.is_complete(expected_total=653))
  assert_false({ ..complete, xfail: 1 }.is_complete(expected_total=653))
}

///|
test "audit corpus: version checksum and total are pinned together" {
  assert_true(
    corpus_is_pinned(
      version="0.31.2",
      sha256="d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20",
      example_count=652,
    ),
  )
  assert_false(
    corpus_is_pinned(
      version="0.31.2",
      sha256="d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20",
      example_count=651,
    ),
  )
  assert_false(
    corpus_is_pinned(
      version="0.30",
      sha256="d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20",
      example_count=652,
    ),
  )
  assert_false(
    corpus_is_pinned(
      version="0.31.2",
      sha256="not-the-pinned-checksum",
      example_count=652,
    ),
  )
}

///|
test "audit corpus: SHA-256 uses UTF-8 bytes and lowercase hex" {
  assert_eq(
    sha256_hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}
