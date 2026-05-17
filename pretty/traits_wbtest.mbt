// Tests for `pretty_unparse` and `pretty_print` wrappers in traits.mbt.
//
// The combinator algebra is covered by `properties_wbtest.mbt` and
// `render_string_wbtest.mbt`. This file pins the trait wrappers using
// a minimal `Pretty` implementor.

///|
priv struct Words {
  parts : Array[String]
}

///|
/// A Pretty impl that joins parts with `line()` inside a single `group`.
/// At a wide width the group stays flat ("a b c …"); at a narrow width it
/// breaks across multiple lines.
impl Pretty for Words with to_layout(self) {
  let parts : Array[Layout[SyntaxCategory]] = self.parts.map(text)
  group(separate(line(), parts))
}

///|
test "pretty_unparse keeps wide groups flat (width=1_000_000)" {
  let probe = Words::{
    parts: ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"],
  }
  // At a narrow width the group breaks across lines.
  inspect(
    pretty_print(probe, width=10),
    content=(
      #|alpha
      #|beta
      #|gamma
      #|delta
      #|epsilon
      #|zeta
    ),
  )
  // pretty_unparse uses width=1_000_000, so the same group stays flat.
  inspect(pretty_unparse(probe), content="alpha beta gamma delta epsilon zeta")
}

///|
test "pretty_unparse on a single-token document" {
  let probe = Words::{ parts: ["only"] }
  inspect(pretty_unparse(probe), content="only")
}
