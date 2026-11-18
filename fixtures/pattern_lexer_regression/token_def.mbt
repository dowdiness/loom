///|
#derive(Eq, Debug)
pub(all) enum Token {
  Minus
  Arrow
  Let
  Ident
  Number
  Whitespace
  Error(String)
  EOF
}

///|
pub extend Token with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}
