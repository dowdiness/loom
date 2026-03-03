// DotNode implementation for AstNode — connects lambda AST to the generic viz renderer.
//
// MoonBit's orphan rule requires the implementing type to be local.
// `DotAstNode` is a thin private newtype wrapper so we can implement
// the foreign `@viz.DotNode` trait within this package.

///|
priv struct DotAstNode {
  node : @ast.AstNode
}

///|
impl @viz.DotNode for DotAstNode with node_id(self) {
  self.node.node_id
}

///|
impl @viz.DotNode for DotAstNode with children(self) {
  self.node.children.map(fn(c) { { node: c } })
}

///|
/// Return the raw display label for this node (escaped by the renderer).
impl @viz.DotNode for DotAstNode with label(self) {
  match self.node.kind {
    If => "If"
    Bop(Plus) => "+"
    Bop(Minus) => "-"
    App => "App"
    Lam(param) => "λ" + param
    Let(name) => "let " + name
    Var(name) => name
    Int(n) => n.to_string()
    Error(err) => err
  }
}

///|
/// Return additional DOT style attributes for this node, or "" for default styling.
impl @viz.DotNode for DotAstNode with node_attrs(self) {
  fn prepend_sharp_if_not_exist(s : String) {
    if s.has_prefix("#") {
      s
    } else {
      "#" + s
    }
  }

  fn color(c, fill, font) {
    let c = prepend_sharp_if_not_exist(c)
    let fill = prepend_sharp_if_not_exist(fill)
    let font = prepend_sharp_if_not_exist(font)
    "color=\"\{c}\", fillcolor=\"\{fill}\", fontcolor=\"\{font}\""
  }
  // Color palette (VSCode dark theme hues):
  //   Error  #ff0000 / #ff000022 / #ff6b6b
  //   Lam    #c586c0 / #c586c022 / #c586c0  (purple — binders)
  //   Var    #9cdcfe / #9cdcfe22 / #9cdcfe  (blue — identifiers)
  //   Int    #b5cea8 / #b5cea822 / #b5cea8  (green — literals)
  //   Bop    #d4d4d4 / #d4d4d422 / #d4d4d4  (grey — operators)
  //   App, If  "" — use default graph-wide node style
  match self.node.kind {
    If | App => ""
    Bop(_) => color("d4d4d4", "d4d4d422", "d4d4d4")
    Lam(_) | Let(_) => color("c586c0", "c586c022", "c586c0")
    Var(_) => color("9cdcfe", "9cdcfe22", "9cdcfe")
    Int(_) => color("b5cea8", "b5cea822", "b5cea8")
    Error(_) => color("ff0000", "ff000022", "ff6b6b")
  }
}

///|
/// Return the label for the i-th outgoing edge, or "" for no label.
impl @viz.DotNode for DotAstNode with edge_label(self, i) {
  match (self.node.kind, i) {
    (If, 0) => "cond"
    (If, 1) => "then"
    (If, 2) => "else"
    (Bop(_), 0) => "left"
    (Bop(_), 1) => "right"
    (App, 0) => "func"
    (App, 1) => "arg"
    (Lam(_), 0) => "body"
    _ => ""
  }
}

///|
/// Convert an AstNode tree to DOT format.
pub fn to_dot(node : @ast.AstNode) -> String {
  @viz.to_dot(DotAstNode::{ node, })
}
