///|
test "to_edits: empty" {
  let result = to_edits([])
  inspect(result.length(), content="0")
}

///|
test "to_edits: retain only produces no edits" {
  let result = to_edits([TextDelta::Retain(10)])
  inspect(result.length(), content="0")
}

///|
test "to_edits: pure insert at start" {
  let result = to_edits([TextDelta::Insert("hi")])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="0")
  inspect(result[0].new_len, content="2")
}

///|
test "to_edits: insert after retain" {
  let result = to_edits([TextDelta::Retain(5), TextDelta::Insert("hi")])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="5")
  inspect(result[0].old_len, content="0")
  inspect(result[0].new_len, content="2")
}

///|
test "to_edits: delete after retain" {
  let result = to_edits([TextDelta::Retain(3), TextDelta::Delete(4)])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="3")
  inspect(result[0].old_len, content="4")
  inspect(result[0].new_len, content="0")
}

///|
test "to_edits: delete+insert merges into replace" {
  // The common CRDT case: [Retain(5), Delete(3), Insert("hi")] → one Edit
  let result = to_edits([
    TextDelta::Retain(5),
    TextDelta::Delete(3),
    TextDelta::Insert("hi"),
  ])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="5")
  inspect(result[0].old_len, content="3")
  inspect(result[0].new_len, content="2")
}

///|
test "to_edits: multi-op adjusts positions sequentially" {
  // [Retain(3), Delete(2), Retain(4), Insert("x")]
  // Edit 1: delete 2 at position 3, no Insert follows → Edit { start: 3, old_len: 2, new_len: 0 }
  // accumulated_delta = -2; cursor_orig = 5
  // Retain(4): cursor_orig = 9
  // Edit 2: insert at position 9 + (-2) = 7 → Edit { start: 7, old_len: 0, new_len: 1 }
  let result = to_edits([
    TextDelta::Retain(3),
    TextDelta::Delete(2),
    TextDelta::Retain(4),
    TextDelta::Insert("x"),
  ])
  inspect(result.length(), content="2")
  inspect(result[0].start, content="3")
  inspect(result[0].old_len, content="2")
  inspect(result[0].new_len, content="0")
  inspect(result[1].start, content="7")
  inspect(result[1].old_len, content="0")
  inspect(result[1].new_len, content="1")
}

///|
test "to_edits: insert then delete — no merge, positions adjusted" {
  // [Insert("x"), Delete(2)] — Insert comes first, Delete does not merge
  // Insert("x"): emit Edit { start: 0, old_len: 0, new_len: 1 }, accumulated_delta = 1
  // Delete(2): emit Edit { start: 0 + 1 = 1, old_len: 2, new_len: 0 }
  let result = to_edits([TextDelta::Insert("x"), TextDelta::Delete(2)])
  inspect(result.length(), content="2")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="0")
  inspect(result[0].new_len, content="1")
  inspect(result[1].start, content="1")
  inspect(result[1].old_len, content="2")
  inspect(result[1].new_len, content="0")
}

///|
test "text_to_delta: identical strings — Retain only" {
  let result = text_to_delta("abc", "abc")
  // Retain(3), no delete/insert
  inspect(result.length(), content="1")
  match result[0] {
    TextDelta::Retain(3) => ()
    other => abort("expected Retain(3), got: " + @debug.to_string(other))
  }
}

///|
test "text_to_delta: pure insert in middle" {
  // "abc" → "abXc": insert "X" at position 2
  let result = text_to_delta("abc", "abXc")
  inspect(result.length(), content="2")
  inspect(result[0], content="Retain(2)")
  inspect(result[1], content="Insert(\"X\")")
}

///|
test "text_to_delta: pure delete in middle" {
  // "abXc" → "abc": delete "X" at position 2
  let result = text_to_delta("abXc", "abc")
  inspect(result.length(), content="2")
  inspect(result[0], content="Retain(2)")
  inspect(result[1], content="Delete(1)")
}

///|
test "text_to_delta: replace middle" {
  // "hello" → "world": nothing in common
  let result = text_to_delta("hello", "world")
  inspect(result.length(), content="2")
  inspect(result[0], content="Delete(5)")
  inspect(result[1], content="Insert(\"world\")")
}

///|
test "text_to_delta: insert at start" {
  // "" → "hi": pure insert
  let result = text_to_delta("", "hi")
  inspect(result.length(), content="1")
  inspect(result[0], content="Insert(\"hi\")")
}

///|
test "text_to_delta: round-trip with to_edits" {
  // text_to_delta → to_edits should produce one Edit for a simple replacement
  let delta = text_to_delta("λx. x", "λx. x + 1")
  let edits = to_edits(delta)
  inspect(edits.length(), content="1")
  inspect(edits[0].start, content="5")
  inspect(edits[0].old_len, content="0")
  inspect(edits[0].new_len, content="4")
}
