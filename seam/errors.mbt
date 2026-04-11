///| Error type for malformed event streams.
///
/// Raised by `build_tree*` when the event stream violates structural
/// invariants. These are parser defects — the ParserContext API
/// guarantees well-formedness by construction.
pub(all) suberror EventStreamError {
  /// FinishNode with no matching StartNode (stack underflow)
  UnbalancedFinish
  /// Unclosed StartNode(s) at end of event stream
  UnbalancedStart(missing_finishes~ : Int)
  /// Token or node with no parent frame on the stack
  OrphanedEvent
} derive(Debug)
