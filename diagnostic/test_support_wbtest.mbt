///|
struct TestSourceResolver {
  resolve : (SourceId) -> SourceSnapshot?
}

///|
impl SourceResolver for TestSourceResolver with fn resolve_source(
  self,
  source_id,
) {
  (self.resolve)(source_id)
}

///|
fn test_source_resolver(
  resolve : (SourceId) -> SourceSnapshot?,
) -> TestSourceResolver {
  { resolve, }
}
