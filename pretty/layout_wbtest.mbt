///|
test "Layout constructors via combinators" {
  let doc : Layout[Unit] = text("hello") + text(" ") + text("world")
  inspect(
    doc,
    content=(
      #|Concat(
      #|  Concat(Text("hello", 5), Text(" ", 1), 6),
      #|  Text("world", 5),
      #|  11,
      #|)
    ),
  )
}
