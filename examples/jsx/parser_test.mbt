///|
/// Render a CST as a single-line s-expression for test assertions.
/// Whitespace tokens are omitted; error tokens render as `ERR:"text"`.
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
test "parse simple element" {
  let source_id = @core.SourceId("jsx-parser-simple-element")
  let result = parse_cst(source_id, "<div></div>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" ">" "<" "/" "div" ">"))
    ),
  )
}

///|
test "parse nested elements" {
  let source_id = @core.SourceId("jsx-parser-nested-elements")
  let result = parse_cst(source_id, "<div><span>hi</span></div>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" ">" (ElementNode "<" "span" ">" (TextLeaf "hi") "<" "/" "span" ">") "<" "/" "div" ">"))
    ),
  )
}

///|
test "parse fragment" {
  let source_id = @core.SourceId("jsx-parser-fragment")
  let result = parse_cst(source_id, "<><p>x</p></>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (FragmentNode "<>" (ElementNode "<" "p" ">" (TextLeaf "x") "<" "/" "p" ">") "</>"))
    ),
  )
}

///|
test "parse self-closing tag" {
  let source_id = @core.SourceId("jsx-parser-self-closing-tag")
  let result = parse_cst(source_id, "<br/>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "br" "/>"))
    ),
  )
}

///|
test "parse attribute with string value" {
  let source_id = @core.SourceId("jsx-parser-string-attribute")
  let result = parse_cst(source_id, "<div class=\"foo\"></div>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" (AttrNode "class" "=" ""foo"") ">" "<" "/" "div" ">"))
    ),
  )
}

///|
test "parse attribute with expression value" {
  let source_id = @core.SourceId("jsx-parser-expression-attribute")
  let result = parse_cst(source_id, "<div id={x}/>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" (AttrNode "id" "=" (ExprSpanNode "{" "x" "}")) "/>"))
    ),
  )
}

///|
test "parse text child" {
  let source_id = @core.SourceId("jsx-parser-text-child")
  let result = parse_cst(source_id, "<p>hello</p>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "p" ">" (TextLeaf "hello") "<" "/" "p" ">"))
    ),
  )
}

///|
test "parse expression child" {
  let source_id = @core.SourceId("jsx-parser-expression-child")
  let result = parse_cst(source_id, "<p>{x}</p>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "p" ">" (ExprSpanNode "{" "x" "}") "<" "/" "p" ">"))
    ),
  )
}

///|
test "attribute expression exit resumes tag body" {
  let source_id = @core.SourceId("jsx-parser-attribute-expression-resume")
  let result = parse_cst(source_id, "<div a={f()} b=\"c\"></div>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" (AttrNode "a" "=" (ExprSpanNode "{" "f()" "}")) (AttrNode "b" "=" ""c"") ">" "<" "/" "div" ">"))
    ),
  )
}

///|
test "stray closing brace in children is literal text" {
  let source_id = @core.SourceId("jsx-parser-stray-closing-brace")
  let result = parse_cst(source_id, "<p>}x</p>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(diagnostics.length(), content="0")
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "p" ">" (TextLeaf "}x") "<" "/" "p" ">"))
    ),
  )
}

///|
test "unclosed element keeps already-parsed children" {
  let source_id = @core.SourceId("jsx-parser-unclosed-element-children")
  let result = parse_cst(source_id, "<div><span>text") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unclosed JSX element: <span> | Unclosed JSX element: <div>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" ">" (ElementNode "<" "span" ">" (TextLeaf "text"))))
    ),
  )
}

///|
test "truncated tag mid tag name" {
  let source_id = @core.SourceId("jsx-parser-truncated-tag-name")
  let result = parse_cst(source_id, "<di") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Truncated tag: <di>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "di"))
    ),
  )
}

///|
test "truncated tag after attribute name" {
  let source_id = @core.SourceId("jsx-parser-truncated-attribute-name")
  let result = parse_cst(source_id, "<div cla") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Truncated tag: <div>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" (AttrNode "cla")))
    ),
  )
}

///|
test "truncated quoted attribute value" {
  let source_id = @core.SourceId("jsx-parser-truncated-attribute-string")
  let result = parse_cst(source_id, "<div class=\"foo") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unterminated attribute string literal | Truncated tag: <div>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" (AttrNode "class" "=" ""foo")))
    ),
  )
}

///|
test "truncated expression missing closing brace" {
  let source_id = @core.SourceId("jsx-parser-truncated-expression")
  let result = parse_cst(source_id, "<p>{foo.bar(") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unclosed expression: missing '}' | Unclosed JSX element: <p>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "p" ">" (ExprSpanNode "{" "foo.bar(")))
    ),
  )
}

///|
test "truncated expression inside string emits both diagnostics" {
  let source_id = @core.SourceId("jsx-parser-truncated-expression-string")
  let result = parse_cst(source_id, "<p>{\"x") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unterminated string literal in expression | Unclosed expression: missing '}' | Unclosed JSX element: <p>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "p" ">" (ExprSpanNode "{" ""x")))
    ),
  )
}

///|
test "expression string truncated at trailing backslash" {
  let source_id = @core.SourceId("jsx-parser-expression-trailing-backslash")
  let result = parse_cst(source_id, "<p>{\"x\\") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unterminated string literal in expression | Unclosed expression: missing '}' | Unclosed JSX element: <p>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "p" ">" (ExprSpanNode "{" ""x\")))
    ),
  )
}

///|
test "mismatched close tag unwinds to matching ancestor" {
  let source_id = @core.SourceId("jsx-parser-mismatched-close-source")
  let result = parse_cst(source_id, "<div><span></div>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Mismatched close tag: expected </span>, got </div>
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ElementNode "<" "div" ">" (ElementNode "<" "span" ">" ERR:"") "<" "/" "div" ">"))
    ),
  )
  let items = diagnostics.items()
  guard items.any(diagnostic => {
    diagnostic.labels().any(label => label.style() is @core.LabelStyle::Primary)
  }) else {
    fail("expected malformed JSX diagnostics to include a primary label")
  }
  guard items.all(diagnostic => {
    diagnostic
    .labels()
    .all(label => {
      !(label.style() is @core.LabelStyle::Primary) ||
      label.span().source_id() == source_id
    })
  }) else {
    fail(
      "expected every primary JSX parser label to retain the caller source id",
    )
  }
}

///|
test "stray close tag at root" {
  let source_id = @core.SourceId("jsx-parser-stray-close-tag")
  let result = parse_cst(source_id, "</span>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unexpected close tag
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (ErrorNode ERR:"<" ERR:"/" ERR:"span" ERR:">"))
    ),
  )
}

///|
test "empty input" {
  let source_id = @core.SourceId("jsx-parser-empty-input")
  let result = parse_cst(source_id, "") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Empty JSX input
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode ERR:"")
    ),
  )
}

///|
test "error-limit circuit breaker terminates on pathological input" {
  // Codex post-implementation-review case: 51 stray close tags exceed
  // MAX_ERRORS; the breaker must degrade to error tokens and terminate,
  // never spin. The assertion is completion plus the error volume.
  let source = "</x>".repeat(51) + "<div></div>"
  let source_id = @core.SourceId("jsx-parser-error-limit")
  let result = parse_cst(source_id, source) catch {
    _ => return fail("lex error")
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 50, content="true")
}

///|
test "depth-limit circuit breaker terminates on deep nesting" {
  // Codex post-implementation-review case: nesting beyond MAX_DEPTH must
  // diagnose and keep making progress to EOF, never spin.
  let source = "<a>".repeat(520)
  let source_id = @core.SourceId("jsx-parser-depth-limit")
  let result = parse_cst(source_id, source) catch {
    _ => return fail("lex error")
  }
  let (_, diagnostics) = result
  inspect(
    diagnostics
    .items()
    .iter()
    .any(d => d.message() == "Maximum JSX nesting depth exceeded"),
    content="true",
  )
}

///|
test "unclosed fragment keeps children" {
  let source_id = @core.SourceId("jsx-parser-unclosed-fragment")
  let result = parse_cst(source_id, "<>text") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message()).join(" | "),
    content=(
      #|Unclosed JSX fragment
    ),
  )
  inspect(
    dump(tree),
    content=(
      #|(RootNode (FragmentNode "<>" (TextLeaf "text")))
    ),
  )
}
