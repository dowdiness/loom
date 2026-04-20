// Type definitions for the bidirectional type checker.

///|
pub(all) enum Type {
  TInt
  TArrow(Type, Type)
  TUnit
  TError
} derive(Eq, Debug)

///|
pub impl Show for Type with output(self, logger) {
  match self {
    TInt => logger.write_string("Int")
    TUnit => logger.write_string("Unit")
    TError => logger.write_string("<error>")
    TArrow(param, ret) => {
      // Parenthesize left-side arrows for readability: (A -> B) -> C
      match param {
        TArrow(_, _) => {
          logger.write_string("(")
          param.output(logger)
          logger.write_string(")")
        }
        _ => param.output(logger)
      }
      logger.write_string(" -> ")
      ret.output(logger)
    }
  }
}

///|
pub(all) struct TypeDiagnostic {
  message : String
  def_name : String?
} derive(Eq, Debug)

///|
pub impl Show for TypeDiagnostic with output(self, logger) {
  logger.write_string(self.message)
  match self.def_name {
    Some(name) => {
      logger.write_string(" (in ")
      logger.write_string(name)
      logger.write_string(")")
    }
    None => ()
  }
}

///|
pub(all) struct TypeResult {
  typ : Type
  had_error : Bool
} derive(Eq, Debug)

///|
pub(all) enum TypeEnv {
  Empty
  Bind(TypeEnv, String, Type)
} derive(Eq, Debug)

///|
pub fn TypeEnv::lookup(self : TypeEnv, name : String) -> Type? {
  match self {
    Empty => None
    Bind(parent, n, t) => if n == name { Some(t) } else { parent.lookup(name) }
  }
}

///|
pub fn TypeEnv::extend(self : TypeEnv, name : String, typ : Type) -> TypeEnv {
  Bind(self, name, typ)
}

///|
pub(all) enum TypedTerm {
  Int(Int)
  Unit
  Var(String)
  Lam(String, Type?, TypedTerm)
  App(TypedTerm, TypedTerm)
  Bop(@ast.Bop, TypedTerm, TypedTerm)
  If(TypedTerm, TypedTerm, TypedTerm)
  Module(Array[(String, TypedTerm)], TypedTerm)
  Unbound(String)
  Error(String)
  Hole(Int)
} derive(Eq, Debug)

///|
pub impl Show for TypedTerm with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Identity key for a top-level definition within a module. Hashed on
/// `name` only: position-independent, so inserting a new def at position 0
/// does not invalidate existing `DefId`s minted for subsequent defs.
/// Position lookup is done through `PipelineState::name_to_idx` maintained
/// by `rebuild_chain`. Invariant: one def per name in a module.
pub(all) struct DefEntry {
  name : String
} derive(Eq, Hash, Debug)

///|
pub(all) struct ResolvedModule {
  defs : Array[(String, TypedTerm)]
  body : TypedTerm
} derive(Eq, Debug)

///|
pub(all) struct ModuleTypeResult {
  body_type : TypeResult
  def_types : Array[(String, TypeResult)]
  all_diagnostics : Array[TypeDiagnostic]
} derive(Eq, Debug)

///|
/// Return value from `build_typecheck_pipeline_with_index`.
///
/// Bundles the pipeline Memo with an InternTable and MemoMap for query-by-DefId
/// access to cached type results.
pub(all) struct TypecheckIndex {
  intern_table : @incr.InternTable[DefEntry]
  memo_map : @incr.MemoMap[@incr.InternId, TypeResult]
}
