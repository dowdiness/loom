///|
test "IncrementalParser snapshots its initial source" {
  let parser = IncrementalParser::IncrementalParser("first\n")
  let document = parser.snapshot()
  assert_eq(document.source(), "first\n")
  assert_eq(document.root().view(), MarkdownNodeView::Document)
}

///|
test "IncrementalParser updates from authoritative source without a hint" {
  let parser = IncrementalParser::IncrementalParser("first\n")
  let before = parser.snapshot()
  parser.update("second\n")
  assert_eq(parser.snapshot().source(), "second\n")
  assert_eq(before.source(), "first\n")
}

///|
test "IncrementalParser accepts a matching multi-edit hint" {
  let parser = IncrementalParser::IncrementalParser("abcd\n")
  let changes = @text_change.ChangeSet::ChangeSet(source_length=5, changes=[
    @text_change.TextChange::ReplaceRange(start=0, delete_len=1, inserted="A"),
    @text_change.TextChange::ReplaceRange(start=3, delete_len=1, inserted="D"),
  ])
  parser.update("AbcD\n", changes~)
  assert_eq(parser.snapshot().source(), "AbcD\n")
}

///|
test "IncrementalParser rejects a mismatched hint without mutation" {
  let parser = IncrementalParser::IncrementalParser("abcd\n")
  let changes = @text_change.ChangeSet::ChangeSet(source_length=5, changes=[
    @text_change.TextChange::ReplaceRange(start=0, delete_len=1, inserted="X"),
  ])
  let result : Result[Unit, Error] = Ok(parser.update("Abcd\n", changes~)) catch {
    error => Err(error)
  }
  match result {
    Err(MarkdownUpdateError::ChangeSetMismatch) => ()
    _ => fail("expected ChangeSetMismatch")
  }
  assert_eq(parser.snapshot().source(), "abcd\n")
}
