///|
/// Reified predicate over a token type `T`.
///
/// The grammar IR carries no host closures: lookahead is data, so a static
/// analysis and a future code emitter can both consume these variants, unlike
/// an opaque `(T) -> Bool`. This is a closed-but-growable vocabulary — new
/// predicate shapes are added as variants, never as an escape-hatch closure.
pub(all) enum Pred[T] {
  Any
  IsToken(T)
  OneOf(Array[T])
  Not(Pred[T])
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
  }
}
