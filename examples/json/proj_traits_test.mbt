///|
test "TreeNode::children — leaf nodes" {
  inspect(@core.TreeNode::children(@json.JsonValue::Null).length(), content="0")
  inspect(@core.TreeNode::children(@json.JsonValue::Bool(true)).length(), content="0")
  inspect(
    @core.TreeNode::children(@json.JsonValue::Number(42.0)).length(),
    content="0",
  )
  inspect(
    @core.TreeNode::children(@json.JsonValue::String("hello")).length(),
    content="0",
  )
}

///|
test "TreeNode::children — Array" {
  let arr = @json.JsonValue::Array([@json.JsonValue::Number(1.0), @json.JsonValue::Number(2.0)])
  inspect(@core.TreeNode::children(arr).length(), content="2")
}

///|
test "TreeNode::children — Object returns values only" {
  let obj = @json.JsonValue::Object([
    ("a", @json.JsonValue::Number(1.0)),
    ("b", @json.JsonValue::Bool(true)),
  ])
  let children = @core.TreeNode::children(obj)
  inspect(children.length(), content="2")
}

///|
test "TreeNode::same_kind" {
  inspect(
    @core.TreeNode::same_kind(@json.JsonValue::Null, @json.JsonValue::Null),
    content="true",
  )
  inspect(
    @core.TreeNode::same_kind(@json.JsonValue::Number(1.0), @json.JsonValue::Number(2.0)),
    content="true",
  )
  inspect(
    @core.TreeNode::same_kind(@json.JsonValue::Null, @json.JsonValue::Bool(true)),
    content="false",
  )
  inspect(
    @core.TreeNode::same_kind(@json.JsonValue::Array([]), @json.JsonValue::Object([])),
    content="false",
  )
}

///|
test "Renderable::kind_tag" {
  inspect(@core.Renderable::kind_tag(@json.JsonValue::Null), content="Null")
  inspect(@core.Renderable::kind_tag(@json.JsonValue::Array([])), content="Array")
}

///|
test "Renderable::label" {
  inspect(@core.Renderable::label(@json.JsonValue::Null), content="null")
  inspect(@core.Renderable::label(@json.JsonValue::Bool(true)), content="true")
  inspect(@core.Renderable::label(@json.JsonValue::Number(42.0)), content="42")
  let obj = @json.JsonValue::Object([
    ("name", @json.JsonValue::String("Alice")),
    ("age", @json.JsonValue::Number(30.0)),
  ])
  inspect(@core.Renderable::label(obj), content="{name, age}")
}

///|
test "Renderable::placeholder" {
  inspect(@core.Renderable::placeholder(@json.JsonValue::Null), content="null")
  inspect(@core.Renderable::placeholder(@json.JsonValue::Bool(true)), content="false")
  inspect(@core.Renderable::placeholder(@json.JsonValue::Number(0.0)), content="0")
  inspect(@core.Renderable::placeholder(@json.JsonValue::String("")), content="\"\"")
  inspect(@core.Renderable::placeholder(@json.JsonValue::Array([])), content="[]")
  inspect(@core.Renderable::placeholder(@json.JsonValue::Object([])), content="{}")
}

///|
test "Renderable::unparse — primitives" {
  inspect(@core.Renderable::unparse(@json.JsonValue::Null), content="null")
  inspect(@core.Renderable::unparse(@json.JsonValue::Bool(true)), content="true")
  inspect(@core.Renderable::unparse(@json.JsonValue::Number(42.0)), content="42")
  inspect(
    @core.Renderable::unparse(@json.JsonValue::String("hello")),
    content="\"hello\"",
  )
}

///|
test "Renderable::unparse — Error produces null" {
  inspect(@core.Renderable::unparse(@json.JsonValue::Error("oops")), content="null")
}
