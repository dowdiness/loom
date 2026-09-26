///|
pub(all) enum LexMode {
  Inline
  LineStart
} derive(Eq, Debug)

///|
pub extend LexMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LexMode with Eq::{equal, not_equal}
