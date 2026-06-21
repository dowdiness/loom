///|
/// Open rule namespace. Rules are authored by string name; `compile` (the
/// interning stage) resolves them to dense slots so hot-path `Ref` dispatch is
/// an array index rather than a map lookup.
pub type RuleName = String

///|
/// One alternative in a `Choice`: a reified start predicate plus the body to
/// run when it matches. `starts` is `Pred` data, never a host closure.
pub(all) struct Alt[T, K] {
  starts : Pred[T]
  body : Expr[T, K]
} derive(Eq, Debug)

///|
/// Reified, generic grammar expression — the heart of the contract.
///
/// No host closures anywhere: lookahead is `Pred[T]` data, so a static analysis
/// and a future code emitter can both consume this IR. Every lambda escape
/// hatch reifies to a structural node here; `ManualNewlineAppExpr` is the one
/// evidence-gated residue (its mode is threaded through recursion — see the
/// design spec §5.1).
pub(all) enum Expr[T, K] {
  /// Wrap the inner expr in a node of the given kind.
  Node(K, Expr[T, K])
  /// Emit the current token as the given kind if it matches.
  Emit(T, K)
  /// Expect the given token, emit as the kind, or emit an error placeholder.
  /// The message is surfaced on the missing-token path.
  Expect(T, K, String)
  /// Delegate to another rule by name.
  Ref(RuleName)
  /// Try alternatives in order; each carries its own reified start predicate.
  Choice(Array[Alt[T, K]])
  /// Repeat a rule at the top level with repeat-group reuse. `starts` gates
  /// item entry; the trailing `Expr` runs once after the loop (e.g. a trailing
  /// expression) — pass `Empty` to reject tails.
  RepeatTopLevel(RuleName, Pred[T], Expr[T, K])
  /// Run each expression in sequence.
  Seq(Array[Expr[T, K]])
  /// Pratt application: parse the atom rule while `starts` holds, wrapping the
  /// run in the node kind. No-op when the first atom stands alone.
  PrattApp(RuleName, K, Pred[T])
  /// Pratt binary: parse the prefix rule, then consume operator/prefix pairs
  /// while the peek matches an op token, wrapping in the binary kind.
  PrattBinary(RuleName, K, Array[(T, K)])
  /// Repeat the body while the predicate holds.
  RepeatWhile(Pred[T], Expr[T, K])
  /// Capture an entry mark and peek: if the next token matches the predicate,
  /// wrap the inner expr in the node kind from that mark; otherwise run the
  /// inner expr unwrapped. The mark is captured by the interpreter at node
  /// entry (no static mark in the IR).
  WrapIfNext(K, Pred[T], Expr[T, K])
  /// Repeat the body while the predicate holds, then — if fewer than `min`
  /// iterations ran — emit `missing_message` (when present). Reifies the
  /// counted-delimiter-with-conditional-diagnostic escape hatch.
  CountedRepeat(Pred[T], Expr[T, K], min~ : Int, missing_message~ : String?)
  /// Emit a diagnostic without creating an error node or placeholder.
  EmitError(String)
  /// Emit an error node consuming until the stop predicate holds.
  ErrorUntil(Pred[T], String)
  /// Evidence-gated residue (Task 8): context-sensitive newline application
  /// whose mode is threaded through recursion. Not yet reified to data.
  ManualNewlineAppExpr
  /// No-op.
  Empty
} derive(Eq, Debug)

///|
/// A complete grammar: named rules plus the root rule name.
pub(all) struct GrammarIr[T, K] {
  rules : Map[RuleName, Expr[T, K]]
  root : RuleName
} derive(Eq, Debug)

///|
/// Construct a grammar from a rule map and the root rule name.
pub fn[T, K] GrammarIr::GrammarIr(
  rules : Map[RuleName, Expr[T, K]],
  root~ : RuleName,
) -> Self[T, K] {
  { rules, root }
}
