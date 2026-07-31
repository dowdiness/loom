///|
fn spike_smoke_source_id() -> @core.SourceId {
  @core.SourceId::SourceId("lambda-spike-smoke")
}

///|
test "spike package can call public lambda parse_cst" {
  let (_, diagnostics) = @lambda.parse_cst(spike_smoke_source_id(), "let x = 1")
  inspect(diagnostics.is_empty(), content="true")
}
