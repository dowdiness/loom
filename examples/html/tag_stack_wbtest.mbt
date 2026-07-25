///|
/// Sharing one tag stack across parses is sound only because the parser
/// restores it: every push in `parse_element` is matched by a pop back to its
/// base before that frame returns, on the raw-text, normal, and recovery paths
/// alike. `make_html_parse_root` depends on this, so pin it here rather than
/// leaving it to be rediscovered.
test "parse_html_root leaves the tag stack empty" {
  let unbalanced = html_grammar.parse_cst("<div><span>") catch {
    _ => return fail("lex error")
  }
  let (_, diagnostics) = unbalanced
  inspect(diagnostics.length() >= 1, content="true")
  inspect(html_tag_stack.is_empty(), content="true")
}

///|
test "parse_html_root leaves the tag stack empty after mismatched closes" {
  let mismatched = html_grammar.parse_cst("<div><span></div>") catch {
    _ => return fail("lex error")
  }
  let (_, diagnostics) = mismatched
  inspect(diagnostics.length() >= 1, content="true")
  inspect(html_tag_stack.is_empty(), content="true")
}
