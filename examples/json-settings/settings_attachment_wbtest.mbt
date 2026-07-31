// settings_attachment_wbtest.mbt — whitebox invariant: identity is not advanced
// until semantic projection succeeds. Whitebox because it inspects the private
// `tracker` baseline, which the blackbox API deliberately does not expose.

///|
test "projection-only failure does not advance the identity baseline" {
  let source_id = @core.SourceId("json-settings-projection-baseline")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":1}")
  let base_before = match a.tracker.baseline() {
    Some(b) => b.source()
    None => abort("expected a committed baseline after first success")
  }
  assert_eq(base_before, "{\"gain\":1}")

  // Projection-invalid input: parses fine, fails the number rule.
  a.set_source("{\"gain\":\"loud\"}")
  inspect(a.state(), content="ProjectionBlocked")

  // The retained baseline is still the previous *successful* source.
  let base_after = match a.tracker.baseline() {
    Some(b) => b.source()
    None => abort("baseline must be retained across a projection failure")
  }
  assert_eq(base_after, base_before)
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
