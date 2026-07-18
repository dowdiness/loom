///|
#loom.token
pub(all) enum Token {
  #loom.literal
  #loom.pattern("(#{1,6})([ \t])")
  #loom.payload("$1.length()")
  HeadingMarker(Int)
  #loom.literal
  #loom.pattern("(`{3,})([^\r\n]*)")
  #loom.payload("$1.length()")
  #loom.payload("$2.to_owned()")
  CodeFenceOpen(Int, String)
  #loom.eof
  EOF
} derive(Eq, Debug)
