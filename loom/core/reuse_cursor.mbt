// Generic ReuseCursor[T, K] — walks an old CST in parallel with parsing
// to find reusable subtrees. Genericized from src/parser/reuse_cursor.mbt.
//
// All language-specific checks are delegated to the LanguageSpec and K-traits:
//   K.to_raw() / whitespace_kind / error_kind — classify old-tree RawKind values
//   token_is_trivia / token_is_eof — classify new token stream values
//   get_text(pos) — source text at token position, for kind+text comparison
//
// Parser-owned edit paths should construct cursors with
// ReuseCursor::new_with_edit so old/new damage coordinates stay derived from a
// single Edit value. ReuseCursor::new stays available for low-level tests and
// infrastructure that already operate on explicit old-tree damage coordinates.

///|
/// Frame in the cursor stack, tracking position within a node.
struct CursorFrame {
  node : @seam.CstNode
  mut child_index : Int32
  start_offset : Int32
  /// Offset of the child at child_index. Maintained incrementally
  /// so seek_node_at does not need to recompute it from scratch on resume.
  mut current_child_offset : Int32
}

///|
/// Flattened non-trivia, non-error token from the old CST.
/// Used for trailing-context matching during reuse checks.
#derive(Debug, Eq, Compare)
struct OldToken {
  kind : @seam.RawKind
  text : StringView
  start : Int32
}

///|
/// Whitebox-only reason for a failed reuse candidate.
///
/// Exposed as an opaque type so rejection inspection can help diagnose cursor
/// regressions without committing to a stable variant surface.
#derive(Debug, Eq)
enum ReuseRejectionReason {
  ReuseRejectGloballyDisabled
  ReuseRejectEditedOffset
  ReuseRejectNoCandidate
  ReuseRejectBelowSizeThreshold
  ReuseRejectDamageOverlap
  ReuseRejectLeadingTokenMismatch
  ReuseRejectFollowTokenMismatch
  ReuseRejectDependencyMismatch
}

///|
/// Generic cursor for walking an old CST to find reusable subtrees.
/// Maintains traversal state for O(depth) lookups.
pub struct ReuseCursor[T, K] {
  stack : Array[CursorFrame]
  mut current_offset : Int32
  damage_start : Int32
  damage_end : Int32
  new_damage_end : Int32
  old_root : @seam.CstNode
  trivia_kinds : Array[@seam.RawKind]
  err_raw : @seam.RawKind
  incomplete_raw : @seam.RawKind
  reuse_globally_disabled : Bool
  reuse_size_threshold : Int32
  allow_left_adjacent_reuse : Bool
  // New token stream (indexed accessors, same layout as ParserContext)
  token_count : Int32
  get_token : (Int32) -> T
  get_start : (Int32) -> Int32
  get_text : (Int32) -> StringView
  spec : LanguageSpec[T, K]
  priv dependencies : ReuseDependencies?
  priv dependency_damage : Edit?
  priv mut last_dependency : NodeDependency?
  priv old_tokens : Ref[Array[OldToken]?]
}

///|
/// Create a new reuse cursor from explicit old-tree damage coordinates.
///
/// This is the low-level constructor. Prefer `ReuseCursor::new_with_edit` for
/// parser-owned edit paths so `damage_start`, `damage_end`, and `new_damage_end`
/// are all derived from the same `Edit`.
///
/// `damage_start`/`damage_end` are old-source code-unit offsets (exclusive-end)
/// of the edited region. `new_damage_end` is the corresponding new-source end
/// offset after the edit.
pub fn[T, K : @seam.ToRawKind] ReuseCursor::new(
  old_tree : @seam.CstNode,
  damage_start : Int32,
  damage_end : Int32,
  token_count : Int32,
  get_token : (Int32) -> T,
  get_start : (Int32) -> Int32,
  get_text : (Int32) -> StringView,
  spec : LanguageSpec[T, K],
  reuse_size_threshold~ : Int32 = 0,
  allow_left_adjacent_reuse~ : Bool = false,
  new_damage_end~ : Int32 = damage_end,
  dependencies~ : ReuseDependencies? = None,
) -> ReuseCursor[T, K] {
  let reuse_globally_disabled = damage_start <= 0 &&
    damage_end >= old_tree.text_len()
  let trivia_kinds = spec.trivia_kinds_raw()
  let err_raw = spec.error_kind.to_raw()
  let incomplete_raw = spec.incomplete_kind.to_raw()
  let stack = [
    {
      node: old_tree,
      child_index: 0,
      start_offset: 0,
      current_child_offset: 0,
    },
  ]
  {
    stack,
    current_offset: 0,
    damage_start,
    damage_end,
    new_damage_end,
    old_root: old_tree,
    trivia_kinds,
    err_raw,
    incomplete_raw,
    reuse_globally_disabled,
    old_tokens: { val: None, },
    reuse_size_threshold,
    allow_left_adjacent_reuse,
    token_count,
    get_token,
    get_start,
    get_text,
    spec,
    dependencies,
    dependency_damage: dependencies.map(deps => {
      deps.combined_edit(
        Edit::new(
          damage_start,
          damage_end - damage_start,
          new_damage_end - damage_start,
        ),
      )
    }),
    last_dependency: None,
  }
}

///|
/// Create a new reuse cursor from a compact edit operation.
///
/// This is the preferred constructor for edit-driven incremental parsing. It
/// derives the old-source damage range and new-source damage end from `edit`,
/// avoiding raw endpoint math at call sites.
/// This wraps `new` by deriving `damage_start`, `damage_end`, and `new_damage_end`
/// from the `edit` coordinates.
pub fn[T, K : @seam.ToRawKind] ReuseCursor::new_with_edit(
  old_tree : @seam.CstNode,
  edit : Edit,
  token_count : Int32,
  get_token : (Int32) -> T,
  get_start : (Int32) -> Int32,
  get_text : (Int32) -> StringView,
  spec : LanguageSpec[T, K],
  reuse_size_threshold~ : Int32 = 0,
  allow_left_adjacent_reuse~ : Bool = false,
  dependencies~ : ReuseDependencies? = None,
) -> ReuseCursor[T, K] {
  ReuseCursor::new(
    old_tree,
    edit.start,
    edit.old_end(),
    token_count,
    get_token,
    get_start,
    get_text,
    spec,
    allow_left_adjacent_reuse~,
    reuse_size_threshold~,
    new_damage_end=edit.new_end(),
    dependencies~,
  )
}

///|
/// True if damage covers the entire tree — no reuse is possible.
pub fn[T, K] ReuseCursor::is_reuse_disabled(self : ReuseCursor[T, K]) -> Bool {
  self.reuse_globally_disabled
}

///|
/// True if the node's code-unit range is entirely outside the damage region.
/// By default, left-adjacent (node_end == damage_start) is excluded because
/// trailing context at the boundary may have changed. Right-adjacent
/// (node_start == damage_end) is safe because damage_end is the first
/// unmodified code unit.
fn is_outside_damage(
  node_start : Int32,
  node_end : Int32,
  damage_start : Int32,
  damage_end : Int32,
  allow_left_adjacent_reuse : Bool,
) -> Bool {
  if allow_left_adjacent_reuse {
    node_end <= damage_start || node_start >= damage_end
  } else {
    node_end < damage_start || node_start >= damage_end
  }
}

///|
/// Convert new-source offsets back to old-tree coordinates.
fn[T, K] ReuseCursor::to_old_offset(
  self : ReuseCursor[T, K],
  new_offset : Int32,
) -> Int32? {
  if new_offset < self.damage_start {
    Some(new_offset)
  } else {
    let delta = self.new_damage_end - self.damage_end
    let old_offset = new_offset - delta
    if old_offset < self.damage_start {
      None
    } else {
      Some(old_offset)
    }
  }
}

///|
/// Convert old-tree offsets to equivalent new-source coordinates.
fn[T, K] ReuseCursor::to_new_offset(
  self : ReuseCursor[T, K],
  old_offset : Int32,
) -> Int32 {
  if old_offset < self.damage_end {
    old_offset
  } else {
    old_offset + (self.new_damage_end - self.damage_end)
  }
}

///|
/// Return the first source-backed non-trivia token in a reusable subtree.
/// Parser-synthetic placeholders are not lexer context and must not control
/// leading-token reuse checks.
fn first_source_backed_token(
  node : @seam.CstNode,
  trivia_kinds : Array[@seam.RawKind],
) -> @seam.CstToken? {
  for child in node.children() {
    match child {
      @seam.CstElement::Token(token) =>
        if token.is_source_backed() && !trivia_kinds.contains(token.kind) {
          return Some(token)
        }
      @seam.CstElement::Node(child_node) =>
        match first_source_backed_token(child_node, trivia_kinds) {
          Some(token) => return Some(token)
          None => ()
        }
    }
  }
  None
}

///|
/// True if the first source-backed non-trivia leaf of node matches the new
/// token at token_pos.
fn[T : @seam.ToRawKind, K] leading_token_matches(
  node : @seam.CstNode,
  cursor : ReuseCursor[T, K],
  token_pos : Int32,
) -> Bool {
  if token_pos >= cursor.token_count {
    return false
  }
  let new_kind = (cursor.get_token)(token_pos).to_raw()
  match first_source_backed_token(node, cursor.trivia_kinds) {
    None => false
    Some(old_tok) =>
      old_tok.kind == new_kind && old_tok.text() == (cursor.get_text)(token_pos)
  }
}

///|
/// Whether an old CST leaf counts as lexer context: source-backed, not trivia,
/// not an error or incomplete placeholder.
fn is_old_context_token(
  token : @seam.CstToken,
  trivia_kinds : Array[@seam.RawKind],
  err_raw : @seam.RawKind,
  incomplete_raw : @seam.RawKind,
) -> Bool {
  token.is_source_backed() &&
  !trivia_kinds.contains(token.kind) &&
  token.kind != err_raw &&
  token.kind != incomplete_raw
}

///|
fn[T, K] ReuseCursor::is_old_context_token(
  self : ReuseCursor[T, K],
  token : @seam.CstToken,
) -> Bool {
  is_old_context_token(
    token,
    self.trivia_kinds,
    self.err_raw,
    self.incomplete_raw,
  )
}

///|
// OffsetIndexed for Array[OldToken]: lets lower_bound search the old-tree
// context-token table by code-unit offset. collect_old_tokens walks the tree
// left-to-right, so .start values are non-decreasing.
impl OffsetIndexed for Array[OldToken] with fn length(self) {
  self.length()
}

///|
impl OffsetIndexed for Array[OldToken] with fn offset_at(self, i) {
  self[i].start
}

///|
fn[T, K] ReuseCursor::collect_old_tokens(
  self : ReuseCursor[T, K],
  node : @seam.CstNode,
  node_start : Int32,
  out : Array[OldToken],
) -> Unit {
  let mut offset = node_start
  for child in node.children() {
    match child {
      @seam.CstElement::Token(token) =>
        if self.is_old_context_token(token) {
          out.push({ kind: token.kind, text: token.text(), start: offset, })
        }
      @seam.CstElement::Node(child_node) =>
        self.collect_old_tokens(child_node, offset, out)
    }
    offset = offset + child.text_len()
  }
}

///|
/// Old context tokens in document order, in old-tree coordinates.
///
/// Built on first use and shared with snapshots. It belongs to this cursor's
/// immutable old tree, so it never needs offset mapping or invalidation; one
/// O(n) walk per cursor replaces a root-to-offset walk per reuse check, which
/// was O(n) per check on wide nodes.
fn[T, K] ReuseCursor::old_tokens(self : ReuseCursor[T, K]) -> Array[OldToken] {
  match self.old_tokens.val {
    Some(tokens) => tokens
    None => {
      let tokens : Array[OldToken] = []
      self.collect_old_tokens(self.old_root, 0, tokens)
      self.old_tokens.val = Some(tokens)
      tokens
    }
  }
}

///|
/// First old context token starting at or after `offset`, in old-tree
/// coordinates. The old tree is immutable, so the answer does not depend on
/// the edit being parsed.
fn[T, K] old_follow_token(
  cursor : ReuseCursor[T, K],
  offset : Int32,
) -> OldToken? {
  let tokens = cursor.old_tokens()
  let i = lower_bound(tokens, offset)
  if i < tokens.length() {
    Some(tokens[i])
  } else {
    None
  }
}

///|
/// Zero-width old lexer tokens that start exactly at `offset` (old-tree
/// coordinates), in document order.
fn[T, K] ReuseCursor::old_zero_width_tokens_at_boundary(
  self : ReuseCursor[T, K],
  offset : Int32,
) -> Array[OldToken] {
  let tokens = self.old_tokens()
  let result : Array[OldToken] = []
  for i = lower_bound(tokens, offset)
      i < tokens.length() && tokens[i].start == offset
      i = i + 1 {
    if tokens[i].text.length() == 0 {
      result.push(tokens[i])
    }
  }
  result
}

///|
// OffsetIndexed for ReuseCursor[T,K]: lets lower_bound search the new token
// stream by code-unit offset using the same get_start closure already stored in the
// cursor. Sorted by tokenizer contract — tokens are emitted left-to-right.
// [T, K] on impl propagates the cursor's type parameters; the methods only use
// Self and Int so no additional constraints are needed.
impl[T, K] OffsetIndexed for ReuseCursor[T, K] with fn length(self) {
  self.token_count
}

///|
impl[T, K] OffsetIndexed for ReuseCursor[T, K] with fn offset_at(self, i) {
  (self.get_start)(i)
}

///|
/// Find the first non-trivia, non-EOF token in the new stream with start >= byte_offset.
/// Binary-search for the first index where get_start(i) >= byte_offset, then
/// scan forward skipping trivia (token_is_trivia) and stopping at EOF (token_is_eof).
/// Returns both the token and its index for get_text(pos) lookup.
fn[T : @seam.IsTrivia + @seam.IsEof, K] new_follow_token_with_pos(
  cursor : ReuseCursor[T, K],
  byte_offset : Int32,
) -> (T, Int32)? {
  let mut lo = lower_bound(cursor, byte_offset)
  while lo < cursor.token_count {
    let t = (cursor.get_token)(lo)
    if @seam.IsEof::is_eof(t) {
      break
    }
    if @seam.IsTrivia::is_trivia(t) {
      lo = lo + 1
      continue
    }
    return Some((t, lo))
  }
  None
}

///|
/// True if the follow token after node_end matches between old and new streams.
/// This is only a local boundary check. Grammars with farther observations
/// additionally require unchanged dependency extents and entry context.
fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] trailing_context_matches(
  cursor : ReuseCursor[T, K],
  old_node_end : Int32,
  node_end : Int32,
) -> Bool {
  // A relex may merge the node's last token with edited text, so the new
  // stream must still have a token boundary at the node end.
  let after = lower_bound(cursor, node_end)
  if after > 0 &&
    (cursor.get_start)(after - 1) + (cursor.get_text)(after - 1).length() >
    node_end {
    return false
  }
  let old_follow = old_follow_token(cursor, old_node_end)
  let new_follow = new_follow_token_with_pos(cursor, node_end)
  match (old_follow, new_follow) {
    (None, None) => true
    (Some(old), Some((new_tok, new_pos))) =>
      old.kind == @seam.ToRawKind::to_raw(new_tok) &&
      old.text == (cursor.get_text)(new_pos)
    _ => false
  }
}

///|
/// Pop the top frame and advance the parent frame's child cursor past it.
/// current_child_offset in the parent advances to the end of the popped frame.
fn[T, K] ReuseCursor::pop_frame(self : ReuseCursor[T, K]) -> Unit {
  let frame = self.stack[self.stack.length() - 1]
  let frame_end = frame.start_offset + frame.node.text_len()
  let _ = self.stack.pop()
  if self.stack.length() > 0 {
    let parent = self.stack[self.stack.length() - 1]
    parent.child_index = parent.child_index + 1
    parent.current_child_offset = frame_end
  }
}

///|
/// Advance through the old tree to find a node at target_offset with expected_kind.
/// O(depth) because we only descend/ascend as needed.
/// current_child_offset in each CursorFrame is maintained incrementally — no
/// O(width) recomputation on frame resume.
fn[T, K] ReuseCursor::seek_node_at(
  self : ReuseCursor[T, K],
  target_offset : Int32,
  expected_kind : @seam.RawKind,
) -> (@seam.CstNode, Int32)? {
  // If target is before current position, reset to root
  if target_offset < self.current_offset {
    let root_frame = self.stack[0]
    let _ = self.stack.drain(1, self.stack.length())
    root_frame.child_index = 0
    root_frame.current_child_offset = 0
    self.current_offset = 0
  }
  while self.stack.length() > 0 {
    let frame = self.stack[self.stack.length() - 1]
    let node = frame.node
    // Check if current frame matches (never return RepeatGroup — traverse it)
    if frame.start_offset == target_offset &&
      node.kind() == expected_kind &&
      node.kind() != @seam.repeat_group_kind {
      return Some((node, frame.start_offset))
    }
    // If target is outside this node's range, pop up
    let node_end = frame.start_offset + node.text_len()
    if target_offset < frame.start_offset || target_offset >= node_end {
      self.pop_frame()
      continue
    }
    // Target is within this node — resume from cached child offset (O(1))
    let mut child_offset = frame.current_child_offset
    let mut found_child = false
    // Search remaining children from where we left off
    while frame.child_index < node.children().length() {
      let child = node.children()[frame.child_index]
      let child_width = child.text_len()
      let child_end = child_offset + child_width
      if target_offset < child_offset {
        break
      }
      if target_offset < child_end {
        match child {
          @seam.CstElement::Node(child_node) => {
            if child_node.kind() == @seam.repeat_group_kind {
              // Always descend into RepeatGroup — only try_reuse_repeat_group reuses whole groups
              self.stack.push({
                node: child_node,
                child_index: 0,
                start_offset: child_offset,
                current_child_offset: child_offset,
              })
              found_child = true
              break
            } else if child_offset == target_offset &&
              child_node.kind() == expected_kind {
              self.current_offset = child_offset
              return Some((child_node, child_offset))
            }
            self.stack.push({
              node: child_node,
              child_index: 0,
              start_offset: child_offset,
              current_child_offset: child_offset,
            })
            found_child = true
            break
          }
          @seam.CstElement::Token(_) => {
            self.current_offset = child_offset
            return None
          }
        }
      }
      child_offset = child_end
      frame.current_child_offset = child_end // keep frame in sync
      frame.child_index = frame.child_index + 1
    }
    if !found_child {
      self.pop_frame()
    }
  }
  None
}

///|
/// Try to get a reusable node at byte_offset with expected_kind.
///
/// Returns Some(node) only if all six conditions hold:
///   1. Reuse not globally disabled
///   2. byte_offset is not inside the damage range
///   3. A node exists at byte_offset with kind == expected_kind
///   4. Node is entirely outside the damage range
///   5. Leading token of node matches the new token at token_pos
///   6. Follow token after the node matches between old and new streams
fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::try_reuse_checked(
  self : ReuseCursor[T, K],
  expected_kind : @seam.RawKind,
  byte_offset : Int32,
  token_pos : Int32,
  context~ : ReuseContext? = None,
) -> Result[@seam.CstNode, ReuseRejectionReason] {
  self.last_dependency = None
  if self.reuse_globally_disabled {
    return Err(ReuseRejectGloballyDisabled)
  }
  let source_offset = match self.to_old_offset(byte_offset) {
    None => return Err(ReuseRejectEditedOffset)
    Some(v) => v
  }
  let result = self.seek_node_at(source_offset, expected_kind)
  match result {
    None => Err(ReuseRejectNoCandidate)
    Some((node, node_offset)) => {
      // Skip reuse for small nodes — reparsing is cheaper than the protocol.
      if self.reuse_size_threshold > 0 &&
        node.text_len() < self.reuse_size_threshold {
        return Err(ReuseRejectBelowSizeThreshold)
      }
      let node_end = node_offset + node.text_len()
      let node_end_in_new = self.to_new_offset(node_end)
      if !is_outside_damage(
          node_offset,
          node_end,
          self.damage_start,
          self.damage_end,
          self.allow_left_adjacent_reuse,
        ) {
        Err(ReuseRejectDamageOverlap)
      } else if !self.dependencies_match(node, node_offset, context) {
        Err(ReuseRejectDependencyMismatch)
      } else if !leading_token_matches(node, self, token_pos) {
        Err(ReuseRejectLeadingTokenMismatch)
      } else if !trailing_context_matches(self, node_end, node_end_in_new) {
        Err(ReuseRejectFollowTokenMismatch)
      } else {
        Ok(node)
      }
    }
  }
}

///|
/// Inspect why a regular node reuse candidate would be rejected.
///
/// This whitebox hook runs the same checks as `try_reuse` on a cursor snapshot,
/// so callers can inspect rejection causes without advancing the live cursor.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::explain_reuse_rejection(
  self : ReuseCursor[T, K],
  expected_kind : @seam.RawKind,
  byte_offset : Int32,
  token_pos : Int32,
) -> ReuseRejectionReason? {
  let cursor = self.snapshot()
  match cursor.try_reuse_checked(expected_kind, byte_offset, token_pos) {
    Ok(_) => None
    Err(reason) => Some(reason)
  }
}

///|
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::try_reuse(
  self : ReuseCursor[T, K],
  expected_kind : @seam.RawKind,
  byte_offset : Int32,
  token_pos : Int32,
) -> @seam.CstNode? {
  match self.try_reuse_checked(expected_kind, byte_offset, token_pos) {
    Ok(node) => Some(node)
    Err(_) => None
  }
}

///|
/// Try to reuse an entire RepeatGroup subtree at byte_offset.
///
/// Walks the cursor stack to find a RepeatGroup child at exactly byte_offset.
/// Returns Some(node) if the group is entirely outside the damage range and
/// leading/trailing token context matches. Unlike try_reuse, this does not
/// require an expected_kind — any undamaged RepeatGroup is eligible.
///
/// Called by grammar code before parsing individual items in a repeat loop
/// to enable O(log n) reuse of balanced subtrees.
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::try_reuse_repeat_group(
  self : ReuseCursor[T, K],
  byte_offset : Int32,
  token_pos : Int32,
) -> @seam.CstNode? {
  self.try_reuse_repeat_group_in_context(byte_offset, token_pos, None)
}

///|
fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::try_reuse_repeat_group_in_context(
  self : ReuseCursor[T, K],
  byte_offset : Int32,
  token_pos : Int32,
  context : ReuseContext?,
) -> @seam.CstNode? {
  self.last_dependency = None
  if self.reuse_globally_disabled {
    return None
  }
  let source_offset = match self.to_old_offset(byte_offset) {
    None => return None
    Some(v) => v
  }
  // Reset to root if target is behind current position
  if source_offset < self.current_offset {
    let root_frame = self.stack[0]
    let _ = self.stack.drain(1, self.stack.length())
    root_frame.child_index = 0
    root_frame.current_child_offset = 0
    self.current_offset = 0
  }
  // Walk the stack to find a RepeatGroup at byte_offset
  while self.stack.length() > 0 {
    let frame = self.stack[self.stack.length() - 1]
    let node = frame.node
    let node_end = frame.start_offset + node.text_len()
    // If target is outside this node's range, pop up
    if source_offset < frame.start_offset || source_offset >= node_end {
      self.pop_frame()
      continue
    }
    // Scan children from cached position
    let mut child_offset = frame.current_child_offset
    let mut found_child = false
    while frame.child_index < node.children().length() {
      let child = node.children()[frame.child_index]
      let child_width = child.text_len()
      let child_end = child_offset + child_width
      if source_offset < child_offset {
        break
      }
      if source_offset < child_end {
        match child {
          @seam.CstElement::Node(child_node) => {
            if child_node.kind() == @seam.repeat_group_kind &&
              child_offset == source_offset &&
              is_outside_damage(
                child_offset,
                child_end,
                self.damage_start,
                self.damage_end,
                self.allow_left_adjacent_reuse,
              ) {
              // Found undamaged RepeatGroup — validate context
              let child_end_in_new = self.to_new_offset(child_end)
              if leading_token_matches(child_node, self, token_pos) &&
                trailing_context_matches(self, child_end, child_end_in_new) &&
                self.dependencies_match(child_node, child_offset, context) {
                self.current_offset = child_offset
                return Some(child_node)
              }
            }
            // Not a match — if it's a RepeatGroup overlapping damage, descend
            if child_node.kind() == @seam.repeat_group_kind {
              self.stack.push({
                node: child_node,
                child_index: 0,
                start_offset: child_offset,
                current_child_offset: child_offset,
              })
              found_child = true
              break
            }
            // Non-RepeatGroup node: descend to look for RepeatGroup children
            self.stack.push({
              node: child_node,
              child_index: 0,
              start_offset: child_offset,
              current_child_offset: child_offset,
            })
            found_child = true
            break
          }
          @seam.CstElement::Token(_) => return None
        }
      }
      child_offset = child_end
      frame.current_child_offset = child_end
      frame.child_index = frame.child_index + 1
    }
    if !found_child {
      self.pop_frame()
    }
  }
  None
}

///|
/// True if the sibling immediately following the most recently found node
/// has any error or incomplete content (token or node anywhere in subtree).
///
/// After try_reuse returns Some, the cursor's parent frame still has
/// child_index pointing to the found node. The next sibling is at
/// child_index + 1, accessible without any seek or cursor advancement.
///
/// Call this between try_reuse and advance_past. Returns false when there
/// is no next sibling or the cursor stack is empty.
///
/// Limitation: only inspects the *immediate* next sibling. If a zero-width
/// trivia node or similar separator sits between the found node and the
/// error-bearing sibling, this returns false and the EOF exception fires.
/// Acceptable for current grammars where error siblings are always adjacent.
pub fn[T, K] ReuseCursor::next_sibling_has_error(
  self : ReuseCursor[T, K],
) -> Bool {
  if self.stack.length() == 0 {
    return false
  }
  let frame = self.stack[self.stack.length() - 1]
  let next_idx = frame.child_index + 1
  if next_idx >= frame.node.children().length() {
    return false
  }
  match frame.node.children()[next_idx] {
    @seam.CstElement::Node(n) => n.has_any_error()
    @seam.CstElement::Token(t) =>
      t.kind == self.err_raw || t.kind == self.incomplete_raw
  }
}

///|
/// Advance cursor past a reused node. Updates current_offset to stay in sync
/// with ParserContext.position so subsequent seeks detect backward movement.
pub fn[T, K] ReuseCursor::advance_past(
  self : ReuseCursor[T, K],
  node : @seam.CstNode,
) -> Unit {
  self.current_offset = self.current_offset + node.text_len()
}

///|
/// Return a structural snapshot of the cursor state.
/// Used by ParserContext checkpoints to restore speculative parses.
pub fn[T, K] ReuseCursor::snapshot(
  self : ReuseCursor[T, K],
) -> ReuseCursor[T, K] {
  let stack : Array[CursorFrame] = []
  for frame in self.stack {
    stack.push({
      node: frame.node,
      child_index: frame.child_index,
      start_offset: frame.start_offset,
      current_child_offset: frame.current_child_offset,
    })
  }
  {
    stack,
    current_offset: self.current_offset,
    damage_start: self.damage_start,
    damage_end: self.damage_end,
    new_damage_end: self.new_damage_end,
    old_root: self.old_root,
    trivia_kinds: self.trivia_kinds,
    err_raw: self.err_raw,
    incomplete_raw: self.incomplete_raw,
    reuse_globally_disabled: self.reuse_globally_disabled,
    reuse_size_threshold: self.reuse_size_threshold,
    allow_left_adjacent_reuse: self.allow_left_adjacent_reuse,
    token_count: self.token_count,
    get_token: self.get_token,
    get_start: self.get_start,
    get_text: self.get_text,
    spec: self.spec,
    dependencies: self.dependencies,
    dependency_damage: self.dependency_damage,
    last_dependency: self.last_dependency,
    old_tokens: self.old_tokens,
  }
}

///|
pub extend OldToken with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend OldToken with Eq::{not_equal, equal}

///|
pub extend OldToken with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend ReuseRejectionReason with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReuseRejectionReason with Eq::{not_equal, equal}
