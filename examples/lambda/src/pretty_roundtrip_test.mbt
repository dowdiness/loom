///|
fn has_error_node(term : @ast.Term) -> Bool {
  match term {
    Error(_) | Unbound(_) | Hole(_) => true
    Int(_) | Var(_) | Unit => false
    Lam(_, body) => has_error_node(body)
    App(f, x) => has_error_node(f) || has_error_node(x)
    Bop(_, l, r) => has_error_node(l) || has_error_node(r)
    If(c, t, e) => has_error_node(c) || has_error_node(t) || has_error_node(e)
    Module(defs, body) => {
      for def in defs {
        if has_error_node(def.1) {
          return true
        }
      }
      has_error_node(body)
    }
  }
}

///|
/// Check whether the term contains Unit (not roundtrippable through parse)
/// or Module nested inside non-top-level positions.
fn has_non_roundtrippable(term : @ast.Term) -> Bool {
  fn go(t : @ast.Term, top_level : Bool) -> Bool {
    match t {
      Unit => true
      Module(_, _) if !top_level => true
      Module(defs, body) => {
        for def in defs {
          if go(def.1, false) {
            return true
          }
        }
        go(body, false)
      }
      Int(_) | Var(_) => false
      Lam(_, body) => go(body, false)
      App(f, x) => go(f, false) || go(x, false)
      Bop(_, l, r) => go(l, false) || go(r, false)
      If(c, t, e) => go(c, false) || go(t, false) || go(e, false)
      Error(_) | Unbound(_) | Hole(_) => true
    }
  }

  go(term, true)
}

///|
/// Property: parse(pretty_print(term)) == term for well-formed terms.
fn prop_parse_pretty_roundtrip(term : @ast.Term) -> Bool {
  if has_error_node(term) || has_non_roundtrippable(term) {
    return true // discard terms that can't roundtrip
  }
  let formatted = @pretty.pretty_print(term)
  let reparsed = parse(formatted) catch { _ => return false }
  reparsed == term
}

///|
test "property: parse(pretty_print(term)) == term" {
  @qc.quick_check_fn(prop_parse_pretty_roundtrip)
}
