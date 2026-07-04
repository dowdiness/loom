///|
#loom.token
pub(all) enum Token {
  #loom.punct("a")
  A
  #loom.punct("b")
  B
  #loom.eof
  Eof
} derive(Eq)
