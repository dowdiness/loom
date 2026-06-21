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
  /// Run each expression in sequence.
  Seq(Array[Expr])
  /// Pratt application: parse atom_rule repeatedly while starts(peek) holds,
  /// retroactively wrapping the run in app_kind. No-op when the first atom
  /// stands alone.
  PrattApp(RuleId, @syntax.SyntaxKind, (@token.Token) -> Bool)
  /// Pratt binary: parse prefix_rule, then consume operator/prefix_rule pairs
  /// while peek matches any op token, retroactively wrapping in binary_kind.
  PrattBinary(
    RuleId,
    @syntax.SyntaxKind,
    Array[(@token.Token, @syntax.SyntaxKind)]
  )
  /// Repeat the given expr while the lookahead predicate holds.
  RepeatWhile((@token.Token) -> Bool, Expr)
  /// After parsing the inner expr, if the NEXT token satisfies the predicate,
  /// wrap from the given mark position in the given node kind.
  WrapIfNext(Int, @syntax.SyntaxKind, (@token.Token) -> Bool, Expr)
  /// Lambda-specific: call parse_definition_ir for one definition (let/fn).
  /// Used inside block expressions to mirror A's definition loop.
  ManualDefinition
  /// Lambda-specific: emit param list matching A's exact raw loop shape.
  ManualParamList
  /// Emit a diagnostic without creating an error node or placeholder.
  EmitError(String)
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
/// Divergence classification for one oracle step result.
///
/// Severity ordering (highest to lowest):
///   WrongModelStop > ReplicationResidual > NoDivergence
///
/// WrongModelStop: any D1 or D2a structural failure — parse tree or structural
///   diagnostics differ. GO blocker. Investigate before any release.
///
/// ReplicationResidual: D2a structural fields match but diagnostic message
///   strings differ (cross-impl wording). Not a GO blocker. File as known
///   deviation.
///
/// NoDivergence: all oracle booleans are true.
pub enum DivergenceClass {
  NoDivergence
  ReplicationResidual(String)
  WrongModelStop(String)
} derive(Eq, Debug)

///|
pub impl Show for DivergenceClass with fn to_string(self) {
  match self {
    DivergenceClass::NoDivergence => "NoDivergence"
    DivergenceClass::ReplicationResidual(s) => "ReplicationResidual(" + s + ")"
    DivergenceClass::WrongModelStop(s) => "WrongModelStop(" + s + ")"
  }
}

///|
pub impl Show for DivergenceClass with fn output(self, logger) {
  logger.write_string(self.to_string())
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
