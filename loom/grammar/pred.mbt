///|
/// Reified predicate over a token type `T`.
///
/// `HostGuard(name)` references a named hand-written `fn(ParserContext) -> Bool`
/// supplied out-of-band via the interpreter's `guards` map. It is never resolved
/// by `matches` (which takes only a token), so it always returns `false` there;
/// the interpreter's `Choice` arm handles it separately. Mirrors `Native(RuleName)`
/// in that the name resolves against host code, not token-identity data.
pub(all) enum Pred[T] {
  Any
  IsToken(T)
  OneOf(Array[T])
  Not(Pred[T])
  /// Reference a host-written predicate function by name. Resolved
  /// out-of-band through the interpreter's `guards` map — never by `matches`,
  /// which returns `false` unconditionally for this variant.
  ///
  /// NOTE: when used as a native-dispatch entry predicate (through
  /// `try_parse_rule`), a HostGuard must be a pure query — it may inspect
  /// parser context and parse-local state but must not mutate either. The
  /// interpreter cannot enforce this; it is an implementation contract.
  HostGuard(String)
  /// Both sides must match. Composes `IsToken`/`OneOf` with `HostGuard` so
  /// a Choice arm can gate on both a specific token AND a computed guard.
  All(Pred[T], Pred[T])
} derive(Eq, Debug)

///|
/// Test whether `token` satisfies this predicate.
///
/// Named `matches` rather than `test` because `test` is a reserved keyword in
/// MoonBit (used for `test "..." { ... }` blocks).
pub fn[T : Eq] Pred::matches(self : Self[T], token : T) -> Bool {
  match self {
    Any => true
    IsToken(expected) => token == expected
    OneOf(tokens) => tokens.iter().any(t => t == token)
    Not(inner) => !inner.matches(token)
    HostGuard(_) => false
    All(left, right) => left.matches(token) && right.matches(token)
  }
}
