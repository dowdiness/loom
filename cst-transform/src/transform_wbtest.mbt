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
  let count = sample_cst().transform((_kind, _text) => 1, (_kind, children) => {
    for c in children; sum = 1 {
      continue sum + c
    } nobreak {
      sum
    }
  })
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "transform: collect SyntaxKind list" {
  let kinds : Array[String] = sample_cst().transform(
    (_kind, _text) => ([] : Array[String]),
    (kind, children) => {
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
  let result = node.transform((_kind, text) => text, (_kind, _children) => "")
  inspect(result, content="hello")
}

// ── fold tests ──────────────────────────────────────────────────────

///|
test "fold: token count" {
  let count = sample_cst().fold((_kind, _text) => 1, (a, b) => a + b, 0)
  inspect(count, content="21")
}

///|
test "fold: identifier collection" {
  let idents = collect_identifiers(sample_cst())
  inspect(idents.to_string() == expected_idents, content="true")
}

///|
test "fold: total text length" {
  let text_len = sample_cst().fold(
    (_kind, text) => text.length(),
    (a, b) => a + b,
    0,
  )
  inspect(text_len, content="31")
}

///|
test "transform: max nesting depth" {
  let depth = sample_cst().transform((_kind, _text) => 1, (_kind, children) => {
    for d in children; max_child = 0 {
      continue if d > max_child { d } else { max_child }
    } nobreak {
      max_child + 1
    }
  })
  inspect(depth, content="6")
}

///|
test "fold: empty branch" {
  let node = Branch(ArgList, [])
  let result = node.fold((_k, _t) => 1, (a, b) => a + b, 0)
  inspect(result, content="0")
}

///|
test "fold: string concatenation (value type)" {
  let text = Leaf(Ident, "hello").fold(
    (_kind, text) => text,
    (a, b) => a + b,
    "",
  )
  inspect(text, content="hello")
}

// ── map tests ───────────────────────────────────────────────────────

///|
test "map: uppercase all identifiers" {
  let uppercased = sample_cst().map(n => {
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
  let replaced = sample_cst().map(n => {
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
  let mapped = original.map(n => n)
  inspect(original == mapped, content="true")
}

// ── iter tests ──────────────────────────────────────────────────────

///|
test "iter: full enumeration count" {
  let count = sample_cst().iter().fold(init=0, (acc, _n) => acc + 1)
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "iter: find first Ident token" {
  let first = sample_cst()
    .iter()
    .find_first(n => {
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
  let branches = sample_cst()
    .iter()
    .filter(n => {
      match n {
        Branch(_, _) => true
        _ => false
      }
    })
    .take(3)
    .collect()
  inspect(branches.length(), content="3")
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
  let items = node.iter().collect()
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
  let count = sample_cst().transform((_k, _t) => 1, (_k, cs) => {
    for c in cs; s = 1 {
      continue s + c
    } nobreak {
      s
    }
  })
  inspect(count > 0, content="true")
}

///|
test "api: fold type inference without annotation" {
  let total = sample_cst().fold((_k, _t) => 1, (a, b) => a + b, 0)
  inspect(total > 0, content="true")
}

///|
test "api: closure capture in transform" {
  let prefix = "node:"
  let result = Leaf(Ident, "x").transform((_k, t) => prefix + t, (_k, _cs) => "")
  inspect(result, content="node:x")
}

///|
test "api: composability — transform result piped to iter" {
  let mapped = sample_cst().map(n => {
    match n {
      Leaf(Ident, text) => Leaf(Ident, text.to_upper())
      _ => n
    }
  })
  let first_ident = mapped
    .iter()
    .find_first(n => {
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
  let result : Result[Int, String] = Branch(Name, [Leaf(Ident, "x")]).transform(
    (kind, _text) => if kind == Ident { Ok(1) } else { Err("unexpected token") },
    (_kind, children) => {
      // Early return prevents for..in loop variable style
      for c in children {
        match c {
          Err(e) => return Err(e)
          _ => ()
        }
      }
      Ok(
        for c in children; sum = 0 {
          match c {
            Ok(v) => continue sum + v
            Err(_) => continue sum
          }
        } nobreak {
          sum
        },
      )
    },
  )
  inspect(result, content="Ok(1)")
}

// ── CPS variant tests ───────────────────────────────────────────────

///|
test "cps: source text reconstruction" {
  let result = sample_cst().transform_cps((_kind, text) => text, (
    _kind,
    each_child,
  ) => {
    let sb = StringBuilder::new()
    each_child(s => sb.write_string(s))
    sb.to_string()
  })
  inspect(result, content="fn add(x, y) let result = x + y")
}

///|
test "cps: node count" {
  // CPS uses emit callback — can't avoid let mut here
  let count = sample_cst().transform_cps((_kind, _text) => 1, (
    _kind,
    each_child,
  ) => {
    let mut sum = 1
    each_child(c => sum = sum + c)
    sum
  })
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "cps: collect into array (opt-in allocation)" {
  let kinds : Array[String] = sample_cst().transform_cps(
    (_kind, _text) => ([] : Array[String]),
    (kind, each_child) => {
      let result : Array[String] = [kind.to_string()]
      each_child(c => result.append(c))
      result
    },
  )
  let expected =
    #|["SourceFile", "FnDef", "Name", "ArgList", "Name", "Name", "LetStmt", "Name", "BinaryExpr", "Name", "Name"]
  inspect(kinds.to_string() == expected, content="true")
}

///|
test "cps: single leaf" {
  let result = Leaf(Ident, "hello").transform_cps((_kind, text) => text, (
    _kind,
    _each_child,
  ) => "")
  inspect(result, content="hello")
}

// ── each tests ──────────────────────────────────────────────────────

///|
test "each: full traversal count" {
  // each uses callback — can't avoid let mut here
  let mut count = 0
  let _ = sample_cst().each(_n => {
    count = count + 1
    true
  })
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "each: early termination finds first Ident" {
  let mut found : String? = None
  let _ = sample_cst().each(n => {
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
  let completed = sample_cst().each(_n => true)
  inspect(completed, content="true")
}

///|
test "each: returns false on early termination" {
  let completed = sample_cst().each(_n => false)
  inspect(completed, content="false")
}

// ── transform_fold tests ────────────────────────────────────────────

///|
test "transform_fold: node count matches hand-written" {
  let count = sample_cst().transform_fold((_kind, _text) => 1, _kind => 1, (
    _kind,
    acc,
    child,
  ) => acc + child)
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "transform_fold: token count" {
  let count = sample_cst().transform_fold((_kind, _text) => 1, _kind => 0, (
    _kind,
    acc,
    child,
  ) => acc + child)
  inspect(count, content="21")
}

///|
test "transform_fold: to_source" {
  let result = sample_cst().transform_fold((_kind, text) => text, _kind => "", (
    _kind,
    acc,
    child,
  ) => acc + child)
  inspect(result, content="fn add(x, y) let result = x + y")
}

///|
test "trait Folder: token count via NodeCount" {
  let result : NodeCount = sample_cst().accept_fold()
  inspect(result.0, content="21")
}

///|
test "trait Folder: token count" {
  let result : TokenCount = sample_cst().accept_fold()
  inspect(result.0, content="21")
}

///|
test "trait TransformFolder: node count matches hand-written" {
  let result : NodeCount = sample_cst().accept_transform_fold()
  inspect(result.0 == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "trait TransformFolder: token count" {
  let result : TokenCount = sample_cst().accept_transform_fold()
  inspect(result.0, content="21")
}

///|
test "transform_fold: max depth via kind-aware init" {
  let depth = sample_cst().transform_fold((_kind, _text) => 1, _kind => 0, (
    _kind,
    acc,
    child,
  ) => {
    let d = child + 1
    if d > acc {
      d
    } else {
      acc
    }
  })
  inspect(depth, content="6")
}
