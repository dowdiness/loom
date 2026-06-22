///|
test "SyntaxKind: WhitespaceToken is trivia" {
  inspect(@syntax.WhitespaceToken.is_trivia(), content="true")
}

///|
test "SyntaxKind: LambdaToken is not trivia" {
  inspect(@syntax.LambdaToken.is_trivia(), content="false")
}

///|
test "SyntaxKind: ErrorToken is error" {
  inspect(@syntax.ErrorToken.is_error(), content="true")
}

///|
test "SyntaxKind: LambdaToken is not error" {
  inspect(@syntax.LambdaToken.is_error(), content="false")
}
