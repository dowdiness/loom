// Generic incremental parser — Wagner-Graham damage tracking strategy.
// Language-specific behavior injected via ImperativeLanguage[Ast] vtable.

///|
pub struct ImperativeParser[Ast] {
  priv lang : ImperativeLanguage[Ast]
  priv mut source : String
  priv mut tree : Ast?
  priv mut syntax_tree : @seam.SyntaxNode?
  priv mut last_reuse_count : Int
  priv mut prev_cst : @seam.CstNode? // cached CstNode from last successful parse
}

///|
pub fn[Ast] ImperativeParser::new(
  source : String,
  lang : ImperativeLanguage[Ast],
) -> ImperativeParser[Ast] {
  {
    lang,
    source,
    tree: None,
    syntax_tree: None,
    last_reuse_count: 0,
    prev_cst: None,
  }
}

///|
pub fn[Ast] ImperativeParser::parse(self : ImperativeParser[Ast]) -> Ast {
  let tree = match (self.lang.full_parse)(self.source) {
    Tree(syntax, _) => {
      let new_cst = syntax.cst_node()
      let ast = match self.prev_cst {
        Some(old_cst) if old_cst == new_cst => self.tree.unwrap()
        _ => (self.lang.to_ast)(syntax)
      }
      self.syntax_tree = Some(syntax)
      self.prev_cst = Some(new_cst)
      self.last_reuse_count = 0
      ast
    }
    LexError(msg) => {
      self.syntax_tree = None
      self.prev_cst = None
      self.last_reuse_count = 0
      (self.lang.on_lex_error)(msg)
    }
  }
  self.tree = Some(tree)
  tree
}

///|
pub fn[Ast] ImperativeParser::edit(
  self : ImperativeParser[Ast],
  edit : @core.Edit,
  new_source : String,
) -> Ast {
  self.source = new_source
  if self.syntax_tree is None {
    return self.parse()
  }
  let new_tree = match self.syntax_tree {
    Some(old_syntax) =>
      match (self.lang.incremental_parse)(new_source, old_syntax, edit) {
        Tree(new_syntax, reuse_count) => {
          let new_cst = new_syntax.cst_node()
          let ast = match self.prev_cst {
            Some(old_cst) if old_cst == new_cst => self.tree.unwrap()
            _ => (self.lang.to_ast)(new_syntax)
          }
          self.syntax_tree = Some(new_syntax)
          self.prev_cst = Some(new_cst)
          self.last_reuse_count = reuse_count
          ast
        }
        LexError(msg) => {
          self.syntax_tree = None
          self.prev_cst = None
          self.last_reuse_count = 0
          (self.lang.on_lex_error)(msg)
        }
      }
    None => self.parse()
  }
  self.tree = Some(new_tree)
  new_tree
}

///|
/// Reset the parser to a new source string, discarding all incremental state.
/// Use this when the source changes in a way that cannot be expressed as an
/// Edit (e.g. after a structural edit regenerates the text in a hybrid editor).
pub fn[Ast] ImperativeParser::reset(
  self : ImperativeParser[Ast],
  source : String,
) -> Ast {
  self.source = source
  self.syntax_tree = None
  self.prev_cst = None
  self.parse()
}

///|
pub fn[Ast] ImperativeParser::get_tree(self : ImperativeParser[Ast]) -> Ast? {
  self.tree
}

///|
pub fn[Ast] ImperativeParser::get_source(
  self : ImperativeParser[Ast],
) -> String {
  self.source
}

///|
pub fn[Ast] ImperativeParser::diagnostics(
  self : ImperativeParser[Ast],
) -> Array[String] {
  (self.lang.get_diagnostics)()
}

///|
pub fn[Ast] ImperativeParser::get_last_reuse_count(
  self : ImperativeParser[Ast],
) -> Int {
  self.last_reuse_count
}
