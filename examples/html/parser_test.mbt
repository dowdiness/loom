///|
fn dump(node : @seam.CstNode) -> String {
  let kind_name = @syntax.SyntaxKind::from_raw(node.kind).to_string()
  let parts = node.children.filter_map(dump_element)
  if parts.is_empty() {
    "(" + kind_name + ")"
  } else {
    "(" + kind_name + " " + parts.join(" ") + ")"
  }
}

///|
fn dump_element(elem : @seam.CstElement) -> String? {
  match elem {
    @seam.CstElement::Node(n) => Some(dump(n))
    @seam.CstElement::Token(tok) => {
      let whitespace_kind = @syntax.SyntaxKind::WhitespaceToken.to_raw()
      let error_kind = @syntax.SyntaxKind::ErrorToken.to_raw()
      if tok.kind == whitespace_kind {
        None
      } else if tok.kind == error_kind {
        Some("ERR:\"" + tok.text().to_owned() + "\"")
      } else {
        Some("\"" + tok.text().to_owned() + "\"")
      }
    }
  }
}

///|
test "root directly contains ElementNode (no double-wrap)" {
  let result = html_grammar.parse_cst("<p>hello</p>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<p>" (TextLeaf "hello") "</p>"))
    ),
  )
}

///|
test "parse void element" {
  let result = html_grammar.parse_cst("<br>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse element with text" {
  let result = html_grammar.parse_cst("<p>hello</p>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse nested elements" {
  let result = html_grammar.parse_cst("<div><p>text</p></div>") catch {
    _ => return
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse self-closing element" {
  let result = html_grammar.parse_cst("<br/>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse empty input" {
  let result = html_grammar.parse_cst("") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "recover from mismatched close tag at root" {
  // Regression for loom #646: a stray CloseTag at the root must not spin
  // parse_html_root's recovery loop (skip_until on a sync point).
  let result = html_grammar.parse_cst("<div></span>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "script content is raw text" {
  // Regression for loom #626: <script>/<style> content must lex as
  // @token.RawText (RawTextLeaf in the tree), not @token.Text (TextLeaf).
  let result = html_grammar.parse_cst("<script>var x = 1;</script>") catch {
    _ => return
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  let raw_text_kind = @syntax.SyntaxKind::RawTextToken.to_raw()
  let raw = @seam.CstElement::Node(tree)
    .iter()
    .find_first(elem => {
      match elem {
        @seam.CstElement::Token(t) => t.kind == raw_text_kind
        _ => false
      }
    })
  guard raw is Some(@seam.CstElement::Token(tok)) else {
    fail("expected a RawTextToken in the tree")
  }
  inspect(tok.text().to_owned(), content="var x = 1;")
}

///|
test "compiled HTML root isolates parse-local native state" {
  let first = html_grammar.parse_cst("<div>open") catch { _ => return }
  let (_, first_diagnostics) = first
  inspect(first_diagnostics.length() >= 1, content="true")
  let second = html_grammar.parse_cst("<div>ok</div>") catch { _ => return }
  let (_, second_diagnostics) = second
  inspect(second_diagnostics.length(), content="0")
}

///|
test "void elements do not require a close-tag stack entry" {
  let result = html_grammar.parse_cst("<br>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "HTML IR compile rejects an unregistered guard" {
  let caught = try {
    let _ = @grammar.compile(
      html_grammar_ir,
      native_names=Set::Set(["parse_html_root"]),
      guard_names=Set::Set([]),
    )
    None
  } catch {
    error => Some(error)
  }
  match caught {
    Some(@grammar.MissingHostGuard("html_tag_stack_valid")) => ()
    _ => fail("expected MissingHostGuard(html_tag_stack_valid)")
  }
}

///|
test "mismatched close tags report diagnostics through close boundary" {
  let result = html_grammar.parse_cst("<div><span></div></span>") catch {
    _ => return
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "mismatched close diagnostics preserve original tag spelling" {
  let result = html_grammar.parse_cst("<DIV></span>") catch {
    _ => fail("mismatched close diagnostic parse raised")
  }
  let (_, diagnostics) = result
  inspect(
    diagnostics.items()[0].message,
    content="Mismatched close tag: expected </DIV>, got </span>",
  )
}

///|
test "mixed-case close tags match case-insensitively" {
  let result = html_grammar.parse_cst("<DIV></div>") catch {
    _ => fail("mixed-case HTML parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "unclosed tags report diagnostics after stack remains nonempty" {
  let result = html_grammar.parse_cst("<div><span>text") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "nested tags and void elements balance the parse-local stack" {
  let result = html_grammar.parse_cst("<div><br><span>ok</span></div>") catch {
    _ => return
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "mismatched nesting preserves a valid sibling" {
  let result = html_grammar.parse_cst("<div><span></div><p>ok</p>") catch {
    _ => return fail("mismatched parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  inspect(
    dump(tree).contains("(ElementNode \"<p>\" (TextLeaf \"ok\") \"</p>\")"),
    content="true",
  )
}

///|
test "extra mismatched close does not prevent the following sibling" {
  let result = html_grammar.parse_cst("<div><span></div></span><p>ok</p>") catch {
    _ => return fail("extra-close parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  inspect(
    dump(tree).contains("(ElementNode \"<p>\" (TextLeaf \"ok\") \"</p>\")"),
    content="true",
  )
}

///|
test "unclosed element reports a diagnostic" {
  let result = html_grammar.parse_cst("<div>open") catch {
    _ => return fail("unclosed parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "MAX_DEPTH recovery reports an error without stack overflow" {
  let source = StringBuilder()
  for _ in 0..<520 {
    source.write_string("<div>")
  }
  let input = source.to_string()
  let result = html_grammar.parse_cst(input) catch {
    _ => return fail("MAX_DEPTH parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  inspect(tree.text_len == input.length(), content="true")
}

///|
test "MAX_ERRORS recovery reaches EOF without retrying sentinel" {
  let source = StringBuilder()
  for _ in 0..<30 {
    source.write_string("<div></span>")
  }
  source.write_string("<p>ok</p>")
  let input = source.to_string()
  let result = html_grammar.parse_cst(input) catch {
    _ => return fail("MAX_ERRORS parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  inspect(tree.text_len == input.length(), content="true")
}

///|
test "malformed parse does not leak stack into the next parse" {
  let first = html_grammar.parse_cst("<div><span></div>") catch {
    _ => return fail("malformed parse raised")
  }
  let (_, first_diags) = first
  inspect(first_diags.length() >= 1, content="true")
  let second = html_grammar.parse_cst("<div>ok</div>") catch {
    _ => return fail("isolated parse raised")
  }
  let (tree, second_diags) = second
  inspect(second_diags.length(), content="0")
  inspect(
    dump(tree),
    content="(RootNode (ElementNode \"<div>\" (TextLeaf \"ok\") \"</div>\"))",
  )
}

///|
test "MAX_DEPTH recovery does not poison a later parse" {
  let deep = StringBuilder()
  for _ in 0..<520 {
    deep.write_string("<div>")
  }
  let first = html_grammar.parse_cst(deep.to_string()) catch {
    _ => return fail("MAX_DEPTH parse raised")
  }
  let (_, first_diags) = first
  inspect(first_diags.length() >= 1, content="true")
  let second = html_grammar.parse_cst("<div>ok</div>") catch {
    _ => return fail("post-depth parse raised")
  }
  let (_, second_diags) = second
  inspect(second_diags.length(), content="0")
}
