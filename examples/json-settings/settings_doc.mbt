// settings_doc.mbt — public copyable semantic domain for the settings example.
//
// A "settings document" is a flat JSON object mapping string keys to numbers.
// Each `Setting` carries a stable public identity (`id`) that survives edits and
// malformed intermediate input, so a downstream authoring UI can keep widget
// state attached to a setting across reparses. The identity policy itself lives
// in `settings_attachment.mbt`; this file is only the value vocabulary.

///|
/// One key→number entry with a stable public identity.
///
/// `id` is allocated by the attachment's identity policy and is stable across
/// edits that do not change this setting's key. `value` is the decoded JSON
/// number; `key` is the decoded (unescaped) JSON object key.
///
/// Fields are read-only outside the package; construct via `Setting::Setting` so
/// the only way to make one is through the (future-proof, validatable)
/// constructor.
pub struct Setting {
  id : String
  key : String
  value : Double
} derive(Eq, Debug)

///|
pub fn Setting::Setting(
  id~ : String,
  key~ : String,
  value~ : Double,
) -> Setting {
  { id, key, value }
}

///|
/// A successfully projected settings document: the ordered settings of a flat,
/// number-valued JSON object with unique keys.
///
/// The backing array is private; `settings()` hands back a defensive copy so a
/// caller cannot mutate the committed last-good document in place.
pub struct SettingsDoc {
  priv settings : Array[Setting]
} derive(Eq, Debug)

///|
pub fn SettingsDoc::SettingsDoc(settings : Array[Setting]) -> SettingsDoc {
  { settings: settings.copy() }
}

///|
/// The settings in document order (a defensive copy).
pub fn SettingsDoc::settings(self : SettingsDoc) -> Array[Setting] {
  self.settings.copy()
}
