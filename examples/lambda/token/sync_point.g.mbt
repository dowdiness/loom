///|
/// Returns `true` if `token` is an error-recovery synchronization point.
/// Generated from `#loom.recovery("sync")` annotations.
pub fn is_sync_point(token : Token) -> Bool {
  match token {
    Lambda | RightParen | If | Then | Else | Fn | Let | LBrace | RBrace | Semicolon | FatArrow | Newline | EOF => true
    _ => false
  }
}
