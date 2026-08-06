///|
/// Grammar-provided configuration for block reparse.
/// Grammar authors implement three functions to enable block-level
/// incremental reparsing for their language.
pub(all) struct BlockReparseSpec[T, K] {
  /// Returns true for node kinds that can be reparsed in isolation.
  is_reparseable : (@seam.RawKind) -> Bool
  /// Selects an isolated parser after lexing a strict candidate range.
  ///
  /// The old `SyntaxNode` preserves stable context; the new source and token
  /// stream let a language reject a candidate whose ownership changed. Returning
  /// `None` explicitly asks the core to try the next strict reparseable parent.
  get_reparser : (@seam.SyntaxNode, String, Array[TokenInfo[T]]) -> ((
    ParserContext[T, K],
  ) -> Unit)?
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
  if root.kind() == target_kind &&
    current_offset == target_offset &&
    current_offset + root.text_len() == target_end {
    return Some(path) // empty path = root is the target
  }
  // Keep drilling until we find the target node
  while true {
    let mut found = false
    let mut child_offset = current_offset
    for i, elem in current.children() {
      let child_len = elem.text_len()
      let child_start = child_offset
      let child_end = child_offset + child_len
      match elem {
        @seam.CstElement::Node(child_node) =>
          if child_start <= target_offset && target_end <= child_end {
            // This child contains the target
            if child_node.kind() == @seam.repeat_group_kind {
              // Transparent: drill into RepeatGroup but record its physical index
              path.push(i)
              current = child_node
              current_offset = child_start
              found = true
              break
            } else if child_start == target_offset &&
              child_end == target_end &&
              child_node.kind() == target_kind {
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
/// Walk up from edit position and collect strict reparseable ancestors from
/// innermost to outermost, with physical paths rooted at the current CST.
fn find_reparseable_ancestors(
  tree : @seam.SyntaxNode,
  edit : Edit,
  is_reparseable : (@seam.RawKind) -> Bool,
) -> Array[(@seam.SyntaxNode, Array[Int])] {
  let candidates : Array[(@seam.SyntaxNode, Array[Int])] = []
  let root_cst = tree.cst_node()
  let leaf = tree.find_at(edit.start)
  let mut current : @seam.SyntaxNode? = Some(leaf)
  while current is Some(node) {
    if is_reparseable(node.kind()) {
      let block_start = node.start()
      let block_new_end = node.end() + edit.delta()
      if edit.start > block_start && edit.start + edit.new_len < block_new_end {
        match
          build_physical_path(root_cst, node.start(), node.end(), node.kind()) {
          Some(path) => candidates.push((node, path))
          None => ()
        }
      }
    }
    current = node.parent()
  }
  candidates
}

///|
/// Find the innermost strict reparseable ancestor.
///
/// "Strictly interior" means the edit is fully inside the block:
///   edit.start > block.start() AND edit.start + edit.new_len < block.end() + edit.delta()
pub fn find_reparseable_ancestor(
  tree : @seam.SyntaxNode,
  edit : Edit,
  is_reparseable : (@seam.RawKind) -> Bool,
) -> (@seam.SyntaxNode, Array[Int])? {
  match find_reparseable_ancestors(tree, edit, is_reparseable) {
    [first, ..] => Some(first)
    [] => None
  }
}

///|
/// Path-copy splice: walk nodes along path, replace bottom-up using
/// policy-preserving reconstruction. Returns a new root CstNode with the node
/// at `path` replaced by `new_node`.
pub fn splice_tree(
  root : @seam.CstNode,
  path : Array[Int],
  new_node : @seam.CstNode,
) -> @seam.CstNode raise Failure {
  if path.length() == 0 {
    return root.with_replaced_root(new_node)
  }
  // Collect the chain of ancestor nodes along the path
  let ancestors : Array[@seam.CstNode] = [root]
  let mut current = root
  for i = 0; i < path.length() - 1; i = i + 1 {
    let idx = path[i]
    match current.children()[idx] {
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
    let new_ancestor = ancestor.with_replaced_child(child_idx, replacement)
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
fn[T : @seam.IsTrivia + @seam.ToRawKind, K] parse_block_isolated(
  source_id : SourceId,
  block_text : String,
  block_kind : @seam.RawKind,
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  reparse_fn : (ParserContext[T, K]) -> Unit,
  spec : LanguageSpec[T, K],
) -> (@seam.CstNode, DiagnosticSet)? raise Failure {
  if starts.length() != tokens.length() {
    return None
  }
  // Create a parser context for the isolated block
  let ctx = ParserContext::new_indexed(
    source_id,
    tokens.length(),
    i => tokens[i].token,
    i => starts[i],
    i => starts[i] + tokens[i].len,
    block_text,
    spec,
  )
  // Call the reparse function (NOT spec.parse_root)
  reparse_fn(ctx)
  // Flush trailing trivia
  ctx.flush_trivia()
  // Auto-close any unclosed nodes
  // node_stack intentionally NOT modified here — terminal loop. tree build follows.
  // If a future caller reads node_stack after this loop, must pop it. 
  while ctx.open_nodes > 0 {
    ctx.events.push(@seam.ParseEvent::FinishNode)
    ctx.open_nodes = ctx.open_nodes - 1
  }
  // Build tree using block_kind as root
  let wrapper = ctx.events.build_tree(
    block_kind,
    policy=spec.cst_metadata_policy,
  ) catch {
    Failure::Failure(_) as failure => raise failure
    e => {
      ctx.error("internal: block reparse failed: " + @debug.to_string(e))
      return None // fall back to full incremental reparse
    }
  }
  // Unwrap: build_tree wraps in a root node of block_kind,
  // and parse_block_expr also emits BlockExpr start/finish,
  // producing block_kind(BlockExpr(...)). Extract the inner node.
  let mut inner : @seam.CstNode? = None
  for child in wrapper.children() {
    match child {
      @seam.CstElement::Node(n) => {
        inner = Some(n)
        break
      }
      @seam.CstElement::Token(_) => ()
    }
  }
  match inner {
    Some(block_cst) => Some((block_cst, ctx.diagnostics))
    None => None
  }
}

///|
/// Three-range diagnostic merge:
/// - before block (keep unchanged)
/// - inside block (discard old, add new offset-adjusted)
/// - after block (shift by delta)
fn diagnostic_offset_failure(
  context : String,
  error : DiagnosticBuildError,
) -> Diagnostic {
  Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="internal: diagnostic offset failed",
    notes=[
      context,
      "diagnostic build error preserved as " + @debug.to_string(error),
    ],
  )
}

///|
fn push_offset_diagnostic(
  result : DiagnosticSet,
  diagnostic : Diagnostic,
  source_id : SourceId,
  delta : Int,
  after : TextOffset,
  context : String,
) -> Unit {
  try diagnostic.offset_by(source_id, delta, after) catch {
    error => result.push(diagnostic_offset_failure(context, error))
  } noraise {
    diagnostic => result.push(diagnostic)
  }
}

///|
fn merge_diagnostics(
  source_id : SourceId,
  old_diagnostics : DiagnosticSet,
  block_start : Int,
  block_old_end : Int,
  new_diagnostics : DiagnosticSet,
  delta : Int,
) -> DiagnosticSet {
  let old_len = block_old_end - block_start
  let result = old_diagnostics.after_relex(
    SourceEdit(source_id, Edit::new(block_start, old_len, old_len + delta)),
    failure_context="block reparse",
  )
  let block_zero = try TextOffset(0) catch {
    error => {
      result.push(diagnostic_offset_failure("block zero offset", error))
      return result
    }
  } noraise {
    offset => offset
  }
  // Append offset-adjusted new diagnostics
  for d in new_diagnostics.items() {
    push_offset_diagnostic(
      result, d, source_id, block_start, block_zero, "new block diagnostic",
    )
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
pub fn[T : @seam.IsTrivia + @seam.ToRawKind, K] reparse_block(
  source_id : SourceId,
  tree : @seam.SyntaxNode,
  new_source : String,
  edit : Edit,
  lex : (SourceId, String) -> LexResult[T],
  spec : LanguageSpec[T, K],
  block_spec : BlockReparseSpec[T, K],
  old_diagnostics : DiagnosticSet,
) -> (@seam.CstNode, DiagnosticSet)? raise Failure {
  let root_cst = tree.cst_node()
  for
    candidate in find_reparseable_ancestors(
      tree,
      edit,
      block_spec.is_reparseable,
    ) {
    let (ancestor, path) = candidate
    let block_kind = ancestor.kind()
    let block_start = ancestor.start()
    let block_old_end = ancestor.end()
    let block_new_end = block_old_end + edit.delta()
    if block_start < 0 ||
      block_new_end > new_source.length() ||
      block_start > block_new_end {
      return None
    }
    let block_text_view : StringView = new_source[block_start:block_new_end]
    let block_text = block_text_view.to_owned()
    let block_lex = lex(source_id, block_text)
    let block_tokens = block_lex.tokens
    let block_starts = block_lex.starts
    let block_lex_diags = block_lex.diagnostics
    if !(block_spec.is_balanced)(block_tokens) {
      return None
    }
    match (block_spec.get_reparser)(ancestor, block_text, block_tokens) {
      None => continue
      Some(reparse_fn) => {
        let (new_block, parse_diags) = match
          parse_block_isolated(
            source_id, block_text, block_kind, block_tokens, block_starts, reparse_fn,
            spec,
          ) {
          Some(result) => result
          None => return None
        }
        let new_diags = block_lex_diags.copy()
        new_diags.add_all(parse_diags)
        let new_root = splice_tree(root_cst, path, new_block)
        let merged = merge_diagnostics(
          source_id,
          old_diagnostics,
          block_start,
          block_old_end,
          new_diags,
          edit.delta(),
        )
        return Some((new_root, merged))
      }
    }
  }
  None
}
