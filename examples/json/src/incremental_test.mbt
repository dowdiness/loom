///|
test "incremental: edit value in object matches full reparse" {
  let source = "{\"a\": 1}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "{\"a\": 2}"
  let edit = @core.Edit::new(6, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
}

///|
test "incremental: edit value in array matches full reparse" {
  let source = "[1, 2, 3]"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "[1, 9, 3]"
  let edit = @core.Edit::new(4, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
}

///|
test "block reparse: edit inside object uses block reparse" {
  let source = "{\"x\": {\"a\": 1}, \"y\": 2}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  // Edit inside inner object: change 1 to 9
  let new_source = "{\"x\": {\"a\": 9}, \"y\": 2}"
  let edit = @core.Edit::new(12, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
  // Block reparse should have been used
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: edit inside array uses block reparse" {
  let source = "{\"arr\": [1, 2, 3]}"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "{\"arr\": [1, 9, 3]}"
  let edit = @core.Edit::new(12, 1, 1)
  let incr = parser.edit(edit, new_source)
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
  inspect(parser.get_last_reuse_count(), content="1")
}

///|
test "block reparse: no container falls through" {
  let source = "42"
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let new_source = "99"
  let edit = @core.Edit::new(0, 2, 2)
  let incr = parser.edit(edit, new_source)
  let full = try! parse(new_source)
  inspect(incr.to_string(), content=full.to_string())
  // No block reparse — reuse_count != 1
  inspect(parser.get_last_reuse_count() != 1, content="true")
}
