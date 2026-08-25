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
