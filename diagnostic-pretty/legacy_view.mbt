///|
/// Substring view with the contract of the `String::view` removed in
/// MoonBit 0.10.21: offsets are bounds-checked (abort on violation) but may
/// split a surrogate pair, which loom spans legitimately do.
fn String::legacy_view(
  self : String,
  start~ : Int32 = 0,
  end? : Int32,
) -> StringView {
  let end = match end {
    Some(end) => end
    None => self.length()
  }
  guard start >= 0 && start <= end && end <= self.length() else {
    abort("legacy_view: offsets out of range")
  }
  self.unsafe_view(start~, end~)
}
