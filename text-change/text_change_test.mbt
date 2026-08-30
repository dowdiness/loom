///|
fn assert_range(
  change : TextChange,
  start : Int,
  delete_len : Int,
  inserted : String,
) -> Unit {
  match change {
    ReplaceRange(
      start=actual_start,
      delete_len=actual_delete_len,
      inserted=actual_inserted
    ) =>
      if actual_start != start ||
        actual_delete_len != delete_len ||
        actual_inserted != inserted {
        abort("ReplaceRange fields differ from expected values")
      }
    ReplaceAll(_) => abort("expected ReplaceRange")
  }
}

///|
test "compute_text_change replaces middle span" {
  assert_range(compute_text_change("abc", "aXYc"), 1, 1, "XY")
}

///|
test "compute_text_change returns no-op for equal text" {
  let change = compute_text_change("abc", "abc")
  assert_range(change, 3, 0, "")
  inspect(change.is_noop(), content="true")
}

///|
test "compute_text_change handles insertion into empty text" {
  assert_range(compute_text_change("", "abc"), 0, 0, "abc")
}

///|
test "compute_text_change handles deleting all text" {
  assert_range(compute_text_change("abc", ""), 0, 3, "")
}

///|
test "compute_text_change replaces whole non-BMP emoji cluster" {
  assert_range(compute_text_change("a😀", "a😁"), 1, 2, "😁")
}

///|
test "compute_text_change appends whole non-BMP emoji cluster" {
  assert_range(compute_text_change("a", "a😀"), 1, 0, "😀")
}

///|
test "compute_text_change replaces whole combining-mark cluster" {
  assert_range(compute_text_change("e\u{0301}", "a\u{0301}"), 0, 2, "a\u{0301}")
}

///|
test "ReplaceRange applies one validated UTF-16 splice" {
  let change = TextChange::ReplaceRange(start=1, delete_len=2, inserted="😁")
  debug_inspect(change.apply("a😀b"), content="Some(\"a😁b\")")
}

///|
test "ReplaceRange rejects an invalid UTF-16 boundary" {
  let change = TextChange::ReplaceRange(start=2, delete_len=1, inserted="x")
  debug_inspect(change.apply("a😀b"), content="None")
}

///|
test "ReplaceAll adopts the complete text" {
  let change = TextChange::ReplaceAll("complete")
  debug_inspect(change.apply("old"), content="Some(\"complete\")")
  inspect(change.is_noop(), content="false")
}

///|
test "ChangeSet empty and single replacement" {
  let empty = ChangeSet::empty(3)
  inspect(empty.is_empty(), content="true")
  inspect(empty.source_length(), content="3")
  inspect(empty.result_length(), content="3")
  debug_inspect(empty.apply("abc"), content="Some(\"abc\")")
  let set = ChangeSet::ChangeSet(source_length=5, changes=[
    TextChange::ReplaceRange(start=1, delete_len=3, inserted="XY"),
  ])
  inspect(set.is_empty(), content="false")
  inspect(set.result_length(), content="4")
  debug_inspect(set.apply("abcde"), content="Some(\"aXYe\")")
}

///|
test "ChangeSet applies multiple adjacent original-coordinate edits" {
  let set = ChangeSet::ChangeSet(source_length=6, changes=[
    TextChange::ReplaceRange(start=1, delete_len=1, inserted="XX"),
    TextChange::ReplaceRange(start=2, delete_len=2, inserted="Y"),
    TextChange::ReplaceRange(start=4, delete_len=0, inserted="Z"),
  ])
  debug_inspect(set.apply("abcdef"), content="Some(\"aXXYZef\")")
  inspect(set.result_length(), content="7")
}

///|
test "ChangeSet normalizes empty no-ops" {
  let set = ChangeSet::ChangeSet(source_length=2, changes=[
    TextChange::ReplaceRange(start=1, delete_len=0, inserted=""),
  ])
  inspect(set.is_empty(), content="true")
  debug_inspect(set.apply("ab"), content="Some(\"ab\")")
}

///|
test "ChangeSet rejects invalid changes" {
  try ChangeSet::empty(-1) catch {
    e => debug_inspect(e, content="NegativeSourceLength")
  } noraise {
    _ => fail("expected negative source length to raise")
  }
  try
    ChangeSet::ChangeSet(source_length=3, changes=[
      TextChange::ReplaceRange(start=-1, delete_len=0, inserted=""),
    ])
  catch {
    e =>
      debug_inspect(e, content="NegativeRange(index=0, start=-1, delete_len=0)")
  } noraise {
    _ => fail("expected negative range to raise")
  }
  try
    ChangeSet::ChangeSet(source_length=3, changes=[
      TextChange::ReplaceRange(start=2, delete_len=2, inserted=""),
    ])
  catch {
    e =>
      debug_inspect(e, content="OutOfBounds(index=0, end=4, source_length=3)")
  } noraise {
    _ => fail("expected out of bounds to raise")
  }
  try
    ChangeSet::ChangeSet(source_length=4, changes=[
      TextChange::ReplaceRange(start=1, delete_len=2, inserted=""),
      TextChange::ReplaceRange(start=2, delete_len=1, inserted=""),
    ])
  catch {
    e => debug_inspect(e, content="Overlapping(index=1)")
  } noraise {
    _ => fail("expected overlap to raise")
  }
  try
    ChangeSet::ChangeSet(source_length=4, changes=[
      TextChange::ReplaceRange(start=2, delete_len=0, inserted="x"),
      TextChange::ReplaceRange(start=1, delete_len=0, inserted="y"),
    ])
  catch {
    e => debug_inspect(e, content="Unordered(index=1)")
  } noraise {
    _ => fail("expected unordered changes to raise")
  }
  try
    ChangeSet::ChangeSet(source_length=3, changes=[TextChange::ReplaceAll("x")])
  catch {
    e => debug_inspect(e, content="ReplaceAll(index=0)")
  } noraise {
    _ => fail("expected ReplaceAll to raise")
  }
}

///|
test "ChangeSet rejects source mismatch and surrogate boundaries" {
  let set = ChangeSet::ChangeSet(source_length=3, changes=[
    TextChange::ReplaceRange(start=1, delete_len=1, inserted="x"),
  ])
  debug_inspect(set.apply("ab"), content="None")
  let surrogate = ChangeSet::ChangeSet(source_length=3, changes=[
    TextChange::ReplaceRange(start=2, delete_len=1, inserted="x"),
  ])
  debug_inspect(surrogate.apply("a😀b"), content="None")
}

///|
test "ChangeSet defensively owns the changes array" {
  let changes = [TextChange::ReplaceRange(start=1, delete_len=1, inserted="x")]
  let set = ChangeSet::ChangeSet(source_length=3, changes~)
  changes[0] = TextChange::ReplaceAll("wrong")
  debug_inspect(set.apply("abc"), content="Some(\"axc\")")
}
