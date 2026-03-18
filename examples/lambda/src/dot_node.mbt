// dot_node.mbt — Term-based DOT graph renderer.
// Uses the DotNode trait from loom/viz via a newtype wrapper (orphan rule).

///|
priv struct TermDotNode {
  id : Int
  term : @ast.Term
  child_nodes : Array[TermDotNode]
  resolution : Resolution?
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
    @ast.Term::Module(defs, _) => {
      let names = defs.map(fn(d) { d.0 })
      "Module(" + names.join(", ") + ")"
    }
    @ast.Term::Unit => "Unit"
    @ast.Term::Unbound(x) => "Unbound(" + x + ")"
    @ast.Term::Error(msg) => "Error(" + msg + ")"
  }
}

///|
impl @viz.DotNode for TermDotNode with node_attrs(self) {
  match self.resolution {
    Some(res) =>
      match res.vars.get(self.id) {
        Some(Bound(_)) => "color=\"#6a9955\", fontcolor=\"#6a9955\""
        Some(Free) => "color=\"#f44747\", fontcolor=\"#f44747\""
        None => ""
      }
    None => ""
  }
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
fn build_term_tree(
  term : @ast.Term,
  counter : Ref[Int],
  resolution? : Resolution? = None,
) -> TermDotNode {
  let id = counter.val
  counter.val = counter.val + 1
  let child_nodes = match term {
    @ast.Term::Lam(_, body) => [build_term_tree(body, counter, resolution~)]
    @ast.Term::App(f, a) =>
      [
        build_term_tree(f, counter, resolution~),
        build_term_tree(a, counter, resolution~),
      ]
    @ast.Term::Bop(_, l, r) =>
      [
        build_term_tree(l, counter, resolution~),
        build_term_tree(r, counter, resolution~),
      ]
    @ast.Term::If(c, t, e) =>
      [
        build_term_tree(c, counter, resolution~),
        build_term_tree(t, counter, resolution~),
        build_term_tree(e, counter, resolution~),
      ]
    @ast.Term::Module(defs, body) => {
      let children : Array[TermDotNode] = []
      for (_, init) in defs {
        children.push(build_term_tree(init, counter, resolution~))
      }
      children.push(build_term_tree(body, counter, resolution~))
      children
    }
    _ => []
  }
  { id, term, child_nodes, resolution }
}

///|
/// Render a Term as a GraphViz DOT string.
pub fn term_to_dot(term : @ast.Term) -> String {
  let counter = Ref::new(0)
  let dot_tree = build_term_tree(term, counter)
  @viz.to_dot(dot_tree)
}

///|
/// Render a resolved Term as a GraphViz DOT string with bound/free coloring.
/// Both `term` and `resolution` must come from the same `resolve()` call —
/// passing the original (pre-resolve) term will produce `Var` labels instead
/// of `Unbound` labels for free variables.
pub fn term_to_dot_resolved(
  term : @ast.Term,
  resolution : Resolution,
) -> String {
  let counter = Ref::new(0)
  let dot_tree = build_term_tree(term, counter, resolution=Some(resolution))
  @viz.to_dot(dot_tree)
}
