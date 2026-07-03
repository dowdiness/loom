///|
test "text" {
  let doc : Layout[Unit] = text("hello")
  inspect(doc, content="Text(\"hello\", 5)")
}

///|
test "char" {
  let doc : Layout[Unit] = char('x')
  inspect(doc, content="Text(\"x\", 1)")
}

///|
test "line" {
  let doc : Layout[Unit] = line()
  inspect(doc, content="Line(1)")
}

///|
test "hardline" {
  let doc : Layout[Unit] = hardline()
  inspect(doc, content="HardLine(-1)")
}

///|
test "softline is group(line)" {
  let doc : Layout[Unit] = softline()
  inspect(doc, content="Group(Line(1), 1)")
}

///|
test "nest" {
  let doc : Layout[Unit] = nest(text("x"))
  inspect(doc, content="Nest(2, Text(\"x\", 1), 1)")
}

///|
test "nest custom indent" {
  let doc : Layout[Unit] = nest(indent=4, text("x"))
  inspect(doc, content="Nest(4, Text(\"x\", 1), 1)")
}

///|
test "group" {
  let doc : Layout[Unit] = group(text("x"))
  inspect(doc, content="Group(Text(\"x\", 1), 1)")
}

///|
test "concat via +" {
  let doc : Layout[Unit] = text("a") + text("b")
  inspect(doc, content="Concat(Text(\"a\", 1), Text(\"b\", 1), 2)")
}

///|
test "annotate" {
  let doc = annotate(42, text("x"))
  inspect(doc, content="Annotate(42, Text(\"x\", 1), 1)")
}

///|
test "separate" {
  let doc : Layout[Unit] = separate(text(", "), [
    text("a"),
    text("b"),
    text("c"),
  ])
  inspect(
    doc,
    content=(
      #|Concat(
      #|  Concat(
      #|    Concat(Concat(Text("a", 1), Text(", ", 2), 3), Text("b", 1), 4),
      #|    Text(", ", 2),
      #|    6,
      #|  ),
      #|  Text("c", 1),
      #|  7,
      #|)
    ),
  )
}

///|
test "separate empty" {
  let doc : Layout[Unit] = separate(text(", "), [])
  inspect(doc, content="Empty(0)")
}

///|
test "parens" {
  let doc : Layout[Unit] = parens(text("x"))
  inspect(doc, content="Concat(Concat(Text(\"(\", 1), Text(\"x\", 1), 2), Text(\")\", 1), 3)")
}
