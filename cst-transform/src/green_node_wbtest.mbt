// green_node_wbtest.mbt — Tests for all GreenNode methods.

// ── Test fixtures ───────────────────────────────────────────────────

///|
let expected_idents =
  #|["add", "x", ",", "y", "result", "x", "y"]

///|
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
fn count_nodes_handwritten(node : GreenNode) -> Int {
  match node {
    Leaf(_, _) => 1
    Branch(_, children) =>
      for child in children; count = 1 {
        continue count + count_nodes_handwritten(child)
      } nobreak {
        count
      }
  }
}

// ── Example helper methods (demonstrate API usage) ──────────────────

///|
fn GreenNode::to_source(self : GreenNode) -> String {
  self.transform((_kind, text) => text, (_kind, children) => {
    let sb = StringBuilder::new()
    for s in children {
      sb.write_string(s)
    }
    sb.to_string()
  })
}

///|
fn GreenNode::rename(self : GreenNode, from : String, to : String) -> GreenNode {
  self.map(n => {
    match n {
      Leaf(Ident, text) => if text == from { Leaf(Ident, to) } else { n }
      _ => n
    }
  })
}

///|
fn GreenNode::collect_identifiers(self : GreenNode) -> Array[String] {
  self.fold(
    (kind, text) => if kind == Ident { [text] } else { [] },
    (a, b) => {
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
fn GreenNode::first_error(self : GreenNode) -> GreenNode? {
  self
  .iter()
  .find_first(n => {
    match n {
      Branch(Error, _) => true
      _ => false
    }
  })
}

// ── transform tests ─────────────────────────────────────────────────

///|
test "transform: source text reconstruction" {
  inspect(sample_cst().to_source(), content="fn add(x, y) let result = x + y")
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
  let result = Leaf(Ident, "hello").transform((_kind, text) => text, (
    _kind,
    _children,
  ) => "")
  inspect(result, content="hello")
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

// ── fold tests ──────────────────────────────────────────────────────

///|
test "fold: token count" {
  let count = sample_cst().fold((_kind, _text) => 1, (a, b) => a + b, 0)
  inspect(count, content="21")
}

///|
test "fold: identifier collection" {
  inspect(
    sample_cst().collect_identifiers().to_string() == expected_idents,
    content="true",
  )
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
test "fold: empty branch" {
  let result = Branch(ArgList, []).fold((_k, _t) => 1, (a, b) => a + b, 0)
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
  let source = sample_cst()
    .map(n => {
      match n {
        Leaf(Ident, text) => Leaf(Ident, text.to_upper())
        _ => n
      }
    })
    .to_source()
  inspect(source, content="fn ADD(X, Y) let RESULT = X + Y")
}

///|
test "map: replace SyntaxKind with Error" {
  let has_error = sample_cst()
    .map(n => {
      match n {
        Branch(BinaryExpr, children) => Branch(Error, children)
        _ => n
      }
    })
    .first_error()
  inspect(has_error is Some(_), content="true")
}

///|
test "map: identity preserves structure" {
  let original = sample_cst()
  inspect(original == original.map(n => n), content="true")
}

// ── iter tests ──────────────────────────────────────────────────────

///|
test "iter: full enumeration count" {
  let count = sample_cst().iter().fold(init=0, (acc, _n) => acc + 1)
  inspect(count == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "iter: find first Ident token" {
  match
    sample_cst()
    .iter()
    .find_first(n => {
      match n {
        Leaf(Ident, _) => true
        _ => false
      }
    }) {
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
  match (branches[0], branches[1], branches[2]) {
    (Branch(SourceFile, _), Branch(FnDef, _), Branch(Name, _)) => ()
    _ => fail("expected SourceFile, FnDef, Name")
  }
}

///|
test "iter: single leaf" {
  inspect(Leaf(Ident, "x").iter().collect().length(), content="1")
}

// ── each tests ──────────────────────────────────────────────────────

///|
test "each: full traversal count" {
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
test "each: returns true/false" {
  inspect(sample_cst().each(_n => true), content="true")
  inspect(sample_cst().each(_n => false), content="false")
}

// ── transform_fold tests ────────────────────────────────────────────

///|
test "transform_fold: node count" {
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
test "transform_fold: max depth" {
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

// ── Trait-based tests ───────────────────────────────────────────────

///|
test "trait Walker: accept_walk early termination" {
  let completed = sample_cst().accept_walk(IdentFinder(()))
  // IdentFinder stops at first Ident leaf, so should NOT complete
  inspect(completed, content="false")
}

///|
test "trait Finder: find first ident" {
  match sample_cst().find(IdentFinder(())) {
    Some(Leaf(Ident, text)) => inspect(text, content="add")
    _ => fail("expected Leaf(Ident, \"add\")")
  }
}

///|
test "trait Folder: counts leaves only (branches contribute fold_empty=0)" {
  // Folder only counts leaves because fold_empty()=0 for branches.
  // NodeCount and TokenCount both return 21 (the leaf count).
  let nodes : NodeCount = sample_cst().accept_fold()
  let tokens : TokenCount = sample_cst().accept_fold()
  inspect(nodes.0, content="21")
  inspect(tokens.0, content="21")
}

///|
test "trait TransformFolder: counts all nodes (tf_init=1 includes branches)" {
  // TransformFolder counts branches too because tf_init()=1.
  let result : NodeCount = sample_cst().accept_transform_fold()
  inspect(result.0 == count_nodes_handwritten(sample_cst()), content="true")
  let result2 : TokenCount = sample_cst().accept_transform_fold()
  inspect(result2.0, content="21")
}

///|
test "trait CstMeta: multi-property single-pass fold" {
  let meta : CstMeta = sample_cst().accept_transform_fold()
  // text_len = "fn add(x, y) let result = x + y" = 31
  inspect(meta.0, content="31")
  // token_count = 21 leaves
  inspect(meta.1, content="21")
  // node_count = all nodes (leaves + branches)
  inspect(meta.2 == count_nodes_handwritten(sample_cst()), content="true")
}

///|
test "trait MutVisitor: multi-property single-pass (mutable)" {
  let meta = MutMeta::{ text_len: 0, token_count: 0, node_count: 0 }
  sample_cst().accept_visitor(meta)
  inspect(meta.text_len, content="31")
  inspect(meta.token_count, content="21")
  inspect(
    meta.node_count == count_nodes_handwritten(sample_cst()),
    content="true",
  )
}

// ── Practical examples ──────────────────────────────────────────────

///|
test "practical: rename + to_source" {
  inspect(
    sample_cst().rename("x", "a").to_source(),
    content="fn add(a, y) let result = a + y",
  )
  inspect(
    sample_cst().rename("result", "sum").to_source(),
    content="fn add(x, y) let sum = x + y",
  )
}

///|
test "practical: collect_identifiers" {
  inspect(
    sample_cst().collect_identifiers().to_string() == expected_idents,
    content="true",
  )
}

///|
test "practical: first_error" {
  inspect(sample_cst().first_error() is None, content="true")
  let with_error = Branch(SourceFile, [
    Branch(Name, [Leaf(Ident, "ok")]),
    Branch(Error, [Leaf(Ident, "bad")]),
  ])
  inspect(with_error.first_error() is Some(_), content="true")
}

// ── API design ──────────────────────────────────────────────────────

///|
test "api: type inference" {
  let count = sample_cst().fold((_k, _t) => 1, (a, b) => a + b, 0)
  inspect(count > 0, content="true")
}

///|
test "api: closure capture" {
  let prefix = "node:"
  let result = Leaf(Ident, "x").transform((_k, t) => prefix + t, (_k, _cs) => "")
  inspect(result, content="node:x")
}

///|
test "api: Result in transform" {
  let result : Result[Int, String] = Branch(Name, [Leaf(Ident, "x")]).transform(
    (kind, _text) => if kind == Ident { Ok(1) } else { Err("unexpected") },
    (_kind, children) => {
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
