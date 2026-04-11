///|
/// Grammar-provided configuration for block reparse.
/// Grammar authors implement three functions to enable block-level
/// incremental reparsing for their language.
pub(all) struct BlockReparseSpec[T, K] {
  /// Returns true for node kinds that can be reparsed in isolation.
  is_reparseable : (@seam.RawKind) -> Bool
  /// Returns the parse function for a reparseable kind.
  get_reparser : (@seam.RawKind) -> ((ParserContext[T, K]) -> Unit)?
  /// Structural integrity check on re-lexed tokens.
  is_balanced : (Array[TokenInfo[T]]) -> Bool
}

// ─── Block reparse orchestration ──────────────────────────────────────────────

///|
/// Drill down from root CstNode to a target node using byte offsets.
/// Traverses through RepeatGroups transparently.
/// Returns Array[Int] of physical child indices, or None if the target
/// cannot be located.
fn build_physical_path(
  root : @seam.CstNode,
  target_offset : Int,
  target_end : Int,
  target_kind : @seam.RawKind,
) -> Array[Int]? {
  let path : Array[Int] = []
  let mut current = root
  let mut current_offset = 0
  // Check if root itself is the target
  if root.kind == target_kind &&
    current_offset == target_offset &&
    current_offset + root.text_len == target_end {
    return Some(path) // empty path = root is the target
  }
  // Keep drilling until we find the target node
  while true {
    let mut found = false
    let mut child_offset = current_offset
    for i, elem in current.children {
      let child_len = elem.text_len()
      let child_start = child_offset
      let child_end = child_offset + child_len
      match elem {
        @seam.CstElement::Node(child_node) =>
          if child_start <= target_offset && target_end <= child_end {
            // This child contains the target
            if child_node.kind == @seam.repeat_group_kind {
              // Transparent: drill into RepeatGroup but record its physical index
              path.push(i)
              current = child_node
              current_offset = child_start
              found = true
              break
            } else if child_start == target_offset &&
              child_end == target_end &&
              child_node.kind == target_kind {
              // Found the exact target
              path.push(i)
              return Some(path)
            } else {
              // Drill deeper into this non-target interior node
              path.push(i)
              current = child_node
              current_offset = child_start
              found = true
              break
            }
          }
        @seam.CstElement::Token(_) => ()
      }
      child_offset = child_end
    }
    if !found {
      return None
    }
  }
  None
}

///|
/// Walk up from edit position via SyntaxNode::parent(), find first
/// reparseable ancestor that strictly contains the edit.
/// Returns the ancestor SyntaxNode and the physical path from root to it.
///
/// "Strictly interior" means the edit is fully inside the block:
///   edit.start > block.start() AND edit.start + edit.new_len < block.end() + edit.delta()
pub fn find_reparseable_ancestor(
  tree : @seam.SyntaxNode,
  edit : Edit,
  is_reparseable : (@seam.RawKind) -> Bool,
) -> (@seam.SyntaxNode, Array[Int])? {
  // Start at the deepest node containing the edit position
  let leaf = tree.find_at(edit.start)
  // Walk up via parent chain
  let mut current : @seam.SyntaxNode? = Some(leaf)
  while current is Some(node) {
    if is_reparseable(node.kind()) {
      // Check "strictly interior": edit must be fully inside the block
      // NOTE: This strictly-interior check assumes single-edit-at-a-time.
      // Multi-edit support would need accumulated delta tracking.
      let block_start = node.start()
      let block_new_end = node.end() + edit.delta()
      if edit.start > block_start && edit.start + edit.new_len < block_new_end {
        // Build physical path from root CST to this node
        let root_cst = tree.cst_node()
        match
          build_physical_path(root_cst, node.start(), node.end(), node.kind()) {
          Some(path) => return Some((node, path))
          None => ()
        }
      }
    }
    current = node.parent()
  }
  None
}

///|
/// Path-copy splice: walk nodes along path, replace bottom-up using
/// with_replaced_child. Returns a new root CstNode with the node at
/// `path` replaced by `new_node`.
pub fn splice_tree(
  root : @seam.CstNode,
  path : Array[Int],
  new_node : @seam.CstNode,
  trivia_kind? : @seam.RawKind? = None,
  error_kind? : @seam.RawKind? = None,
  incomplete_kind? : @seam.RawKind? = None,
) -> @seam.CstNode {
  if path.length() == 0 {
    return new_node
  }
  // Collect the chain of ancestor nodes along the path
  let ancestors : Array[@seam.CstNode] = [root]
  let mut current = root
  for i = 0; i < path.length() - 1; i = i + 1 {
    let idx = path[i]
    match current.children[idx] {
      @seam.CstElement::Node(child) => {
        ancestors.push(child)
        current = child
      }
      @seam.CstElement::Token(_) =>
        abort("splice_tree: path index points to a token, not a node")
    }
  }
  // Replace bottom-up
  let mut replacement : @seam.CstElement = @seam.CstElement::Node(new_node)
  for i = path.length() - 1; i >= 0; i = i - 1 {
    let ancestor = ancestors[i]
    let child_idx = path[i]
    let new_ancestor = ancestor.with_replaced_child(
      child_idx,
      replacement,
      trivia_kind~,
      error_kind~,
      incomplete_kind~,
    )
    replacement = @seam.CstElement::Node(new_ancestor)
  }
  match replacement {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) =>
      abort("splice_tree: replacement should be a node")
  }
}

///|
/// Create ParserContext from pre-tokenized tokens, call reparse_fn,
/// flush trivia, auto-close unclosed nodes, and build tree.
/// Returns the reparsed CstNode and any new diagnostics, or None
/// if parsing produces no node child.
fn[T : @seam.IsTrivia, K : @seam.ToRawKind] parse_block_isolated(
  block_text : String,
  block_kind : @seam.RawKind,
  tokens : Array[TokenInfo[T]],
  reparse_fn : (ParserContext[T, K]) -> Unit,
  spec : LanguageSpec[T, K],
) -> (@seam.CstNode, Array[Diagnostic[T]])? {
  // Create a parser context for the isolated block
  let ctx = ParserContext::new(tokens, block_text, spec)
  // Call the reparse function (NOT spec.parse_root)
  reparse_fn(ctx)
  // Flush trailing trivia
  ctx.flush_trivia()
  // Auto-close any unclosed nodes
  while ctx.open_nodes > 0 {
    ctx.events.push(@seam.ParseEvent::FinishNode)
    ctx.open_nodes = ctx.open_nodes - 1
  }
  // Build tree using block_kind as root
  let ws_raw = spec.whitespace_kind.to_raw()
  let err_raw = spec.error_kind.to_raw()
  let inc_raw = spec.incomplete_kind.to_raw()
  let wrapper = ctx.events.build_tree(
    block_kind,
    trivia_kind=Some(ws_raw),
    error_kind=Some(err_raw),
    incomplete_kind=Some(inc_raw),
  ) catch {
    e => {
      ctx.error("internal: block reparse failed: " + @debug.to_string(e))
      return None // fall back to full incremental reparse
    }
  }
  // Unwrap: build_tree wraps in a root node of block_kind,
  // and parse_block_expr also emits BlockExpr start/finish,
  // producing block_kind(BlockExpr(...)). Extract the inner node.
  let mut inner : @seam.CstNode? = None
  for child in wrapper.children {
    match child {
      @seam.CstElement::Node(n) => {
        inner = Some(n)
        break
      }
      @seam.CstElement::Token(_) => ()
    }
  }
  match inner {
    Some(block_cst) => Some((block_cst, ctx.errors))
    None => None
  }
}

///|
/// Three-range diagnostic merge:
/// - before block (keep unchanged)
/// - inside block (discard old, add new offset-adjusted)
/// - after block (shift by delta)
fn[T] merge_diagnostics(
  old_diagnostics : Array[Diagnostic[T]],
  block_start : Int,
  block_old_end : Int,
  new_diagnostics : Array[Diagnostic[T]],
  delta : Int,
) -> Array[Diagnostic[T]] {
  let result : Array[Diagnostic[T]] = []
  // Single pass: partition old diagnostics into before/inside/after
  for d in old_diagnostics {
    if d.end <= block_start {
      result.push(d) // before: keep as-is
    } else if d.start >= block_old_end {
      // after: shift by delta
      result.push({
        message: d.message,
        start: d.start + delta,
        end: d.end + delta,
        got_token: d.got_token,
      })
    }
    // inside: discard
  }
  // Append offset-adjusted new diagnostics
  for d in new_diagnostics {
    result.push({
      message: d.message,
      start: d.start + block_start,
      end: d.end + block_start,
      got_token: d.got_token,
    })
  }
  result
}

///|
/// Orchestrate block-level incremental reparse.
///
/// 1. Find reparseable ancestor containing the edit
/// 2. Extract block text from new source
/// 3. Tokenize and check balance
/// 4. Parse in isolation
/// 5. Splice new subtree into old tree
/// 6. Merge diagnostics
///
/// Returns the new root CstNode and merged diagnostics, or None if
/// block reparse is not applicable (falls back to full reparse).
pub fn[T : @seam.IsTrivia, K : @seam.ToRawKind] reparse_block(
  tree : @seam.SyntaxNode,
  new_source : String,
  edit : Edit,
  tokenize : (String) -> Array[TokenInfo[T]] raise LexError,
  spec : LanguageSpec[T, K],
  block_spec : BlockReparseSpec[T, K],
  old_diagnostics : Array[Diagnostic[T]],
) -> (@seam.CstNode, Array[Diagnostic[T]])? {
  // 1. Find reparseable ancestor
  let (ancestor, path) = match
    find_reparseable_ancestor(tree, edit, block_spec.is_reparseable) {
    Some(result) => result
    None => return None
  }
  let block_kind = ancestor.kind()
  let block_start = ancestor.start()
  let block_old_end = ancestor.end()
  let block_new_end = block_old_end + edit.delta()
  // 2. Extract block text from new source
  if block_start < 0 ||
    block_new_end > new_source.length() ||
    block_start > block_new_end {
    return None
  }
  let block_text_view : StringView = new_source[block_start:block_new_end]
  let block_text = block_text_view.to_string()
  // 3. Tokenize and check balance
  let block_tokens = tokenize(block_text) catch { LexError(_) => return None }
  if !(block_spec.is_balanced)(block_tokens) {
    return None
  }
  // 4. Get the reparser for this block kind
  let reparse_fn = match (block_spec.get_reparser)(block_kind) {
    Some(f) => f
    None => return None
  }
  // 5. Parse in isolation
  let (new_block, new_diags) = match
    parse_block_isolated(block_text, block_kind, block_tokens, reparse_fn, spec) {
    Some(result) => result
    None => return None
  }
  // 6. Splice new subtree into old tree
  let root_cst = tree.cst_node()
  let ws_raw = spec.whitespace_kind.to_raw()
  let err_raw = spec.error_kind.to_raw()
  let inc_raw = spec.incomplete_kind.to_raw()
  let new_root = splice_tree(
    root_cst,
    path,
    new_block,
    trivia_kind=Some(ws_raw),
    error_kind=Some(err_raw),
    incomplete_kind=Some(inc_raw),
  )
  // 7. Merge diagnostics
  let merged = merge_diagnostics(
    old_diagnostics,
    block_start,
    block_old_end,
    new_diags,
    edit.delta(),
  )
  Some((new_root, merged))
}
