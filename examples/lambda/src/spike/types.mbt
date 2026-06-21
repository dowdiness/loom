///|
/// Rule identifiers for the grammar IR.
pub enum RuleId {
  Source
  Definition
  Expression
  Binary
  Application
  Atom
  ParamList
} derive(Eq, Debug)

///|
/// Grammar IR expressions. Closures (fn(@token.Token) -> Bool) prevent
/// derive(Eq) and derive(Debug) — assert values by pattern match in tests.
pub enum Expr {
  /// Wrap the inner expr in a node of the given kind.
  Node(@syntax.SyntaxKind, Expr)
  /// Emit the current token as the given syntax kind without consuming.
  Emit(@token.Token, @syntax.SyntaxKind)
  /// Expect the given token, emit as the given kind, or emit error placeholder.
  Expect(@token.Token, @syntax.SyntaxKind, String)
  /// Delegate to another grammar rule.
  Ref(RuleId)
  /// Try alternatives in order; each branch has a lookahead predicate.
  Choice(Array[Alt])
  /// Repeat rule at the top level with optional reuse (cripple_reuse flag).
  RepeatTopLevel(RuleId, Bool)
  /// Repeat the given expr while the lookahead predicate holds.
  RepeatWhile((@token.Token) -> Bool, Expr)
  /// After parsing the inner expr, if the NEXT token satisfies the predicate,
  /// wrap from the given mark position in the given node kind.
  WrapIfNext(Int, @syntax.SyntaxKind, (@token.Token) -> Bool, Expr)
  /// Lambda-specific: emit param list matching A's exact raw loop shape.
  ManualParamList
  /// Emit error node consuming until the stop predicate.
  ErrorUntil((@token.Token) -> Bool, String)
  /// No-op.
  Empty
}

///|
/// One alternative in a Choice expr. Cannot derive due to closure field.
pub struct Alt {
  starts : (@token.Token) -> Bool
  body : Expr
}

///|
/// Hand-authored grammar IR value. Cannot derive due to Expr fields
/// containing closures.
pub struct GrammarIr {
  source : Expr
  definition : Expr
  expression : Expr
  binary : Expr
  application : Expr
  atom : Expr
  param_list : Expr
}

///|
/// Retrieve the expression for a given rule.
pub fn GrammarIr::rule(self : GrammarIr, id : RuleId) -> Expr {
  match id {
    RuleId::Source => self.source
    RuleId::Definition => self.definition
    RuleId::Expression => self.expression
    RuleId::Binary => self.binary
    RuleId::Application => self.application
    RuleId::Atom => self.atom
    RuleId::ParamList => self.param_list
  }
}

