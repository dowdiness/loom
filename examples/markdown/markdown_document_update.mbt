///|
/// Lightweight evidence that an accepted update may be the direct previous
/// update used to match a later result.
pub struct MarkdownPreviousUpdate {
  priv domain : Ref[Unit]
  priv sequence : Int
}

///|
/// One current top-level semantic block and its optional match in the validated
/// direct previous update.
pub struct MarkdownTopLevelBlock {
  priv node : MarkdownNode
  priv matched_previous_block_index : Int?
}

///|
/// One canonical Markdown document plus top-level matches computed against the
/// producer's direct previous result.
pub struct MarkdownDocumentUpdate {
  priv document : MarkdownDocument
  priv blocks : Array[MarkdownTopLevelBlock]
  priv domain : Ref[Unit]
  priv sequence : Int
  priv previous_sequence : Int?
}

///|
/// Return the canonical detached document for this update.
pub fn MarkdownDocumentUpdate::document(
  self : MarkdownDocumentUpdate,
) -> MarkdownDocument {
  self.document
}

///|
/// Return lightweight evidence that this update was accepted by a consumer.
///
/// Pass the value to a later update's `top_level_blocks` call. Positive matches
/// are exposed only when it represents the producer's direct previous update.
pub fn MarkdownDocumentUpdate::as_previous(
  self : MarkdownDocumentUpdate,
) -> MarkdownPreviousUpdate {
  { domain: self.domain, sequence: self.sequence }
}

///|
/// Return current top-level blocks with safely gated direct-previous matches.
///
/// Missing, skipped, or foreign previous updates expose no positive matches.
/// `None` means that no safe correspondence is proven; it does not by itself
/// mean that the block's Markdown content changed.
pub fn MarkdownDocumentUpdate::top_level_blocks(
  self : MarkdownDocumentUpdate,
  previous~ : MarkdownPreviousUpdate?,
) -> ArrayView[MarkdownTopLevelBlock] {
  let matches_previous = match (previous, self.previous_sequence) {
    (Some(previous), Some(sequence)) =>
      physical_equal(previous.domain, self.domain) &&
      previous.sequence == sequence
    _ => false
  }
  if matches_previous {
    self.blocks[:]
  } else {
    self.blocks.map(block => {
      node: block.node,
      matched_previous_block_index: None,
    })[:]
  }
}

///|
/// Return the current semantic node represented by this top-level block.
pub fn MarkdownTopLevelBlock::node(
  self : MarkdownTopLevelBlock,
) -> MarkdownNode {
  self.node
}

///|
/// Return the corresponding block index in the validated direct previous
/// update, when the producer can prove a safe position-independent match.
pub fn MarkdownTopLevelBlock::matched_previous_block_index(
  self : MarkdownTopLevelBlock,
) -> Int? {
  self.matched_previous_block_index
}
