///|
test "error recovery: unclosed bold" {
  let block = parse("**unclosed\n")
  match block {
    Document(blocks) => inspect(blocks.length() > 0, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "error recovery: unclosed link" {
  let block = parse("[unclosed\n")
  match block {
    Document(blocks) => inspect(blocks.length() > 0, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "error recovery: unclosed code fence" {
  let block = parse("```\ncode without close\n")
  match block {
    Document(blocks) => inspect(blocks.length() > 0, content="true")
    _ => inspect(false, content="true")
  }
}
