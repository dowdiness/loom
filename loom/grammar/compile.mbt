///|
/// Raised by `compile` when the authored grammar is malformed. `DuplicateRule`
/// is intentionally absent: the rule namespace is a `Map`, so duplicate names
/// cannot occur by construction.
pub suberror GrammarCompileError {
  MissingRoot(RuleName)
  MissingRef(RuleName)
  MissingFragment(RuleName)
  MissingNative(RuleName)
  MissingNativeDispatchRule(RuleName, RuleName)
  NativeDispatchTargetNotChoice(RuleName, RuleName)
  AmbiguousRule(RuleName)
  MissingHostGuard(RuleName)
  AmbiguousGuard(RuleName)
  LeftRecursiveRule(RuleName)
  ZeroProgressRepeat(RuleName)
} derive(Eq, Debug)

///|
/// Opaque dense slot for an authored grammar rule.
pub struct RuleSlot {
  priv index : Int
} derive(Eq, Debug, Compare)

///|
/// Opaque dense slot for a declared native.
pub struct NativeSlot {
  priv index : Int
} derive(Eq, Debug, Compare)

///|
/// Opaque dense slot for a declared host guard.
pub struct GuardSlot {
  priv index : Int
} derive(Eq, Debug, Compare)

///|
/// Compiled, context-aware predicate snapshot.
pub enum CompiledPred[T] {
  Any
  IsToken(T)
  OneOf(Array[T])
  Not(CompiledPred[T])
  All(CompiledPred[T], CompiledPred[T])
  HostGuardSlot(GuardSlot)
} derive(Eq, Debug)

///|
/// Compiled form of `Expr`; all names and predicates are resolved.
pub enum CompiledExpr[T, K] {
  Node(K, CompiledExpr[T, K])
  Emit(T, K)
  Expect(T, K)
  RefSlot(RuleSlot)
  NativeSlot(NativeSlot)
  Choice(Array[CompiledAlt[T, K]])
  RepeatTopLevel(
    RuleSlot,
    starts~ : CompiledPred[T],
    delim~ : CompiledPred[T],
    delim_kind~ : K,
    between_msg~ : String,
    after_msg~ : String
  )
  Seq(Array[CompiledExpr[T, K]])
  PrattApp(RuleSlot, K, CompiledPred[T])
  PrattBinary(RuleSlot, K, Array[(T, K)], skip~ : (CompiledPred[T], K)?)
  RepeatWhile(CompiledPred[T], CompiledExpr[T, K])
  WrapIfNext(K, CompiledPred[T], CompiledExpr[T, K])
  EmitError(String)
  ErrorUntil(CompiledPred[T], String)
  Fail(String)
  EmitOr(T, K, String)
  DiagnoseIf(CompiledPred[T], String)
  ExpectSkip(CompiledPred[T], K, T, K)
  ConsumeGated(CompiledPred[T], K, CompiledPred[T])
  RequireSep(
    Array[(T, K)],
    CompiledPred[T],
    CompiledPred[T],
    msg_alt~ : String,
    msg_else~ : String
  )
  ErrorNodeUntil(K, CompiledPred[T], String)
  ManualNewlineAppExpr
  Empty
} derive(Eq, Debug)

///|
pub struct CompiledAlt[T, K] {
  starts : CompiledPred[T]
  body : CompiledExpr[T, K]
} derive(Eq, Debug)

///|
/// Compiler-owned executable storage. Its fields are intentionally private.
pub struct CompiledGrammar[T, K] {
  priv names : Array[RuleName]
  priv rules : Array[CompiledExpr[T, K]]
  priv root : RuleSlot
  priv native_names : Array[RuleName]
  priv guard_names : Array[RuleName]
  priv native_dispatch : Array[Array[RuleSlot]]
  priv rule_slots : Map[RuleName, RuleSlot]
}

///|
/// Entry slot of the compiled grammar.
pub fn[T, K] CompiledGrammar::root_slot(self : Self[T, K]) -> RuleSlot {
  self.root
}

///|
/// Fresh snapshot of the rule names in deterministic slot order.
pub fn[T, K] CompiledGrammar::names_snapshot(
  self : Self[T, K],
) -> Array[RuleName] {
  self.names.copy()
}

///|
/// Resolve an authored rule name without exposing its integer slot.
pub fn[T, K] CompiledGrammar::slot_for_name(
  self : Self[T, K],
  name : RuleName,
) -> RuleSlot? {
  self.rule_slots.get(name)
}

///|
/// Fresh snapshot of native names in deterministic slot order.
pub fn[T, K] CompiledGrammar::native_names_snapshot(
  self : Self[T, K],
) -> Array[RuleName] {
  self.native_names.copy()
}

///|
/// Fresh snapshot of guard names in deterministic slot order.
pub fn[T, K] CompiledGrammar::guard_names_snapshot(
  self : Self[T, K],
) -> Array[RuleName] {
  self.guard_names.copy()
}

///|
/// Fresh snapshot of the native's resolved rule dependencies.
pub fn[T, K] CompiledGrammar::native_dispatch_snapshot(
  self : Self[T, K],
  slot : NativeSlot,
) -> Array[RuleSlot] {
  self.native_dispatch[slot.index].copy()
}

///|
/// Deep snapshot of one compiled rule body. Generic payloads are not cloned.
pub fn[T, K] CompiledGrammar::rule_snapshot(
  self : Self[T, K],
  slot : RuleSlot,
) -> CompiledExpr[T, K] {
  clone_compiled_expr(self.rules[slot.index])
}

///|
/// Compile authored grammar into deterministic, resolved slot storage.
pub fn[T, K] compile(
  ir : GrammarIr[T, K],
  native_names? : Set[RuleName] = Set::Set([]),
  guard_names? : Set[RuleName] = Set::Set([]),
  native_rule_refs? : Map[RuleName, Set[RuleName]] = Map([]),
) -> CompiledGrammar[T, K] raise GrammarCompileError {
  guard ir.rules.get(ir.root) is Some(_) else { raise MissingRoot(ir.root) }
  for name in ir.rules.keys() {
    if native_names.contains(name) {
      raise AmbiguousRule(name)
    }
    if guard_names.contains(name) {
      raise AmbiguousGuard(name)
    }
  }

  let others : Array[RuleName] = ir.rules
    .keys()
    .filter(n => n != ir.root)
    .collect()
  others.sort()
  let names : Array[RuleName] = [ir.root, ..others]
  let rule_slots : Map[RuleName, RuleSlot] = Map([])
  for i, name in names {
    rule_slots[name] = RuleSlot::{ index: i }
  }

  let ordered_natives : Array[RuleName] = native_names.iter().collect()
  ordered_natives.sort()
  let native_slots : Map[RuleName, NativeSlot] = Map([])
  for i, name in ordered_natives {
    native_slots[name] = NativeSlot::{ index: i }
  }

  let ordered_guards : Array[RuleName] = guard_names.iter().collect()
  ordered_guards.sort()
  let guard_slots : Map[RuleName, GuardSlot] = Map([])
  for i, name in ordered_guards {
    guard_slots[name] = GuardSlot::{ index: i }
  }

  for native_name in native_rule_refs.keys() {
    if !native_names.contains(native_name) {
      raise MissingNative(native_name)
    }
    guard native_rule_refs.get(native_name) is Some(targets) else { () }
    for target_name in targets {
      guard ir.rules.get(target_name) is Some(target_expr) else {
        raise MissingNativeDispatchRule(native_name, target_name)
      }
      match target_expr {
        Choice(_) => ()
        _ => raise NativeDispatchTargetNotChoice(native_name, target_name)
      }
    }
  }

  let native_dispatch : Array[Array[RuleSlot]] = []
  for native_name in ordered_natives {
    let resolved : Array[RuleSlot] = []
    match native_rule_refs.get(native_name) {
      Some(targets) =>
        for target_name in targets {
          resolved.push(resolve(target_name, rule_slots))
        }
      None => ()
    }
    resolved.sort_by((left, right) => left.index - right.index)
    native_dispatch.push(resolved)
  }

  let rules : Array[CompiledExpr[T, K]] = []
  for name in names {
    guard ir.rules.get(name) is Some(expr)
    rules.push(lower(expr, rule_slots, native_slots, guard_slots))
  }
  for i, expr in rules {
    let owner = names[i]
    match progress_of(expr, rules, [RuleSlot::{ index: i }]) {
      Cycle(_) => raise LeftRecursiveRule(owner)
      _ => ()
    }
    validate_progress(expr, owner, RuleSlot::{ index: i }, rules)
  }
  {
    names,
    rules,
    root: RuleSlot::{ index: 0 },
    native_names: ordered_natives,
    guard_names: ordered_guards,
    native_dispatch,
    rule_slots,
  }
}

///|
/// Resolve a rule name to an opaque slot.
fn resolve(
  name : RuleName,
  slots : Map[RuleName, RuleSlot],
) -> RuleSlot raise GrammarCompileError {
  match slots.get(name) {
    Some(slot) => slot
    None =>
      if name.has_prefix("__loom_frag__") {
        raise MissingFragment(name)
      } else {
        raise MissingRef(name)
      }
  }
}

///|
/// Resolve a declared native name to its opaque slot.
fn resolve_native(
  name : RuleName,
  slots : Map[RuleName, NativeSlot],
) -> NativeSlot raise GrammarCompileError {
  match slots.get(name) {
    Some(slot) => slot
    None => raise MissingNative(name)
  }
}

///|
/// Lower every authored predicate to a context-aware compiled predicate.
fn[T] lower_pred(
  pred : Pred[T],
  guard_slots : Map[RuleName, GuardSlot],
) -> CompiledPred[T] raise GrammarCompileError {
  match pred {
    Any => CompiledPred::Any
    IsToken(token) => CompiledPred::IsToken(token)
    OneOf(tokens) => CompiledPred::OneOf(tokens.copy())
    Not(inner) => CompiledPred::Not(lower_pred(inner, guard_slots))
    All(left, right) =>
      CompiledPred::All(
        lower_pred(left, guard_slots),
        lower_pred(right, guard_slots),
      )
    HostGuard(name) =>
      match guard_slots.get(name) {
        Some(slot) => CompiledPred::HostGuardSlot(slot)
        None => raise MissingHostGuard(name)
      }
  }
}

///|
/// Lower one authored expression, resolving every nested reference.
fn[T, K] lower(
  expr : Expr[T, K],
  rule_slots : Map[RuleName, RuleSlot],
  native_slots : Map[RuleName, NativeSlot],
  guard_slots : Map[RuleName, GuardSlot],
) -> CompiledExpr[T, K] raise GrammarCompileError {
  match expr {
    Node(k, body) =>
      CompiledExpr::Node(k, lower(body, rule_slots, native_slots, guard_slots))
    Emit(t, k) => CompiledExpr::Emit(t, k)
    Expect(t, k) => CompiledExpr::Expect(t, k)
    Ref(name) => CompiledExpr::RefSlot(resolve(name, rule_slots))
    Native(name) => CompiledExpr::NativeSlot(resolve_native(name, native_slots))
    Choice(alts) => {
      let compiled : Array[CompiledAlt[T, K]] = []
      for alt in alts {
        compiled.push(CompiledAlt::{
          starts: lower_pred(alt.starts, guard_slots),
          body: lower(alt.body, rule_slots, native_slots, guard_slots),
        })
      }
      CompiledExpr::Choice(compiled)
    }
    RepeatTopLevel(name, starts~, delim~, delim_kind~, between_msg~, after_msg~) =>
      CompiledExpr::RepeatTopLevel(
        resolve(name, rule_slots),
        starts=lower_pred(starts, guard_slots),
        delim=lower_pred(delim, guard_slots),
        delim_kind~,
        between_msg~,
        after_msg~,
      )
    Seq(exprs) => {
      let compiled : Array[CompiledExpr[T, K]] = []
      for expr in exprs {
        compiled.push(lower(expr, rule_slots, native_slots, guard_slots))
      }
      CompiledExpr::Seq(compiled)
    }
    PrattApp(name, k, starts) =>
      CompiledExpr::PrattApp(
        resolve(name, rule_slots),
        k,
        lower_pred(starts, guard_slots),
      )
    PrattBinary(name, k, ops, skip~) =>
      CompiledExpr::PrattBinary(
        resolve(name, rule_slots),
        k,
        ops.copy(),
        skip=skip.map(pair => (lower_pred(pair.0, guard_slots), pair.1)),
      )
    RepeatWhile(pred, body) =>
      CompiledExpr::RepeatWhile(
        lower_pred(pred, guard_slots),
        lower(body, rule_slots, native_slots, guard_slots),
      )
    WrapIfNext(k, pred, body) =>
      CompiledExpr::WrapIfNext(
        k,
        lower_pred(pred, guard_slots),
        lower(body, rule_slots, native_slots, guard_slots),
      )
    EmitError(msg) => CompiledExpr::EmitError(msg)
    ErrorUntil(pred, msg) =>
      CompiledExpr::ErrorUntil(lower_pred(pred, guard_slots), msg)
    Fail(msg) => CompiledExpr::Fail(msg)
    EmitOr(t, k, msg) => CompiledExpr::EmitOr(t, k, msg)
    DiagnoseIf(pred, msg) =>
      CompiledExpr::DiagnoseIf(lower_pred(pred, guard_slots), msg)
    ExpectSkip(skip, skip_kind, expected, kind) =>
      CompiledExpr::ExpectSkip(
        lower_pred(skip, guard_slots),
        skip_kind,
        expected,
        kind,
      )
    ConsumeGated(skip, skip_kind, look) =>
      CompiledExpr::ConsumeGated(
        lower_pred(skip, guard_slots),
        skip_kind,
        lower_pred(look, guard_slots),
      )
    RequireSep(delims, stop, alt, msg_alt~, msg_else~) =>
      CompiledExpr::RequireSep(
        delims.copy(),
        lower_pred(stop, guard_slots),
        lower_pred(alt, guard_slots),
        msg_alt~,
        msg_else~,
      )
    ErrorNodeUntil(kind, stop, msg) =>
      CompiledExpr::ErrorNodeUntil(kind, lower_pred(stop, guard_slots), msg)
    ManualNewlineAppExpr => CompiledExpr::ManualNewlineAppExpr
    Empty => CompiledExpr::Empty
  }
}

///|
/// Conservative progress classification used by compile-time safety checks.
/// `Unknown` is intentionally accepted: context-sensitive token consumption and
/// opaque native callbacks require a runtime or host-level progress contract.
priv enum ProgressFact {
  Never
  Unknown
  Cycle(RuleSlot)
}

///|
fn[T, K] progress_of(
  expr : CompiledExpr[T, K],
  rules : Array[CompiledExpr[T, K]],
  visiting : Array[RuleSlot],
) -> ProgressFact {
  match expr {
    Empty | EmitError(_) | Fail(_) | DiagnoseIf(_, _) => Never
    Emit(_, _) | Expect(_, _) | EmitOr(_, _, _) => Unknown
    Node(_, body) => progress_of(body, rules, visiting)
    RefSlot(slot) =>
      if visiting.iter().any(current => current == slot) {
        Cycle(slot)
      } else {
        let next = visiting.copy()
        next.push(slot)
        progress_of(rules[slot.index], rules, next)
      }
    NativeSlot(_) => Unknown
    Choice(alts) => {
      let mut saw_unknown = false
      let mut cycle : RuleSlot? = None
      for alt in alts {
        if definitely_false(alt.starts) {
          continue
        }
        match progress_of(alt.body, rules, visiting) {
          Never => ()
          Unknown => saw_unknown = true
          Cycle(slot) => cycle = Some(slot)
        }
        if definitely_true(alt.starts) {
          break
        }
      }
      match cycle {
        Some(slot) => Cycle(slot)
        None => if saw_unknown { Unknown } else { Never }
      }
    }
    RepeatTopLevel(slot, starts~, ..) =>
      if definitely_false(starts) {
        Never
      } else {
        match progress_of(rules[slot.index], rules, visiting) {
          Cycle(cycle_slot) => Cycle(cycle_slot)
          _ => Never
        }
      }
    Seq(exprs) => {
      let mut saw_unknown = false
      let mut cycle : RuleSlot? = None
      for part in exprs {
        match progress_of(part, rules, visiting) {
          Never => ()
          Unknown => saw_unknown = true
          Cycle(slot) => {
            if saw_unknown {
              return Unknown
            }
            cycle = Some(slot)
          }
        }
      }
      if saw_unknown {
        Unknown
      } else {
        match cycle {
          Some(slot) => Cycle(slot)
          None => Never
        }
      }
    }
    PrattApp(slot, _, _) | PrattBinary(slot, _, _, ..) =>
      match progress_of(rules[slot.index], rules, visiting) {
        Cycle(cycle_slot) => Cycle(cycle_slot)
        _ => Unknown
      }
    RepeatWhile(_, _) => Never
    WrapIfNext(_, _, body) => progress_of(body, rules, visiting)
    ErrorUntil(stop, _) => if definitely_true(stop) { Never } else { Unknown }
    ExpectSkip(_, _, _, _) => Unknown
    ConsumeGated(_, _, _) => Unknown
    RequireSep(_, _, _, ..) => Unknown
    ErrorNodeUntil(_, stop, _) =>
      if definitely_true(stop) {
        Never
      } else {
        Unknown
      }
    ManualNewlineAppExpr => Unknown
  }
}

///|
fn[T] definitely_true(pred : CompiledPred[T]) -> Bool {
  match pred {
    Any => true
    Not(inner) => definitely_false(inner)
    All(left, right) => definitely_true(left) && definitely_true(right)
    _ => false
  }
}

///|
/// Decide only the predicate cases that are provably unable to enter.
fn[T] definitely_false(pred : CompiledPred[T]) -> Bool {
  match pred {
    OneOf(tokens) => tokens.is_empty()
    Not(inner) => definitely_true(inner)
    All(left, right) => definitely_false(left) || definitely_false(right)
    _ => false
  }
}

///|
fn[T, K] validate_progress(
  expr : CompiledExpr[T, K],
  owner : RuleName,
  owner_slot : RuleSlot,
  rules : Array[CompiledExpr[T, K]],
) -> Unit raise GrammarCompileError {
  match expr {
    RepeatWhile(pred, body) => {
      if definitely_false(pred) {
        return ()
      }
      match progress_of(body, rules, [owner_slot]) {
        Never => raise ZeroProgressRepeat(owner)
        Cycle(_) => raise LeftRecursiveRule(owner)
        _ => ()
      }
      validate_progress(body, owner, owner_slot, rules)
    }
    Node(_, body) | WrapIfNext(_, _, body) =>
      validate_progress(body, owner, owner_slot, rules)
    Choice(alts) =>
      for alt in alts {
        if !definitely_false(alt.starts) {
          validate_progress(alt.body, owner, owner_slot, rules)
        }
        if definitely_true(alt.starts) {
          break
        }
      }
    Seq(exprs) =>
      for part in exprs {
        validate_progress(part, owner, owner_slot, rules)
      }
    RepeatTopLevel(slot, starts~, ..) =>
      if !definitely_false(starts) {
        match progress_of(rules[slot.index], rules, [owner_slot]) {
          Never => raise ZeroProgressRepeat(owner)
          Cycle(_) => raise LeftRecursiveRule(owner)
          _ => ()
        }
      }
    PrattApp(_, _, _)
    | PrattBinary(_, _, _, ..)
    | Empty
    | Emit(_, _)
    | Expect(_, _)
    | RefSlot(_)
    | NativeSlot(_)
    | EmitError(_)
    | ErrorUntil(_, _)
    | Fail(_)
    | EmitOr(_, _, _)
    | DiagnoseIf(_, _)
    | ExpectSkip(_, _, _, _)
    | ConsumeGated(_, _, _)
    | RequireSep(_, _, _, ..)
    | ErrorNodeUntil(_, _, _)
    | ManualNewlineAppExpr => ()
  }
}

///|
/// Deep-copy a compiled predicate snapshot.
fn[T] clone_compiled_pred(pred : CompiledPred[T]) -> CompiledPred[T] {
  match pred {
    Any => Any
    IsToken(token) => IsToken(token)
    OneOf(tokens) => OneOf(tokens.copy())
    Not(inner) => Not(clone_compiled_pred(inner))
    All(left, right) =>
      All(clone_compiled_pred(left), clone_compiled_pred(right))
    HostGuardSlot(slot) => HostGuardSlot(slot)
  }
}

///|
/// Deep-copy a compiled expression snapshot without cloning payload values.
fn[T, K] clone_compiled_expr(expr : CompiledExpr[T, K]) -> CompiledExpr[T, K] {
  match expr {
    Node(kind, body) => Node(kind, clone_compiled_expr(body))
    Emit(token, kind) => Emit(token, kind)
    Expect(token, kind) => Expect(token, kind)
    RefSlot(slot) => RefSlot(slot)
    NativeSlot(slot) => NativeSlot(slot)
    Choice(alts) =>
      Choice(
        alts.map(alt => CompiledAlt::{
          starts: clone_compiled_pred(alt.starts),
          body: clone_compiled_expr(alt.body),
        }),
      )
    RepeatTopLevel(slot, starts~, delim~, delim_kind~, between_msg~, after_msg~) =>
      RepeatTopLevel(
        slot,
        starts=clone_compiled_pred(starts),
        delim=clone_compiled_pred(delim),
        delim_kind~,
        between_msg~,
        after_msg~,
      )
    Seq(exprs) => Seq(exprs.map(expr => clone_compiled_expr(expr)))
    PrattApp(slot, kind, starts) =>
      PrattApp(slot, kind, clone_compiled_pred(starts))
    PrattBinary(slot, kind, ops, skip~) =>
      PrattBinary(
        slot,
        kind,
        ops.copy(),
        skip=skip.map(pair => (clone_compiled_pred(pair.0), pair.1)),
      )
    RepeatWhile(pred, body) =>
      RepeatWhile(clone_compiled_pred(pred), clone_compiled_expr(body))
    WrapIfNext(kind, pred, body) =>
      WrapIfNext(kind, clone_compiled_pred(pred), clone_compiled_expr(body))
    EmitError(msg) => EmitError(msg)
    ErrorUntil(pred, msg) => ErrorUntil(clone_compiled_pred(pred), msg)
    Fail(msg) => Fail(msg)
    EmitOr(token, kind, msg) => EmitOr(token, kind, msg)
    DiagnoseIf(pred, msg) => DiagnoseIf(clone_compiled_pred(pred), msg)
    ExpectSkip(skip, skip_kind, expected, kind) =>
      ExpectSkip(clone_compiled_pred(skip), skip_kind, expected, kind)
    ConsumeGated(skip, skip_kind, look) =>
      ConsumeGated(
        clone_compiled_pred(skip),
        skip_kind,
        clone_compiled_pred(look),
      )
    RequireSep(delims, stop, alt, msg_alt~, msg_else~) =>
      RequireSep(
        delims.copy(),
        clone_compiled_pred(stop),
        clone_compiled_pred(alt),
        msg_alt~,
        msg_else~,
      )
    ErrorNodeUntil(kind, stop, msg) =>
      ErrorNodeUntil(kind, clone_compiled_pred(stop), msg)
    ManualNewlineAppExpr => ManualNewlineAppExpr
    Empty => Empty
  }
}
