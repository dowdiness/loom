///|
test "Token: Whitespace is trivia" {
  inspect(@token.Whitespace.is_trivia(), content="true")
}

///|
test "Token: Lambda is not trivia" {
  inspect(@token.Lambda.is_trivia(), content="false")
}

///|
test "Token: EOF is_eof" {
  inspect(@token.EOF.is_eof(), content="true")
}

///|
test "Token: Lambda is not eof" {
  inspect(@token.Lambda.is_eof(), content="false")
}
