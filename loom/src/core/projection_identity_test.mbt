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
fn test_make_string_id(key : String, occurrence : Int) -> String {
  "mini:" + key + ":" + occurrence.to_string()
}

///|
struct TestProjectionItem {
  start : Int
  end : Int
  family : String
  text : String
}

///|
struct TestStableProjectionItem {
  start : Int
  end : Int
  family : String
  text : String
  id : String
}

///|
fn test_item(
  start : Int,
  end : Int,
  family : String,
  text : String,
) -> TestProjectionItem {
  { start, end, family, text }
}

///|
fn test_item_key(item : TestProjectionItem) -> String {
  item.family + ":" + item.text
}

///|
fn test_item_leaf(item : TestProjectionItem) -> ProjectionLeaf {
  ProjectionLeaf::new(item.start, item.end, test_item_key(item))
}

///|
fn test_item_with_id(
  item : TestProjectionItem,
  id : String,
) -> TestStableProjectionItem {
  { start: item.start, end: item.end, family: item.family, text: item.text, id }
}

///|
fn test_item_ids(items : Array[TestStableProjectionItem]) -> Array[String] {
  let ids : Array[String] = []
  for item in items {
    ids.push(item.id)
  }
  ids
}

///|
fn test_item_summaries(
  items : Array[TestStableProjectionItem],
) -> Array[String] {
  let summaries : Array[String] = []
  for item in items {
    summaries.push(
      item.family +
      ":" +
      item.text +
      "@" +
      item.start.to_string() +
      "-" +
      item.end.to_string() +
      "#" +
      item.id,
    )
  }
  summaries
}

///|
test "projection identity: string allocator mints per-key occurrences" {
  let allocator = ProjectionStringIdAllocator::new(test_make_string_id)
  let first = allocator.allocate(test_leaf(0, 2, "sound:bd"))
  let second = allocator.allocate(test_leaf(3, 5, "sound:bd"))
  let other = allocator.allocate(test_leaf(6, 8, "sound:sd"))
  debug_inspect(
    [first, second, other],
    content="[\"mini:sound:bd:0\", \"mini:sound:bd:1\", \"mini:sound:sd:0\"]",
  )
}

///|
test "projection identity: string allocator skips baseline ids" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "mini:sound:bd:0"),
    test_stable(3, 5, "sound:bd", "mini:sound:bd:1"),
  ])
  let allocator = ProjectionStringIdAllocator::from_baseline(
    baseline, test_make_string_id,
  )
  let first = allocator.allocate(test_leaf(3, 5, "sound:bd"))
  let second = allocator.allocate(test_leaf(6, 8, "sound:bd"))
  let other = allocator.allocate(test_leaf(9, 11, "sound:sd"))
  debug_inspect(
    [first, second, other],
    content="[\"mini:sound:bd:2\", \"mini:sound:bd:3\", \"mini:sound:sd:0\"]",
  )
}

///|
test "projection identity: item adapter zips ids back onto domain items" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "mini:sound:bd:0"),
    test_stable(3, 5, "sound:bd", "mini:sound:bd:1"),
  ])
  let allocator = ProjectionStringIdAllocator::from_baseline(
    baseline, test_make_string_id,
  )
  let items = [
    test_item(0, 2, "sound", "bd"),
    test_item(3, 5, "sound", "bd"),
    test_item(6, 8, "sound", "bd"),
  ]
  let result = realign_projection_items(
    baseline,
    "bd bd bd",
    items,
    test_item_leaf,
    test_item_with_id,
    fn(leaf) { allocator.allocate(leaf) },
    edit=Edit::insert(3, 3),
  )
  debug_inspect(
    test_item_ids(result),
    content="[\"mini:sound:bd:0\", \"mini:sound:bd:2\", \"mini:sound:bd:1\"]",
  )
  debug_inspect(
    test_item_summaries(result),
    content=(
      #|[
      #|  "sound:bd@0-2#mini:sound:bd:0",
      #|  "sound:bd@3-5#mini:sound:bd:2",
      #|  "sound:bd@6-8#mini:sound:bd:1",
      #|]
    ),
  )
}

///|
test "projection identity: optional item adapter accepts None fallback" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "mini:sound:bd:0"),
    test_stable(3, 5, "sound:bd", "mini:sound:bd:1"),
  ])
  let allocator = ProjectionStringIdAllocator::from_baseline(
    baseline, test_make_string_id,
  )
  let items = [
    test_item(0, 2, "sound", "bd"),
    test_item(3, 5, "sound", "sd"),
    test_item(6, 8, "sound", "bd"),
  ]
  let result = realign_projection_items_with_optional_edit(
    baseline,
    "bd sd bd",
    items,
    test_item_leaf,
    test_item_with_id,
    fn(leaf) { allocator.allocate(leaf) },
    None,
  )
  debug_inspect(
    test_item_ids(result),
    content="[\"mini:sound:bd:0\", \"mini:sound:sd:0\", \"mini:sound:bd:1\"]",
  )
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
test "projection identity: optional edit helper accepts Some edit" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:bd", "bd:1"),
  ])
  let next = [
    test_leaf(0, 2, "sound:bd"),
    test_leaf(3, 5, "sound:sd"),
    test_leaf(6, 8, "sound:bd"),
  ]
  let result = realign_projection_identities_with_optional_edit(
    baseline,
    "bd sd bd",
    next,
    test_allocate("fresh:"),
    Some(Edit::insert(3, 3)),
  )
  debug_inspect(
    test_ids(result),
    content="[\"bd:0\", \"fresh:sound:sd:0\", \"bd:1\"]",
  )
}

///|
test "projection identity: optional edit helper accepts None fallback" {
  let baseline = ProjectionIdentityBaseline::new("bd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:bd", "bd:1"),
  ])
  let next = [
    test_leaf(0, 2, "sound:bd"),
    test_leaf(3, 5, "sound:sd"),
    test_leaf(6, 8, "sound:bd"),
  ]
  let result = realign_projection_identities_with_optional_edit(
    baseline,
    "bd sd bd",
    next,
    test_allocate("fresh:"),
    None,
  )
  debug_inspect(
    test_ids(result),
    content="[\"bd:0\", \"fresh:sound:sd:0\", \"bd:1\"]",
  )
}

///|
test "projection identity: baseline optional edit advance preserves suffix" {
  let baseline = ProjectionIdentityBaseline::new("bd sd bd", [
    test_stable(0, 2, "sound:bd", "bd:0"),
    test_stable(3, 5, "sound:sd", "sd:0"),
    test_stable(6, 8, "sound:bd", "bd:1"),
  ])
  let next = [test_leaf(0, 2, "sound:bd"), test_leaf(3, 5, "sound:bd")]
  let advanced = baseline.advance_with_optional_edit(
    "bd bd",
    next,
    test_allocate("fresh:"),
    Some(Edit::delete(3, 6)),
  )
  debug_inspect(test_ids(advanced.leaves()), content="[\"bd:0\", \"bd:1\"]")
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

///|
test "projection identity tracker: first success without baseline allocates all ids" {
  let tracker : ProjectionIdentityTracker[String] = ProjectionIdentityTracker::new()
  let next = [test_leaf(0, 2, "sound:aa"), test_leaf(3, 5, "sound:bb")]
  let stable = tracker.realign_success("aa bb", next, test_allocate("fresh:"))
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:aa:0\", \"fresh:sound:bb:1\"]",
  )
  inspect(tracker.baseline() is None, content="true")
  tracker.commit_success("aa bb", stable)
  match tracker.baseline() {
    Some(baseline) => {
      inspect(baseline.source(), content="aa bb")
      debug_inspect(
        test_ids(baseline.leaves()),
        content="[\"fresh:sound:aa:0\", \"fresh:sound:bb:1\"]",
      )
    }
    None => fail("expected committed baseline")
  }
}

///|
test "projection identity tracker: direct successful edit previews then commits" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("bd sd bd", [
      test_stable(0, 2, "sound:bd", "bd:0"),
      test_stable(3, 5, "sound:sd", "sd:0"),
      test_stable(6, 8, "sound:bd", "bd:1"),
    ]),
  )
  let next = [test_leaf(0, 2, "sound:bd"), test_leaf(3, 5, "sound:bd")]
  let stable = tracker.realign_success(
    "bd bd",
    next,
    test_allocate("fresh:"),
    edit=Edit::delete(3, 6),
  )
  debug_inspect(test_ids(stable), content="[\"bd:0\", \"bd:1\"]")
  match tracker.baseline() {
    Some(baseline) => inspect(baseline.source(), content="bd sd bd")
    None => fail("expected retained baseline before commit")
  }
  tracker.commit_success("bd bd", stable)
  match tracker.baseline() {
    Some(baseline) => {
      inspect(baseline.source(), content="bd bd")
      debug_inspect(test_ids(baseline.leaves()), content="[\"bd:0\", \"bd:1\"]")
    }
    None => fail("expected committed baseline")
  }
}

///|
test "projection identity tracker: failed input exact edit is reused on recovery" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("bd bd", [
      test_stable(0, 2, "sound:bd", "bd:0"),
      test_stable(3, 5, "sound:bd", "bd:1"),
    ]),
  )
  tracker.record_failed_input(
    "bd sd bd",
    source_before_edit="bd bd",
    edit=Edit::insert(3, 3),
  )
  let recovered = [
    test_leaf(0, 2, "sound:bd"),
    test_leaf(3, 5, "sound:sd"),
    test_leaf(6, 8, "sound:bd"),
  ]
  let stable = tracker.realign_success(
    "bd sd bd",
    recovered,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"bd:0\", \"fresh:sound:sd:0\", \"bd:1\"]",
  )
  match tracker.baseline() {
    Some(baseline) => inspect(baseline.source(), content="bd bd")
    None => fail("expected retained baseline before commit")
  }
}

///|
test "projection identity tracker: projection failure with no edit uses source diff" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
    ]),
  )
  tracker.record_failed_input("xx aa bb")
  let recovered = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:bb"),
  ]
  let stable = tracker.realign_success(
    "xx aa bb",
    recovered,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx:0\", \"aa:0\", \"bb:0\"]",
  )
}

///|
test "projection identity tracker: mismatched pending exact edit falls back to source diff" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
    ]),
  )
  tracker.record_failed_input(
    "aa bb xx",
    source_before_edit="aa bb",
    edit=Edit::insert(5, 3),
  )
  let recovered = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:bb"),
  ]
  let stable = tracker.realign_success(
    "xx aa bb",
    recovered,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx:0\", \"aa:0\", \"bb:0\"]",
  )
}

///|
test "projection identity tracker: invalid exact edit length falls back to source diff" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
    ]),
  )
  let recovered = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:bb"),
  ]
  let stable = tracker.realign_success(
    "xx aa bb",
    recovered,
    test_allocate("fresh:"),
    edit=Edit::insert(5, 1),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx:0\", \"aa:0\", \"bb:0\"]",
  )
}

///|
test "projection identity tracker: wrong-position exact edit falls back to source diff" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
    ]),
  )
  let recovered = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:bb"),
  ]
  let stable = tracker.realign_success(
    "xx aa bb",
    recovered,
    test_allocate("fresh:"),
    edit=Edit::insert(5, 3),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx:0\", \"aa:0\", \"bb:0\"]",
  )
}

///|
test "projection identity tracker: second failed edit degrades to source diff" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
    ]),
  )
  tracker.record_failed_input_with_optional_edit(
    "aa bb xx",
    Some("aa bb"),
    Some(Edit::insert(5, 3)),
  )
  tracker.record_failed_input("xx aa bb")
  let recovered = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:bb"),
  ]
  let stable = tracker.realign_success(
    "xx aa bb",
    recovered,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx:0\", \"aa:0\", \"bb:0\"]",
  )
}

///|
test "projection identity tracker: allocator only runs for changed leaves" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb cc", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
      test_stable(6, 8, "sound:cc", "cc:0"),
    ]),
  )
  let allocated : Array[String] = []
  let next = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:bb"),
    test_leaf(9, 11, "sound:cc"),
  ]
  let stable = tracker.realign_success(
    "xx aa bb cc",
    next,
    fn(leaf) {
      allocated.push(leaf.key)
      "fresh:" + leaf.key
    },
    edit=Edit::insert(0, 3),
  )
  debug_inspect(allocated, content="[\"sound:xx\"]")
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx\", \"aa:0\", \"bb:0\", \"cc:0\"]",
  )
}
