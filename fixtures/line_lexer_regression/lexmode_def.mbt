///|
#derive(Eq, Debug)
pub(all) enum LexMode {
  Inline
  LineStart
}

///|
pub extend LexMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LexMode with Eq::{equal, not_equal}
