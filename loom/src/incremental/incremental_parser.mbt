// Generic incremental parser — Wagner-Graham damage tracking strategy.
// Language-specific behavior injected via IncrementalLanguage[Ast] vtable.

///|
pub struct IncrementalParser[Ast] {
  priv lang : IncrementalLanguage[Ast]
  priv mut source : String
  priv mut tree : Ast?
  priv mut syntax_tree : @seam.SyntaxNode?
  priv mut last_reuse_count : Int
  priv mut prev_cst_hash : Int? // cached hash of last successful CstNode
}

///|
pub fn[Ast] IncrementalParser::new(
  source : String,
  lang : IncrementalLanguage[Ast],
) -> IncrementalParser[Ast] {
  {
    lang,
    source,
    tree: None,
    syntax_tree: None,
    last_reuse_count: 0,
    prev_cst_hash: None,
  }
}

///|
pub fn[Ast] IncrementalParser::parse(self : IncrementalParser[Ast]) -> Ast {
  let tree = match (self.lang.full_parse)(self.source) {
    Tree(syntax, _) => {
      let new_hash = syntax.cst_node().hash
      let ast = match self.prev_cst_hash {
        Some(old_hash) if old_hash == new_hash => self.tree.unwrap()
        _ => (self.lang.to_ast)(syntax)
      }
      self.syntax_tree = Some(syntax)
      self.prev_cst_hash = Some(new_hash)
      self.last_reuse_count = 0
      ast
    }
    LexError(msg) => {
      self.syntax_tree = None
      self.prev_cst_hash = None
      self.last_reuse_count = 0
      (self.lang.on_lex_error)(msg)
    }
  }
  self.tree = Some(tree)
  tree
}

///|
pub fn[Ast] IncrementalParser::edit(
  self : IncrementalParser[Ast],
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
          let new_hash = new_syntax.cst_node().hash
          let ast = match self.prev_cst_hash {
            Some(old_hash) if old_hash == new_hash => self.tree.unwrap()
            _ => (self.lang.to_ast)(new_syntax)
          }
          self.syntax_tree = Some(new_syntax)
          self.prev_cst_hash = Some(new_hash)
          self.last_reuse_count = reuse_count
          ast
        }
        LexError(msg) => {
          self.syntax_tree = None
          self.prev_cst_hash = None
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
pub fn[Ast] IncrementalParser::reset(
  self : IncrementalParser[Ast],
  source : String,
) -> Ast {
  self.source = source
  self.syntax_tree = None
  self.prev_cst_hash = None
  self.parse()
}

///|
pub fn[Ast] IncrementalParser::get_tree(self : IncrementalParser[Ast]) -> Ast? {
  self.tree
}

///|
pub fn[Ast] IncrementalParser::get_source(
  self : IncrementalParser[Ast],
) -> String {
  self.source
}

///|
pub fn[Ast] IncrementalParser::diagnostics(
  self : IncrementalParser[Ast],
) -> Array[String] {
  (self.lang.get_diagnostics)()
}

///|
pub fn[Ast] IncrementalParser::get_last_reuse_count(
  self : IncrementalParser[Ast],
) -> Int {
  self.last_reuse_count
}
