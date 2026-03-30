// bench_wbtest.mbt — Benchmarks: library functions vs hand-written recursion.
//
// Tree size: depth=8, branching=4 ≈ 65,536 leaf nodes + ~21,845 internal = ~87,381 total.
// Run: moon bench --release

// ── Benchmark helpers ───────────────────────────────────────────────

///|
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
fn bench_tree() -> GreenNode {
  generate_large_cst(8, 4)
}

///|
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

// ── 1. transform (to_source) vs hand-written ────────────────────────

///|
test "bench: to_source via transform" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.to_source()
    b.keep(result)
  })
}

///|
test "bench: to_source hand-written" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = to_source_handwritten(tree)
    b.keep(result)
  })
}

// ── 2. fold vs transform for identifier collection ──────────────────

///|
test "bench: collect idents via fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.fold(
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
    b.keep(result)
  })
}

///|
test "bench: collect idents via transform" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result : Array[String] = tree.transform(
      (kind, text) => if kind == Ident { [text] } else { [] },
      (_kind, children) => {
        let result : Array[String] = []
        for c in children {
          result.append(c)
        }
        result
      },
    )
    b.keep(result)
  })
}

///|
test "bench: collect idents hand-written" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = collect_idents_handwritten(tree)
    b.keep(result)
  })
}

// ── 3. iter + find_first vs hand-written DFS ────────────────────────

///|
test "bench: find first ident via iter" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree
      .iter()
      .find_first(n => {
        match n {
          Leaf(Ident, _) => true
          _ => false
        }
      })
    b.keep(result)
  })
}

///|
test "bench: find first ident hand-written" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = find_first_ident_handwritten(tree)
    b.keep(result)
  })
}

// ── 4. map identity — reconstruction cost ───────────────────────────

///|
test "bench: map identity" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.map(n => n)
    b.keep(result)
  })
}

///|
test "bench: node count via transform" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform((_kind, _text) => 1, (_kind, children) => {
      for c in children; sum = 1 {
        continue sum + c
      } nobreak {
        sum
      }
    })
    b.keep(result)
  })
}

///|
test "bench: node count hand-written" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = count_nodes_handwritten(tree)
    b.keep(result)
  })
}

// ── 5. fold with Int (no allocation) vs transform ───────────────────

///|
test "bench: token count via fold (Int)" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.fold((_k, _t) => 1, (a, b) => a + b, 0)
    b.keep(result)
  })
}

///|
test "bench: token count via transform (Array[Int])" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform((_kind, _text) => 1, (_kind, children) => {
      for c in children; sum = 0 {
        continue sum + c
      } nobreak {
        sum
      }
    })
    b.keep(result)
  })
}

// ── 6. CPS variants ─────────────────────────────────────────────────

///|
test "bench: to_source via transform_cps" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform_cps((_kind, text) => text, (_kind, each_child) => {
      let sb = StringBuilder::new()
      each_child(s => sb.write_string(s))
      sb.to_string()
    })
    b.keep(result)
  })
}

///|
test "bench: node count via transform_cps" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform_cps((_kind, _text) => 1, (_kind, each_child) => {
      let mut sum = 1
      each_child(c => sum = sum + c)
      sum
    })
    b.keep(result)
  })
}

///|
test "bench: token count via transform_cps" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform_cps((_kind, _text) => 1, (_kind, each_child) => {
      let mut sum = 0
      each_child(c => sum = sum + c)
      sum
    })
    b.keep(result)
  })
}

// ── 7. Optimized variants ───────────────────────────────────────────

///|
test "bench: find first ident via each" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let mut result : String? = None
    let _ = tree.each(n => {
      match n {
        Leaf(Ident, text) => {
          result = Some(text)
          false
        }
        _ => true
      }
    })
    b.keep(result)
  })
}

///|
test "bench: node count via transform_fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform_fold((_kind, _text) => 1, _kind => 1, (
      _kind,
      acc,
      child,
    ) => acc + child)
    b.keep(result)
  })
}

///|
test "bench: token count via transform_fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform_fold((_kind, _text) => 1, _kind => 0, (
      _kind,
      acc,
      child,
    ) => acc + child)
    b.keep(result)
  })
}

///|
test "bench: to_source via transform_fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.transform_fold((_kind, text) => text, _kind => "", (
      _kind,
      acc,
      child,
    ) => acc + child)
    b.keep(result)
  })
}

///|
test "bench: full traversal count via each" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let mut count = 0
    let _ = tree.each(_n => {
      count = count + 1
      true
    })
    b.keep(count)
  })
}

///|
test "bench: full traversal count via iter" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.iter().fold(init=0, (acc, _n) => acc + 1)
    b.keep(result)
  })
}

// ── 8. Trait-based static dispatch ──────────────────────────────────

///|
test "bench: node count via trait Folder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result : NodeCount = tree.accept_fold()
    b.keep(result)
  })
}

///|
test "bench: node count via trait TransformFolder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result : NodeCount = tree.accept_transform_fold()
    b.keep(result)
  })
}

///|
test "bench: token count via trait Folder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result : TokenCount = tree.accept_fold()
    b.keep(result)
  })
}

///|
test "bench: token count via trait TransformFolder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result : TokenCount = tree.accept_transform_fold()
    b.keep(result)
  })
}

///|
test "bench: find first ident via trait Finder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(() => {
    let result = tree.find(IdentFinder(()))
    b.keep(result)
  })
}
