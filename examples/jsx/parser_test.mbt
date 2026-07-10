///|
/// Render a CST as a single-line s-expression for test assertions.
/// Whitespace tokens are omitted; error tokens render as `ERR:"text"`.
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
test "parse simple element" {
  let result = parse_cst("<div></div>") catch { _ => return fail("lex error") }
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
  let result = parse_cst("<div><span>hi</span></div>") catch {
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
  let result = parse_cst("<><p>x</p></>") catch {
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
  let result = parse_cst("<br/>") catch { _ => return fail("lex error") }
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
  let result = parse_cst("<div class=\"foo\"></div>") catch {
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
  let result = parse_cst("<div id={x}/>") catch {
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
  let result = parse_cst("<p>hello</p>") catch { _ => return fail("lex error") }
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
  let result = parse_cst("<p>{x}</p>") catch { _ => return fail("lex error") }
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
  let result = parse_cst("<div a={f()} b=\"c\"></div>") catch {
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
  let result = parse_cst("<p>}x</p>") catch { _ => return fail("lex error") }
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
  let result = parse_cst("<div><span>text") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<di") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<div cla") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<div class=\"foo") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<p>{foo.bar(") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<p>{\"x") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<p>{\"x\\") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("<div><span></div>") catch {
    _ => return fail("lex error")
  }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
}

///|
test "stray close tag at root" {
  let result = parse_cst("</span>") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst("") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
  let result = parse_cst(source) catch { _ => return fail("lex error") }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 50, content="true")
}

///|
test "depth-limit circuit breaker terminates on deep nesting" {
  // Codex post-implementation-review case: nesting beyond MAX_DEPTH must
  // diagnose and keep making progress to EOF, never spin.
  let source = "<a>".repeat(520)
  let result = parse_cst(source) catch { _ => return fail("lex error") }
  let (_, diagnostics) = result
  inspect(
    diagnostics
    .items()
    .iter()
    .any(d => d.message == "Maximum JSX nesting depth exceeded"),
    content="true",
  )
}

///|
test "unclosed fragment keeps children" {
  let result = parse_cst("<>text") catch { _ => return fail("lex error") }
  let (tree, diagnostics) = result
  inspect(
    diagnostics.items().map(d => d.message).join(" | "),
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
