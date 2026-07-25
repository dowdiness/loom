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
  HostGuardInTokenScan(String)
  LeftRecursiveRule(RuleName)
  ZeroProgressRepeat(RuleName)
} derive(Eq, Debug)

///|
/// Fresh owner identity shared by every rule/native slot in one compilation.
priv struct SlotBrand {
  token : Ref[Unit]
} derive(Debug)

///|
/// Opaque dense slot for an authored grammar rule.
pub struct RuleSlot {
  priv brand : SlotBrand
  priv index : Int
} derive(Debug)

///|
/// Equality is *structural*, over the slot index alone, so that `CompiledExpr`
/// values remain comparable across compilations of the same grammar.
///
/// Ownership is a separate concern and is enforced where it matters — at the
/// API boundary, by `rule_snapshot` and `native_dispatch_snapshot`, which
/// reject a slot carrying a foreign brand. Do not fold the brand into `Eq` to
/// get a second layer: it would make every derived `CompiledExpr` equality
/// compilation-specific, which is not what those derives are for.
pub impl Eq for RuleSlot with fn equal(self, other) {
  self.index == other.index
}

///|
pub impl Compare for RuleSlot with fn compare(self, other) {
  self.index.compare(other.index)
}

///|
/// Opaque dense slot for a declared native.
pub struct NativeSlot {
  priv brand : SlotBrand
  priv index : Int
} derive(Debug)

///|
/// Structural, like `RuleSlot`'s — see the note there. Native-capability
/// ownership is enforced by the per-native brand check in
/// `NativeDispatcher::try_rule`, not here.
pub impl Eq for NativeSlot with fn equal(self, other) {
  self.index == other.index
}

///|
pub impl Compare for NativeSlot with fn compare(self, other) {
  self.index.compare(other.index)
}

///|
/// Opaque dense slot for a declared host guard.
pub struct GuardSlot {
  priv index : Int
} derive(Eq, Debug, Compare)

///|
fn SlotBrand::same(self : SlotBrand, other : SlotBrand) -> Bool {
  physical_equal(self.token, other.token)
}

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
  priv slot_brand : SlotBrand
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
) -> Array[RuleSlot]? {
  if !self.slot_brand.same(slot.brand) ||
    slot.index < 0 ||
    slot.index >= self.native_dispatch.length() {
    return None
  }
  Some(self.native_dispatch[slot.index].copy())
}

///|
/// Deep snapshot of one compiled rule body. Generic payloads are not cloned.
pub fn[T, K] CompiledGrammar::rule_snapshot(
  self : Self[T, K],
  slot : RuleSlot,
) -> CompiledExpr[T, K]? {
  if !self.slot_brand.same(slot.brand) ||
    slot.index < 0 ||
    slot.index >= self.rules.length() {
    return None
  }
  Some(clone_compiled_expr(self.rules[slot.index]))
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
  let slot_brand = SlotBrand::{ token: Ref::Ref(()) }
  let rule_slots : Map[RuleName, RuleSlot] = Map([])
  for i, name in names {
    rule_slots[name] = RuleSlot::{ brand: slot_brand, index: i }
  }

  let ordered_natives : Array[RuleName] = native_names.iter().collect()
  ordered_natives.sort()
  let native_slots : Map[RuleName, NativeSlot] = Map([])
  for i, name in ordered_natives {
    native_slots[name] = NativeSlot::{ brand: slot_brand, index: i }
  }

  let ordered_guards : Array[RuleName] = guard_names.iter().collect()
  ordered_guards.sort()
  let guard_slots : Map[RuleName, GuardSlot] = Map([])
  for i, name in ordered_guards {
    guard_slots[name] = GuardSlot::{ index: i }
  }

  for native_name, targets in native_rule_refs {
    if !native_names.contains(native_name) {
      raise MissingNative(native_name)
    }
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
  let progress_memo : ProgressMemo = Map([])
  for i, expr in rules {
    let owner = names[i]
    guard rule_slots.get(owner) is Some(owner_slot)
    match progress_of(expr, rules, [owner_slot], progress_memo) {
      Cycle(_) => raise LeftRecursiveRule(owner)
      _ => ()
    }
    validate_progress(expr, owner, owner_slot, rules, progress_memo)
  }
  {
    names,
    rules,
    root: RuleSlot::{ brand: slot_brand, index: 0 },
    native_names: ordered_natives,
    guard_names: ordered_guards,
    native_dispatch,
    rule_slots,
    slot_brand,
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
/// Reject context-sensitive guards where the token callback may inspect a
/// lookahead token while the ParserContext remains at the current token.
fn[T] lower_token_scan_pred(
  pred : Pred[T],
  guard_slots : Map[RuleName, GuardSlot],
  position : String,
) -> CompiledPred[T] raise GrammarCompileError {
  if pred_contains_host_guard(pred) {
    raise HostGuardInTokenScan(position)
  }
  lower_pred(pred, guard_slots)
}

///|
fn[T] pred_contains_host_guard(pred : Pred[T]) -> Bool {
  match pred {
    HostGuard(_) => true
    Not(inner) => pred_contains_host_guard(inner)
    All(left, right) =>
      pred_contains_host_guard(left) || pred_contains_host_guard(right)
    Any | IsToken(_) | OneOf(_) => false
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
        skip=skip.map(pair => {
          (
            lower_token_scan_pred(pair.0, guard_slots, "PrattBinary.skip"),
            pair.1,
          )
        }),
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
        lower_token_scan_pred(skip, guard_slots, "ExpectSkip.skip"),
        skip_kind,
        expected,
        kind,
      )
    ConsumeGated(skip, skip_kind, look) =>
      CompiledExpr::ConsumeGated(
        lower_token_scan_pred(skip, guard_slots, "ConsumeGated.skip"),
        skip_kind,
        lower_token_scan_pred(look, guard_slots, "ConsumeGated.look"),
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
/// Abstract classification of "does evaluating this expression consume input?",
/// computed over the compiled rule table before any parsing happens.
///
/// The lattice is about *evidence*, not about behaviour, and the two are easy
/// to confuse. Nothing here claims an expression cannot consume input; the
/// question is whether the compiler can prove it must.
///
/// - `NoProgressEvidence` — the analysis found nothing that must consume a
///   token. This is *not* "never consumes": `RepeatWhile` and `RepeatTopLevel`
///   land here because zero iterations is possible, and they may otherwise
///   consume the whole input. It is the rejecting fact, because a repetition
///   body that may consume nothing can spin on an unchanged cursor.
/// - `RuntimeDependent` — consumption exists but is decided by the token
///   stream (`Emit`, `Expect`, a `Choice` whose arms disagree) or by opaque
///   host code (`Native`, host guards). Deliberately accepted: the interpreter's
///   cursor checks and rule stack enforce progress for these at parse time.
/// - `Cycle(slot)` — a path that consumes nothing re-enters `slot`, so the
///   grammar is left-recursive. The payload records where the cycle was
///   observed; it depends on traversal order and no caller reads it.
///
/// The public errors keep the vocabulary of the defect rather than of the
/// lattice: `NoProgressEvidence` on a repetition raises `ZeroProgressRepeat`,
/// and `Cycle` raises `LeftRecursiveRule`.
priv enum ProgressFact {
  NoProgressEvidence
  RuntimeDependent
  Cycle(RuleSlot)
}

///|
/// Cache of already-classified `(rule slot, active visiting path)` pairs.
type ProgressMemo = Map[String, ProgressFact]

///|
/// Identify one `progress_of` call on a rule body. The separator keeps adjacent
/// indices unambiguous, so distinct paths never share a key.
fn progress_key(slot : RuleSlot, visiting : Array[RuleSlot]) -> String {
  let buf = StringBuilder::new()
  buf.write_string(slot.index.to_string())
  for current in visiting {
    buf.write_string("|")
    buf.write_string(current.index.to_string())
  }
  buf.to_string()
}

///|
/// Memoized `progress_of` for one rule body under an active visiting path.
///
/// `progress_of` is a pure function of `(expr, rules, visiting)` and `rules` is
/// fixed for one compilation, so caching on `(slot, visiting)` is exact. Without
/// the cache, a rule referenced twice from the same position re-expands its
/// whole subtree twice, which is exponential in reference depth.
fn[T, K] progress_of_rule(
  slot : RuleSlot,
  rules : Array[CompiledExpr[T, K]],
  visiting : Array[RuleSlot],
  memo : ProgressMemo,
) -> ProgressFact {
  let key = progress_key(slot, visiting)
  match memo.get(key) {
    Some(fact) => fact
    None => {
      let fact = progress_of(rules[slot.index], rules, visiting, memo)
      memo[key] = fact
      fact
    }
  }
}

///|
fn[T, K] progress_of(
  expr : CompiledExpr[T, K],
  rules : Array[CompiledExpr[T, K]],
  visiting : Array[RuleSlot],
  memo : ProgressMemo,
) -> ProgressFact {
  match expr {
    Empty | EmitError(_) | Fail(_) | DiagnoseIf(_, _) => NoProgressEvidence
    Emit(_, _) | Expect(_, _) | EmitOr(_, _, _) => RuntimeDependent
    Node(_, body) => progress_of(body, rules, visiting, memo)
    RefSlot(slot) =>
      if visiting.iter().any(current => current == slot) {
        Cycle(slot)
      } else {
        let next = visiting.copy()
        next.push(slot)
        progress_of_rule(slot, rules, next, memo)
      }
    NativeSlot(_) => RuntimeDependent
    Choice(alts) => {
      let mut saw_runtime_dependent = false
      let mut cycle : RuleSlot? = None
      for alt in alts {
        if definitely_false(alt.starts) {
          continue
        }
        match progress_of(alt.body, rules, visiting, memo) {
          NoProgressEvidence => ()
          RuntimeDependent => saw_runtime_dependent = true
          Cycle(slot) => cycle = Some(slot)
        }
        if definitely_true(alt.starts) {
          break
        }
      }
      match cycle {
        Some(slot) => Cycle(slot)
        None =>
          if saw_runtime_dependent {
            RuntimeDependent
          } else {
            NoProgressEvidence
          }
      }
    }
    RepeatTopLevel(slot, starts~, ..) =>
      if definitely_false(starts) {
        NoProgressEvidence
      } else {
        match progress_of_rule(slot, rules, visiting, memo) {
          Cycle(cycle_slot) => Cycle(cycle_slot)
          _ => NoProgressEvidence
        }
      }
    Seq(exprs) => {
      let mut saw_runtime_dependent = false
      for part in exprs {
        match progress_of(part, rules, visiting, memo) {
          NoProgressEvidence => ()
          RuntimeDependent => saw_runtime_dependent = true
          Cycle(slot) => {
            if saw_runtime_dependent {
              return RuntimeDependent
            }
            return Cycle(slot)
          }
        }
      }
      if saw_runtime_dependent {
        RuntimeDependent
      } else {
        NoProgressEvidence
      }
    }
    PrattApp(slot, _, _) | PrattBinary(slot, _, _, ..) =>
      match progress_of_rule(slot, rules, visiting, memo) {
        Cycle(cycle_slot) => Cycle(cycle_slot)
        _ => RuntimeDependent
      }
    RepeatWhile(_, _) => NoProgressEvidence
    WrapIfNext(_, _, body) => progress_of(body, rules, visiting, memo)
    ErrorUntil(stop, _) =>
      if definitely_true(stop) {
        NoProgressEvidence
      } else {
        RuntimeDependent
      }
    ExpectSkip(_, _, _, _) => RuntimeDependent
    ConsumeGated(_, _, _) => RuntimeDependent
    RequireSep(_, _, _, ..) => RuntimeDependent
    ErrorNodeUntil(_, stop, _) =>
      if definitely_true(stop) {
        NoProgressEvidence
      } else {
        RuntimeDependent
      }
    ManualNewlineAppExpr => RuntimeDependent
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
  memo : ProgressMemo,
) -> Unit raise GrammarCompileError {
  match expr {
    RepeatWhile(pred, body) => {
      if definitely_false(pred) {
        return ()
      }
      match progress_of(body, rules, [owner_slot], memo) {
        NoProgressEvidence => raise ZeroProgressRepeat(owner)
        Cycle(_) => raise LeftRecursiveRule(owner)
        _ => ()
      }
      validate_progress(body, owner, owner_slot, rules, memo)
    }
    Node(_, body) | WrapIfNext(_, _, body) =>
      validate_progress(body, owner, owner_slot, rules, memo)
    Choice(alts) =>
      for alt in alts {
        if !definitely_false(alt.starts) {
          validate_progress(alt.body, owner, owner_slot, rules, memo)
        }
        if definitely_true(alt.starts) {
          break
        }
      }
    Seq(exprs) =>
      for part in exprs {
        validate_progress(part, owner, owner_slot, rules, memo)
      }
    RepeatTopLevel(slot, starts~, ..) =>
      if !definitely_false(starts) {
        match progress_of_rule(slot, rules, [owner_slot], memo) {
          NoProgressEvidence => raise ZeroProgressRepeat(owner)
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
