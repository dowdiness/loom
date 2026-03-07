// dot_node.mbt — Term-based DOT graph renderer.
// Uses the DotNode trait from loom/viz via a newtype wrapper (orphan rule).

///|
priv struct TermDotNode {
  id : Int
  term : @ast.Term
  child_nodes : Array[TermDotNode]
}

///|
impl @viz.DotNode for TermDotNode with node_id(self) {
  self.id
}

///|
impl @viz.DotNode for TermDotNode with label(self) {
  match self.term {
    @ast.Term::Int(n) => "Int(" + n.to_string() + ")"
    @ast.Term::Var(s) => "Var(" + s + ")"
    @ast.Term::Lam(s, _) => "Lam(" + s + ")"
    @ast.Term::App(_, _) => "App"
    @ast.Term::Bop(op, _, _) => "Bop(" + op.to_string() + ")"
    @ast.Term::If(_, _, _) => "If"
    @ast.Term::Let(s, _, _) => "Let(" + s + ")"
    @ast.Term::Unit => "Unit"
    @ast.Term::Error(msg) => "Error(" + msg + ")"
  }
}

///|
impl @viz.DotNode for TermDotNode with node_attrs(_self) {
  ""
}

///|
impl @viz.DotNode for TermDotNode with children(self) {
  self.child_nodes
}

///|
impl @viz.DotNode for TermDotNode with edge_label(_self, _i) {
  ""
}

///|
fn build_term_tree(term : @ast.Term, counter : Ref[Int]) -> TermDotNode {
  let id = counter.val
  counter.val = counter.val + 1
  let child_nodes = match term {
    @ast.Term::Lam(_, body) => [build_term_tree(body, counter)]
    @ast.Term::App(f, a) =>
      [build_term_tree(f, counter), build_term_tree(a, counter)]
    @ast.Term::Bop(_, l, r) =>
      [build_term_tree(l, counter), build_term_tree(r, counter)]
    @ast.Term::If(c, t, e) =>
      [
        build_term_tree(c, counter),
        build_term_tree(t, counter),
        build_term_tree(e, counter),
      ]
    @ast.Term::Let(_, v, body) =>
      [build_term_tree(v, counter), build_term_tree(body, counter)]
    _ => []
  }
  { id, term, child_nodes }
}

///|
/// Render a Term as a GraphViz DOT string.
pub fn term_to_dot(term : @ast.Term) -> String {
  let counter = Ref::new(0)
  let dot_tree = build_term_tree(term, counter)
  @viz.to_dot(dot_tree)
}
