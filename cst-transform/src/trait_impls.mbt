// trait_impls.mbt — Concrete trait implementations for benchmarks.
//
// Each impl is a defunctionalized closure — the compiler monomorphizes
// `accept_fold` / `accept_transform_fold` for each type, producing
// code identical to hand-written recursion.

// ── NodeCount: count all nodes via Folder ───────────────────────────

///|
pub(all) struct NodeCount {
  val : Int
} derive(Show)

///|
pub impl Folder for NodeCount with fold_token(_kind, _text) {
  { val: 1 }
}

///|
pub impl Folder for NodeCount with fold_combine(self, other) {
  { val: self.val + other.val }
}

///|
pub impl Folder for NodeCount with fold_empty() {
  { val: 0 }
}

// ── NodeCount via TransformFolder (includes branch count) ───────────

///|
pub impl TransformFolder for NodeCount with tf_token(_kind, _text) {
  { val: 1 }
}

///|
pub impl TransformFolder for NodeCount with tf_init(_kind) {
  { val: 1 }
}

///|
pub impl TransformFolder for NodeCount with tf_child(_kind, acc, child) {
  { val: acc.val + child.val }
}

// ── TokenCount: count leaf tokens via Folder ────────────────────────

///|
pub(all) struct TokenCount {
  val : Int
} derive(Show)

///|
pub impl Folder for TokenCount with fold_token(_kind, _text) {
  { val: 1 }
}

///|
pub impl Folder for TokenCount with fold_combine(self, other) {
  { val: self.val + other.val }
}

///|
pub impl Folder for TokenCount with fold_empty() {
  { val: 0 }
}

///|
pub impl TransformFolder for TokenCount with tf_token(_kind, _text) {
  { val: 1 }
}

///|
pub impl TransformFolder for TokenCount with tf_init(_kind) {
  { val: 0 }
}

///|
pub impl TransformFolder for TokenCount with tf_child(_kind, acc, child) {
  { val: acc.val + child.val }
}
