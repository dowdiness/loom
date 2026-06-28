/// Fixture for #522 GrammarIr generation. Exercises the FIRST-set-dependent
/// constructs: a `Star` repetition over a rule `Ref` (so the loop gate is the
/// referenced rule's FIRST set), an alternation lowering to a `Choice`, and a
/// trailing terminal. `Item`'s FIRST set is `{A, B}`, so the repeat gate must be
/// `OneOf([A, B])` — a multi-token predicate, not a single `IsToken`.

#loom.token
pub(all) enum Tok {
  #loom.punct("a")
  A
  #loom.punct("b")
  B
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum T {
  #loom.root
  #loom.rule("Item* Eof")
  Items

  #loom.node
  #loom.rule("(A | B)")
  Item
} derive(Eq, Debug)
