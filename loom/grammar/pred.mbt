///|
/// Reified predicate over a token type `T`.
///
/// `HostGuard(name)` references a named hand-written `fn(ParserContext) -> Bool`
/// supplied out-of-band via the interpreter's `guards` map. It is never resolved
/// by `matches` (which takes only a token), so it always returns `false` there.
/// The compiled interpreter resolves it in predicates evaluated at the current
/// cursor. Compilation rejects it in token scans where the callback may receive
/// a lookahead token while the context remains at the current cursor. Mirrors
/// `Native(RuleName)` in that the name resolves against host code, not
/// token-identity data.
pub(all) enum Pred[T] {
  Any
  IsToken(T)
  OneOf(Array[T])
  Not(Pred[T])
  /// Reference a host-written predicate function by name. Resolved
  /// out-of-band through the interpreter's `guards` map — never by `matches`,
  /// which returns `false` unconditionally for this variant.
  ///
  /// A HostGuard must be a pure query: it may inspect parser context and
  /// parse-local state but must not mutate either. The interpreter cannot
  /// enforce this; it is an implementation contract.
  HostGuard(String)
  /// Both sides must match. Composes token predicates with `HostGuard` at
  /// current-cursor predicate positions.
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
