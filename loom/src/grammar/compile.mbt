///|
/// Raised by `compile` when the authored grammar is malformed. `DuplicateRule`
/// is intentionally absent: the rule namespace is a `Map`, so duplicate names
/// cannot occur by construction.
pub suberror GrammarCompileError {
  MissingRoot(RuleName)
  MissingRef(RuleName)
} derive(Eq, Debug)

///|
/// The compiled form of `Expr`: every `Ref(name)` is resolved to a dense
/// `RefSlot(Int)`, so the interpreter's per-edit `Ref` dispatch is an array
/// index rather than a map lookup.
pub enum CompiledExpr[T, K] {
  Node(K, CompiledExpr[T, K])
  Emit(T, K)
  Expect(T, K, String)
  RefSlot(Int)
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
  PrattBinary(Int, K, Array[(T, K)])
  RepeatWhile(Pred[T], CompiledExpr[T, K])
  WrapIfNext(K, Pred[T], CompiledExpr[T, K])
  CountedRepeat(
    Pred[T],
    CompiledExpr[T, K],
    min~ : Int,
    missing_message~ : String?
  )
  EmitError(String)
  ErrorUntil(Pred[T], String)
  Fail(String)
  EmitOr(T, K, String)
  DiagnoseIf(Pred[T], String)
  ExpectSkip(Pred[T], K, T, K)
  ConsumeGated(Pred[T], K, Pred[T])
  RequireSep(
    Pred[T],
    K,
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
pub fn[T, K] compile(
  ir : GrammarIr[T, K],
) -> CompiledGrammar[T, K] raise GrammarCompileError {
  guard ir.rules.get(ir.root) is Some(_) else { raise MissingRoot(ir.root) }
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
    rules.push(lower(expr, slot_of))
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
    None => raise MissingRef(name)
  }
}

///|
/// Lower one `Expr` to `CompiledExpr`, resolving every nested `Ref` to a slot.
fn[T, K] lower(
  expr : Expr[T, K],
  slot_of : Map[RuleName, Int],
) -> CompiledExpr[T, K] raise GrammarCompileError {
  match expr {
    Node(k, body) => CompiledExpr::Node(k, lower(body, slot_of))
    Emit(t, k) => CompiledExpr::Emit(t, k)
    Expect(t, k, msg) => CompiledExpr::Expect(t, k, msg)
    Ref(name) => CompiledExpr::RefSlot(resolve(name, slot_of))
    Choice(alts) => {
      let compiled : Array[CompiledAlt[T, K]] = []
      for a in alts {
        compiled.push(CompiledAlt::{
          starts: a.starts,
          body: lower(a.body, slot_of),
        })
      }
      CompiledExpr::Choice(compiled)
    }
    RepeatTopLevel(name, starts~, delim~, delim_kind~, between_msg~, after_msg~) =>
      CompiledExpr::RepeatTopLevel(
        resolve(name, slot_of),
        starts~,
        delim~,
        delim_kind~,
        between_msg~,
        after_msg~,
      )
    Seq(exprs) => {
      let compiled : Array[CompiledExpr[T, K]] = []
      for e in exprs {
        compiled.push(lower(e, slot_of))
      }
      CompiledExpr::Seq(compiled)
    }
    PrattApp(name, k, pred) =>
      CompiledExpr::PrattApp(resolve(name, slot_of), k, pred)
    PrattBinary(name, k, ops) =>
      CompiledExpr::PrattBinary(resolve(name, slot_of), k, ops)
    RepeatWhile(pred, body) =>
      CompiledExpr::RepeatWhile(pred, lower(body, slot_of))
    WrapIfNext(k, pred, body) =>
      CompiledExpr::WrapIfNext(k, pred, lower(body, slot_of))
    CountedRepeat(pred, body, min~, missing_message~) =>
      CompiledExpr::CountedRepeat(
        pred,
        lower(body, slot_of),
        min~,
        missing_message~,
      )
    EmitError(msg) => CompiledExpr::EmitError(msg)
    ErrorUntil(pred, msg) => CompiledExpr::ErrorUntil(pred, msg)
    Fail(msg) => CompiledExpr::Fail(msg)
    EmitOr(t, k, msg) => CompiledExpr::EmitOr(t, k, msg)
    DiagnoseIf(pred, msg) => CompiledExpr::DiagnoseIf(pred, msg)
    ExpectSkip(skip, skip_kind, expected, kind) =>
      CompiledExpr::ExpectSkip(skip, skip_kind, expected, kind)
    ConsumeGated(skip, skip_kind, look) =>
      CompiledExpr::ConsumeGated(skip, skip_kind, look)
    RequireSep(skip, skip_kind, stop, alt, msg_alt~, msg_else~) =>
      CompiledExpr::RequireSep(skip, skip_kind, stop, alt, msg_alt~, msg_else~)
    ErrorNodeUntil(kind, stop, msg) =>
      CompiledExpr::ErrorNodeUntil(kind, stop, msg)
    ManualNewlineAppExpr => CompiledExpr::ManualNewlineAppExpr
    Empty => CompiledExpr::Empty
  }
}
