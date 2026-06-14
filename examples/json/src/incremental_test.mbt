///|
fn nested_array_source(depth : Int, leaf : String) -> String {
  let builder = StringBuilder::new()
  for _i = 0; _i < depth; _i = _i + 1 {
    builder.write_char('[')
  }
  builder.write_string(leaf)
  for _i = 0; _i < depth; _i = _i + 1 {
    builder.write_char(']')
  }
  builder.to_string()
}

///|
test "incremental: edit value in object matches full reparse" {
  let source = "{\"a\": 1}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse().ast
  let new_source = "{\"a\": 2}"
  let edit = @core.Edit::new(6, 1, 1)
  let incr = parser.edit(edit, new_source).ast
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
}

///|
test "incremental: edit value in array matches full reparse" {
  let source = "[1, 2, 3]"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse().ast
  let new_source = "[1, 9, 3]"
  let edit = @core.Edit::new(4, 1, 1)
  let incr = parser.edit(edit, new_source).ast
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
}

///|
test "incremental: deletion opt-in reuses left-adjacent array element" {
  let source = "[1 , 2]"
  let (old_tree, _) = try! parse_cst(source)
  let new_source = "[1, 2]"
  let tokens = try! tokenize(new_source)
  let edit = @core.Edit::delete(2, 3)
  let strict_cursor = make_reuse_cursor_with_edit(
    old_tree, edit, tokens, new_source,
  )
  let (_, strict_errors, strict_reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    tokens,
    Some(strict_cursor),
  )
  let relaxed_cursor = make_reuse_cursor_with_edit(
    old_tree,
    edit,
    tokens,
    new_source,
    allow_left_adjacent_reuse=true,
  )
  let (incr, errors, relaxed_reuse_count) = parse_cst_recover_with_tokens(
    new_source,
    tokens,
    Some(relaxed_cursor),
  )
  let (full, _) = try! parse_cst(new_source)
  inspect(incr == full, content="true")
  inspect(strict_errors.length(), content="0")
  inspect(errors.length(), content="0")
  inspect(relaxed_reuse_count > strict_reuse_count, content="true")
}

///|
test "block reparse: edit inside object uses block reparse" {
  let source = "{\"x\": {\"a\": 1}, \"y\": 2}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse().ast
  // Edit inside inner object: change 1 to 9
  let new_source = "{\"x\": {\"a\": 9}, \"y\": 2}"
  let edit = @core.Edit::new(12, 1, 1)
  let incr = parser.edit(edit, new_source).ast
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
  // Block reparse should have been used
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: edit inside array uses block reparse" {
  let source = "{\"arr\": [1, 2, 3]}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse().ast
  let new_source = "{\"arr\": [1, 9, 3]}"
  let edit = @core.Edit::new(12, 1, 1)
  let incr = parser.edit(edit, new_source).ast
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: carries absolute nesting depth" {
  let depth = 512
  let source = nested_array_source(depth, "0")
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let initial = parser.parse()
  inspect(initial.diagnostics.length(), content="0")
  let new_source = nested_array_source(depth, "[0]")
  let edit = @core.Edit::new(depth, 1, 3)
  let incr = parser.edit(edit, new_source)
  let (full_cst, full_diagnostics) = try! parse_cst(new_source)
  inspect(incr.diagnostics.length() > 0, content="true")
  inspect(
    incr.diagnostics.format() == full_diagnostics.format(),
    content="true",
  )
  inspect(
    @core.tree_diff(incr.syntax.cst_node(), full_cst).length(),
    content="0",
  )
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: no container falls through" {
  let source = "42"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse().ast
  let new_source = "99"
  let edit = @core.Edit::new(0, 2, 2)
  let incr = parser.edit(edit, new_source).ast
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
  // No block reparse — reuse_count != 1
  inspect(parser.get_last_reuse_count() != 1, content="true")
}
