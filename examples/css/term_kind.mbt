///|
/// Term kind enum for CSS parser capstone (#610).
/// Consumed by loomgen via --term to generate GrammarIr from #loom.rule annotations.
///
/// Grammar:
///   Stylesheet = Rule* EOF
///   Rule      = Ident~ LBrace Decls RBrace  // ~ unconditional consume (gated by RepeatWhile FIRST)
///   Decls     = Decl* @until(RBrace)         // @until trailing recovery
///   Decl      = Ident! Colon! (Ident | Number)* Semicolon!  // ! error-tolerant consumption
#loom.term
pub(all) enum TermKind {
  #loom.root
  #loom.rule("Rule* EOF")
  Stylesheet
  #loom.node
  #loom.rule("Ident~ LBrace Decls RBrace")
  Rule
  #loom.node
  #loom.rule("Decl* @until(RBrace)")
  Decls
  #loom.node
  #loom.rule("Ident! Colon! (Ident | Number)* Semicolon!")
  Decl
  #loom.errornode
  ErrorNode
}
