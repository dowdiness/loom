///|
/// Sample CST representing:
/// ```
/// fn add(x, y) {
///   let result = x + y
///   result
/// }
/// ```
fn sample_cst() -> GreenNode {
  Branch(SourceFile, [
    Branch(FnDef, [
      Leaf(Fn_, "fn"),
      Leaf(Whitespace, " "),
      Branch(Name, [Leaf(Ident, "add")]),
      Leaf(LParen, "("),
      Branch(ArgList, [
        Branch(Name, [Leaf(Ident, "x")]),
        Leaf(Ident, ","),
        Leaf(Whitespace, " "),
        Branch(Name, [Leaf(Ident, "y")]),
      ]),
      Leaf(RParen, ")"),
      Leaf(Whitespace, " "),
      Branch(LetStmt, [
        Leaf(Let, "let"),
        Leaf(Whitespace, " "),
        Branch(Name, [Leaf(Ident, "result")]),
        Leaf(Whitespace, " "),
        Leaf(Eq, "="),
        Leaf(Whitespace, " "),
        Branch(BinaryExpr, [
          Branch(Name, [Leaf(Ident, "x")]),
          Leaf(Whitespace, " "),
          Leaf(Plus, "+"),
          Leaf(Whitespace, " "),
          Branch(Name, [Leaf(Ident, "y")]),
        ]),
      ]),
    ]),
  ])
}

///|
/// Generate a large CST tree for benchmarking.
/// Total node count ≈ branching^depth (leaves) + internal nodes.
fn generate_large_cst(depth : Int, branching : Int) -> GreenNode {
  if depth <= 0 {
    Leaf(Ident, "x")
  } else {
    let children = Array::new(capacity=branching)
    for i in 0..<branching {
      let _ = i
      children.push(generate_large_cst(depth - 1, branching))
    }
    Branch(BinaryExpr, children)
  }
}

///|
/// Hand-written recursive source text reconstruction (baseline for benchmarks).
fn to_source_handwritten(node : GreenNode) -> String {
  match node {
    Leaf(_, text) => text
    Branch(_, children) => {
      let sb = StringBuilder::new()
      for child in children {
        sb.write_string(to_source_handwritten(child))
      }
      sb.to_string()
    }
  }
}

///|
/// Hand-written recursive identifier collection (baseline for benchmarks).
fn collect_idents_handwritten(node : GreenNode) -> Array[String] {
  match node {
    Leaf(Ident, text) => [text]
    Leaf(_, _) => []
    Branch(_, children) => {
      let result : Array[String] = []
      for child in children {
        result.append(collect_idents_handwritten(child))
      }
      result
    }
  }
}

///|
/// Hand-written recursive DFS to find first Ident leaf (baseline for benchmarks).
fn find_first_ident_handwritten(node : GreenNode) -> String? {
  match node {
    Leaf(Ident, text) => Some(text)
    Leaf(_, _) => None
    Branch(_, children) => {
      for child in children {
        match find_first_ident_handwritten(child) {
          Some(t) => return Some(t)
          None => ()
        }
      }
      None
    }
  }
}

///|
/// Hand-written recursive node count (baseline for benchmarks).
fn count_nodes_handwritten(node : GreenNode) -> Int {
  match node {
    Leaf(_, _) => 1
    Branch(_, children) => {
      let mut count = 1
      for child in children {
        count = count + count_nodes_handwritten(child)
      }
      count
    }
  }
}

///|
/// Source text reconstruction via `transform`.
fn to_source(node : GreenNode) -> String {
  node.transform(fn(_kind, text) { text }, fn(_kind, children) {
    let sb = StringBuilder::new()
    for s in children {
      sb.write_string(s)
    }
    sb.to_string()
  })
}

///|
/// Identifier renaming via `map`.
fn rename(node : GreenNode, from : String, to : String) -> GreenNode {
  node.map(fn(n) {
    match n {
      Leaf(Ident, text) => if text == from { Leaf(Ident, to) } else { n }
      _ => n
    }
  })
}

///|
/// Identifier collection via `fold`.
///
/// IMPORTANT: `fold`'s `empty` parameter is shared across all recursive calls.
/// For mutable types like `Array`, `combine` must NOT mutate its arguments —
/// it must create a new value. Otherwise the shared `empty` gets corrupted.
fn collect_identifiers(node : GreenNode) -> Array[String] {
  node.fold(
    fn(kind, text) { if kind == Ident { [text] } else { [] } },
    fn(a, b) {
      let result = Array::new(capacity=a.length() + b.length())
      for item in a {
        result.push(item)
      }
      for item in b {
        result.push(item)
      }
      result
    },
    [],
  )
}

///|
/// First error node detection via `iter`.
fn first_error(node : GreenNode) -> GreenNode? {
  node
  .iter()
  .find_first(fn(n) {
    match n {
      Branch(Error, _) => true
      _ => false
    }
  })
}
