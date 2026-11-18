///|
/// Every intermediate state is edited incrementally and must match a fresh
/// parse. The sequence moves `let b = 2\n` in front of `let a = 1`, passing
/// through texts with stray tokens; it caught stale follow-token evidence in
/// the persistent old-token cache after earlier incremental edits.
test "incremental parse: sequential edits through invalid states match a fresh parse" {
  let sid = @core.SourceId::SourceId("lambda-sequential-edits")
  let mut source = "let a = 1\nlet b = 2\na"
  let parser = @loom.new_imperative_parser(sid, source, @lambda.lambda_grammar)
  let _ = parser.parse().ast
  let check = fn(incremental : @ast.Term) -> Unit raise {
    let fresh = @loom.new_imperative_parser(sid, source, @lambda.lambda_grammar).parse().ast
    inspect(@ast.print_term(incremental), content=@ast.print_term(fresh))
  }
  for _ in 0..<10 {
    let next = source[:9].to_owned() + source[10:].to_owned()
    let incremental = parser.edit(@core.Edit::delete(9, 10), next).ast
    source = next
    check(incremental)
  }
  let moved = "let b = 2\n"
  for i in 0..<moved.length() {
    let next = source[:i].to_owned() +
      moved[i:i + 1].to_owned() +
      source[i:].to_owned()
    let incremental = parser.edit(@core.Edit::insert(i, 1), next).ast
    source = next
    check(incremental)
  }
}

///|
/// A node ending at a pure deletion's start was reused although the deleted
/// text was its follow token (or its last token merged with the text after
/// the deletion). Each deletion starts from a fresh parser.
test "incremental parse: single deletions at a node boundary match a fresh parse" {
  let sid = @core.SourceId::SourceId("lambda-boundary-deletions")
  let cases = [
    ("let a = 1\n 2\na", 9, 10),
    ("let a = 1= 2\na", 9, 11),
    ("let a = 1\n 2\na", 9, 11),
    ("let a = 1 b 2\na", 13, 14),
    ("let a = 1\nlet b = 2\na", 19, 20),
  ]
  for c in cases {
    let (source, start, end) = c
    let next = source[:start].to_owned() + source[end:].to_owned()
    let parser = @loom.new_imperative_parser(
      sid, source, @lambda.lambda_grammar,
    )
    let _ = parser.parse().ast
    let incremental = parser.edit(@core.Edit::delete(start, end), next).ast
    let fresh = @loom.new_imperative_parser(sid, next, @lambda.lambda_grammar).parse().ast
    inspect(@ast.print_term(incremental), content=@ast.print_term(fresh))
  }
}
