///|
/// Extract projection leaves from a lambda CST.
///
/// NOTE: This is a spike-local helper for the A-vs-B oracle. It fires on ANY
/// node that has a direct IdentToken or IntToken child — so it emits a var:
/// leaf not only for VarRef nodes but also for LetDef names and ParamList
/// parameters, and binder x collides with use x on the same key var:x.
/// Duplicate keys are acceptable here because the extractor only needs to be a
/// deterministic, A/B-symmetric function of the CST; the tracker handles
/// repeated keys. This is NOT a realistic projection; a real consumer would key
/// off node kind and binding structure. That is an E2 honesty caveat (Task 12).
pub fn project_lambda_leaves(root : @seam.SyntaxNode) -> Array[@core.ProjectionLeaf] {
  let acc : Array[@core.ProjectionLeaf] = Array::new()
  collect_lambda_leaves(root, acc)
  acc
}

///|
fn collect_lambda_leaves(
  node : @seam.SyntaxNode,
  acc : Array[@core.ProjectionLeaf],
) -> Unit {
  collect_var_ref_leaf(node, acc)
  collect_int_literal_leaf(node, acc)
  for child in node.children() {
    collect_lambda_leaves(child, acc)
  }
}

///|
fn collect_var_ref_leaf(
  node : @seam.SyntaxNode,
  acc : Array[@core.ProjectionLeaf],
) -> Unit {
  match node.required_direct_token_of_kind(
    @syntax.IdentToken.to_raw(),
    message="var ref identifier",
  ) {
    Ok(token) =>
      acc.push(@core.ProjectionLeaf::new(token.start(), token.end(), "var:" + token.text()))
    Err(_) => ()
  }
}

///|
fn collect_int_literal_leaf(
  node : @seam.SyntaxNode,
  acc : Array[@core.ProjectionLeaf],
) -> Unit {
  match node.required_direct_token_of_kind(
    @syntax.IntToken.to_raw(),
    message="integer literal",
  ) {
    Ok(token) =>
      acc.push(@core.ProjectionLeaf::new(token.start(), token.end(), "int:" + token.text()))
    Err(_) => ()
  }
}
