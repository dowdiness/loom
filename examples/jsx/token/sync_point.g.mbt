///|
/// Returns `true` if `token` is an error-recovery synchronization point.
/// Generated from `#loom.recovery("sync")` annotations.
pub fn is_sync_point(token : Token) -> Bool {
  match token {
    OpenTagStart | TagEnd | SelfCloseEnd | FragmentOpen | FragmentClose | EOF =>
      true
    _ => false
  }
}
