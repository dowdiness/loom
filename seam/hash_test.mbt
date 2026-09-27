///|
test "string_hash is deterministic" {
  inspect(
    @seam.string_hash("hello") == @seam.string_hash("hello"),
    content="true",
  )
}

///|
test "string_hash differs for different strings" {
  inspect(@seam.string_hash("a") == @seam.string_hash("b"), content="false")
}

///|
test "combine_hash is nonzero for nonzero inputs" {
  inspect(@seam.combine_hash(1, 2) != 0, content="true")
}
