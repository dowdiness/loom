///|
test "label styles are constructible across the public package boundary" {
  let primary = @core.LabelStyle::Primary
  let secondary = @core.LabelStyle::Secondary
  inspect(primary is @core.LabelStyle::Primary, content="true")
  inspect(secondary is @core.LabelStyle::Secondary, content="true")
}
