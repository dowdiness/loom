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
test "projection identity tracker: failed baseline edit survives recovery that restores text" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb cc", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
      test_stable(6, 8, "sound:cc", "cc:0"),
    ]),
  )
  tracker.record_failed_input(
    "aa xx cc!",
    source_before_edit="aa bb cc",
    edit=Edit::replace(3, 5, 5),
  )
  let recovered = [
    test_leaf(0, 2, "sound:aa"),
    test_leaf(3, 5, "sound:bb"),
    test_leaf(6, 8, "sound:cc"),
  ]
  let stable = tracker.realign_success(
    "aa bb cc",
    recovered,
    test_allocate("fresh:"),
    edit=Edit::replace(3, 9, 8),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"aa:0\", \"fresh:sound:bb:0\", \"cc:0\"]",
  )
}

///|
test "projection identity tracker: recovery edit relative to malformed text does not overwrite pending edit" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa aa cc", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:aa", "aa:1"),
      test_stable(6, 8, "sound:cc", "cc:0"),
    ]),
  )
  tracker.record_failed_input(
    "aa xx cc!",
    source_before_edit="aa aa cc",
    edit=Edit::replace(3, 5, 5),
  )
  let recovered = [
    test_leaf(0, 2, "sound:aa"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:cc"),
  ]
  let stable = tracker.realign_success(
    "aa aa cc",
    recovered,
    test_allocate("fresh:"),
    edit=Edit::replace(3, 9, 8),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"aa:0\", \"fresh:sound:aa:0\", \"cc:0\"]",
  )
}

///|
test "projection identity tracker: multiple failed edits compose reverted text exactly" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa bb cc", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:bb", "bb:0"),
      test_stable(6, 8, "sound:cc", "cc:0"),
    ]),
  )
  tracker.record_failed_input(
    "aa xx cc",
    source_before_edit="aa bb cc",
    edit=Edit::replace(3, 5, 5),
  )
  tracker.record_failed_input_with_optional_edit(
    "aa bb cc",
    Some("aa xx cc"),
    Some(Edit::replace(3, 5, 5)),
  )
  let recovered = [
    test_leaf(0, 2, "sound:aa"),
    test_leaf(3, 5, "sound:bb"),
    test_leaf(6, 8, "sound:cc"),
  ]
  let stable = tracker.realign_success(
    "aa bb cc",
    recovered,
    test_allocate("fresh:"),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"aa:0\", \"fresh:sound:bb:0\", \"cc:0\"]",
  )
}

///|
test "projection identity tracker: composition allows extra malformed damage" {
  let tracker = ProjectionIdentityTracker::from_baseline(
    ProjectionIdentityBaseline::new("aa aa cc", [
      test_stable(0, 2, "sound:aa", "aa:0"),
      test_stable(3, 5, "sound:aa", "aa:1"),
      test_stable(6, 8, "sound:cc", "cc:0"),
    ]),
  )
  tracker.record_failed_input(
    "aa xx cc!",
    source_before_edit="aa aa cc",
    edit=Edit::replace(3, 5, 5),
  )
  let recovered = [
    test_leaf(0, 2, "sound:xx"),
    test_leaf(3, 5, "sound:aa"),
    test_leaf(6, 8, "sound:cc"),
  ]
  let stable = tracker.realign_success(
    "xx aa cc",
    recovered,
    test_allocate("fresh:"),
    edit=Edit::replace(0, 9, 8),
  )
  debug_inspect(
    test_ids(stable),
    content="[\"fresh:sound:xx:0\", \"fresh:sound:aa:1\", \"fresh:sound:cc:2\"]",
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
