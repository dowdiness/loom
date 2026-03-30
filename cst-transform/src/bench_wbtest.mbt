// bench_test.mbt — Benchmarks: library functions vs hand-written recursion.
//
// Tree size: depth=8, branching=4 ≈ 65,536 leaf nodes + ~21,845 internal = ~87,381 total.
// Run: moon bench --release

///|
/// Shared large tree for all benchmarks.
fn bench_tree() -> GreenNode {
  generate_large_cst(8, 4)
}

// ── 1. transform (to_source) vs hand-written ────────────────────────

///|
test "bench: to_source via transform" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = to_source(tree)
    b.keep(result)
  })
}

///|
test "bench: to_source hand-written" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = to_source_handwritten(tree)
    b.keep(result)
  })
}

// ── 2. fold vs transform for identifier collection ──────────────────

///|
test "bench: collect idents via fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = fold(
      tree,
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
    b.keep(result)
  })
}

///|
test "bench: collect idents via transform" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result : Array[String] = transform(
      tree,
      fn(kind, text) { if kind == Ident { [text] } else { [] } },
      fn(_kind, children) {
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
  b.bench(fn() {
    let result = collect_idents_handwritten(tree)
    b.keep(result)
  })
}

// ── 3. iter + find_first vs hand-written DFS ────────────────────────

///|
test "bench: find first ident via iter" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = iter(tree).find_first(fn(n) {
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
  b.bench(fn() {
    let result = find_first_ident_handwritten(tree)
    b.keep(result)
  })
}

// ── 4. map identity — reconstruction cost ───────────────────────────

///|
test "bench: map identity" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = map(tree, fn(n) { n })
    b.keep(result)
  })
}

///|
test "bench: node count via transform" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform(tree, fn(_kind, _text) { 1 }, fn(_kind, children) {
      let mut sum = 1
      for c in children {
        sum = sum + c
      }
      sum
    })
    b.keep(result)
  })
}

///|
test "bench: node count hand-written" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = count_nodes_handwritten(tree)
    b.keep(result)
  })
}

// ── 5. fold with Int (no allocation) vs transform ───────────────────

///|
test "bench: token count via fold (Int)" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = fold(tree, fn(_k, _t) { 1 }, fn(a, b) { a + b }, 0)
    b.keep(result)
  })
}

///|
test "bench: token count via transform (Array[Int])" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform(tree, fn(_kind, _text) { 1 }, fn(_kind, children) {
      let mut sum = 0
      for c in children {
        sum = sum + c
      }
      sum
    })
    b.keep(result)
  })
}

// ── 6. CPS variants ─────────────────────────────────────────────────

///|
test "bench: to_source via transform_cps" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform_cps(tree, fn(_kind, text) { text }, fn(
      _kind,
      each_child,
    ) {
      let sb = StringBuilder::new()
      each_child(fn(s) { sb.write_string(s) })
      sb.to_string()
    })
    b.keep(result)
  })
}

///|
test "bench: node count via transform_cps" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform_cps(tree, fn(_kind, _text) { 1 }, fn(
      _kind,
      each_child,
    ) {
      let mut sum = 1
      each_child(fn(c) { sum = sum + c })
      sum
    })
    b.keep(result)
  })
}

///|
test "bench: token count via transform_cps" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform_cps(tree, fn(_kind, _text) { 1 }, fn(
      _kind,
      each_child,
    ) {
      let mut sum = 0
      each_child(fn(c) { sum = sum + c })
      sum
    })
    b.keep(result)
  })
}

// ── 7. Optimized variants ───────────────────────────────────────────

///|
test "bench: find first ident via each" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let mut result : String? = None
    let _ = each(tree, fn(n) {
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
  b.bench(fn() {
    let result = transform_fold(tree, fn(_kind, _text) { 1 }, fn(_kind) { 1 }, fn(
      _kind,
      acc,
      child,
    ) {
      acc + child
    })
    b.keep(result)
  })
}

///|
test "bench: token count via transform_fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform_fold(tree, fn(_kind, _text) { 1 }, fn(_kind) { 0 }, fn(
      _kind,
      acc,
      child,
    ) {
      acc + child
    })
    b.keep(result)
  })
}

///|
test "bench: to_source via transform_fold" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = transform_fold(
      tree,
      fn(_kind, text) { text },
      fn(_kind) { "" },
      fn(_kind, acc, child) { acc + child },
    )
    b.keep(result)
  })
}

///|
test "bench: full traversal count via each" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let mut count = 0
    let _ = each(tree, fn(_n) {
      count = count + 1
      true
    })
    b.keep(count)
  })
}

///|
test "bench: full traversal count via iter" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result = iter(tree).fold(init=0, fn(acc, _n) { acc + 1 })
    b.keep(result)
  })
}

// ── 8. Trait-based static dispatch ──────────────────────────────────

///|
test "bench: node count via trait Folder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result : NodeCount = tree.accept_fold()
    b.keep(result)
  })
}

///|
test "bench: node count via trait TransformFolder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result : NodeCount = tree.accept_transform_fold()
    b.keep(result)
  })
}

///|
test "bench: token count via trait Folder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result : TokenCount = tree.accept_fold()
    b.keep(result)
  })
}

///|
test "bench: token count via trait TransformFolder" (b : @bench.T) {
  let tree = bench_tree()
  b.bench(fn() {
    let result : TokenCount = tree.accept_transform_fold()
    b.keep(result)
  })
}
