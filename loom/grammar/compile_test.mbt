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
test "compile raises MissingFragment for unbound __loom_frag__ refs" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("__loom_frag__pratt"),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(MissingFragment("__loom_frag__pratt")) => ()
    _ => fail("expected MissingFragment(\"__loom_frag__pratt\")")
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

///|
test "compile raises MissingHostGuard when HostGuard references an unregistered guard" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Choice([
      Alt::{
        starts: Pred::HostGuard("is_at_indent_4"),
        body: Expr::Emit(1, 10),
      },
    ]),
  }
  let caught = try {
    let _ = compile(
      GrammarIr::GrammarIr(rules, root="source"),
      guard_names=Set::Set([]),
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(MissingHostGuard("is_at_indent_4")) => ()
    _ => fail("expected MissingHostGuard(\"is_at_indent_4\")")
  }
}

///|
test "compile raises AmbiguousGuard when a name is both a grammar rule and a guard, even unreferenced" {
  let rules : Map[RuleName, Expr[Int, Int]] = { "source": Expr::Emit(1, 10) }
  let caught = try {
    let _ = compile(
      GrammarIr::GrammarIr(rules, root="source"),
      guard_names=Set::Set(["source"]),
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(AmbiguousGuard("source")) => ()
    _ => fail("expected AmbiguousGuard(\"source\")")
  }
}

///|
test "compile passes HostGuard refs when guard_names contains the name" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Choice([
      Alt::{
        starts: Pred::All(Pred::IsToken(1), Pred::HostGuard("is_at_indent_4")),
        body: Expr::Emit(1, 10),
      },
    ]),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    guard_names=Set::Set(["is_at_indent_4"]),
  )
  match compiled.rule(compiled.root_slot()) {
    CompiledExpr::Choice(alts) => {
      inspect(alts.length(), content="1")
      match alts[0].starts {
        Pred::All(_, Pred::HostGuard("is_at_indent_4")) => ()
        _ => fail("expected All(IsToken(1), HostGuard(...))")
      }
    }
    _ => fail("expected Choice")
  }
}

///|
test "compile succeeds when dispatch target is a top-level Choice" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("native"),
    "choice": Expr::Choice([
      Alt::{ starts: Pred::IsToken(1), body: Expr::Emit(1, 10) },
    ]),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["native"]),
    native_rule_refs={"native": Set::Set(["choice"])},
  )
  inspect(compiled.root_slot(), content="0")
}

///|
test "compile raises MissingNativeDispatchRule for undeclared dispatch target" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("native"),
  }
  let caught = try {
    let _ = compile(
      GrammarIr::GrammarIr(rules, root="source"),
      native_names=Set::Set(["native"]),
      native_rule_refs={"native": Set::Set(["missing"])},
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(MissingNativeDispatchRule("native", "missing")) => ()
    _ => fail("expected MissingNativeDispatchRule(\"native\", \"missing\")")
  }
}

///|
test "compile raises NativeDispatchTargetNotChoice for non-Choice target" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("native"),
    "emit_only": Expr::Emit(1, 10),
  }
  let caught = try {
    let _ = compile(
      GrammarIr::GrammarIr(rules, root="source"),
      native_names=Set::Set(["native"]),
      native_rule_refs={"native": Set::Set(["emit_only"])},
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(NativeDispatchTargetNotChoice("native", "emit_only")) => ()
    _ => fail("expected NativeDispatchTargetNotChoice(\"native\", \"emit_only\")")
  }
}
