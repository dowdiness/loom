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
  /// Delimited top-level repeat with per-group reuse. `starts` gates item entry;
  /// each iteration tries `try_reuse_repeat_group` first and parses the item
  /// rule on a miss. `delim` tokens are consumed (emitted as `delim_kind`)
  /// before the loop, after every reused group, and after every parsed item;
  /// when a parsed item is not followed by a delimiter and we are not at EOF,
  /// `between_msg` is emitted if another item starts next (`starts` holds), else
  /// `after_msg`. The trailing expression and trailing-garbage recovery compose
  /// in the caller (e.g. a `Seq` around this node), not in the node itself.
  RepeatTopLevel(
    RuleName,
    starts~ : Pred[T],
    delim~ : Pred[T],
    delim_kind~ : K,
    between_msg~ : String,
    after_msg~ : String
  )
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
  /// Emit a diagnostic and an error placeholder — the generic "required
  /// construct missing here" recovery fallback.
  Fail(String)
  /// Emit the token as the kind when present; otherwise emit the diagnostic and
  /// an error placeholder. Reifies "emit this token, or report it missing".
  EmitOr(T, K, String)
  /// Emit a diagnostic when the next token matches the predicate, without
  /// consuming. Reifies a conditional lookahead diagnostic.
  DiagnoseIf(Pred[T], String)
  /// Consume soft-separator tokens matching the predicate (each emitted as the
  /// skip kind) when the expected token follows the run, then expect it.
  /// Reifies `expect_after_skip` — soft line continuation before a required
  /// token. Argument order mirrors the engine: skip pred, skip kind, expected
  /// token, emit kind.
  ExpectSkip(Pred[T], K, T, K)
  /// Consume a run of skip-predicate tokens (each emitted as the skip kind) only
  /// when the token after the run satisfies the lookahead predicate. Reifies
  /// `consume_while_emit_if` — soft separators before a syntactic category,
  /// never the structural separators between constructs. Argument order: skip
  /// pred, skip kind, lookahead pred.
  ConsumeGated(Pred[T], K, Pred[T])
  /// Require a separator run: consume skip-predicate tokens (each emitted as the
  /// skip kind); then, if none preceded and the `stop` predicate does not hold,
  /// emit `msg_alt` when `alt` matches the current token, else `msg_else`.
  /// Argument order: skip pred, skip kind, stop pred, alt pred.
  RequireSep(
    Pred[T],
    K,
    Pred[T],
    Pred[T],
    msg_alt~ : String,
    msg_else~ : String
  )
  /// Emit a diagnostic, open an error node of the given kind, bump tokens into
  /// it until the stop predicate holds, then close it. Callers guard the
  /// stop-already-holds case (e.g. at EOF) with a `Choice`, so this never opens
  /// an empty error node.
  ErrorNodeUntil(K, Pred[T], String)
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
