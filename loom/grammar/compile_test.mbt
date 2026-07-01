///|
test "compile interns string rule refs to dense slots" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Emit(1, 10),
  }
  let compiled = compile(GrammarIr::GrammarIr(rules, root="source"))
  inspect(compiled.root_slot(), content="0")
  match compiled.rule(0) {
    CompiledExpr::RefSlot(1) => ()
    _ => fail("source should point at dense expr slot")
  }
}

///|
test "compile rejects unresolved refs before parsing" {
  let rules : Map[RuleName, Expr[Int, Int]] = { "source": Expr::Ref("missing") }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(MissingRef("missing")) => ()
    _ => fail("expected MissingRef(\"missing\")")
  }
}

///|
test "compile raises MissingNative when Native names an unregistered host rule" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("parse_element_with_stack"),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(MissingNative("parse_element_with_stack")) => ()
    _ => fail("expected MissingNative(\"parse_element_with_stack\")")
  }
}

///|
test "compile raises AmbiguousRule when a name is both a grammar rule and a native, even unreferenced" {
  // "source" is declared a native name but never appears in a `Native(...)`
  // node anywhere in the IR — the ambiguity must still be caught, because the
  // namespace check is global, not scoped to reachable `Native` nodes.
  let rules : Map[RuleName, Expr[Int, Int]] = { "source": Expr::Emit(1, 10) }
  let caught = try {
    let _ = compile(
      GrammarIr::GrammarIr(rules, root="source"),
      native_names=Set::Set(["source"]),
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(AmbiguousRule("source")) => ()
    _ => fail("expected AmbiguousRule(\"source\")")
  }
}

///|
test "compile lowers a declared Native to NativeRef, not RefSlot" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("parse_element_with_stack"),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["parse_element_with_stack"]),
  )
  match compiled.rule(compiled.root_slot()) {
    CompiledExpr::NativeRef("parse_element_with_stack") => ()
    _ => fail("expected NativeRef(\"parse_element_with_stack\")")
  }
}

///|
test "compile with no native_names argument still compiles ordinary grammars" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Emit(1, 10),
  }
  let compiled = compile(GrammarIr::GrammarIr(rules, root="source"))
  inspect(compiled.root_slot(), content="0")
}
