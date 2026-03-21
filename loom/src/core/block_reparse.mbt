///|
/// Grammar-provided configuration for block reparse.
/// Grammar authors implement three functions to enable block-level
/// incremental reparsing for their language.
pub struct BlockReparseSpec[T, K] {
  /// Returns true for node kinds that can be reparsed in isolation.
  is_reparseable : (@seam.RawKind) -> Bool
  /// Returns the parse function for a reparseable kind.
  get_reparser : (@seam.RawKind) -> ((ParserContext[T, K]) -> Unit)?
  /// Structural integrity check on re-lexed tokens.
  is_balanced : (Array[TokenInfo[T]]) -> Bool
}
