///|
test "compile interns string rule refs to dense slots" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Ref("expr"),
    "expr": @grammar.Expr::Emit(1, 10),
  }
  let compiled = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
  guard! compiled.slot_for_name("source") is Some(source_slot)
  guard! compiled.slot_for_name("expr") is Some(expr_slot)
  assert_true(compiled.root_slot() == source_slot)
  match compiled.rule_snapshot(source_slot).unwrap() {
    @grammar.CompiledExpr::RefSlot(slot) => assert_true(slot == expr_slot)
    _ => fail("source should point at dense expr slot")
  }
}

///|
test "compile rejects unresolved refs before parsing" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = { "source": @grammar.Expr::Ref("missing") }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Ref("__loom_frag__pratt"),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Native("parse_element_with_stack"),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = { "source": @grammar.Expr::Emit(1, 10) }
  let caught = try {
    let _ = @grammar.compile(
      @grammar.GrammarIr::GrammarIr(rules, root="source"),
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Native("parse_element_with_stack"),
  }
  let compiled = @grammar.compile(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["parse_element_with_stack"]),
  )
  match compiled.rule_snapshot(compiled.root_slot()).unwrap() {
    @grammar.CompiledExpr::NativeSlot(_) => ()
    _ => fail("expected NativeSlot")
  }
}

///|
test "compile with no native_names argument still compiles ordinary grammars" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Ref("expr"),
    "expr": @grammar.Expr::Emit(1, 10),
  }
  let compiled = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
  guard! compiled.slot_for_name("source") is Some(source_slot)
  assert_true(compiled.root_slot() == source_slot)
}

///|
test "compile raises MissingHostGuard when HostGuard references an unregistered guard" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::HostGuard("is_at_indent_4"),
        body: @grammar.Expr::Emit(1, 10),
      },
    ]),
  }
  let caught = try {
    let _ = @grammar.compile(
      @grammar.GrammarIr::GrammarIr(rules, root="source"),
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
test "compile rejects HostGuard in a token-scanning predicate" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::ExpectSkip(@grammar.Pred::HostGuard("skip"), 1, 2, 2),
  }
  let caught = try {
    let _ = @grammar.compile(
      @grammar.GrammarIr::GrammarIr(rules, root="source"),
      guard_names=Set::Set(["skip"]),
    )
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(HostGuardInTokenScan("ExpectSkip.skip")) => ()
    _ => fail("expected HostGuardInTokenScan for ExpectSkip.skip")
  }
}

///|
test "compile accepts HostGuard at a current-token recovery boundary" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::ErrorUntil(@grammar.Pred::HostGuard("stop"), "stop"),
  }
  let _ = @grammar.compile(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    guard_names=Set::Set(["stop"]),
  )
}

///|
test "compile raises AmbiguousGuard when a name is both a grammar rule and a guard, even unreferenced" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = { "source": @grammar.Expr::Emit(1, 10) }
  let caught = try {
    let _ = @grammar.compile(
      @grammar.GrammarIr::GrammarIr(rules, root="source"),
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::All(@grammar.Pred::IsToken(1), @grammar.Pred::HostGuard("is_at_indent_4")),
        body: @grammar.Expr::Emit(1, 10),
      },
    ]),
  }
  let compiled = @grammar.compile(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    guard_names=Set::Set(["is_at_indent_4"]),
  )
  match compiled.rule_snapshot(compiled.root_slot()).unwrap() {
    @grammar.CompiledExpr::Choice(alts) => {
      inspect(alts.length(), content="1")
      match alts[0].starts {
        @grammar.CompiledPred::All(_, @grammar.CompiledPred::HostGuardSlot(_)) => ()
        _ => fail("expected All(IsToken(1), HostGuardSlot(...))")
      }
    }
    _ => fail("expected Choice")
  }
}

///|
test "compile succeeds when dispatch target is a top-level Choice" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Native("native"),
    "choice": @grammar.Expr::Choice([
      @grammar.Alt::{ starts: @grammar.Pred::IsToken(1), body: @grammar.Expr::Emit(1, 10), },
    ]),
  }
  let compiled = @grammar.compile(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["native"]),
    native_rule_refs={ "native": Set::Set(["choice"]) },
  )
  guard! compiled.slot_for_name("source") is Some(source_slot)
  assert_true(compiled.root_slot() == source_slot)
}

///|
test "compile raises MissingNativeDispatchRule for undeclared dispatch target" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Native("native"),
  }
  let caught = try {
    let _ = @grammar.compile(
      @grammar.GrammarIr::GrammarIr(rules, root="source"),
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Native("native"),
    "emit_only": @grammar.Expr::Emit(1, 10),
  }
  let caught = try {
    let _ = @grammar.compile(
      @grammar.GrammarIr::GrammarIr(rules, root="source"),
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
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Native("z_native"),
    "z_rule": @grammar.Expr::Choice([
      @grammar.Alt::{ starts: @grammar.Pred::HostGuard("z_guard"), body: @grammar.Expr::Empty, },
    ]),
    "a_rule": @grammar.Expr::Choice([
      @grammar.Alt::{ starts: @grammar.Pred::HostGuard("a_guard"), body: @grammar.Expr::Empty, },
    ]),
  }
  let compiled = @grammar.compile(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
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
  guard! compiled.slot_for_name("source") is Some(source_slot)
  guard! compiled.slot_for_name("a_rule") is Some(a_slot)
  guard! compiled.slot_for_name("z_rule") is Some(z_slot)
  assert_true(compiled.root_slot() == source_slot)
  match compiled.rule_snapshot(source_slot).unwrap() {
    @grammar.CompiledExpr::NativeSlot(native_slot) => {
      let targets = compiled.native_dispatch_snapshot(native_slot).unwrap()
      assert_true(targets.length() == 2)
      assert_true(targets[0] == a_slot)
      assert_true(targets[1] == z_slot)
    }
    _ => fail("expected native root")
  }
  match compiled.rule_snapshot(a_slot).unwrap() {
    @grammar.CompiledExpr::Choice(alts) =>
      match alts[0].starts {
        @grammar.CompiledPred::HostGuardSlot(_) => ()
        _ => fail("expected compiled guard slot")
      }
    _ => fail("expected choice rule")
  }
}

///|
test "compiled grammar rejects a rule slot from another grammar" {
  let first : @grammar.CompiledGrammar[Int, Int] = @grammar.compile(
    @grammar.GrammarIr::GrammarIr({ "source": @grammar.Expr::Emit(1, 10) }, root="source"),
  )
  let second : @grammar.CompiledGrammar[Int, Int] = @grammar.compile(
    @grammar.GrammarIr::GrammarIr({ "source": @grammar.Expr::Empty }, root="source"),
  )
  inspect(second.rule_snapshot(first.root_slot()) is None, content="true")
}

///|
test "compiled grammar rejects a native slot from another grammar" {
  let first : @grammar.CompiledGrammar[Int, Int] = @grammar.compile(
    @grammar.GrammarIr::GrammarIr({ "source": @grammar.Expr::Native("first") }, root="source"),
    native_names=Set::Set(["first"]),
  )
  guard! first.rule_snapshot(first.root_slot())
    is Some(@grammar.CompiledExpr::NativeSlot(foreign_slot))
  let second : @grammar.CompiledGrammar[Int, Int] = @grammar.compile(
    @grammar.GrammarIr::GrammarIr({ "source": @grammar.Expr::Native("second") }, root="source"),
    native_names=Set::Set(["second"]),
  )
  inspect(second.native_dispatch_snapshot(foreign_slot) is None, content="true")
}

///|
test "compile rejects direct leading recursion" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = { "source": @grammar.Expr::Ref("source") }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected LeftRecursiveRule(\"source\")")
  }
}

///|
test "compile rejects leading recursion through Choice" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Choice([
      @grammar.Alt::{ starts: @grammar.Pred::Any, body: @grammar.Expr::Ref("source"), },
    ]),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected Choice leading recursion to be rejected")
  }
}

///|
test "compile rejects nullable leading recursion" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Seq([@grammar.Expr::Empty, @grammar.Expr::Ref("source")]),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected nullable leading recursion to be rejected")
  }
}

///|
test "compile rejects leading recursion before a later consuming expression" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::Seq([@grammar.Expr::Ref("source"), @grammar.Expr::Emit(1, 10)]),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected leading recursion before Emit to be rejected")
  }
}

///|
test "compile rejects recursion from a repetition body" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(@grammar.Pred::Any, @grammar.Expr::Ref("source")),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::LeftRecursiveRule("source")) => ()
    _ => fail("expected repetition recursion to be rejected")
  }
}

///|
test "compile rejects structurally zero-progress repetition" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(@grammar.Pred::Any, @grammar.Expr::Empty),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected ZeroProgressRepeat(\"source\")")
  }
}

///|
test "compile rejects ErrorUntil with an always-true stop in repetition" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(
      @grammar.Pred::Any,
      @grammar.Expr::ErrorUntil(@grammar.Pred::Any, "unexpected input"),
    ),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected always-stopping ErrorUntil to be rejected")
  }
}

///|
test "compile rejects ErrorNodeUntil with an always-true stop in repetition" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(
      @grammar.Pred::Any,
      @grammar.Expr::ErrorNodeUntil(1, @grammar.Pred::Any, "unexpected input"),
    ),
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected always-stopping ErrorNodeUntil to be rejected")
  }
}

///|
test "compile accepts ErrorUntil repetition with a conditional stop" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(
      @grammar.Pred::Any,
      @grammar.Expr::ErrorUntil(@grammar.Pred::IsToken(1), "unexpected input"),
    ),
  }
  let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile accepts ErrorNodeUntil repetition with a conditional stop" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(
      @grammar.Pred::Any,
      @grammar.Expr::ErrorNodeUntil(1, @grammar.Pred::IsToken(1), "unexpected input"),
    ),
  }
  let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile ignores unreachable zero-progress repetition" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(
      @grammar.Pred::Not(@grammar.Pred::Not(@grammar.Pred::Not(@grammar.Pred::Any))),
      @grammar.Expr::Empty,
    ),
  }
  let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile rejects zero-progress RepeatTopLevel targets" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatTopLevel(
      "empty",
      starts=@grammar.Pred::Any,
      delim=@grammar.Pred::Any,
      delim_kind=1,
      between_msg="",
      after_msg="",
    ),
    "empty": @grammar.Expr::Empty,
  }
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::ZeroProgressRepeat("source")) => ()
    _ => fail("expected zero-progress RepeatTopLevel to be rejected")
  }
}

///|
test "compile ignores a false-gated RepeatTopLevel recursion" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatTopLevel(
      "source",
      starts=@grammar.Pred::Not(@grammar.Pred::Any),
      delim=@grammar.Pred::Any,
      delim_kind=1,
      between_msg="",
      after_msg="",
    ),
  }
  let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="source"))
}

///|
test "compile leaves opaque Native progress for runtime enforcement" {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = {
    "source": @grammar.Expr::RepeatWhile(@grammar.Pred::Any, @grammar.Expr::Native("native")),
  }
  let compiled = @grammar.compile(
    @grammar.GrammarIr::GrammarIr(rules, root="source"),
    native_names=Set::Set(["native"]),
  )
  match compiled.rule_snapshot(compiled.root_slot()).unwrap() {
    @grammar.CompiledExpr::RepeatWhile(_, @grammar.CompiledExpr::NativeSlot(_)) => ()
    _ => fail("expected opaque Native repeat to compile")
  }
}

///|
/// Build `r0 .. rn` where every rule references its successor twice, so the
/// number of distinct reference *paths* through the grammar is 2^n while the
/// number of distinct `(rule, visiting path)` pairs stays linear.
fn diamond_chain_rules(
  depth : Int,
  leaf : @grammar.Expr[Int, Int],
) -> Map[@grammar.RuleName, @grammar.Expr[Int, Int]] {
  let rules : Map[@grammar.RuleName, @grammar.Expr[Int, Int]] = Map([])
  for i in 0..<depth {
    rules["r\{i}"] = @grammar.Expr::Seq([@grammar.Expr::Ref("r\{i + 1}"), @grammar.Expr::Ref("r\{i + 1}")])
  }
  rules["r\{depth}"] = leaf
  rules
}

///|
/// Progress classification must be memoized on `(rule, visiting path)`. Without
/// the cache each shared reference re-expands its whole subtree, so this grammar
/// takes exponential time to compile (measured: depth 22 ~1s, depth 26 ~65s).
///
/// Depth is 64, not larger: 2^64 paths is already unreachable without the memo,
/// while the memo itself costs O(depth^2) entries, so a deeper chain buys no
/// extra proof and makes this the heaviest compile in the suite.
test "compile classifies progress without re-expanding shared references" {
  let rules = diamond_chain_rules(64, @grammar.Expr::Emit(1, 10))
  let compiled = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="r0"))
  inspect(compiled.names_snapshot().length(), content="65")
}

///|
/// The memo must not lose a cycle that is only reachable through the shared
/// references, so the same shape with a back edge still fails to compile.
test "compile still detects left recursion behind shared references" {
  let rules = diamond_chain_rules(64, @grammar.Expr::Ref("r0"))
  let caught = try {
    let _ = @grammar.compile(@grammar.GrammarIr::GrammarIr(rules, root="r0"))
    None
  } catch {
    e => Some(e)
  }
  match caught {
    Some(@grammar.GrammarCompileError::LeftRecursiveRule("r0")) => ()
    _ => fail("expected LeftRecursiveRule(\"r0\") through shared references")
  }
}
