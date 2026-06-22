// Tests for damage tracking

///|
test "DamageTracker::new from edit" {
  let edit = @core.Edit::new(10, 5, 10)
  let tracker = DamageTracker::new(edit)
  inspect(tracker.damaged_ranges.length(), content="1")
  inspect(tracker.damaged_ranges[0].start, content="10")
  inspect(tracker.damaged_ranges[0].end, content="20")
}

///|
test "DamageTracker::is_damaged" {
  let edit = @core.Edit::new(10, 5, 10)
  let tracker = DamageTracker::new(edit)
  inspect(tracker.is_damaged(@core.Range::new(5, 8)), content="false")
  inspect(tracker.is_damaged(@core.Range::new(12, 18)), content="true")
  inspect(tracker.is_damaged(@core.Range::new(25, 30)), content="false")
}

///|
test "DamageTracker::is_position_damaged" {
  let edit = @core.Edit::new(10, 5, 10)
  let tracker = DamageTracker::new(edit)
  inspect(tracker.is_position_damaged(5), content="false")
  inspect(tracker.is_position_damaged(12), content="true")
  inspect(tracker.is_position_damaged(25), content="false")
}

///|
test "DamageTracker::add_range merges overlapping" {
  let tracker = DamageTracker::empty()
  tracker.add_range(@core.Range::new(5, 10))
  tracker.add_range(@core.Range::new(8, 15))

  // Should have merged into one range
  inspect(tracker.damaged_ranges.length(), content="1")
  inspect(tracker.damaged_ranges[0].start, content="5")
  inspect(tracker.damaged_ranges[0].end, content="15")
}

///|
test "DamageTracker::add_range keeps non-overlapping separate" {
  let tracker = DamageTracker::empty()
  tracker.add_range(@core.Range::new(5, 10))
  tracker.add_range(@core.Range::new(20, 25))

  // Should have two separate ranges
  inspect(tracker.damaged_ranges.length(), content="2")
}

///|
test "DamageTracker::expand_for_node" {
  let edit = @core.Edit::new(10, 5, 10)
  let tracker = DamageTracker::new(edit)

  // Expand to include a node that overlaps
  tracker.expand_for_node(8, 25)
  let total_range = tracker.range()
  inspect(total_range.start, content="8")
  inspect(total_range.end, content="25")
}
