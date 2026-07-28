///|
test "char_before: decodes the preceding non-BMP scalar" {
  inspect(char_before("a😈*", 3) == Some('😈'), content="true")
}
