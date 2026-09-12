// settings_attachment_test.mbt — blackbox behavior matrix for the semantic
// settings attachment. Blackbox (separate package): exercises only the public
// surface, never private model or identity-baseline state.

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
  let source_id = @core.SourceId("json-settings-initial-valid")
  let a = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1,\"cutoff\":2}",
  )
  inspect(a.state(), content="Current")
  let doc = ok_doc(a.current_result())
  let keys = doc.settings().map(s => s.key)
  @debug.assert_eq(keys, ["gain", "cutoff"])
  let values = doc.settings().map(s => s.value)
  @debug.assert_eq(values, [1.0, 2.0])
  // Opaque, allocation-order ids (the public schema downstream copies).
  let ids = doc.settings().map(s => s.id)
  @debug.assert_eq(ids, ["setting#0", "setting#1"])
}

///|
test "malformed source blocks at parser, retains last good" {
  let source_id = @core.SourceId("json-settings-parser-blocked-last-good")
  let a = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1,\"cutoff\":2}",
  )
  let good = ok_doc(a.current_result())
  a.set_source("{\"gain\":}")
  inspect(a.state(), content="ParserBlocked")
  // current_result is an error; last_good still the previous success.
  assert_true(a.current_result() is Err(_))
  assert_true(a.last_good() == Some(good))
}

///|
test "projection-invalid value blocks at projection, retains last good" {
  let source_id = @core.SourceId("json-settings-projection-blocked-last-good")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":1}")
  let good = ok_doc(a.current_result())
  a.set_source("{\"gain\":\"loud\"}")
  inspect(a.state(), content="ProjectionBlocked")
  assert_true(a.current_result() is Err(_))
  assert_true(a.last_good() == Some(good))
}

///|
test "recovery after failure returns Current and keeps unchanged-key id" {
  let source_id = @core.SourceId("json-settings-recovery")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":1}")
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
  let source_id = @core.SourceId("json-settings-apply-edit-value")
  let a = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1,\"cutoff\":2}",
  )
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
  let source_id = @core.SourceId("json-settings-apply-edit-insertion")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"a\":1,\"b\":2}")
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
  let source_id = @core.SourceId("json-settings-set-source-replace")
  let a = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1,\"cutoff\":2}",
  )
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
  let source_id = @core.SourceId("json-settings-initial-malformed")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{")
  inspect(a.state(), content="ParserBlocked")
  assert_true(a.last_good() is None)
  assert_true(a.current_result() is Err(_))
}

///|
test "non-object root blocks at projection" {
  let source_id = @core.SourceId("json-settings-non-object")
  let a = SettingsAttachment::SettingsAttachment(source_id, "[1, 2]")
  inspect(a.state(), content="ProjectionBlocked")
}

///|
test "non-number value blocks at projection" {
  let source_id = @core.SourceId("json-settings-non-number")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":true}")
  inspect(a.state(), content="ProjectionBlocked")
}

///|
test "duplicate key blocks at projection" {
  let source_id = @core.SourceId("json-settings-duplicate-key")
  let a = SettingsAttachment::SettingsAttachment(
    source_id, "{\"gain\":1,\"gain\":2}",
  )
  inspect(a.state(), content="ProjectionBlocked")
}

///|
test "dispose is idempotent and leaves cached state readable" {
  let source_id = @core.SourceId("json-settings-dispose")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":1}")
  inspect(a.state(), content="Current")
  a.dispose()
  a.dispose() // second dispose must not crash
  // Cached state stays readable after dispose (it is not a graph read).
  inspect(a.state(), content="Current")
}

///|
test "successive renames eagerly settle a through b through c" {
  let source_id = @core.SourceId("json-settings-eager-sequence")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"a\":1}")
  let first = ok_doc(a.current_result())
  a.apply_edit(@core.Edit::new(2, 1, 1), "{\"b\":1}")
  let second = ok_doc(a.current_result())
  @debug.assert_eq(doc_id_of(second, "b"), Some("setting#1"))
  a.apply_edit(@core.Edit::new(2, 1, 1), "{\"c\":1}")
  inspect(a.state(), content="Current")
  @debug.assert_eq(
    doc_id_of(ok_doc(a.current_result()), "c"),
    Some("setting#0"),
  )
  @debug.assert_eq(doc_id_of(first, "a"), Some("setting#0"))
  @debug.assert_eq(doc_id_of(second, "b"), Some("setting#1"))
}

///|
test "same-text explicit key replacement still settles semantic intent" {
  let source_id = @core.SourceId("json-settings-same-text-key-edit")
  let source = "{\"gain\":1,\"cutoff\":2}"
  let a = SettingsAttachment::SettingsAttachment(source_id, source)
  let before = ok_doc(a.current_result())
  let id_before = doc_id_of(before, "gain")
  // Replace the key token with the identical text. The source is unchanged,
  // but the explicit edit must still be delivered to semantic coordination.
  a.apply_edit(@core.Edit::new(2, 4, 4), source)
  inspect(a.state(), content="Current")
  let after = ok_doc(a.current_result())
  assert_true(doc_id_of(after, "gain").unwrap() != id_before.unwrap())
  @debug.assert_eq(doc_id_of(after, "cutoff"), doc_id_of(before, "cutoff"))
  @debug.assert_eq(doc_id_of(before, "gain"), id_before)
}

///|
test "returned documents and settings arrays cannot mutate accepted state" {
  let source_id = @core.SourceId("json-settings-defensive-copies")
  let a = SettingsAttachment::SettingsAttachment(source_id, "{\"gain\":1}")
  let doc = ok_doc(a.current_result())
  let leaked = doc.settings()
  leaked[0] = Setting::Setting(id="spoof", key="spoof", value=99.0)
  leaked.push(Setting::Setting(id="extra", key="extra", value=100.0))
  let observed = ok_doc(a.current_result())
  inspect(observed.settings().length(), content="1")
  inspect(observed.settings()[0].key, content="gain")
  inspect(observed.settings()[0].value, content="1")
  let retained = match a.last_good() {
    Some(last) => last
    None => abort("expected an accepted last-good document")
  }
  let retained_leaked = retained.settings()
  retained_leaked[0] = Setting::Setting(
    id="retained-spoof",
    key="bad",
    value=101.0,
  )
  retained_leaked.push(
    Setting::Setting(id="retained-extra", key="extra", value=102.0),
  )
  let retained_again = match a.last_good() {
    Some(last) => last
    None => abort("accepted document must remain retained")
  }
  inspect(retained_again.settings().length(), content="1")
  inspect(retained_again.settings()[0].key, content="gain")
  inspect(retained_again.settings()[0].id, content="setting#0")
  a.apply_edit(@core.Edit::new(8, 1, 1), "{\"gain\":2}")
  a.set_source("{\"gain\":}")
  a.dispose()
  inspect(doc.settings()[0].value, content="1")
  inspect(retained.settings()[0].value, content="1")
  inspect(a.last_good().unwrap().settings()[0].value, content="2")
  assert_true(a.current_result() is Err(_))
}
