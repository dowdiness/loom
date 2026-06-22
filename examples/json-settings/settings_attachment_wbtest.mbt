// settings_attachment_wbtest.mbt — whitebox invariant: identity is not advanced
// until semantic projection succeeds. Whitebox because it inspects the private
// `tracker` baseline, which the blackbox API deliberately does not expose.

///|
test "projection-only failure does not advance the identity baseline" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1}")
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
