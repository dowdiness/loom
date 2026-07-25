///|
test "compile interns string rule refs to dense slots" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Emit(1, 10),
  }
  let compiled = compile(GrammarIr::GrammarIr(rules, root="source"))
  guard compiled.slot_for_name("source") is Some(source_slot)
  guard compiled.slot_for_name("expr") is Some(expr_slot)
  assert_true(compiled.root_slot() == source_slot)
  match compiled.rule_snapshot(source_slot) {
    CompiledExpr::RefSlot(slot) => assert_true(slot == expr_slot)
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
test "compile lowers a declared Native to NativeSlot, not RefSlot" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("parse_element_with_stack"),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["parse_element_with_stack"]),
  )
  match compiled.rule_snapshot(compiled.root_slot()) {
    CompiledExpr::NativeSlot(_) => ()
    _ => fail("expected NativeSlot")
  }
}

///|
test "compile with no native_names argument still compiles ordinary grammars" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Ref("expr"),
    "expr": Expr::Emit(1, 10),
  }
  let compiled = compile(GrammarIr::GrammarIr(rules, root="source"))
  guard compiled.slot_for_name("source") is Some(source_slot)
  assert_true(compiled.root_slot() == source_slot)
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
  match compiled.rule_snapshot(compiled.root_slot()) {
    CompiledExpr::Choice(alts) => {
      inspect(alts.length(), content="1")
      match alts[0].starts {
        CompiledPred::All(_, CompiledPred::HostGuardSlot(_)) => ()
        _ => fail("expected All(IsToken(1), HostGuardSlot(...))")
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
    native_rule_refs={ "native": Set::Set(["choice"]) },
  )
  guard compiled.slot_for_name("source") is Some(source_slot)
  assert_true(compiled.root_slot() == source_slot)
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
      native_rule_refs={ "native": Set::Set(["missing"]) },
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
      native_rule_refs={ "native": Set::Set(["emit_only"]) },
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(NativeDispatchTargetNotChoice("native", "emit_only")) => ()
    _ =>
      fail("expected NativeDispatchTargetNotChoice(\"native\", \"emit_only\")")
  }
}

///|
test "compile assigns deterministic rule native guard and dispatch slots" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Native("z_native"),
    "z_rule": Expr::Choice([
      Alt::{ starts: Pred::HostGuard("z_guard"), body: Expr::Empty },
    ]),
    "a_rule": Expr::Choice([
      Alt::{ starts: Pred::HostGuard("a_guard"), body: Expr::Empty },
    ]),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["z_native", "a_native"]),
    guard_names=Set::Set(["z_guard", "a_guard"]),
    native_rule_refs={ "z_native": Set::Set(["z_rule", "a_rule"]) },
  )
  debug_inspect(
    compiled.names_snapshot(),
    content="[\"source\", \"a_rule\", \"z_rule\"]",
  )
  debug_inspect(
    compiled.native_names_snapshot(),
    content="[\"a_native\", \"z_native\"]",
  )
  debug_inspect(
    compiled.guard_names_snapshot(),
    content="[\"a_guard\", \"z_guard\"]",
  )
  guard compiled.slot_for_name("source") is Some(source_slot)
  guard compiled.slot_for_name("a_rule") is Some(a_slot)
  guard compiled.slot_for_name("z_rule") is Some(z_slot)
  assert_true(compiled.root_slot() == source_slot)
  match compiled.rule_snapshot(source_slot) {
    CompiledExpr::NativeSlot(native_slot) => {
      let targets = compiled.native_dispatch_snapshot(native_slot)
      assert_true(targets.length() == 2)
      assert_true(targets[0] == a_slot)
      assert_true(targets[1] == z_slot)
    }
    _ => fail("expected native root")
  }
  match compiled.rule_snapshot(a_slot) {
    CompiledExpr::Choice(alts) =>
      match alts[0].starts {
        CompiledPred::HostGuardSlot(_) => ()
        _ => fail("expected compiled guard slot")
      }
    _ => fail("expected choice rule")
  }
}

///|
test "compile rejects direct leading recursion" {
  let rules : Map[RuleName, Expr[Int, Int]] = { "source": Expr::Ref("source") }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected LeftRecursiveRule(\"source\")")
  }
}

///|
test "compile rejects leading recursion through Choice" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Choice([
      Alt::{ starts: Pred::Any, body: Expr::Ref("source") },
    ]),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected Choice leading recursion to be rejected")
  }
}

///|
test "compile rejects nullable leading recursion" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::Seq([Expr::Empty, Expr::Ref("source")]),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected nullable leading recursion to be rejected")
  }
}

///|
test "compile rejects recursion from a repetition body" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(Pred::Any, Expr::Ref("source")),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected repetition recursion to be rejected")
  }
}

///|
test "compile rejects structurally zero-progress repetition" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(Pred::Any, Expr::Empty),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected ZeroProgressRepeat(\"source\")")
  }
}

///|
test "compile rejects ErrorUntil with an always-true stop in repetition" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(
      Pred::Any,
      Expr::ErrorUntil(Pred::Any, "unexpected input"),
    ),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected always-stopping ErrorUntil to be rejected")
  }
}

///|
test "compile rejects ErrorNodeUntil with an always-true stop in repetition" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(
      Pred::Any,
      Expr::ErrorNodeUntil(1, Pred::Any, "unexpected input"),
    ),
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected always-stopping ErrorNodeUntil to be rejected")
  }
}

///|
test "compile accepts ErrorUntil repetition with a conditional stop" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(
      Pred::Any,
      Expr::ErrorUntil(Pred::IsToken(1), "unexpected input"),
    ),
  }
  let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile accepts ErrorNodeUntil repetition with a conditional stop" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(
      Pred::Any,
      Expr::ErrorNodeUntil(1, Pred::IsToken(1), "unexpected input"),
    ),
  }
  let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile ignores unreachable zero-progress repetition" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(
      Pred::Not(Pred::Not(Pred::Not(Pred::Any))),
      Expr::Empty,
    ),
  }
  let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile rejects zero-progress RepeatTopLevel targets" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatTopLevel(
      "empty",
      starts=Pred::Any,
      delim=Pred::Any,
      delim_kind=1,
      between_msg="",
      after_msg="",
    ),
    "empty": Expr::Empty,
  }
  let caught = try {
    let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected zero-progress RepeatTopLevel to be rejected")
  }
}

///|
test "compile ignores a false-gated RepeatTopLevel recursion" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatTopLevel(
      "source",
      starts=Pred::Not(Pred::Any),
      delim=Pred::Any,
      delim_kind=1,
      between_msg="",
      after_msg="",
    ),
  }
  let _ = compile(GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile leaves opaque Native progress for runtime enforcement" {
  let rules : Map[RuleName, Expr[Int, Int]] = {
    "source": Expr::RepeatWhile(Pred::Any, Expr::Native("native")),
  }
  let compiled = compile(
    GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["native"]),
  )
  match compiled.rule_snapshot(compiled.root_slot()) {
    CompiledExpr::RepeatWhile(_, CompiledExpr::NativeSlot(_)) => ()
    _ => fail("expected opaque Native repeat to compile")
  }
}
