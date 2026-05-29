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
  let ids : Array[String] = []
  for leaf in leaves {
    ids.push(leaf.id)
  }
  ids
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

///|
test "projection identity: insertion among duplicates preserves suffix" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:bd", "bd:1"),
  ])
  let next = [
    test_leaf(0, 2, "sound:bd"),
    test_leaf(3, 5, "sound:sd"),
    test_leaf(6, 8, "sound:bd"),
  ]
  let result = realign_projection_identities(
    baseline,
    "bd sd bd",
    next,
    test_allocate("fresh:"),
    edit=Edit::insert(3, 3),
  )
  debug_inspect(
    test_ids(result),
    content="[\"bd:0\", \"fresh:sound:sd:0\", \"bd:1\"]",
  )
}

///|
test "projection identity: deletion preserves shifted suffix duplicate" {
  let baseline = ProjectionIdentityBaseline::new("bd sd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:sd", "sd:0"),
    test_stable(6, 8, "sound:bd", "bd:1"),
  ])
  let next = [test_leaf(0, 2, "sound:bd"), test_leaf(3, 5, "sound:bd")]
  let advanced = baseline.advance(
    "bd bd",
    next,
    test_allocate("fresh:"),
    edit=Edit::delete(3, 6),
  )
  debug_inspect(test_ids(advanced.leaves()), content="[\"bd:0\", \"bd:1\"]")
}

///|
test "projection identity: replacement inside duplicate family is fresh" {
  let baseline = ProjectionIdentityBaseline::new("bd bd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:bd", "bd:1"),
    test_stable(6, 8, "sound:bd", "bd:2"),
  ])
  let next = [
    test_leaf(0, 2, "sound:bd"),
    test_leaf(3, 5, "sound:sd"),
    test_leaf(6, 8, "sound:bd"),
  ]
  let result = realign_projection_identities(
    baseline,
    "bd sd bd",
    next,
    test_allocate("fresh:"),
    edit=Edit::replace(3, 5, 5),
  )
  debug_inspect(
    test_ids(result),
    content="[\"bd:0\", \"fresh:sound:sd:0\", \"bd:2\"]",
  )
}

///|
test "projection identity: whitespace-only edit preserves sourced ids" {
  let baseline = ProjectionIdentityBaseline::new("bd sd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:sd", "sd:0"),
  ])
  let next = [test_leaf(0, 2, "sound:bd"), test_leaf(5, 7, "sound:sd")]
  let result = realign_projection_identities(
    baseline,
    "bd   sd",
    next,
    test_allocate("fresh:"),
    edit=Edit::insert(3, 2),
  )
  debug_inspect(test_ids(result), content="[\"bd:0\", \"sd:0\"]")
}

///|
test "projection identity: source diff fallback preserves prefix and suffix" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:bd", "bd:1"),
  ])
  let next = [
    test_leaf(0, 2, "sound:bd"),
    test_leaf(3, 5, "sound:sd"),
    test_leaf(6, 8, "sound:bd"),
  ]
  let result = realign_projection_identities(
    baseline,
    "bd sd bd",
    next,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(result),
    content="[\"bd:0\", \"fresh:sound:sd:0\", \"bd:1\"]",
  )
}

///|
test "projection identity: retained last-good baseline survives recovery" {
  let baseline = ProjectionIdentityBaseline::new("s(\"bd sd bd bd\")", [
    test_stable(3, 5, "sound:bd", "mini:sound:bd:0"),
    test_stable(6, 8, "sound:sd", "mini:sound:sd:0"),
    test_stable(9, 11, "sound:bd", "mini:sound:bd:2"),
    test_stable(12, 14, "sound:bd", "mini:sound:bd:1"),
  ])
  let recovered = [
    test_leaf(3, 5, "sound:bd"),
    test_leaf(6, 8, "sound:sd"),
    test_leaf(9, 11, "sound:bd"),
    test_leaf(12, 14, "sound:bd"),
  ]
  let result = realign_projection_identities(
    baseline,
    "s(\"bd sd bd bd\")",
    recovered,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(result),
    content="[\n  \"mini:sound:bd:0\",\n  \"mini:sound:sd:0\",\n  \"mini:sound:bd:2\",\n  \"mini:sound:bd:1\",\n]",
  )
}

///|
test "projection identity: key mismatch in reusable region allocates fresh" {
  let baseline = ProjectionIdentityBaseline::new("aa bb", [
    test_stable(0, 2, "sound:aa", "aa:0"),
    test_stable(3, 5, "sound:bb", "bb:0"),
  ])
  let next = [test_leaf(0, 2, "note:aa"), test_leaf(3, 5, "sound:bb")]
  let result = realign_projection_identities(
    baseline,
    "aa bb!",
    next,
    test_allocate("fresh:"),
    edit=Edit::insert(5, 1),
  )
  debug_inspect(test_ids(result), content="[\"fresh:note:aa:0\", \"bb:0\"]")
}
