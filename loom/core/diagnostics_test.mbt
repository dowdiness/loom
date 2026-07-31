///|
test "label styles are constructible across the public package boundary" {
  let primary = LabelStyle::Primary
  let secondary = LabelStyle::Secondary
  inspect(primary is LabelStyle::Primary, content="true")
  inspect(secondary is LabelStyle::Secondary, content="true")
}
