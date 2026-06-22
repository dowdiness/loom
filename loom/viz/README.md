# `dowdiness/loom/viz`

Language-agnostic Graphviz DOT renderer. Defines the `DotNode` trait; language
packages supply the implementation.

## Public API

```moonbit
pub(open) trait DotNode {
  node_id(Self)         -> Int
  label(Self)           -> String
  node_attrs(Self)      -> String
  children(Self)        -> Array[Self]
  edge_label(Self, Int) -> String
}

pub fn[T : DotNode] to_dot(T) -> String
```

## Method contracts

| Method | Returns | Notes |
|--------|---------|-------|
| `node_id` | Unique integer | Used as the DOT node name `node<id>` |
| `label` | Raw display text | The renderer DOT-escapes `"`, `\`, `\n` |
| `node_attrs` | Bare DOT attributes or `""` | e.g. `color="#c586c0", fillcolor="#c586c022"` — **no outer brackets** |
| `children` | Child nodes in order | `Array[Self]` keeps traversal monomorphic |
| `edge_label` | Role name or `""` | e.g. `"body"`, `"func"` — **no brackets** |

`node_attrs` and `edge_label` must return the **content inside** the DOT attribute
brackets, not the brackets themselves. The renderer owns the surrounding `[...]`.

## DOT output shape

```dot
digraph {
  bgcolor="transparent";
  node [shape=box, style="rounded,filled", fillcolor="#252526", ...];
  edge [fontname="Arial", fontcolor="#858585", ...];

  node0 [label="λx"] [color="#c586c0", ...];
  node0 -> node1 [label="body"];
  node1 [label="x"];
}
```

Default graph-wide style uses a dark theme. Per-node overrides via `node_attrs`
add a second attribute block on the same line, which is valid DOT.

## Implementing `DotNode` for a new language

MoonBit's orphan rule applies: you cannot implement a foreign trait for a foreign
type. Since `DotNode` is defined here and your AST type is defined elsewhere,
you need a local newtype wrapper:

```moonbit
// In your language package (e.g. src/my_lang/)
priv struct MyDotNode { node : @ast.MyAstNode }

impl @viz.DotNode for MyDotNode with node_id(self) { self.node.id }
impl @viz.DotNode for MyDotNode with label(self) { ... }
impl @viz.DotNode for MyDotNode with node_attrs(self) { ... }
impl @viz.DotNode for MyDotNode with children(self) {
  self.node.children.map(fn(c) { { node: c } })
}
impl @viz.DotNode for MyDotNode with edge_label(self, i) { ... }

pub fn to_dot(node : @ast.MyAstNode) -> String {
  @viz.to_dot({ node, })
}
```

See `examples/lambda/src/dot_node.mbt` for the reference implementation.
