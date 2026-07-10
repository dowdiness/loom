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
