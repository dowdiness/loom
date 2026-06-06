///|
/// Placeholder AST published by the skeleton grammar.
///
/// The full integration should replace this with a CST-to-official-AST fold once
/// the MoonBit grammar has been ported. Keeping this type `Eq` lets it flow
/// through `@loom.Parser` today.
pub(all) struct MoonbitParseShell {
  item_count : Int
  token_count : Int
  contains_errors : Bool
} derive(Eq, Debug)

///|
fn MoonbitParseShell::empty() -> MoonbitParseShell {
  { item_count: 0, token_count: 0, contains_errors: false }
}

///|
fn MoonbitParseShell::combine(
  self : MoonbitParseShell,
  other : MoonbitParseShell,
) -> MoonbitParseShell {
  {
    item_count: self.item_count + other.item_count,
    token_count: self.token_count + other.token_count,
    contains_errors: self.contains_errors || other.contains_errors,
  }
}
