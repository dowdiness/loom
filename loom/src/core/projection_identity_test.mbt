///|
fn test_leaf(start : Int, end : Int, key : String) -> ProjectionLeaf {
  ProjectionLeaf::new(start, end, key)
}

///|
fn test_stable(
  start : Int,
  end : Int,
  key : String,
  id : String,
) -> StableProjectionLeaf[String] {
  StableProjectionLeaf::new(start, end, key, id)
}

///|
fn test_ids(leaves : Array[StableProjectionLeaf[String]]) -> Array[String] {
  leaves.map(fn(leaf) { leaf.id })
}

///|
fn test_allocate(prefix : String) -> (ProjectionLeaf) -> String {
  let mut next = 0
  fn(leaf) {
    let id = prefix + leaf.key + ":" + next.to_string()
    next += 1
    id
  }
}
