///|
test "TreeNode::children — leaf nodes" {
  inspect(@core.TreeNode::children(JsonValue::Null).length(), content="0")
  inspect(@core.TreeNode::children(JsonValue::Bool(true)).length(), content="0")
  inspect(
    @core.TreeNode::children(JsonValue::Number(42.0)).length(),
    content="0",
  )
  inspect(
    @core.TreeNode::children(JsonValue::String("hello")).length(),
    content="0",
  )
}

///|
test "TreeNode::children — Array" {
  let arr = JsonValue::Array([JsonValue::Number(1.0), JsonValue::Number(2.0)])
  inspect(@core.TreeNode::children(arr).length(), content="2")
}

///|
test "TreeNode::children — Object returns values only" {
  let obj = JsonValue::Object([
    ("a", JsonValue::Number(1.0)),
    ("b", JsonValue::Bool(true)),
  ])
  let children = @core.TreeNode::children(obj)
  inspect(children.length(), content="2")
}

///|
test "TreeNode::same_kind" {
  inspect(
    @core.TreeNode::same_kind(JsonValue::Null, JsonValue::Null),
    content="true",
  )
  inspect(
    @core.TreeNode::same_kind(JsonValue::Number(1.0), JsonValue::Number(2.0)),
    content="true",
  )
  inspect(
    @core.TreeNode::same_kind(JsonValue::Null, JsonValue::Bool(true)),
    content="false",
  )
  inspect(
    @core.TreeNode::same_kind(JsonValue::Array([]), JsonValue::Object([])),
    content="false",
  )
}

///|
test "Renderable::kind_tag" {
  inspect(@core.Renderable::kind_tag(JsonValue::Null), content="Null")
  inspect(@core.Renderable::kind_tag(JsonValue::Array([])), content="Array")
}

///|
test "Renderable::label" {
  inspect(@core.Renderable::label(JsonValue::Null), content="null")
  inspect(@core.Renderable::label(JsonValue::Bool(true)), content="true")
  inspect(@core.Renderable::label(JsonValue::Number(42.0)), content="42")
  let obj = JsonValue::Object([
    ("name", JsonValue::String("Alice")),
    ("age", JsonValue::Number(30.0)),
  ])
  inspect(@core.Renderable::label(obj), content="{name, age}")
}

///|
test "Renderable::placeholder" {
  inspect(@core.Renderable::placeholder(JsonValue::Null), content="null")
  inspect(@core.Renderable::placeholder(JsonValue::Bool(true)), content="false")
  inspect(@core.Renderable::placeholder(JsonValue::Number(0.0)), content="0")
  inspect(@core.Renderable::placeholder(JsonValue::String("")), content="\"\"")
  inspect(@core.Renderable::placeholder(JsonValue::Array([])), content="[]")
  inspect(@core.Renderable::placeholder(JsonValue::Object([])), content="{}")
}

///|
test "Renderable::unparse — primitives" {
  inspect(@core.Renderable::unparse(JsonValue::Null), content="null")
  inspect(@core.Renderable::unparse(JsonValue::Bool(true)), content="true")
  inspect(@core.Renderable::unparse(JsonValue::Number(42.0)), content="42")
  inspect(
    @core.Renderable::unparse(JsonValue::String("hello")),
    content="\"hello\"",
  )
}

///|
test "Renderable::unparse — Error produces null" {
  inspect(@core.Renderable::unparse(JsonValue::Error("oops")), content="null")
}
