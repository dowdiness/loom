///|
test "push_offset_diagnostic reports invalid shifted diagnostic" {
  let source_id = SourceId("block-reparse-source")
  let diagnostic = Diagnostic(
    origin=DiagnosticOrigin("parser"),
    severity=Error,
    message="after",
    labels=[
      DiagnosticLabel(
        LabelStyle::Primary,
        SourceSpan(source_id, test_range(10, 11)),
        None,
      ),
      DiagnosticLabel(
        LabelStyle::Secondary,
        SourceSpan(source_id, test_range(9, 10)),
        Some("spans old end"),
      ),
    ],
  )
  let after = try TextOffset(10) catch {
    _ => abort("expected valid diagnostic shift boundary")
  } noraise {
    offset => offset
  }
  let merged = DiagnosticSet::empty()
  push_offset_diagnostic(
    merged, diagnostic, source_id, -10, after, "old diagnostic after block",
  )
  inspect(merged.length(), content="1")
  let diagnostic = merged.items()[0]
  inspect(diagnostic.format(), content="internal: diagnostic offset failed")
  debug_inspect(
    diagnostic.notes(),
    content=(
      #|[
      #|  "old diagnostic after block",
      #|  "diagnostic build error preserved as InvalidTextRange(9, 0)",
      #|]
    ),
  )
}

///|
test "splice_tree rejects a root replacement from another metadata domain" {
  let receiver_policy = @seam.CstMetadataPolicy::new([@seam.RawKind(8)])
  let foreign_policy = @seam.CstMetadataPolicy::new([@seam.RawKind(9)])
  let root = @seam.CstNode::new(
    @seam.RawKind(1),
    [
      @seam.CstElement::Token(
        @seam.CstToken::CstToken(@seam.RawKind(2), "root"),
      ),
    ],
    policy=receiver_policy,
  )
  let foreign = @seam.CstNode::new(@seam.RawKind(3), [], policy=foreign_policy)
  let mut caught = false
  try {
    let _ = splice_tree(root, [], foreign)
  } catch {
    Failure::Failure(_) => caught = true
  } noraise {
    _ => ()
  }
  assert_true(caught)
  assert_eq(root.text_len(), 4)
  assert_eq(foreign.kind(), @seam.RawKind(3))
}

///|
test "splice_tree accepts an equivalent-domain root replacement" {
  let receiver_policy = @seam.CstMetadataPolicy::new([
    @seam.RawKind(9),
    @seam.RawKind(8),
  ])
  let equivalent_policy = @seam.CstMetadataPolicy::new([
    @seam.RawKind(8),
    @seam.RawKind(9),
    @seam.RawKind(8),
  ])
  let root = @seam.CstNode::new(@seam.RawKind(1), [], policy=receiver_policy)
  let replacement = @seam.CstNode::new(
    @seam.RawKind(2),
    [],
    policy=equivalent_policy,
  )
  let rebuilt = splice_tree(root, [], replacement)
  assert_eq(rebuilt.kind(), @seam.RawKind(2))
}

///|
test "find_reparseable_ancestor admits only strict block interior" {
  let block_kind = @seam.RawKind(2)
  let token_kind = @seam.RawKind(3)
  let first = @seam.CstNode::new_unclassified(block_kind, [
    @seam.CstElement::Token(@seam.CstToken::CstToken(token_kind, "alpha\n")),
  ])
  let second = @seam.CstNode::new_unclassified(block_kind, [
    @seam.CstElement::Token(@seam.CstToken::CstToken(token_kind, "beta\n")),
  ])
  let root = @seam.CstNode::new_unclassified(@seam.RawKind(1), [
    @seam.CstElement::Node(first),
    @seam.CstElement::Node(second),
  ])
  let syntax = @seam.SyntaxNode::from_cst(root)
  let reparseable = kind => kind == block_kind

  inspect(
    find_reparseable_ancestor(syntax, Edit::replace(1, 2, 2), reparseable)
    is Some(_),
    content="true",
  )
  inspect(
    find_reparseable_ancestor(syntax, Edit::replace(0, 1, 1), reparseable)
    is None,
    content="true",
  )
  inspect(
    find_reparseable_ancestor(syntax, Edit::replace(5, 6, 6), reparseable)
    is None,
    content="true",
  )
  inspect(
    find_reparseable_ancestor(syntax, Edit::insert(6, 1), reparseable) is None,
    content="true",
  )
}
