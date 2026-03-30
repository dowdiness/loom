// trait_impls.mbt — Concrete trait implementations for benchmarks.
//
// Each impl is a defunctionalized closure — the compiler monomorphizes
// `accept_fold` / `accept_transform_fold` for each type, producing
// code identical to hand-written recursion.

// ── NodeCount: count all nodes via Folder ───────────────────────────

///|
pub(all) struct NodeCount(Int) derive(Show)

///|
pub impl Folder for NodeCount with fold_token(_kind, _text) {
  NodeCount(1)
}

///|
pub impl Folder for NodeCount with fold_combine(self, other) {
  NodeCount(self.0 + other.0)
}

///|
pub impl Folder for NodeCount with fold_empty() {
  NodeCount(0)
}

// ── NodeCount via TransformFolder (includes branch count) ───────────

///|
pub impl TransformFolder for NodeCount with tf_token(_kind, _text) {
  NodeCount(1)
}

///|
pub impl TransformFolder for NodeCount with tf_init(_kind) {
  NodeCount(1)
}

///|
pub impl TransformFolder for NodeCount with tf_child(_kind, acc, child) {
  NodeCount(acc.0 + child.0)
}

// ── TokenCount: count leaf tokens via Folder ────────────────────────

///|
pub(all) struct TokenCount(Int) derive(Show)

///|
pub impl Folder for TokenCount with fold_token(_kind, _text) {
  TokenCount(1)
}

///|
pub impl Folder for TokenCount with fold_combine(self, other) {
  TokenCount(self.0 + other.0)
}

///|
pub impl Folder for TokenCount with fold_empty() {
  TokenCount(0)
}

///|
pub impl TransformFolder for TokenCount with tf_token(_kind, _text) {
  TokenCount(1)
}

///|
pub impl TransformFolder for TokenCount with tf_init(_kind) {
  TokenCount(0)
}

///|
pub impl TransformFolder for TokenCount with tf_child(_kind, acc, child) {
  TokenCount(acc.0 + child.0)
}
