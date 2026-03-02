// Generic incremental parser — Wagner-Graham damage tracking strategy.
// Language-specific behavior injected via IncrementalLanguage[Ast] vtable.

///|
pub struct IncrementalParser[Ast] {
  priv lang : IncrementalLanguage[Ast]
  priv mut source : String
  priv mut tree : Ast?
  priv mut syntax_tree : @seam.SyntaxNode?
  priv mut last_reuse_count : Int
}

///|
pub fn[Ast] IncrementalParser::new(
  source : String,
  lang : IncrementalLanguage[Ast],
) -> IncrementalParser[Ast] {
  { lang, source, tree: None, syntax_tree: None, last_reuse_count: 0 }
}

///|
pub fn[Ast] IncrementalParser::parse(self : IncrementalParser[Ast]) -> Ast {
  let tree = match (self.lang.full_parse)(self.source) {
    Tree(syntax, _) => {
      self.syntax_tree = Some(syntax)
      self.last_reuse_count = 0
      (self.lang.to_ast)(syntax)
    }
    LexError(msg) => {
      self.syntax_tree = None
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
          self.syntax_tree = Some(new_syntax)
          self.last_reuse_count = reuse_count
          (self.lang.to_ast)(new_syntax)
        }
        LexError(msg) => {
          self.syntax_tree = None
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
pub fn[Ast] IncrementalParser::get_last_reuse_count(
  self : IncrementalParser[Ast],
) -> Int {
  self.last_reuse_count
}
