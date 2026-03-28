// Capability traits for projectional editing over arbitrary AST types.
// Language AST packages implement these; the editor framework consumes them
// via trait bounds without depending on any specific AST type.

///|
/// Tree structure capability — structural access for reconciliation and traversal.
pub(open) trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///|
/// Rendering + text capability — display and serialization for projectional editors.
pub(open) trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}
