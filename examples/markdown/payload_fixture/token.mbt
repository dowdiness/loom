///|
#derive(Eq, Debug)
#loom.token
pub(all) enum Token {
  #loom.literal
  #loom.pattern("(#{1,6}) ")
  #loom.payload("$1.length()")
  HeadingMarker(Int32)
  #loom.eof
  EOF
}

///|
pub extend Token with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}
