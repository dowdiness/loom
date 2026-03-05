// dot_node.mbt — Term-based DOT graph renderer.
// Produces a Graphviz DOT string from an @ast.Term using the same format
// as the generic to_dot renderer in dowdiness/loom/viz.

///|
/// Escape special characters in DOT labels (mirrors loom/viz escape_label).
fn escape_dot_label(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    match s.code_unit_at(i).to_char() {
      Some('"') => buf.write_string("\\\"")
      Some('\\') => buf.write_string("\\\\")
      Some('\n') => buf.write_string("\\n")
      Some(c) => buf.write_char(c)
      None => ()
    }
  }
  buf.to_string()
}

///|
/// Render a Term as a GraphViz DOT string.
/// Produces the same format as @loom/viz.to_dot — same header, footer,
/// node naming (node0, node1, …), and attribute style.
pub fn term_to_dot(term : @ast.Term) -> String {
  let buf = StringBuilder::new()
  buf.write_string("digraph {\n")
  buf.write_string("  bgcolor=\"transparent\";\n")
  buf.write_string(
    "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#252526\", fontname=\"Arial\", fontcolor=\"#d4d4d4\", color=\"#3c3c3c\"];\n",
  )
  buf.write_string(
    "  edge [fontname=\"Arial\", fontcolor=\"#858585\", color=\"#3c3c3c\"];\n\n",
  )
  let counter = Ref::new(0)
  fn node_id() -> Int {
    let id = counter.val
    counter.val = counter.val + 1
    id
  }
  fn write_node(id : Int, label : String) -> Unit {
    buf.write_string("  node")
    buf.write_string(id.to_string())
    buf.write_string(" [label=\"")
    buf.write_string(escape_dot_label(label))
    buf.write_string("\"];\n")
  }
  fn write_edge(parent_id : Int, child_id : Int) -> Unit {
    buf.write_string("  node")
    buf.write_string(parent_id.to_string())
    buf.write_string(" -> node")
    buf.write_string(child_id.to_string())
    buf.write_string(";\n")
  }
  fn render(t : @ast.Term, parent_id : Int?) -> Int {
    let id = node_id()
    let label = match t {
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
    write_node(id, label)
    match parent_id {
      Some(pid) => write_edge(pid, id)
      None => ()
    }
    match t {
      @ast.Term::Lam(_, body) => {
        let _ = render(body, Some(id))
        ()
      }
      @ast.Term::App(f, a) => {
        let _ = render(f, Some(id))
        let _ = render(a, Some(id))
        ()
      }
      @ast.Term::Bop(_, l, r) => {
        let _ = render(l, Some(id))
        let _ = render(r, Some(id))
        ()
      }
      @ast.Term::If(c, t2, e) => {
        let _ = render(c, Some(id))
        let _ = render(t2, Some(id))
        let _ = render(e, Some(id))
        ()
      }
      @ast.Term::Let(_, v, body) => {
        let _ = render(v, Some(id))
        let _ = render(body, Some(id))
        ()
      }
      _ => ()
    }
    id
  }
  let _ = render(term, None)
  buf.write_string("}\n")
  buf.to_string()
}
