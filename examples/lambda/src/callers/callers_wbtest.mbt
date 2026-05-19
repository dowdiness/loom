// Whitebox tests for internal helpers in the callers package.
//
// build_visibility takes Array[Def] + Array[(ScopeId, ScopeId)] as input.
// Synthetic Def construction requires whitebox access because `pub struct
// Def` is not `pub(all)` — field-construction is package-internal by
// MoonBit visibility rules.

///|
test "build_visibility: TopScope-only defs are visible from TopScope" {
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 9 },
    { name: "g", scope: TopScope, start: 10, end: 19 },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = []
  let v = build_visibility(defs, enclosing)
  inspect(v.get((TopScope, "f")) is Some(_), content="true")
  inspect(v.get((TopScope, "g")) is Some(_), content="true")
  inspect(v.get((TopScope, "absent")) is Some(_), content="false")
}

///|
test "build_visibility: child scope inherits parent's bindings" {
  let inner = LambdaScope(10, 20)
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 9 },
    { name: "x", scope: inner, start: 10, end: 20 },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = [(inner, TopScope)]
  let v = build_visibility(defs, enclosing)
  // Inner scope sees both its own param (x) and the inherited top-level binding (f).
  inspect(v.get((inner, "x")) is Some(_), content="true")
  inspect(v.get((inner, "f")) is Some(_), content="true")
  // TopScope sees only f, not x.
  inspect(v.get((TopScope, "f")) is Some(_), content="true")
  inspect(v.get((TopScope, "x")) is Some(_), content="false")
}

///|
test "build_visibility: deeply nested chain transitively inherits" {
  let outer = LambdaScope(5, 30)
  let inner = LambdaScope(15, 25)
  let defs : Array[Def] = [
    { name: "f", scope: TopScope, start: 0, end: 4 },
    { name: "x", scope: outer, start: 5, end: 30 },
    { name: "y", scope: inner, start: 15, end: 25 },
  ]
  let enclosing : Array[(ScopeId, ScopeId)] = [
    (outer, TopScope),
    (inner, outer),
  ]
  let v = build_visibility(defs, enclosing)
  // inner sees y (own), x (outer), f (TopScope).
  inspect(v.get((inner, "y")) is Some(_), content="true")
  inspect(v.get((inner, "x")) is Some(_), content="true")
  inspect(v.get((inner, "f")) is Some(_), content="true")
  // outer sees x and f, not y.
  inspect(v.get((outer, "x")) is Some(_), content="true")
  inspect(v.get((outer, "f")) is Some(_), content="true")
  inspect(v.get((outer, "y")) is Some(_), content="false")
}

///|
test "build_visibility: scope with no own bindings still inherits ancestors" {
  // Models the malformed-lambda case at callers.mbt:204: frame pushed
  // without a Def. The child scope must still appear and inherit.
  let empty_inner = LambdaScope(10, 12)
  let defs : Array[Def] = [{ name: "f", scope: TopScope, start: 0, end: 9 }]
  let enclosing : Array[(ScopeId, ScopeId)] = [(empty_inner, TopScope)]
  let v = build_visibility(defs, enclosing)
  inspect(v.get((empty_inner, "f")) is Some(_), content="true")
  inspect(v.get((empty_inner, "anything_else")) is Some(_), content="false")
}
