///|
fn test_leaf(start : Int, end : Int, key : String) -> @projection.ProjectionLeaf {
  @projection.ProjectionLeaf::new(start, end, key)
}

///|
fn test_stable(
  start : Int,
  end : Int,
  key : String,
  id : String,
) -> @projection.StableProjectionLeaf[String] {
  @projection.StableProjectionLeaf::new(start, end, key, id)
}

///|
fn test_ids(leaves : Array[@projection.StableProjectionLeaf[String]]) -> Array[String] {
  leaves.map(leaf => leaf.id)
}

///|
fn test_allocate(prefix : String) -> (@projection.ProjectionLeaf) -> String {
  let mut next = 0
  fn(leaf) {
    let id = prefix + leaf.key + ":" + next.to_string()
    next += 1
    id
  }
}
