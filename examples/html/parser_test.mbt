///|
fn dump(node : @seam.CstNode) -> String {
  let kind_name = @syntax.SyntaxKind::from_raw(node.kind()).to_string()
  let parts = node.children().filter_map(dump_element)
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
fn html_diagnostic_start(diag : @core.Diagnostic) -> Int {
  match
    diag
    .labels()
    .iter()
    .find_first(label => label.style() is @core.LabelStyle::Primary) {
    Some(label) => label.span().range().start().value()
    None => abort("expected primary HTML diagnostic label")
  }
}

///|
test "root directly contains ElementNode (no double-wrap)" {
  let source_id = @core.SourceId("html-parser-root-element")
  let result = parse_cst(source_id, "<p>hello</p>") catch {
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
  let source_id = @core.SourceId("html-parser-void-element")
  let result = html_grammar.parse_cst(source_id, "<br>") catch {
    _ => return fail("void element parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse element with text" {
  let source_id = @core.SourceId("html-parser-text-content")
  let result = html_grammar.parse_cst(source_id, "<p>hello</p>") catch {
    _ => return fail("element-with-text parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse nested elements" {
  let source_id = @core.SourceId("html-parser-nested-elements")
  let result = html_grammar.parse_cst(source_id, "<div><p>text</p></div>") catch {
    _ => return fail("nested element parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse self-closing element" {
  let source_id = @core.SourceId("html-parser-self-closing-element")
  let result = html_grammar.parse_cst(source_id, "<br/>") catch {
    _ => return fail("self-closing element parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse empty input" {
  let source_id = @core.SourceId("html-parser-empty-input")
  let result = html_grammar.parse_cst(source_id, "") catch {
    _ => return fail("empty-input parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "recover from mismatched close tag at root" {
  // Regression for loom #646: a stray CloseTag at the root must not spin
  // parse_html_root's recovery loop (skip_until on a sync point).
  let source_id = @core.SourceId("html-parser-mismatched-close-source")
  let result = html_grammar.parse_cst(source_id, "<div></span>") catch {
    _ => return fail("root mismatch recovery raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  let items = diagnostics.items()
  guard items.any(diagnostic => {
    diagnostic.labels().any(label => label.style() is @core.LabelStyle::Primary)
  }) else {
    fail("expected malformed HTML diagnostics to include a primary label")
  }
  guard items.all(diagnostic => {
    diagnostic
    .labels()
    .all(label => {
      !(label.style() is @core.LabelStyle::Primary) ||
      label.span().source_id() == source_id
    })
  }) else {
    fail("expected every primary HTML label to retain the caller source id")
  }
}

///|
test "script content is raw text" {
  // Regression for loom #626: <script>/<style> content must lex as
  // @token.RawText (RawTextLeaf in the tree), not @token.Text (TextLeaf).
  let source_id = @core.SourceId("html-parser-script-raw-text")
  let result = html_grammar.parse_cst(source_id, "<script>var x = 1;</script>") catch {
    _ => return fail("raw-text parse raised")
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
  let first_source_id = @core.SourceId("html-parser-isolated-malformed")
  let first = html_grammar.parse_cst(first_source_id, "<div>open") catch {
    _ => return fail("first isolated parse raised")
  }
  let (_, first_diagnostics) = first
  inspect(first_diagnostics.length() >= 1, content="true")
  let second_source_id = @core.SourceId("html-parser-isolated-valid")
  let second = html_grammar.parse_cst(second_source_id, "<div>ok</div>") catch {
    _ => return fail("second isolated parse raised")
  }
  let (_, second_diagnostics) = second
  inspect(second_diagnostics.length(), content="0")
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
  let source_id = @core.SourceId("html-parser-close-boundary")
  let result = html_grammar.parse_cst(source_id, "<div><span></div></span>") catch {
    _ => return fail("close-boundary mismatch parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}

///|
test "mismatched close diagnostics preserve original tag spelling" {
  let source_id = @core.SourceId("html-parser-original-tag-spelling")
  let result = html_grammar.parse_cst(source_id, "<DIV></span>") catch {
    _ => fail("mismatched close diagnostic parse raised")
  }
  let (_, diagnostics) = result
  inspect(
    diagnostics.items()[0].message(),
    content="Mismatched close tag: expected </DIV>, got </span>",
  )
  inspect(html_diagnostic_start(diagnostics.items()[0]), content="5")
}

///|
test "mixed-case close tags match case-insensitively" {
  let source_id = @core.SourceId("html-parser-mixed-case-close")
  let result = html_grammar.parse_cst(source_id, "<DIV></div>") catch {
    _ => fail("mixed-case HTML parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "unclosed tags report diagnostics after stack remains nonempty" {
  let source_id = @core.SourceId("html-parser-unclosed-stack")
  let result = html_grammar.parse_cst(source_id, "<div><span>text") catch {
    _ => return fail("unclosed-tag parse raised")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  let unclosed = diagnostics
    .items()
    .iter()
    .find_first(d => d.message() == "Unclosed element: span")
  match unclosed {
    Some(diag) => inspect(html_diagnostic_start(diag), content="15")
    None => fail("expected span unclosed diagnostic")
  }
}

///|
test "nested tags and void elements preserve sibling structure" {
  let source_id = @core.SourceId("html-parser-nested-void-siblings")
  let result = html_grammar.parse_cst(
    source_id, "<div><br><span>ok</span></div>",
  ) catch {
    _ => return fail("nested void-element parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree).contains(
      "(ElementNode \"<span>\" (TextLeaf \"ok\") \"</span>\")",
    ),
    content="true",
  )
}

///|
test "mismatched nesting preserves a valid sibling" {
  let source_id = @core.SourceId("html-parser-mismatched-valid-sibling")
  let result = html_grammar.parse_cst(source_id, "<div><span></div><p>ok</p>") catch {
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
  let source_id = @core.SourceId("html-parser-extra-close-sibling")
  let result = html_grammar.parse_cst(
    source_id, "<div><span></div></span><p>ok</p>",
  ) catch {
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
  let source_id = @core.SourceId("html-parser-unclosed-element")
  let result = html_grammar.parse_cst(source_id, "<div>open") catch {
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
  let source_id = @core.SourceId("html-parser-max-depth")
  let result = html_grammar.parse_cst(source_id, input) catch {
    _ => return fail("MAX_DEPTH parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  inspect(tree.text_len() == input.length(), content="true")
}

///|
test "MAX_ERRORS recovery reaches EOF without retrying sentinel" {
  let source = StringBuilder()
  for _ in 0..<30 {
    source.write_string("<div></span>")
  }
  source.write_string("<p>ok</p>")
  let input = source.to_string()
  let source_id = @core.SourceId("html-parser-max-errors")
  let result = html_grammar.parse_cst(source_id, input) catch {
    _ => return fail("MAX_ERRORS parse raised")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
  inspect(tree.text_len() == input.length(), content="true")
}

///|
test "malformed parse does not leak stack into the next parse" {
  let first_source_id = @core.SourceId("html-parser-stack-leak-malformed")
  let first = html_grammar.parse_cst(first_source_id, "<div><span></div>") catch {
    _ => return fail("malformed parse raised")
  }
  let (_, first_diags) = first
  inspect(first_diags.length() >= 1, content="true")
  let second_source_id = @core.SourceId("html-parser-stack-leak-valid")
  let second = html_grammar.parse_cst(second_source_id, "<div>ok</div>") catch {
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
  let first_source_id = @core.SourceId("html-parser-depth-poison-malformed")
  let first = html_grammar.parse_cst(first_source_id, deep.to_string()) catch {
    _ => return fail("MAX_DEPTH parse raised")
  }
  let (_, first_diags) = first
  inspect(first_diags.length() >= 1, content="true")
  let second_source_id = @core.SourceId("html-parser-depth-poison-valid")
  let second = html_grammar.parse_cst(second_source_id, "<div>ok</div>") catch {
    _ => return fail("post-depth parse raised")
  }
  let (_, second_diags) = second
  inspect(second_diags.length(), content="0")
}
