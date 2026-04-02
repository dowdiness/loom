// Generic ReuseCursor[T, K] — walks an old CST in parallel with parsing
// to find reusable subtrees. Genericized from src/parser/reuse_cursor.mbt.
//
// All language-specific checks are delegated to the LanguageSpec and K-traits:
//   K.to_raw() / whitespace_kind / error_kind — classify old-tree RawKind values
//   token_is_trivia / token_is_eof — classify new token stream values
//   get_text(pos) — source text at token position, for kind+text comparison
//
// Uses (damage_start, damage_end : Int) instead of Range to keep the
// ReuseCursor::new signature uniform and avoid coupling it to the Range type.

///|
/// Frame in the cursor stack, tracking position within a node.
struct CursorFrame {
  node : @seam.CstNode
  mut child_index : Int
  start_offset : Int
  /// Offset of the child at child_index. Maintained incrementally
  /// so seek_node_at does not need to recompute it from scratch on resume.
  mut current_child_offset : Int
}

///|
/// Flattened non-trivia, non-error token from the old CST.
/// Used for trailing-context matching during reuse checks.
struct OldToken {
  kind : @seam.RawKind
  text : String
  start : Int
} derive(Show, Eq, Compare)

///|
/// Persistent cache for the flattened old-token table.
///
/// Survives across edits to avoid O(n) collect_old_tokens rebuild.
/// Tokens are stored with offsets from the tree they were built from.
/// After an edit with non-zero delta (insert/delete), `pending_delta`
/// accumulates the offset shift for tokens after the damage zone.
/// `damage_boundary` records where the shift begins — tokens before
/// this offset use their stored offset; tokens at or after use
/// stored offset + pending_delta.
///
/// On read, `old_follow_token_lazy` adjusts the binary search target
/// by subtracting pending_delta for the post-damage region, so the
/// cached offsets match the query without rewriting the array.
pub struct OldTokenCache {
  mut tokens : Array[OldToken]?
  mut pending_delta : Int // cumulative offset shift for post-damage tokens
  mut damage_boundary : Int // offsets >= this need pending_delta adjustment
}

///|
/// Create an empty old-token cache.
pub fn OldTokenCache::empty() -> OldTokenCache {
  { tokens: None, pending_delta: 0, damage_boundary: 2147483647 }
}

///|
/// Update the cache after an edit. Call BEFORE creating the next ReuseCursor.
/// - Removes cached tokens in the old damage range [damage_start, damage_end)
/// - Accumulates delta for post-damage offset adjustment
pub fn OldTokenCache::apply_edit(
  self : OldTokenCache,
  damage_start : Int,
  damage_end : Int,
  new_damage_end : Int,
) -> Unit {
  let delta = new_damage_end - damage_end
  match self.tokens {
    None => () // no cache to patch
    Some(tokens) => {
      // Remove tokens in the old damage range
      let mut remove_start = -1
      let mut remove_end = -1
      for i = 0; i < tokens.length(); i = i + 1 {
        let tok_offset = tokens[i].start
        if tok_offset >= damage_start && tok_offset < damage_end {
          if remove_start == -1 {
            remove_start = i
          }
          remove_end = i + 1
        } else if tok_offset >= damage_end {
          break
        }
      }
      if remove_start >= 0 {
        let _ = tokens.drain(remove_start, remove_end)
      }
      // Update the damage boundary and delta for reads
      self.damage_boundary = damage_start
      self.pending_delta = self.pending_delta + delta
    }
  }
}

///|
/// Generic cursor for walking an old CST to find reusable subtrees.
/// Maintains traversal state for O(depth) lookups.
pub struct ReuseCursor[T, K] {
  stack : Array[CursorFrame]
  mut current_offset : Int
  damage_start : Int
  damage_end : Int
  old_root : @seam.CstNode
  ws_raw : @seam.RawKind
  err_raw : @seam.RawKind
  incomplete_raw : @seam.RawKind
  cache : OldTokenCache
  reuse_globally_disabled : Bool
  reuse_size_threshold : Int
  // New token stream (indexed accessors, same layout as ParserContext)
  token_count : Int
  get_token : (Int) -> T
  get_start : (Int) -> Int
  get_text : (Int) -> StringView
  spec : LanguageSpec[T, K]
}

///|
// OffsetIndexed for Array[OldToken]: lets lower_bound search the flattened
// old-tree token list by code-unit offset. Sorted by construction — collect_old_tokens
// walks the tree left-to-right so .start values are strictly increasing.
impl OffsetIndexed for Array[OldToken] with length(self) {
  self.length()
}

///|
impl OffsetIndexed for Array[OldToken] with offset_at(self, i) {
  self[i].start
}

///|
/// Flatten non-trivia, non-error, non-incomplete leaves from old tree into out array.
fn collect_old_tokens(
  node : @seam.CstNode,
  node_start : Int,
  out : Array[OldToken],
  ws_raw : @seam.RawKind,
  err_raw : @seam.RawKind,
  incomplete_raw : @seam.RawKind,
) -> Unit {
  let mut offset = node_start
  for child in node.children {
    match child {
      @seam.CstElement::Token(t) => {
        if t.kind != ws_raw && t.kind != err_raw && t.kind != incomplete_raw {
          out.push({ kind: t.kind, text: t.text, start: offset })
        }
        offset = offset + t.text_len()
      }
      @seam.CstElement::Node(n) => {
        collect_old_tokens(n, offset, out, ws_raw, err_raw, incomplete_raw)
        offset = offset + n.text_len
      }
    }
  }
}

///|
/// Create a new reuse cursor positioned at the start of the old tree.
/// damage_start/damage_end are code-unit offsets (exclusive-end) of the edited region.
pub fn[T, K : @seam.ToRawKind] ReuseCursor::new(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_text : (Int) -> StringView,
  spec : LanguageSpec[T, K],
  reuse_size_threshold? : Int = 0,
  old_token_cache? : OldTokenCache = OldTokenCache::empty(),
) -> ReuseCursor[T, K] {
  let reuse_globally_disabled = damage_start <= 0 &&
    damage_end >= old_tree.text_len
  let ws_raw = spec.whitespace_kind.to_raw()
  let err_raw = spec.error_kind.to_raw()
  let incomplete_raw = spec.incomplete_kind.to_raw()
  let stack = [
    { node: old_tree, child_index: 0, start_offset: 0, current_child_offset: 0 },
  ]
  {
    stack,
    current_offset: 0,
    damage_start,
    damage_end,
    old_root: old_tree,
    ws_raw,
    err_raw,
    incomplete_raw,
    cache: old_token_cache,
    reuse_globally_disabled,
    reuse_size_threshold,
    token_count,
    get_token,
    get_start,
    get_text,
    spec,
  }
}

///|
/// True if damage covers the entire tree — no reuse is possible.
pub fn[T, K] ReuseCursor::is_reuse_disabled(self : ReuseCursor[T, K]) -> Bool {
  self.reuse_globally_disabled
}

///|
/// Get the old-token cache for persistence across edits.
/// Call after parsing completes and pass to the next ReuseCursor::new
/// to avoid rebuilding the flat token array from scratch.
pub fn[T, K] ReuseCursor::get_old_token_cache(
  self : ReuseCursor[T, K],
) -> OldTokenCache {
  self.cache
}

///|
/// True if the node's code-unit range is entirely outside the damage region.
/// Left-adjacent (node_end == damage_start) is excluded: trailing context
/// at the boundary may have changed. Right-adjacent (node_start == damage_end)
/// is safe because damage_end is the first unmodified code unit.
fn is_outside_damage(
  node_start : Int,
  node_end : Int,
  damage_start : Int,
  damage_end : Int,
) -> Bool {
  node_end < damage_start || node_start >= damage_end
}

///|
/// True if the first non-trivia leaf of node matches the new token at token_pos.
fn[T : @seam.ToRawKind, K] leading_token_matches(
  node : @seam.CstNode,
  cursor : ReuseCursor[T, K],
  token_pos : Int,
) -> Bool {
  if token_pos >= cursor.token_count {
    return false
  }
  let new_kind = (cursor.get_token)(token_pos).to_raw()
  match node.first_token(fn(r) { r == cursor.ws_raw }) {
    None => false
    Some(old_tok) =>
      old_tok.kind == new_kind &&
      old_tok.text.view() == (cursor.get_text)(token_pos)
  }
}

///|
/// Materialize the flattened old-token table on first use.
/// Once built, the table is cached in the shared OldTokenCache cell
/// so all snapshot branches reuse the same array.
fn[T, K] ReuseCursor::ensure_old_tokens(
  self : ReuseCursor[T, K],
) -> Array[OldToken] {
  match self.cache.tokens {
    Some(tokens) => tokens
    None => {
      let tokens : Array[OldToken] = []
      collect_old_tokens(
        self.old_root,
        0,
        tokens,
        self.ws_raw,
        self.err_raw,
        self.incomplete_raw,
      )
      self.cache.tokens = Some(tokens)
      tokens
    }
  }
}

///|
/// Binary search: first old non-trivia token with start >= offset.
/// Lazily materializes the old-token table on first call.
/// Adjusts search offset for persistent-cache delta when the query
/// falls in the post-damage region.
fn[T, K] old_follow_token_lazy(
  cursor : ReuseCursor[T, K],
  offset : Int,
) -> OldToken? {
  let old_tokens = cursor.ensure_old_tokens()
  // Adjust query offset for accumulated delta from previous edits.
  // Tokens in the cache have offsets from the tree they were built from.
  // Post-damage tokens shifted by pending_delta — reverse the shift to match.
  let search_offset = if cursor.cache.pending_delta != 0 &&
    offset >= cursor.cache.damage_boundary {
    offset - cursor.cache.pending_delta
  } else {
    offset
  }
  let lo = lower_bound(old_tokens, search_offset)
  if lo < old_tokens.length() {
    Some(old_tokens[lo])
  } else {
    None
  }
}

///|
// OffsetIndexed for ReuseCursor[T,K]: lets lower_bound search the new token
// stream by code-unit offset using the same get_start closure already stored in the
// cursor. Sorted by tokenizer contract — tokens are emitted left-to-right.
// [T, K] on impl propagates the cursor's type parameters; the methods only use
// Self and Int so no additional constraints are needed.
impl[T, K] OffsetIndexed for ReuseCursor[T, K] with length(self) {
  self.token_count
}

///|
impl[T, K] OffsetIndexed for ReuseCursor[T, K] with offset_at(self, i) {
  (self.get_start)(i)
}

///|
/// Find the first non-trivia, non-EOF token in the new stream with start >= byte_offset.
/// Binary-search for the first index where get_start(i) >= byte_offset, then
/// scan forward skipping trivia (token_is_trivia) and stopping at EOF (token_is_eof).
/// Returns both the token and its index for get_text(pos) lookup.
fn[T : @seam.IsTrivia + @seam.IsEof, K] new_follow_token_with_pos(
  cursor : ReuseCursor[T, K],
  byte_offset : Int,
) -> (T, Int)? {
  let mut lo = lower_bound(cursor, byte_offset)
  while lo < cursor.token_count {
    let t = (cursor.get_token)(lo)
    if t.is_eof() {
      break
    }
    if t.is_trivia() {
      lo = lo + 1
      continue
    }
    return Some((t, lo))
  }
  None
}

///|
/// True if the follow token after node_end matches between old and new streams.
/// Option B correctness: if the first token after the node is the same in both
/// old and new source, the node boundary is stable and reuse is safe.
fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] trailing_context_matches(
  cursor : ReuseCursor[T, K],
  node_end : Int,
) -> Bool {
  let old_follow = old_follow_token_lazy(cursor, node_end)
  let new_follow = new_follow_token_with_pos(cursor, node_end)
  match (old_follow, new_follow) {
    (None, None) => true
    (Some(old), Some((new_tok, new_pos))) =>
      old.kind == new_tok.to_raw() &&
      old.text.view() == (cursor.get_text)(new_pos)
    _ => false
  }
}

///|
/// Pop the top frame and advance the parent frame's child cursor past it.
/// current_child_offset in the parent advances to the end of the popped frame.
fn[T, K] ReuseCursor::pop_frame(self : ReuseCursor[T, K]) -> Unit {
  let frame = self.stack[self.stack.length() - 1]
  let frame_end = frame.start_offset + frame.node.text_len
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
  target_offset : Int,
  expected_kind : @seam.RawKind,
) -> (@seam.CstNode, Int)? {
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
      node.kind == expected_kind &&
      node.kind != @seam.repeat_group_kind {
      return Some((node, frame.start_offset))
    }
    // If target is outside this node's range, pop up
    let node_end = frame.start_offset + node.text_len
    if target_offset < frame.start_offset || target_offset >= node_end {
      self.pop_frame()
      continue
    }
    // Target is within this node — resume from cached child offset (O(1))
    let mut child_offset = frame.current_child_offset
    let mut found_child = false
    // Search remaining children from where we left off
    while frame.child_index < node.children.length() {
      let child = node.children[frame.child_index]
      let child_width = child.text_len()
      let child_end = child_offset + child_width
      if target_offset < child_offset {
        break
      }
      if target_offset < child_end {
        match child {
          @seam.CstElement::Node(child_node) => {
            if child_node.kind == @seam.repeat_group_kind {
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
              child_node.kind == expected_kind {
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
pub fn[T : @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind, K] ReuseCursor::try_reuse(
  self : ReuseCursor[T, K],
  expected_kind : @seam.RawKind,
  byte_offset : Int,
  token_pos : Int,
) -> @seam.CstNode? {
  if self.reuse_globally_disabled ||
    (byte_offset >= self.damage_start && byte_offset < self.damage_end) {
    return None
  }
  let result = self.seek_node_at(byte_offset, expected_kind)
  match result {
    None => None
    Some((node, node_offset)) => {
      // Skip reuse for small nodes — reparsing is cheaper than the protocol.
      if self.reuse_size_threshold > 0 &&
        node.text_len < self.reuse_size_threshold {
        return None
      }
      let node_end = node_offset + node.text_len
      if !is_outside_damage(
          node_offset,
          node_end,
          self.damage_start,
          self.damage_end,
        ) {
        None
      } else if !leading_token_matches(node, self, token_pos) {
        None
      } else if !trailing_context_matches(self, node_end) {
        None
      } else {
        Some(node)
      }
    }
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
  byte_offset : Int,
  token_pos : Int,
) -> @seam.CstNode? {
  if self.reuse_globally_disabled ||
    (byte_offset >= self.damage_start && byte_offset < self.damage_end) {
    return None
  }
  // Reset to root if target is behind current position
  if byte_offset < self.current_offset {
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
    let node_end = frame.start_offset + node.text_len
    // If target is outside this node's range, pop up
    if byte_offset < frame.start_offset || byte_offset >= node_end {
      self.pop_frame()
      continue
    }
    // Scan children from cached position
    let mut child_offset = frame.current_child_offset
    let mut found_child = false
    while frame.child_index < node.children.length() {
      let child = node.children[frame.child_index]
      let child_width = child.text_len()
      let child_end = child_offset + child_width
      if byte_offset < child_offset {
        break
      }
      if byte_offset < child_end {
        match child {
          @seam.CstElement::Node(child_node) => {
            if child_node.kind == @seam.repeat_group_kind &&
              child_offset == byte_offset &&
              is_outside_damage(
                child_offset,
                child_end,
                self.damage_start,
                self.damage_end,
              ) {
              // Found undamaged RepeatGroup — validate context
              if leading_token_matches(child_node, self, token_pos) &&
                trailing_context_matches(self, child_end) {
                self.current_offset = child_offset
                return Some(child_node)
              }
            }
            // Not a match — if it's a RepeatGroup overlapping damage, descend
            if child_node.kind == @seam.repeat_group_kind {
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
  if next_idx >= frame.node.children.length() {
    return false
  }
  match frame.node.children[next_idx] {
    @seam.CstElement::Node(n) => n.has_any_error
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
  self.current_offset = self.current_offset + node.text_len
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
    old_root: self.old_root,
    ws_raw: self.ws_raw,
    err_raw: self.err_raw,
    incomplete_raw: self.incomplete_raw,
    cache: self.cache, // shared mutable cell — all snapshots see same materialized table
    reuse_globally_disabled: self.reuse_globally_disabled,
    reuse_size_threshold: self.reuse_size_threshold,
    token_count: self.token_count,
    get_token: self.get_token,
    get_start: self.get_start,
    get_text: self.get_text,
    spec: self.spec,
  }
}
