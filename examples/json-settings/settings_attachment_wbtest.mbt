// settings_attachment_wbtest.mbt — whitebox integration regressions.
//
// The tests below use private construction only to supply a real parser +
// `attach_semantic` callback that deliberately faults after the production
// candidate builder has allocated IDs. No production fault hook is involved.

///|
fn make_faulting_attachment(
  source_id : @core.SourceId,
  source : String,
  fail_next : Ref[Bool],
) -> SettingsAttachment raise Failure {
  let parser = @loom.new_parser(source_id, source, @json.json_grammar)
  let analysis = parser.attach_semantic(fn(previous, snapshot, change) raise {
    let candidate = project_settings_candidate(previous, snapshot, change)
    if fail_next.val {
      fail_next.val = false
      ignore(candidate)
      raise Failure::Failure("candidate fault after identity allocation")
    }
    candidate
  })
  { parser, analysis, }
}

///|
test "projection rejection preserves accepted baseline behavior" {
  let source_id = @core.SourceId("json-settings-projection-baseline")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":1}")
  let before = match a.current_result() {
    Ok(doc) => doc
    Err(_) => abort("expected an accepted initial document")
  }
  let id_before = before.settings()[0].id
  a.set_source("{\"gain\":\"loud\"}")
  inspect(a.state(), content="ProjectionBlocked")
  a.set_source("{\"gain\":2}")
  inspect(a.state(), content="Current")
  let after = match a.current_result() {
    Ok(doc) => doc
    Err(_) => abort("expected recovery to accept the document")
  }
  @debug.assert_eq(after.settings()[0].id, id_before)
}

///|
test "candidate fault after fresh-ID allocation is retained and retryable" {
  let source_id = @core.SourceId("json-settings-candidate-retry")
  let source = "{\"gain\":1}"
  let edited = "{\"cutoff\":0,\"gain\":1}"
  let edit = @core.Edit::new(1, 0, 11)
  let expected = SettingsAttachment::SettingsAttachment(
    @core.SourceId("json-settings-candidate-retry-expected"),
    source,
  )
  expected.apply_edit(edit, edited)
  let expected_doc = match expected.current_result() {
    Ok(doc) => doc
    Err(_) => abort("expected direct transition to settle")
  }

  let fail_next : Ref[Bool] = Ref(false)
  let a = make_faulting_attachment(source_id, source, fail_next)
  a.retry()
  fail_next.val = true
  a.apply_edit(edit, edited)
  inspect(a.state(), content="CandidateBlocked")
  assert_true(a.current_result() is Err(_))
  let retained = match a.last_good() {
    Some(doc) => doc
    None => abort("candidate failure must retain the accepted document")
  }
  // Both the accepted value and its baseline remain the pre-edit state.
  inspect(retained.settings()[0].key, content="gain")
  inspect(retained.settings()[0].id, content="setting#0")
  a.retry()
  inspect(a.state(), content="Current")
  let recovered = match a.current_result() {
    Ok(doc) => doc
    Err(_) => abort("retry must settle the candidate")
  }
  @debug.assert_eq(recovered.settings(), expected_doc.settings())
  inspect(recovered.settings()[0].id, content="setting#1")
  inspect(recovered.settings()[1].id, content="setting#0")
}

///|
test "candidate fault then next edit uses newest source and accepted baseline" {
  let source = "{\"a\":1,\"b\":2}"
  let inserted = "{\"c\":0,\"a\":1,\"b\":2}"
  let newest = "{\"c\":0,\"a\":3,\"b\":2}"

  let expected = SettingsAttachment::SettingsAttachment(
    @core.SourceId("json-settings-fault-free-history"),
    source,
  )
  expected.apply_edit(@core.Edit::new(1, 0, 6), inserted)
  expected.apply_edit(@core.Edit::new(11, 1, 1), newest)
  let expected_a = match expected.current_result() {
    Ok(doc) => doc.settings()[1].id
    Err(_) => abort("expected fault-free history to settle")
  }

  let fail_next : Ref[Bool] = Ref(false)
  let actual = make_faulting_attachment(
    @core.SourceId("json-settings-faulted-history"),
    source,
    fail_next,
  )
  actual.retry()
  fail_next.val = true
  actual.apply_edit(@core.Edit::new(1, 0, 6), inserted)
  inspect(actual.state(), content="CandidateBlocked")
  // Do not retry the failed candidate. The next update must still project the
  // newest source against the last accepted baseline.
  actual.apply_edit(@core.Edit::new(11, 1, 1), newest)
  inspect(actual.state(), content="Current")
  let actual_doc = match actual.current_result() {
    Ok(doc) => doc
    Err(_) => abort("next edit must settle without an explicit retry")
  }
  inspect(actual_doc.settings()[1].value, content="3")
  assert_true(actual_doc.settings()[1].id != expected_a)
}

///|
test "settings attachment preserves explicit diagnostic source identity" {
  let source_a = @core.SourceId("json-settings-a")
  let source_b = @core.SourceId("json-settings-b")
  guard source_a != source_b else {
    fail("expected distinct settings source identities")
  }
  let attachment_a = SettingsAttachment::SettingsAttachment(
    source_a, "{\"gain\":}",
  )
  let attachment_b = SettingsAttachment::SettingsAttachment(source_b, "[1,]")
  guard attachment_a.parser.source_id() == source_a else {
    fail("expected attachment A parser to preserve its supplied source id")
  }
  guard attachment_b.parser.source_id() == source_b else {
    fail("expected attachment B parser to preserve its supplied source id")
  }
  let diagnostics_a = attachment_a.parser.diagnostics().read_or_abort()
  let diagnostics_b = attachment_b.parser.diagnostics().read_or_abort()
  guard !diagnostics_a.is_empty() else {
    fail("expected malformed source A to produce diagnostics")
  }
  guard !diagnostics_b.is_empty() else {
    fail("expected malformed source B to produce diagnostics")
  }
  guard diagnostics_a
    .items()
    .any(diagnostic => {
      diagnostic
      .labels()
      .any(label => label.style() is @core.LabelStyle::Primary)
    }) else {
    fail("expected source A diagnostics to include a primary label")
  }
  guard diagnostics_b
    .items()
    .any(diagnostic => {
      diagnostic
      .labels()
      .any(label => label.style() is @core.LabelStyle::Primary)
    }) else {
    fail("expected source B diagnostics to include a primary label")
  }
  guard diagnostics_a
    .items()
    .all(diagnostic => {
      diagnostic
      .labels()
      .all(label => {
        !(label.style() is @core.LabelStyle::Primary) ||
        label.span().source_id() == source_a
      })
    }) else {
    fail("expected every primary label for source A to retain source A")
  }
  guard diagnostics_b
    .items()
    .all(diagnostic => {
      diagnostic
      .labels()
      .all(label => {
        !(label.style() is @core.LabelStyle::Primary) ||
        label.span().source_id() == source_b
      })
    }) else {
    fail("expected every primary label for source B to retain source B")
  }
  attachment_a.set_source("{\"gain\":1}")
  guard attachment_a.parser.source_id() == source_a else {
    fail("expected set_source to preserve attachment A source identity")
  }
  attachment_a.apply_edit(@core.Edit::new(8, 1, 1), "{\"gain\":2}")
  guard attachment_a.parser.source_id() == source_a else {
    fail("expected apply_edit to preserve attachment A source identity")
  }
}
