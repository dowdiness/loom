// Phase 0 baseline for the public LexResult collection-ownership boundary.

///|
enum CoreOwnershipBenchToken {
  Token
} derive(Eq, Debug)

///|
test "core ownership: LexResult::with_starts 10000 tokens" (b : @bench.T) {
  let tokens : Array[TokenInfo[CoreOwnershipBenchToken]] = Array::make(
    10000,
    TokenInfo::new(Token, 1),
  )
  let starts : Array[Int] = Array::makei(10000, fn(i) { i })
  let diagnostics = DiagnosticSet::empty()
  b.bench(fn() { b.keep(LexResult::with_starts(tokens, starts, diagnostics~)) })
}
