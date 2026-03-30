// Shared expected values for tests

///|
let expected_idents =
  #|["add", "x", ",", "y", "result", "x", "y"]

// ── transform tests ─────────────────────────────────────────────────

///|
test "transform: source text reconstruction" {
  let result = to_source(sample_cst())
  inspect(result, content="fn add(x, y) let result = x + y")
}

///|
test "transform: node count" {
  let count = transform(sample_cst(), fn(_kind, _text) { 1 }, fn(
    _kind,
    children,
  ) {
    let mut sum = 1
    for c in children {
      sum = sum + c
    }
    sum
  })
  // Verify against hand-written baseline
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "transform: collect SyntaxKind list" {
  let kinds : Array[String] = transform(
    sample_cst(),
    fn(_kind, _text) { ([] : Array[String]) },
    fn(kind, children) {
      let result : Array[String] = [kind.to_string()]
      for c in children {
        result.append(c)
      }
      result
    },
  )
  let expected =
    #|["SourceFile", "FnDef", "Name", "ArgList", "Name", "Name", "LetStmt", "Name", "BinaryExpr", "Name", "Name"]
  inspect(kinds.to_string() == expected, content="true")
}

///|
test "transform: single leaf" {
  let node = Leaf(Ident, "hello")
  let result = transform(node, fn(_kind, text) { text }, fn(_kind, _children) {
    ""
  })
  inspect(result, content="hello")
}

// ── fold tests ──────────────────────────────────────────────────────

///|
test "fold: token count" {
  let count = fold(sample_cst(), fn(_kind, _text) { 1 }, fn(a, b) { a + b }, 0)
  inspect(count, content="21")
}

///|
test "fold: identifier collection" {
  let idents = collect_identifiers(sample_cst())
  inspect(idents.to_string() == expected_idents, content="true")
}

///|
test "fold: total text length" {
  let text_len = fold(
    sample_cst(),
    fn(_kind, text) { text.length() },
    fn(a, b) { a + b },
    0,
  )
  // "fn add(x, y) let result = x + y" = 31 chars
  inspect(text_len, content="31")
}

///|
test "transform: max nesting depth" {
  let depth = transform(sample_cst(), fn(_kind, _text) { 1 }, fn(
    _kind,
    children,
  ) {
    let mut max_child = 0
    for d in children {
      if d > max_child {
        max_child = d
      }
    }
    max_child + 1
  })
  // SourceFile > FnDef > LetStmt > BinaryExpr > Name > Leaf = 6
  inspect(depth, content="6")
}

///|
test "fold: empty branch" {
  let node = Branch(ArgList, [])
  let result = fold(node, fn(_k, _t) { 1 }, fn(a, b) { a + b }, 0)
  inspect(result, content="0")
}

///|
test "fold: string concatenation (value type)" {
  let text = fold(
    Leaf(Ident, "hello"),
    fn(_kind, text) { text },
    fn(a, b) { a + b },
    "",
  )
  inspect(text, content="hello")
}

// ── map tests ───────────────────────────────────────────────────────

///|
test "map: uppercase all identifiers" {
  let uppercased = map(sample_cst(), fn(n) {
    match n {
      Leaf(Ident, text) => Leaf(Ident, text.to_upper())
      _ => n
    }
  })
  let source = to_source(uppercased)
  inspect(source, content="fn ADD(X, Y) let RESULT = X + Y")
}

///|
test "map: replace SyntaxKind with Error" {
  let replaced = map(sample_cst(), fn(n) {
    match n {
      Branch(BinaryExpr, children) => Branch(Error, children)
      _ => n
    }
  })
  let has_error = first_error(replaced)
  inspect(has_error is Some(_), content="true")
}

///|
test "map: identity preserves structure" {
  let original = sample_cst()
  let mapped = map(original, fn(n) { n })
  inspect(original == mapped, content="true")
}

// ── iter tests ──────────────────────────────────────────────────────

///|
test "iter: full enumeration count" {
  let count = iter(sample_cst()).fold(init=0, fn(acc, _n) { acc + 1 })
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "iter: find first Ident token" {
  let first = iter(sample_cst()).find_first(fn(n) {
    match n {
      Leaf(Ident, _) => true
      _ => false
    }
  })
  match first {
    Some(Leaf(_, text)) => inspect(text, content="add")
    _ => fail("expected Leaf(Ident, \"add\")")
  }
}

///|
test "iter: filter + take composition" {
  let branches = iter(sample_cst())
    .filter(fn(n) {
      match n {
        Branch(_, _) => true
        _ => false
      }
    })
    .take(3)
    .collect()
  inspect(branches.length(), content="3")
  // First 3 branches in DFS pre-order: SourceFile, FnDef, Name
  match branches[0] {
    Branch(SourceFile, _) => ()
    _ => fail("expected SourceFile")
  }
  match branches[1] {
    Branch(FnDef, _) => ()
    _ => fail("expected FnDef")
  }
  match branches[2] {
    Branch(Name, _) => ()
    _ => fail("expected Name")
  }
}

///|
test "iter: single leaf" {
  let node = Leaf(Ident, "x")
  let items = iter(node).collect()
  inspect(items.length(), content="1")
}

// ── practical examples (Task 3) ─────────────────────────────────────

///|
test "practical: to_source reconstructs text" {
  inspect(to_source(sample_cst()), content="fn add(x, y) let result = x + y")
}

///|
test "practical: rename identifier" {
  let renamed = rename(sample_cst(), "x", "a")
  let source = to_source(renamed)
  inspect(source, content="fn add(a, y) let result = a + y")
}

///|
test "practical: collect_identifiers" {
  let idents = collect_identifiers(sample_cst())
  inspect(idents.to_string() == expected_idents, content="true")
}

///|
test "practical: first_error on clean tree" {
  let result = first_error(sample_cst())
  inspect(result is None, content="true")
}

///|
test "practical: first_error finds error node" {
  let tree_with_error = Branch(SourceFile, [
    Branch(Name, [Leaf(Ident, "ok")]),
    Branch(Error, [Leaf(Ident, "bad")]),
    Branch(Name, [Leaf(Ident, "after")]),
  ])
  let result = first_error(tree_with_error)
  inspect(result is Some(_), content="true")
}

///|
test "practical: rename + to_source round-trip" {
  let cst = sample_cst()
  let renamed = rename(cst, "result", "sum")
  let source = to_source(renamed)
  inspect(source, content="fn add(x, y) let sum = x + y")
}

// ── API design: type inference ──────────────────────────────────────

///|
test "api: transform type inference without annotation" {
  // R should be inferred as Int from on_token/on_node return types
  let count = transform(sample_cst(), fn(_k, _t) { 1 }, fn(_k, cs) {
    let mut s = 1
    for c in cs {
      s = s + c
    }
    s
  })
  inspect(count > 0, content="true")
}

///|
test "api: fold type inference without annotation" {
  // R should be inferred as Int
  let total = fold(sample_cst(), fn(_k, _t) { 1 }, fn(a, b) { a + b }, 0)
  inspect(total > 0, content="true")
}

///|
test "api: closure capture in transform" {
  let prefix = "node:"
  let result = transform(Leaf(Ident, "x"), fn(_k, t) { prefix + t }, fn(
    _k,
    _cs,
  ) {
    ""
  })
  inspect(result, content="node:x")
}

///|
test "api: composability — transform result piped to iter" {
  let mapped = map(sample_cst(), fn(n) {
    match n {
      Leaf(Ident, text) => Leaf(Ident, text.to_upper())
      _ => n
    }
  })
  let first_ident = iter(mapped).find_first(fn(n) {
    match n {
      Leaf(Ident, _) => true
      _ => false
    }
  })
  match first_ident {
    Some(Leaf(_, text)) => inspect(text, content="ADD")
    _ => fail("expected uppercased ident")
  }
}

///|
test "api: Result return type in transform callbacks" {
  let result : Result[Int, String] = transform(
    Branch(Name, [Leaf(Ident, "x")]),
    fn(kind, _text) {
      if kind == Ident {
        Ok(1)
      } else {
        Err("unexpected token")
      }
    },
    fn(_kind, children) {
      let mut sum = 0
      for c in children {
        match c {
          Ok(v) => sum = sum + v
          Err(e) => return Err(e)
        }
      }
      Ok(sum)
    },
  )
  inspect(result, content="Ok(1)")
}

// ── CPS variant tests ───────────────────────────────────────────────

///|
test "cps: source text reconstruction" {
  let result = transform_cps(sample_cst(), fn(_kind, text) { text }, fn(
    _kind,
    each_child,
  ) {
    let sb = StringBuilder::new()
    each_child(fn(s) { sb.write_string(s) })
    sb.to_string()
  })
  inspect(result, content="fn add(x, y) let result = x + y")
}

///|
test "cps: node count" {
  let count = transform_cps(sample_cst(), fn(_kind, _text) { 1 }, fn(
    _kind,
    each_child,
  ) {
    let mut sum = 1
    each_child(fn(c) { sum = sum + c })
    sum
  })
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "cps: collect into array (opt-in allocation)" {
  let kinds : Array[String] = transform_cps(
    sample_cst(),
    fn(_kind, _text) { ([] : Array[String]) },
    fn(kind, each_child) {
      let result : Array[String] = [kind.to_string()]
      each_child(fn(c) { result.append(c) })
      result
    },
  )
  let expected =
    #|["SourceFile", "FnDef", "Name", "ArgList", "Name", "Name", "LetStmt", "Name", "BinaryExpr", "Name", "Name"]
  inspect(kinds.to_string() == expected, content="true")
}

///|
test "cps: single leaf" {
  let result = transform_cps(Leaf(Ident, "hello"), fn(_kind, text) { text }, fn(
    _kind,
    _each_child,
  ) {
    ""
  })
  inspect(result, content="hello")
}

// ── each tests ──────────────────────────────────────────────────────

///|
test "each: full traversal count" {
  let mut count = 0
  let _ = each(sample_cst(), fn(_n) {
    count = count + 1
    true
  })
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "each: early termination finds first Ident" {
  let mut found : String? = None
  let _ = each(sample_cst(), fn(n) {
    match n {
      Leaf(Ident, text) => {
        found = Some(text)
        false
      }
      _ => true
    }
  })
  inspect(found, content="Some(\"add\")")
}

///|
test "each: returns true on complete traversal" {
  let completed = each(sample_cst(), fn(_n) { true })
  inspect(completed, content="true")
}

///|
test "each: returns false on early termination" {
  let completed = each(sample_cst(), fn(_n) { false })
  inspect(completed, content="false")
}

// ── transform_fold tests ────────────────────────────────────────────

///|
test "transform_fold: node count matches hand-written" {
  let count = transform_fold(
    sample_cst(),
    fn(_kind, _text) { 1 },
    fn(_kind) { 1 },
    fn(_kind, acc, child) { acc + child },
  )
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "transform_fold: token count" {
  let count = transform_fold(
    sample_cst(),
    fn(_kind, _text) { 1 },
    fn(_kind) { 0 },
    fn(_kind, acc, child) { acc + child },
  )
  inspect(count, content="21")
}

///|
test "transform_fold: to_source" {
  let result = transform_fold(
    sample_cst(),
    fn(_kind, text) { text },
    fn(_kind) { "" },
    fn(_kind, acc, child) { acc + child },
  )
  inspect(result, content="fn add(x, y) let result = x + y")
}

///|
test "trait Folder: token count via NodeCount" {
  // Folder counts leaves only (branches contribute fold_empty=0 + children)
  let result : NodeCount = sample_cst().accept_fold()
  inspect(result.val, content="21")
}

///|
test "trait Folder: token count" {
  let result : TokenCount = sample_cst().accept_fold()
  inspect(result.val, content="21")
}

///|
test "trait TransformFolder: node count matches hand-written" {
  let result : NodeCount = sample_cst().accept_transform_fold()
  inspect(result.val == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "trait TransformFolder: token count" {
  let result : TokenCount = sample_cst().accept_transform_fold()
  inspect(result.val, content="21")
}

///|
test "transform_fold: max depth via kind-aware init" {
  // Each branch adds 1 to the max child depth
  let depth = transform_fold(
    sample_cst(),
    fn(_kind, _text) { 1 },
    fn(_kind) { 0 },
    fn(_kind, acc, child) {
      let d = child + 1
      if d > acc {
        d
      } else {
        acc
      }
    },
  )
  // SourceFile > FnDef > LetStmt > BinaryExpr > Name > Leaf = 6
  inspect(depth, content="6")
}
