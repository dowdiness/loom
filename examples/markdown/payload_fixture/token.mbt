///|
#loom.token
pub(all) enum Token {
  #loom.literal
  #loom.pattern("(#{1,6}) ")
  #loom.payload("$1.length()")
  HeadingMarker(Int)
  #loom.eof
  EOF
} derive(Eq, Debug)
