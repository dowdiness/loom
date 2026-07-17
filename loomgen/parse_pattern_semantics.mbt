///|
fn Quantifier::is_nullable(self : Quantifier) -> Bool {
  match self.kind {
    ZeroOrMore | Optional => true
    OneOrMore => false
    Counted(bounds) => bounds.min() == 0
  }
}

///|
fn Pattern::is_nullable(self : Pattern) -> Bool {
  match self {
    Empty => true
    Seq(parts) => {
      let mut all = true
      for part in parts {
        if !part.is_nullable() {
          all = false
          break
        }
      }
      all
    }
    Anchor => true
    Literal => false
    Escape => false
    Class => false
    Group(inner) => inner.is_nullable()
    Quantified(inner, quantifier) =>
      quantifier.is_nullable() || inner.is_nullable()
  }
}
