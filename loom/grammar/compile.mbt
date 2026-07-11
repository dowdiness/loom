///|
/// Raised by `compile` when the authored grammar is malformed. `DuplicateRule`
/// is intentionally absent: the rule namespace is a `Map`, so duplicate names
/// cannot occur by construction.
pub suberror GrammarCompileError {
  MissingRoot(RuleName)
  MissingRef(RuleName)
  MissingFragment(RuleName)
  /// `Native(name)` appeared but `name` is absent from `compile`'s
  /// `native_names` argument — resolved and validated at compile time, never
  /// mid-parse, mirroring `MissingRef`.
  MissingNative(RuleName)
  /// `name` is declared in both `ir.rules` and `native_names` — a name must be
  /// either a grammar rule or a native, never both. Checked globally over the
  /// whole namespace, not only for names a `Native(...)` node reaches.
  AmbiguousRule(RuleName)
  /// `HostGuard(name)` appeared but `name` is absent from `compile`'s
  /// `guard_names` argument — resolved and validated at compile time, never
  /// mid-parse, mirroring `MissingNative`.
  MissingHostGuard(RuleName)
  /// `name` is declared in both `ir.rules` and `guard_names` — a name must be
  /// either a grammar rule or a host guard, never both. Checked globally over
  /// the whole namespace, not only for names a `HostGuard(...)` node reaches.
  AmbiguousGuard(RuleName)
} derive(Eq, Debug)

///|
/// The compiled form of `Expr`: every `Ref(name)` is resolved to a dense
/// `RefSlot(Int)`, so the interpreter's per-edit `Ref` dispatch is an array
/// index rather than a map lookup.
pub enum CompiledExpr[T, K] {
  Node(K, CompiledExpr[T, K])
  Emit(T, K)
  Expect(T, K)
  RefSlot(Int)
  NativeRef(RuleName)
  Choice(Array[CompiledAlt[T, K]])
  RepeatTopLevel(
    Int,
    starts~ : Pred[T],
    delim~ : Pred[T],
    delim_kind~ : K,
    between_msg~ : String,
    after_msg~ : String
  )
  Seq(Array[CompiledExpr[T, K]])
  PrattApp(Int, K, Pred[T])
  PrattBinary(Int, K, Array[(T, K)], skip~ : (Pred[T], K)?)
  RepeatWhile(Pred[T], CompiledExpr[T, K])
  WrapIfNext(K, Pred[T], CompiledExpr[T, K])
  EmitError(String)
  ErrorUntil(Pred[T], String)
  Fail(String)
  EmitOr(T, K, String)
  DiagnoseIf(Pred[T], String)
  ExpectSkip(Pred[T], K, T, K)
  ConsumeGated(Pred[T], K, Pred[T])
  RequireSep(
    Array[(T, K)],
    Pred[T],
    Pred[T],
    msg_alt~ : String,
    msg_else~ : String
  )
  ErrorNodeUntil(K, Pred[T], String)
  ManualNewlineAppExpr
  Empty
} derive(Eq, Debug)

///|
pub struct CompiledAlt[T, K] {
  starts : Pred[T]
  body : CompiledExpr[T, K]
} derive(Eq, Debug)

///|
/// A grammar with rules in dense slot order. `names[i]` is the source name of
/// slot `i`; `rules[i]` is its compiled body; `root` is the entry slot.
pub struct CompiledGrammar[T, K] {
  names : Array[RuleName]
  rules : Array[CompiledExpr[T, K]]
  root : Int
} derive(Eq, Debug)

///|
/// The entry slot of the compiled grammar.
pub fn[T, K] CompiledGrammar::root_slot(self : Self[T, K]) -> Int {
  self.root
}

///|
/// The compiled body of slot `slot`.
pub fn[T, K] CompiledGrammar::rule(
  self : Self[T, K],
  slot : Int,
) -> CompiledExpr[T, K] {
  self.rules[slot]
}

///|
/// Compile an authored grammar into dense-slot form. Slot 0 is always the root;
/// remaining rules follow in sorted-name order for determinism. Every `Ref` is
/// resolved during compile, so an unresolved reference fails here rather than
/// mid-parse.
///
/// `native_names` declares which names `Native(...)` may delegate to (empty by
/// default — existing callers are unaffected). A name must be either a grammar
/// rule or a native, never both: this is checked once, globally, over the
/// whole namespace, before any lowering — not only for names a reachable
/// `Native(...)` node happens to reference.
pub fn[T, K] compile(
  ir : GrammarIr[T, K],
  native_names? : Set[RuleName] = Set::Set([]),
  guard_names? : Set[RuleName] = Set::Set([]),
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
  let others = ir.rules.keys().filter(n => n != ir.root).collect()
  others.sort()
  let names = [ir.root, ..others]
  let slot_of : Map[RuleName, Int] = Map([])
  for i, name in names {
    slot_of[name] = i
  }
  let rules : Array[CompiledExpr[T, K]] = []
  for name in names {
    guard ir.rules.get(name) is Some(expr)
    rules.push(lower(expr, slot_of, native_names, guard_names))
  }
  { names, rules, root: 0 }
}

///|
/// Resolve a rule name to its dense slot, or raise `MissingRef`.
fn resolve(
  name : RuleName,
  slot_of : Map[RuleName, Int],
) -> Int raise GrammarCompileError {
  match slot_of.get(name) {
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
/// Resolve a native name to itself, or raise `MissingNative`. Validated at
/// compile time so an unregistered `Native(...)` name fails here, never
/// mid-parse — mirrors `resolve` for `Ref`.
fn resolve_native(
  name : RuleName,
  native_names : Set[RuleName],
) -> RuleName raise GrammarCompileError {
  if native_names.contains(name) {
    name
  } else {
    raise MissingNative(name)
  }
}

///|
/// Validate a `Pred` value against `guard_names`: every `HostGuard(name)`
/// must be in `guard_names`. Recurses into `Not` and `All`.
fn[T] check_pred_guards(
  pred : Pred[T],
  guard_names : Set[RuleName],
) -> Unit raise GrammarCompileError {
  match pred {
    HostGuard(name) =>
      if !guard_names.contains(name) {
        raise MissingHostGuard(name)
      }
    Not(inner) => check_pred_guards(inner, guard_names)
    All(left, right) => {
      check_pred_guards(left, guard_names)
      check_pred_guards(right, guard_names)
    }
    Any | IsToken(_) | OneOf(_) => ()
  }
}

///|
/// Lower one `Expr` to `CompiledExpr`, resolving every nested `Ref` to a slot
/// and every nested `Native` against the declared `native_names`,
/// and every `HostGuard` against `guard_names`.
fn[T, K] lower(
  expr : Expr[T, K],
  slot_of : Map[RuleName, Int],
  native_names : Set[RuleName],
  guard_names : Set[RuleName],
) -> CompiledExpr[T, K] raise GrammarCompileError {
  match expr {
    Node(k, body) => CompiledExpr::Node(k, lower(body, slot_of, native_names, guard_names))
    Emit(t, k) => CompiledExpr::Emit(t, k)
    Expect(t, k) => CompiledExpr::Expect(t, k)
    Ref(name) => CompiledExpr::RefSlot(resolve(name, slot_of))
    Native(name) => CompiledExpr::NativeRef(resolve_native(name, native_names))
    Choice(alts) => {
      let compiled : Array[CompiledAlt[T, K]] = []
      for a in alts {
        check_pred_guards(a.starts, guard_names)
        compiled.push(CompiledAlt::{
          starts: a.starts,
          body: lower(a.body, slot_of, native_names, guard_names),
        })
      }
      CompiledExpr::Choice(compiled)
    }
    RepeatTopLevel(name, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      check_pred_guards(starts, guard_names)
      check_pred_guards(delim, guard_names)
      CompiledExpr::RepeatTopLevel(
        resolve(name, slot_of),
        starts~,
        delim~,
        delim_kind~,
        between_msg~,
        after_msg~,
      )
    }
    Seq(exprs) => {
      let compiled : Array[CompiledExpr[T, K]] = []
      for e in exprs {
        compiled.push(lower(e, slot_of, native_names, guard_names))
      }
      CompiledExpr::Seq(compiled)
    }
    PrattApp(name, k, pred) => {
      check_pred_guards(pred, guard_names)
      CompiledExpr::PrattApp(resolve(name, slot_of), k, pred)
    }
    PrattBinary(name, k, ops, skip~) => {
      match skip {
        Some((sep, _)) => check_pred_guards(sep, guard_names)
        None => ()
      }
      CompiledExpr::PrattBinary(resolve(name, slot_of), k, ops, skip~)
    }
    RepeatWhile(pred, body) => {
      check_pred_guards(pred, guard_names)
      CompiledExpr::RepeatWhile(pred, lower(body, slot_of, native_names, guard_names))
    }
    WrapIfNext(k, pred, body) => {
      check_pred_guards(pred, guard_names)
      CompiledExpr::WrapIfNext(k, pred, lower(body, slot_of, native_names, guard_names))
    }
    EmitError(msg) => CompiledExpr::EmitError(msg)
    ErrorUntil(pred, msg) => {
      check_pred_guards(pred, guard_names)
      CompiledExpr::ErrorUntil(pred, msg)
    }
    Fail(msg) => CompiledExpr::Fail(msg)
    EmitOr(t, k, msg) => CompiledExpr::EmitOr(t, k, msg)
    DiagnoseIf(pred, msg) => {
      check_pred_guards(pred, guard_names)
      CompiledExpr::DiagnoseIf(pred, msg)
    }
    ExpectSkip(skip, skip_kind, expected, kind) => {
      check_pred_guards(skip, guard_names)
      CompiledExpr::ExpectSkip(skip, skip_kind, expected, kind)
    }
    ConsumeGated(skip, skip_kind, look) => {
      check_pred_guards(skip, guard_names)
      check_pred_guards(look, guard_names)
      CompiledExpr::ConsumeGated(skip, skip_kind, look)
    }
    RequireSep(delims, stop, alt, msg_alt~, msg_else~) => {
      check_pred_guards(stop, guard_names)
      check_pred_guards(alt, guard_names)
      CompiledExpr::RequireSep(delims, stop, alt, msg_alt~, msg_else~)
    }
    ErrorNodeUntil(kind, stop, msg) => {
      check_pred_guards(stop, guard_names)
      CompiledExpr::ErrorNodeUntil(kind, stop, msg)
    }
    ManualNewlineAppExpr => CompiledExpr::ManualNewlineAppExpr
    Empty => CompiledExpr::Empty
  }
}
