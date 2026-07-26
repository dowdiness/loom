// Authoring pipeline benchmarks.
// Run with: NEW_MOON_MOD=0 moon bench --release -p dowdiness/json-settings
// Toolchain: moon 0.1.20260713 / moonc 0.10.4+2cc641edf
//
// Each edit benchmark reports one forward-and-restore cycle.

///|
/// Generate one deterministic, realistic settings document.
fn make_settings_source(value_offset : Int) -> String {
  let members : Array[String] = []
  for i = 0; i < 50; i = i + 1 {
    members.push("\"setting_\{i}\":\{100 + value_offset + i}")
  }
  "{" + members.join(",") + "}"
}

///|
/// Locate a setting value without duplicating parser or projection behavior.
fn setting_value_start(source : String, index : Int) -> (Int, Int) {
  let old = (100 + index).to_string()
  let marker = "\"setting_\{index}\":\{old}"
  let marker_start = match source.find(marker) {
    Some(position) => position
    None => abort("benchmark setup: setting value target not found")
  }
  (marker_start + marker.length() - old.length(), old.length())
}

///|
/// Replace one numeric setting value and return its exact edit.
fn setting_edit(
  source : String,
  index : Int,
  replacement : String,
) -> (@core.Edit, String) {
  let (start, old_length) = setting_value_start(source, index)
  let edited = source[:start].to_owned() +
    replacement +
    source[start + old_length:].to_owned()
  (@core.Edit::new(start, old_length, replacement.length()), edited)
}

///|
/// Replace one setting with a non-number while keeping the document valid JSON.
fn projection_failure_source(source : String) -> String {
  let (_, edited) = setting_edit(source, 0, "\"loud\"")
  edited
}

///|
/// Assert the fixture is in its valid settled state outside a timed body.
fn assert_current(attachment : SettingsAttachment) -> Unit {
  if attachment.state().to_string() != "Current" {
    abort("benchmark setup: expected Current state")
  }
  match attachment.current_result() {
    Ok(_) => ()
    Err(message) => abort("benchmark setup: expected Current, got " + message)
  }
}

///|
test "authoring parser: apply_edit start + syntax read" (b : @bench.T) {
  let source = make_settings_source(0)
  let (edit, edited) = setting_edit(source, 0, "900")
  let parser = @loom.new_parser(source, @json.json_grammar)
  let _ = parser.syntax_tree().read_or_abort()
  let _ = parser.diagnostics().read_or_abort()
  b.bench(fn() {
    parser.apply_edit(edit, edited)
    let _ = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    parser.apply_edit(edit, source)
    let restored = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    b.keep(restored)
  })
}

///|
test "authoring parser: apply_edit middle + syntax read" (b : @bench.T) {
  let source = make_settings_source(0)
  let (edit, edited) = setting_edit(source, 25, "925")
  let parser = @loom.new_parser(source, @json.json_grammar)
  let _ = parser.syntax_tree().read_or_abort()
  let _ = parser.diagnostics().read_or_abort()
  b.bench(fn() {
    parser.apply_edit(edit, edited)
    let _ = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    parser.apply_edit(edit, source)
    let restored = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    b.keep(restored)
  })
}

///|
test "authoring parser: apply_edit end + syntax read" (b : @bench.T) {
  let source = make_settings_source(0)
  let (edit, edited) = setting_edit(source, 49, "949")
  let parser = @loom.new_parser(source, @json.json_grammar)
  let _ = parser.syntax_tree().read_or_abort()
  let _ = parser.diagnostics().read_or_abort()
  b.bench(fn() {
    parser.apply_edit(edit, edited)
    let _ = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    parser.apply_edit(edit, source)
    let restored = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    b.keep(restored)
  })
}

///|
test "authoring parser: set_source full replace + syntax read" (b : @bench.T) {
  let source = make_settings_source(0)
  let replacement = make_settings_source(1)
  let parser = @loom.new_parser(source, @json.json_grammar)
  let _ = parser.syntax_tree().read_or_abort()
  let _ = parser.diagnostics().read_or_abort()
  b.bench(fn() {
    parser.set_source(replacement)
    let _ = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    parser.set_source(source)
    let restored = parser.syntax_tree().read_or_abort()
    let _ = parser.diagnostics().read_or_abort()
    b.keep(restored)
  })
}

///|
test "authoring parser: malformed -> recovery + diagnostics reads" (
  b : @bench.T,
) {
  let source = make_settings_source(0)
  let malformed = source[:source.length() - 1].to_owned()
  let parser = @loom.new_parser(source, @json.json_grammar)
  let _ = parser.syntax_tree().read_or_abort()
  let _ = parser.diagnostics().read_or_abort()
  b.bench(fn() {
    parser.set_source(malformed)
    let failed = parser.diagnostics().read_or_abort()
    parser.set_source(source)
    let recovered = parser.diagnostics().read_or_abort()
    b.keep(recovered)
    let _ = failed
  })
}

///|
test "authoring pipeline: apply_edit start + settle" (b : @bench.T) {
  let source = make_settings_source(0)
  let (edit, edited) = setting_edit(source, 0, "900")
  let attachment = SettingsAttachment::SettingsAttachment(source)
  assert_current(attachment)
  b.bench(fn() {
    attachment.apply_edit(edit, edited)
    let _ = attachment.current_result()
    attachment.apply_edit(edit, source)
    b.keep(attachment.current_result())
  })
  assert_current(attachment)
  attachment.dispose()
}

///|
test "authoring pipeline: apply_edit middle + settle" (b : @bench.T) {
  let source = make_settings_source(0)
  let (edit, edited) = setting_edit(source, 25, "925")
  let attachment = SettingsAttachment::SettingsAttachment(source)
  assert_current(attachment)
  b.bench(fn() {
    attachment.apply_edit(edit, edited)
    let _ = attachment.current_result()
    attachment.apply_edit(edit, source)
    b.keep(attachment.current_result())
  })
  assert_current(attachment)
  attachment.dispose()
}

///|
test "authoring pipeline: apply_edit end + settle" (b : @bench.T) {
  let source = make_settings_source(0)
  let (edit, edited) = setting_edit(source, 49, "949")
  let attachment = SettingsAttachment::SettingsAttachment(source)
  assert_current(attachment)
  b.bench(fn() {
    attachment.apply_edit(edit, edited)
    let _ = attachment.current_result()
    attachment.apply_edit(edit, source)
    b.keep(attachment.current_result())
  })
  assert_current(attachment)
  attachment.dispose()
}

///|
test "authoring pipeline: set_source full replace + settle" (b : @bench.T) {
  let source = make_settings_source(0)
  let replacement = make_settings_source(1)
  let attachment = SettingsAttachment::SettingsAttachment(source)
  assert_current(attachment)
  b.bench(fn() {
    attachment.set_source(replacement)
    let _ = attachment.current_result()
    attachment.set_source(source)
    b.keep(attachment.current_result())
  })
  assert_current(attachment)
  attachment.dispose()
}

///|
test "authoring pipeline: parser failure -> recovery" (b : @bench.T) {
  let source = make_settings_source(0)
  let malformed = source[:source.length() - 1].to_owned()
  let attachment = SettingsAttachment::SettingsAttachment(source)
  assert_current(attachment)
  b.bench(fn() {
    attachment.set_source(malformed)
    let _ = attachment.current_result()
    attachment.set_source(source)
    b.keep(attachment.current_result())
  })
  assert_current(attachment)
  attachment.dispose()
}

///|
test "authoring pipeline: projection failure -> recovery" (b : @bench.T) {
  let source = make_settings_source(0)
  let invalid = projection_failure_source(source)
  let attachment = SettingsAttachment::SettingsAttachment(source)
  assert_current(attachment)
  b.bench(fn() {
    attachment.set_source(invalid)
    let _ = attachment.current_result()
    attachment.set_source(source)
    b.keep(attachment.current_result())
  })
  assert_current(attachment)
  attachment.dispose()
}

///|
test "authoring pipeline: cold construction + initial settle" (b : @bench.T) {
  let source = make_settings_source(0)
  b.bench(fn() {
    let attachment = SettingsAttachment::SettingsAttachment(source)
    b.keep(attachment.current_result())
    attachment.dispose()
  })
}
