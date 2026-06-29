///|
fn has_error_node(term : @ast.Term) -> Bool {
  match term {
    Error(_) | Unbound(_) | Hole(_) => true
    Int(_) | Var(_) | Unit => false
    LetDef(_, init) => has_error_node(init)
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
/// Check whether the term contains Unit/LetDef (not roundtrippable through
/// parse). Modules — including nested ones — ARE roundtrippable since the
/// printers always brace them, so they are no longer discarded.
fn has_non_roundtrippable(term : @ast.Term) -> Bool {
  match term {
    Unit => true
    LetDef(_, _) => true
    Module(defs, body) => {
      for def in defs {
        if has_non_roundtrippable(def.1) {
          return true
        }
      }
      has_non_roundtrippable(body)
    }
    Int(_) | Var(_) => false
    Lam(_, body) => has_non_roundtrippable(body)
    App(f, x) => has_non_roundtrippable(f) || has_non_roundtrippable(x)
    Bop(_, l, r) => has_non_roundtrippable(l) || has_non_roundtrippable(r)
    If(c, t, e) =>
      has_non_roundtrippable(c) ||
      has_non_roundtrippable(t) ||
      has_non_roundtrippable(e)
    Error(_) | Unbound(_) | Hole(_) => true
  }
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

///|
/// Property: parse(print_term(term)) == term — covers the SourceText (string)
/// printer, the path the layout property above does not exercise.
fn prop_parse_source_roundtrip(term : @ast.Term) -> Bool {
  if has_error_node(term) || has_non_roundtrippable(term) {
    return true // discard terms that can't roundtrip
  }
  let formatted = @ast.print_term(term)
  let reparsed = parse(formatted) catch { _ => return false }
  reparsed == term
}

///|
test "property: parse(print_term(term)) == term" {
  @qc.quick_check_fn(prop_parse_source_roundtrip)
}

///|
/// Positive control: a block-bodied lambda contains a nested Module, the exact
/// case `has_non_roundtrippable` discards from the @qc property. Always-braced
/// output must reparse to the same term.
test "roundtrip: block-bodied lambda (nested module)" {
  let term : @ast.Term = @ast.Term::Module(
    [
      (
        "f",
        @ast.Term::Lam(
          "x",
          @ast.Term::Module(
            [
              (
                "y",
                @ast.Term::Bop(
                  @ast.Bop::Plus,
                  @ast.Term::Var("x"),
                  @ast.Term::Int(1),
                ),
              ),
            ],
            @ast.Term::Var("y"),
          ),
        ),
      ),
    ],
    @ast.Term::Var("f"),
  )
  let formatted = @pretty.pretty_print(term)
  let reparsed = parse(formatted) catch {
    _ => @ast.Term::Error("parse failed")
  }
  inspect(reparsed == term, content="true")
}
