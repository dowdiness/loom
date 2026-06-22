///|
test "Pred::matches covers primitive predicate vocabulary" {
  inspect(Pred::Any.matches(1), content="true")
  inspect(Pred::IsToken(2).matches(2), content="true")
  inspect(Pred::IsToken(2).matches(3), content="false")
  inspect(Pred::OneOf([1, 3, 5]).matches(3), content="true")
  inspect(Pred::OneOf([1, 3, 5]).matches(2), content="false")
  inspect(Pred::Not(Pred::IsToken(4)).matches(5), content="true")
  inspect(Pred::Not(Pred::IsToken(4)).matches(4), content="false")
}
