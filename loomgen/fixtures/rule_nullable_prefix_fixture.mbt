/// Fixture for #522 — the nullable-prefix FIRST-set case. `Number := Sign? Digits`
/// has a NULLABLE leading element (`Sign?`), so `FIRST(Number)` must union THROUGH
/// it to include `Digits` — not collapse to `{Sign}`. A head-only FIRST would gate
/// the `(Number | Word)` alternative on `Sign` alone and silently drop an unsigned
/// number. The generated predicate for the Number alternative must therefore be
/// `OneOf([Sign, Digits])`. (The textual golden looks fine either way — only the
/// predicate contents reveal the bug.)

#loom.token
pub(all) enum Tok {
  #loom.punct("-")
  Sign
  #loom.literal
  Digits
  #loom.ident
  Word
  #loom.error
  Error(String)
  #loom.eof
  Eof
} derive(Eq, Debug)

#loom.term
pub(all) enum T {
  #loom.root
  #loom.rule("(Number | Word)* Eof")
  List

  #loom.node
  #loom.rule("Sign? Digits")
  Number
} derive(Eq, Debug)
