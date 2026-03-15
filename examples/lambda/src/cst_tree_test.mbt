// Tests for Phase 2 CST implementation

// ============================================================================
// Helper: parse a source string and return the CstNode
// ============================================================================

///|
fn test_parse_cst(source : String) -> @seam.CstNode {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  cst
}

// ============================================================================
// 1. Basic parsing to CST
// ============================================================================

///|
test "cst: simple integer" {
  let cst = test_parse_cst("42")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  inspect(cst.children.length() > 0, content="true")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IntLiteral")
}

///|
test "cst: simple variable" {
  let cst = test_parse_cst("x")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="VarRef")
}

///|
test "cst: lambda expression" {
  let cst = test_parse_cst("λx.x")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LambdaExpr")
}

///|
test "cst: application" {
  let cst = test_parse_cst("f x")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="AppExpr")
}

///|
test "cst: binary operation" {
  let cst = test_parse_cst("1 + 2")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="BinaryExpr")
}

///|
test "cst: if-then-else" {
  let cst = test_parse_cst("if x then 1 else 2")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IfExpr")
}

// ============================================================================
// 2. ParenExpr node presence - distinguishing x from (x)
// ============================================================================

///|
test "cst: ParenExpr is present" {
  let cst = test_parse_cst("(x)")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  // (x) should have ParenExpr as the outer node
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="ParenExpr")
}

///|
test "cst: x vs (x) have different structure" {
  let cst_bare = test_parse_cst("x")
  let cst_paren = test_parse_cst("(x)")
  let bare_child = match cst_bare.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  let paren_child = match cst_paren.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  // bare x is VarRef, (x) is ParenExpr
  inspect(@syntax.SyntaxKind::from_raw(bare_child.kind), content="VarRef")
  inspect(@syntax.SyntaxKind::from_raw(paren_child.kind), content="ParenExpr")
  // They must be different
  inspect(bare_child.kind != paren_child.kind, content="true")
}

///|
test "cst: nested parentheses ((x))" {
  let cst = test_parse_cst("((x))")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="ParenExpr")
  // The inner expression should also be a ParenExpr
  let mut inner_paren_found = false
  for elem in child.children {
    match elem {
      @seam.CstElement::Node(n) =>
        match @syntax.SyntaxKind::from_raw(n.kind) {
          @syntax.ParenExpr => inner_paren_found = true
          _ => ()
        }
      @seam.CstElement::Token(_) => continue
    }
  }
  inspect(inner_paren_found, content="true")
}

///|
test "cst: deeply nested parentheses (((1)))" {
  let cst = test_parse_cst("(((1)))")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  // Count the nesting depth of ParenExpr
  fn count_paren_depth(node : @seam.CstNode) -> Int {
    match @syntax.SyntaxKind::from_raw(node.kind) {
      @syntax.ParenExpr => {
        for elem in node.children {
          match elem {
            @seam.CstElement::Node(n) => return 1 + count_paren_depth(n)
            @seam.CstElement::Token(_) => continue
          }
        }
        1
      }
      _ => 0
    }
  }

  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(count_paren_depth(child), content="3")
}

// ============================================================================
// 3. Position correctness via SyntaxNode
// ============================================================================

///|
test "cst: SyntaxNode positions for simple expression" {
  let cst = test_parse_cst("x + y")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.start(), content="0")
  inspect(syntax.end(), content="5")
}

///|
test "cst: SyntaxNode positions for integer" {
  let cst = test_parse_cst("42")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.start(), content="0")
  inspect(syntax.end(), content="2")
}

///|
test "cst: SyntaxNode positions for lambda" {
  let cst = test_parse_cst("λx.x")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  inspect(syntax.start(), content="0")
  inspect(syntax.end(), content="4")
}

///|
test "cst: SyntaxNode children positions" {
  let cst = test_parse_cst("1 + 2")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let children = syntax.children()
  inspect(children.length(), content="1")
  let binary_expr = children[0]
  inspect(
    @syntax.SyntaxKind::from_raw(binary_expr.kind()),
    content="BinaryExpr",
  )
  inspect(binary_expr.start(), content="0")
  inspect(binary_expr.end(), content="5")
}

///|
test "cst: SyntaxNode child positions in application" {
  let cst = test_parse_cst("f x")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let children = syntax.children()
  inspect(children.length(), content="1")
  let app_expr = children[0]
  inspect(@syntax.SyntaxKind::from_raw(app_expr.kind()), content="AppExpr")
  let app_children = app_expr.children()
  inspect(app_children.length(), content="2")
  inspect(app_children[0].start(), content="0")
  inspect(app_children[0].end(), content="1")
  inspect(app_children[1].start(), content="1")
  inspect(app_children[1].end(), content="3")
}

// ============================================================================
// 4. Parse produces expected Terms
// ============================================================================

///|
test "cst: parse - simple integer" {
  let term = parse("42") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="42")
}

///|
test "cst: parse - variable" {
  let term = parse("x") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="x")
}

///|
test "cst: parse - lambda" {
  let term = parse("λx.x") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="(λx. x)")
}

///|
test "cst: parse - lambda with body" {
  let term = parse("λx.x + 1") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="(λx. (x + 1))")
}

///|
test "cst: parse - application" {
  let term = parse("f x") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="(f x)")
}

///|
test "cst: parse - nested application" {
  let term = parse("f x y") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="((f x) y)")
}

///|
test "cst: parse - binary operation" {
  let term = parse("1 + 2") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="(1 + 2)")
}

///|
test "cst: parse - chained binary (same op)" {
  let term = parse("1 + 2 + 3") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="((1 + 2) + 3)")
}

///|
test "cst: parse - if-then-else" {
  let term = parse("if x then 1 else 2") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="if x then 1 else 2")
}

///|
test "cst: parse - parenthesized expression" {
  let term = parse("(x)") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="x")
}

///|
test "cst: parse - complex expression" {
  let term = parse("λf.λx.f (f x)") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(term), content="(λf. (λx. (f (f x))))")
}

// ============================================================================
// 5. Structural sharing potential - identical tokens have same text
// ============================================================================

///|
test "cst: identical integer tokens have same text" {
  let cst = test_parse_cst("1 + 1")
  fn collect_int_tokens(node : @seam.CstNode) -> Array[String] {
    let tokens : Array[String] = []
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IntToken.to_raw() {
            tokens.push(t.text)
          }
        @seam.CstElement::Node(n) => tokens.append(collect_int_tokens(n))
      }
    }
    tokens
  }

  let int_tokens = collect_int_tokens(cst)
  inspect(int_tokens.length(), content="2")
  // Both tokens should have the same text "1"
  inspect(int_tokens[0] == int_tokens[1], content="true")
  inspect(int_tokens[0], content="1")
}

///|
test "cst: identical identifier tokens have same text" {
  let cst = test_parse_cst("x + x")
  fn collect_ident_tokens(node : @seam.CstNode) -> Array[String] {
    let tokens : Array[String] = []
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IdentToken.to_raw() {
            tokens.push(t.text)
          }
        @seam.CstElement::Node(n) => tokens.append(collect_ident_tokens(n))
      }
    }
    tokens
  }

  let ident_tokens = collect_ident_tokens(cst)
  inspect(ident_tokens.length(), content="2")
  // Both tokens should have the same text "x"
  inspect(ident_tokens[0] == ident_tokens[1], content="true")
  inspect(ident_tokens[0], content="x")
}

///|
test "cst: token text is preserved correctly" {
  let cst = test_parse_cst("abc + 123")
  fn find_first_ident(node : @seam.CstNode) -> String? {
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IdentToken.to_raw() {
            return Some(t.text)
          } else {
            continue
          }
        @seam.CstElement::Node(n) => {
          let result = find_first_ident(n)
          match result {
            Some(s) => return Some(s)
            None => continue
          }
        }
      }
    }
    None
  }

  fn find_first_int(node : @seam.CstNode) -> String? {
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IntToken.to_raw() {
            return Some(t.text)
          } else {
            continue
          }
        @seam.CstElement::Node(n) => {
          let result = find_first_int(n)
          match result {
            Some(s) => return Some(s)
            None => continue
          }
        }
      }
    }
    None
  }

  inspect(find_first_ident(cst), content="Some(\"abc\")")
  inspect(find_first_int(cst), content="Some(\"123\")")
}

// ============================================================================
// Additional test cases
// ============================================================================

///|
test "cst: lambda with application body" {
  let cst = test_parse_cst("λf.f x")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LambdaExpr")
}

///|
test "cst: nested if-then-else" {
  let cst = test_parse_cst("if x then if y then 1 else 2 else 3")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IfExpr")
}

///|
test "cst: parenthesized lambda" {
  let cst = test_parse_cst("(λx.x)")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="ParenExpr")
}

///|
test "cst: application with parenthesized argument" {
  let cst = test_parse_cst("f (x)")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="AppExpr")
}

///|
test "cst: binary with parenthesized operands" {
  let cst = test_parse_cst("(1) + (2)")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="BinaryExpr")
}

///|
test "cst: text_len is computed correctly" {
  let cst = test_parse_cst("abc")
  inspect(cst.text_len, content="3")
  let cst2 = test_parse_cst("1 + 2")
  inspect(cst2.text_len, content="5")
}

///|
test "cst: CstElement kind accessor" {
  let cst = test_parse_cst("42")
  let elem = cst.children[0]
  inspect(@syntax.SyntaxKind::from_raw(elem.kind()), content="IntLiteral")
}

///|
test "cst: CstElement text_len accessor" {
  let cst = test_parse_cst("42")
  let elem = cst.children[0]
  inspect(elem.text_len(), content="2")
}

///|
test "cst: position comparison" {
  let source = "x + y"
  let cst = test_parse_cst(source)
  let root = @seam.SyntaxNode::from_cst(cst)
  let node = root.nth_child(0).unwrap()
  inspect(node.start(), content="0")
  inspect(node.end(), content="5")
}

///|
test "cst: structural sharing - identical CstNodes are equal" {
  let cst1 = test_parse_cst("x")
  let cst2 = test_parse_cst("x")
  let node1 = match cst1.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node")
  }
  let node2 = match cst2.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node")
  }
  inspect(node1 == node2, content="true")
}

// ============================================================================
// 6. Error recovery in CST
// ============================================================================

///|
test "cst: has_errors on valid input" {
  let cst = test_parse_cst("42")
  inspect(
    cst.has_errors(@syntax.ErrorNode.to_raw(), @syntax.ErrorToken.to_raw()),
    content="false",
  )
}

///|
test "cst: has_errors on valid lambda" {
  let cst = test_parse_cst("λx.x")
  inspect(
    cst.has_errors(@syntax.ErrorNode.to_raw(), @syntax.ErrorToken.to_raw()),
    content="false",
  )
}

///|
test "cst: error recovery - missing param produces ErrorToken" {
  let (cst, diagnostics) = parse_cst("λ.x") catch { _ => abort("lex error") }
  inspect(
    cst.has_errors(@syntax.ErrorNode.to_raw(), @syntax.ErrorToken.to_raw()),
    content="true",
  )
  inspect(diagnostics.length(), content="1")
  // Should still have SourceFile > LambdaExpr structure
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LambdaExpr")
}

///|
test "cst: error recovery - extra tokens wrapped in ErrorNode" {
  let (cst, diagnostics) = parse_cst("42 )") catch { _ => abort("lex error") }
  inspect(diagnostics.length() > 0, content="true")
  // SourceFile should have IntLiteral + ErrorNode
  let mut found_int = false
  let mut found_error = false
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        match @syntax.SyntaxKind::from_raw(n.kind) {
          @syntax.IntLiteral => found_int = true
          @syntax.ErrorNode => found_error = true
          _ => ()
        }
      @seam.CstElement::Token(_) => ()
    }
  }
  inspect(found_int, content="true")
  inspect(found_error, content="true")
}

///|
test "cst: error recovery - missing else in if" {
  let (cst, diagnostics) = parse_cst("if x then y") catch {
    _ => abort("lex error")
  }
  inspect(diagnostics.length() > 0, content="true")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IfExpr")
}

///|
test "cst: error recovery - text_len preserved" {
  let (cst, _) = parse_cst("λ.x") catch { _ => abort("lex error") }
  // text_len should cover the entire source
  inspect(cst.text_len, content="3")
}

///|
test "cst: error recovery - multiple errors" {
  let (cst, diagnostics) = parse_cst("λ.x + )") catch {
    _ => abort("lex error")
  }
  // Should have at least 2 errors: missing param, extra ")"
  inspect(diagnostics.length() >= 2, content="true")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
}

///|
test "cst: error recovery preserves valid input" {
  // Valid inputs should produce identical trees via recover vs strict
  let inputs = ["42", "x", "λx.x", "f x", "1 + 2", "if x then 1 else 2", "(x)"]
  for input in inputs {
    let (recovered, diagnostics) = parse_cst(input) catch {
      _ => abort("lex error")
    }
    inspect(diagnostics.length(), content="0")
    // Just verify the tree is valid
    inspect(@syntax.SyntaxKind::from_raw(recovered.kind), content="SourceFile")
  }
}

///|
/// Collect the text of all leaf tokens in a CST (depth-first).
fn collect_leaf_texts(node : @seam.CstNode) -> String {
  let parts : Array[String] = []
  fn walk(n : @seam.CstNode) -> Unit {
    for elem in n.children {
      match elem {
        @seam.CstElement::Token(t) => parts.push(t.text)
        @seam.CstElement::Node(child) => walk(child)
      }
    }
  }

  walk(node)
  parts.join("")
}

///|
test "parse preserves all whitespace in CST" {
  let source = "  x + 1  "
  let (tree, _) = parse_cst(source) catch { _ => abort("lex error") }
  let texts = collect_leaf_texts(tree)
  inspect(texts, content="  x + 1  ")
}

///|
test "parse preserves leading and trailing whitespace" {
  let source = "  42  "
  let (tree, _) = parse_cst(source) catch { _ => abort("lex error") }
  let texts = collect_leaf_texts(tree)
  inspect(texts, content="  42  ")
}

///|
test "parse preserves internal whitespace in application" {
  let source = "f  x"
  let (tree, _) = parse_cst(source) catch { _ => abort("lex error") }
  let texts = collect_leaf_texts(tree)
  inspect(texts, content="f  x")
}

///|
test "cst: let definition" {
  let (cst, _) = parse_cst("let x = 1\nx") catch { _ => abort("lex error") }
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LetDef")
}

///|
test "cst: nested let defs" {
  let (cst, _) = parse_cst("let x = 1\nlet y = 2\nx") catch {
    _ => abort("lex error")
  }
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LetDef")
}

///|
test "source file: two LetDef children" {
  let (cst, _) = parse_cst("let id = 1\nlet const = 2") catch {
    _ => abort("lex error")
  }
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let mut node_count = 0
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) => {
        node_count = node_count + 1
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      }
      _ => ()
    }
  }
  inspect(node_count, content="2")
  inspect(node_kinds[0], content="LetDef")
  inspect(node_kinds[1], content="LetDef")
}

///|
test "source file: LetDef has correct token structure" {
  let (cst, _) = parse_cst("let id = 1") catch { _ => abort("lex error") }
  let letdef = for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) => break n
      _ => continue
    }
  } nobreak {
    abort("No LetDef node found")
  }
  inspect(@syntax.SyntaxKind::from_raw(letdef.kind), content="LetDef")
  // Non-whitespace children: LetKeyword, IdentToken, EqToken, IntLiteral node
  let non_ws : Array[String] = []
  for elem in letdef.children {
    match elem {
      @seam.CstElement::Token(t) =>
        if @syntax.SyntaxKind::from_raw(t.kind) != @syntax.WhitespaceToken {
          non_ws.push(@syntax.SyntaxKind::from_raw(t.kind).to_string())
        }
      @seam.CstElement::Node(n) =>
        non_ws.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
    }
  }
  inspect(
    non_ws,
    content="[\"LetKeyword\", \"IdentToken\", \"EqToken\", \"IntLiteral\"]",
  )
}

///|
test "source file: single expression (no defs)" {
  let (cst, _) = parse_cst("42") catch { _ => abort("lex error") }
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      _ => ()
    }
  }
  inspect(node_kinds, content="[\"IntLiteral\"]")
}

///|
test "source file: def + final expression" {
  let (cst, _) = parse_cst("let id = 1\nid") catch { _ => abort("lex error") }
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      _ => ()
    }
  }
  inspect(node_kinds, content="[\"LetDef\", \"VarRef\"]")
}

///|
test "source file: leading newlines before def + final expression" {
  let (cst, diagnostics) = parse_cst("\nlet id = 1\nid") catch {
    _ => abort("lex error")
  }
  inspect(diagnostics.length(), content="0")
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      _ => ()
    }
  }
  inspect(node_kinds, content="[\"LetDef\", \"VarRef\"]")
}

///|
test "source file: trailing tokens after final expression produce error" {
  let (cst, diagnostics) = parse_cst("1 in x") catch { _ => abort("lex error") }
  inspect(diagnostics.length() > 0, content="true")
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      _ => ()
    }
  }
  inspect(node_kinds, content="[\"IntLiteral\", \"ErrorNode\"]")
}
