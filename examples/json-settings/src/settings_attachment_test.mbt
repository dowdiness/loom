// settings_attachment_test.mbt — blackbox behavior matrix for the last-good
// settings attachment. Blackbox (separate package): exercises only the public
// surface, never private tracker/projection state.

///|
/// Look up the stable id of a key in a settings document, if present.
fn doc_id_of(doc : SettingsDoc, key : String) -> String? {
  for s in doc.settings() {
    if s.key == key {
      return Some(s.id)
    }
  }
  None
}

///|
/// Unwrap a `current_result` that is expected to be `Ok`.
fn ok_doc(result : Result[SettingsDoc, String]) -> SettingsDoc {
  match result {
    Ok(doc) => doc
    Err(msg) => abort("expected Ok settings doc, got Err: " + msg)
  }
}

///|
test "initial valid object projects to Current with two settings" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1,\"cutoff\":2}")
  inspect(a.state(), content="Current")
  let doc = ok_doc(a.current_result())
  let keys = doc.settings().map(fn(s) { s.key })
  @debug.assert_eq(keys, ["gain", "cutoff"])
  let values = doc.settings().map(fn(s) { s.value })
  @debug.assert_eq(values, [1.0, 2.0])
  // Opaque, allocation-order ids (the public schema downstream copies).
  let ids = doc.settings().map(fn(s) { s.id })
  @debug.assert_eq(ids, ["setting#0", "setting#1"])
}

///|
test "malformed source blocks at parser, retains last good" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1,\"cutoff\":2}")
  let good = ok_doc(a.current_result())
  a.set_source("{\"gain\":}")
  inspect(a.state(), content="ParserBlocked")
  // current_result is an error; last_good still the previous success.
  assert_true(a.current_result() is Err(_))
  assert_true(a.last_good() == Some(good))
}

///|
test "projection-invalid value blocks at projection, retains last good" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1}")
  let good = ok_doc(a.current_result())
  a.set_source("{\"gain\":\"loud\"}")
  inspect(a.state(), content="ProjectionBlocked")
  assert_true(a.current_result() is Err(_))
  assert_true(a.last_good() == Some(good))
}

///|
test "recovery after failure returns Current and keeps unchanged-key id" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1}")
  let id_before = doc_id_of(ok_doc(a.current_result()), "gain")
  a.set_source("{\"gain\":}") // malformed — retains baseline
  inspect(a.state(), content="ParserBlocked")
  a.set_source("{\"gain\":5}") // recover with a new value, same key
  inspect(a.state(), content="Current")
  let id_after = doc_id_of(ok_doc(a.current_result()), "gain")
  inspect(ok_doc(a.current_result()).settings()[0].value, content="5")
  // The "gain" setting keeps its identity across the failed intermediate input.
  @debug.assert_eq(id_before, id_after)
}

///|
test "apply_edit preserves ids through the edited value" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1,\"cutoff\":2}")
  let before = ok_doc(a.current_result())
  let gain_before = doc_id_of(before, "gain")
  let cutoff_before = doc_id_of(before, "cutoff")
  // Replace the `1` at offset 8 with `10`.
  a.apply_edit(@core.Edit::new(8, 1, 2), "{\"gain\":10,\"cutoff\":2}")
  inspect(a.state(), content="Current")
  let after = ok_doc(a.current_result())
  @debug.assert_eq(doc_id_of(after, "gain"), gain_before)
  @debug.assert_eq(doc_id_of(after, "cutoff"), cutoff_before)
  inspect(after.settings()[0].value, content="10")
}

///|
test "apply_edit insertion preserves trailing settings' ids" {
  // The biting identity test: inserting a member shifts the existing ones, so
  // freshly recomputed ids would renumber them. Stable identity must keep them.
  let a = SettingsAttachment::SettingsAttachment("{\"a\":1,\"b\":2}")
  let before = ok_doc(a.current_result())
  let a_id = doc_id_of(before, "a")
  let b_id = doc_id_of(before, "b")
  // Insert a new first member `"c":0,` at offset 1 (right after `{`).
  a.apply_edit(@core.Edit::new(1, 0, 6), "{\"c\":0,\"a\":1,\"b\":2}")
  inspect(a.state(), content="Current")
  let after = ok_doc(a.current_result())
  // `a` and `b` keep the ids they were first allocated...
  @debug.assert_eq(doc_id_of(after, "a"), a_id)
  @debug.assert_eq(doc_id_of(after, "b"), b_id)
  // ...and only `c` receives a fresh, distinct identity.
  let c_id = doc_id_of(after, "c")
  assert_true(c_id != a_id && c_id != b_id)
}

///|
test "set_source full replace preserves unchanged-key ids" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1,\"cutoff\":2}")
  let before = ok_doc(a.current_result())
  let gain_before = doc_id_of(before, "gain")
  let cutoff_before = doc_id_of(before, "cutoff")
  a.set_source("{\"gain\":1,\"cutoff\":3}")
  inspect(a.state(), content="Current")
  let after = ok_doc(a.current_result())
  @debug.assert_eq(doc_id_of(after, "gain"), gain_before)
  @debug.assert_eq(doc_id_of(after, "cutoff"), cutoff_before)
}

///|
test "first snapshot malformed has no last good and blocks at parser" {
  let a = SettingsAttachment::SettingsAttachment("{")
  inspect(a.state(), content="ParserBlocked")
  assert_true(a.last_good() is None)
  assert_true(a.current_result() is Err(_))
}

///|
test "non-object root blocks at projection" {
  let a = SettingsAttachment::SettingsAttachment("[1, 2]")
  inspect(a.state(), content="ProjectionBlocked")
}

///|
test "non-number value blocks at projection" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":true}")
  inspect(a.state(), content="ProjectionBlocked")
}

///|
test "duplicate key blocks at projection" {
  let a = SettingsAttachment::SettingsAttachment("{\"gain\":1,\"gain\":2}")
  inspect(a.state(), content="ProjectionBlocked")
}
