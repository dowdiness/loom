///|
/// Property-based and hand-written tests for generated *Proj accessor structs
/// in the syntax package.

// ─── Helpers ─────────────────────────────────────────────────────────────────

///|
fn parse_to_syn(input : String) -> @seam.SyntaxNode {
  let (cst, _) = parse_cst(input) catch { _ => abort("lex error") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn find_ifexpr_node(node : @seam.SyntaxNode) -> @seam.SyntaxNode? {
  if @syntax.SyntaxKind::from_raw(node.kind()) == @syntax.IfExpr {
    return Some(node)
  }
  for child in node.children() {
    let result = find_ifexpr_node(child)
    if result is Some(_) {
      return result
    }
  }
  None
}

// ─── Property tests ──────────────────────────────────────────────────────────

///|
/// Filter terms that cannot roundtrip through parse(pretty_print(t)).
fn has_non_roundtrippable(term : @ast.Term) -> Bool {
  fn go(t : @ast.Term, top_level : Bool) -> Bool {
    match t {
      @ast.Term::Unit => true
      @ast.Term::LetDef(_, _) => true
      @ast.Term::Module(_, _) if !top_level => true
      @ast.Term::Module(defs, body) => {
        for def in defs {
          if go(def.1, false) {
            return true
          }
        }
        go(body, false)
      }
      @ast.Term::Int(_) | @ast.Term::Var(_) => false
      @ast.Term::Lam(_, body) => go(body, false)
      @ast.Term::App(f, x) => go(f, false) || go(x, false)
      @ast.Term::Bop(_, l, r) => go(l, false) || go(r, false)
      @ast.Term::If(c, t, e) => go(c, false) || go(t, false) || go(e, false)
      @ast.Term::Error(_) | @ast.Term::Unbound(_) | @ast.Term::Hole(_) => true
    }
  }
  go(term, true)
}

///|
/// Property: every generated IfExpr matches IfExprProj::cast and its accessors
/// agree with the raw projection shape helpers.
test "property: ifexpr_proj accessors match raw projections" {
  let terms : Array[@ast.Term] = @quickcheck.samples(200)
  let mut hit_count = 0
  for term in terms {
    if has_non_roundtrippable(term) {
      continue
    }
    let input = @pretty.pretty_print(term)
    let (cst, _diags) = parse_cst(input) catch { _ => continue }
    let syn = @seam.SyntaxNode::from_cst(cst)
    let ifexpr_child = match find_ifexpr_node(syn) {
      Some(n) => n
      None => continue
    }
    hit_count += 1

    // Invariant 1: Cast success
    let proj = match @syntax.IfExprProj::cast(ifexpr_child) {
      Some(p) => p
      None => abort("IfExprProj::cast returned None for IfExpr node")
    }

    // Invariant 4: AstView identity
    inspect(proj.syntax_node() == ifexpr_child, content="true")

    // Invariant 2: Accessor parity — condition is required
    let cond_raw = ifexpr_child.required_direct_child_of_kind(
      @syntax.IfCondition.to_raw(),
      message="",
    )
    inspect(proj.condition() == cond_raw, content="true")

    // then_branch is required
    let then_raw = ifexpr_child.required_direct_child_of_kind(
      @syntax.IfThen.to_raw(),
      message="",
    )
    inspect(proj.then_branch() == then_raw, content="true")

    // else_branch is optional
    let else_raw = ifexpr_child.optional_direct_child_of_kind(
      @syntax.IfElse.to_raw(),
      message="",
    )
    inspect(proj.else_branch() == else_raw, content="true")

    // Invariant 6: Nested views — condition child castable to IfConditionProj
    match proj.condition() {
      Ok(cond_node) =>
        inspect(
          @syntax.IfConditionProj::cast(cond_node) is Some(_),
          content="true",
        )
      _ => abort("expected Ok from condition()")
    }
  }
  inspect(hit_count >= 1, content="true")
}

///|
/// Property: seed-free stress run over 1000 random Terms.
test "property: ifexpr_proj stress (seed-free)" {
  let terms : Array[@ast.Term] = @quickcheck.samples(1000)
  for term in terms {
    if has_non_roundtrippable(term) {
      continue
    }
    let input = @pretty.pretty_print(term)
    let (cst, _diags) = parse_cst(input) catch { _ => continue }
    let syn = @seam.SyntaxNode::from_cst(cst)
    let ifexpr_child = match find_ifexpr_node(syn) {
      Some(n) => n
      None => continue
    }
    let proj = match @syntax.IfExprProj::cast(ifexpr_child) {
      Some(p) => p
      None => abort("IfExprProj::cast returned None for IfExpr node")
    }
    inspect(proj.syntax_node() == ifexpr_child, content="true")
    inspect(proj.condition() is Ok(_), content="true")
    inspect(proj.then_branch() is Ok(_), content="true")
    inspect(
      proj.else_branch() is Ok(_) || proj.else_branch() is Ok(None),
      content="true",
    )
    match proj.condition() {
      Ok(cond_node) =>
        inspect(
          @syntax.IfConditionProj::cast(cond_node) is Some(_),
          content="true",
        )
      _ => abort("expected Ok from condition()")
    }
  }
}
//|

// ─── Hand-written tests ──────────────────────────────────────────────────────

///|
/// IfExprProj::cast returns Some for a well-formed if-then-else CST node.
test "cast_success" {
  let syn = parse_to_syn("if 1 then 2 else 3")
  let if_child = syn.children()[0]
  inspect(@syntax.IfExprProj::cast(if_child) is Some(_), content="true")
}

///|
/// IfExprProj::cast returns None for a non-IfExpr CST node.
test "cast_failure" {
  let syn = parse_to_syn("42")
  let int_child = syn.children()[0]
  inspect(@syntax.IfExprProj::cast(int_child) is None, content="true")
}

///|
/// When the else branch is absent, optional accessor returns Ok(None).
test "missing_optional" {
  let syn = parse_to_syn("if 1 then 2")
  let if_child = syn.children()[0]
  let proj = match @syntax.IfExprProj::cast(if_child) {
    Some(p) => p
    None => abort("expected IfExpr")
  }
  inspect(proj.condition() is Ok(_), content="true")
  inspect(proj.then_branch() is Ok(_), content="true")
  inspect(proj.else_branch() is Ok(None), content="true")
}

///|
/// Malformed input does not panic when calling adjacent accessors.
test "error_resilience" {
  let syn = parse_to_syn("if ( then )")
  let if_child = syn.children()[0]
  let proj = match @syntax.IfExprProj::cast(if_child) {
    Some(p) => p
    None => abort("expected IfExpr even with errors")
  }
  inspect(
    proj.condition() is Ok(_) || proj.condition() is Err(_),
    content="true",
  )
  inspect(
    proj.then_branch() is Ok(_) || proj.then_branch() is Err(_),
    content="true",
  )
  inspect(
    proj.else_branch() is Ok(_) ||
    proj.else_branch() is Ok(None) ||
    proj.else_branch() is Err(_),
    content="true",
  )
}

///|
/// The condition child of IfExprProj is castable to IfConditionProj.
test "nested_view" {
  let syn = parse_to_syn("if 1 then 2 else 3")
  let if_child = syn.children()[0]
  let proj = match @syntax.IfExprProj::cast(if_child) {
    Some(p) => p
    None => abort("expected IfExpr")
  }
  let cond_node = match proj.condition() {
    Ok(n) => n
    _ => abort("expected Ok from condition()")
  }
  inspect(
    @syntax.SyntaxKind::from_raw(cond_node.kind()) == @syntax.IfCondition,
    content="true",
  )
  inspect(@syntax.IfConditionProj::cast(cond_node) is Some(_), content="true")
}

///|
/// LambdaExprProj::cast succeeds for a lambda node, syntax_node preserves
/// identity, and body() matches the raw LambdaBody child.
test "lambda_proj_parity" {
  let syn = parse_to_syn("(x) => x")
  let lam_child = syn.children()[0]
  inspect(@syntax.LambdaExprProj::cast(lam_child) is Some(_), content="true")
  let proj = @syntax.LambdaExprProj::cast(lam_child).unwrap()
  inspect(proj.syntax_node() == lam_child, content="true")
  let body_raw = lam_child.required_direct_child_of_kind(
    @syntax.LambdaBody.to_raw(),
    message="",
  )
  inspect(proj.body() == body_raw, content="true")
  match proj.body() {
    Ok(body_node) => {
      inspect(
        @syntax.LambdaBodyProj::cast(body_node) is Some(_),
        content="true",
      )
      inspect(
        @syntax.SyntaxKind::from_raw(body_node.kind()) == @syntax.LambdaBody,
        content="true",
      )
    }
    _ => abort("expected Ok from body()")
  }
}
//|

///|
/// BlockExprProj::defs returns an empty array when there are no LetDef children.
test "array_empty" {
  let syn = parse_to_syn("{}")
  let block_child = syn.children()[0]
  let proj = match @syntax.BlockExprProj::cast(block_child) {
    Some(p) => p
    None => abort("expected BlockExpr")
  }
  let defs : Array[@seam.SyntaxNode] = proj.defs()
  inspect(defs.is_empty(), content="true")
}

///|
/// AstView identity: proj.syntax_node() returns the original SyntaxNode.
test "astview_identity" {
  let syn = parse_to_syn("if 1 then 2 else 3")
  let if_child = syn.children()[0]
  let proj = match @syntax.IfExprProj::cast(if_child) {
    Some(p) => p
    None => abort("expected IfExpr")
  }
  inspect(proj.syntax_node() == if_child, content="true")
}

// ─── Reactive pipeline test ──────────────────────────────────────────────────

///|
/// Verify that *Proj accessors work through the reactive SyntaxParser pipeline.
test "reactive_pipeline: syntax_tree() exposes castable nodes" {
  let parser = @loom.new_parser("if 1 then 2 else 3", lambda_grammar)
  let syn = parser.syntax_tree().read_or_abort()
  let if_child = find_ifexpr_node(syn)
  inspect(if_child is Some(_), content="true")
  let proj = match if_child {
    Some(n) => @syntax.IfExprProj::cast(n)
    None => abort("expected IfExpr child")
  }
  inspect(proj is Some(_), content="true")
  let p = proj.unwrap()
  inspect(p.syntax_node() == if_child.unwrap(), content="true")
  inspect(p.condition() is Ok(_), content="true")
  inspect(p.then_branch() is Ok(_), content="true")
  inspect(p.else_branch() is Ok(_), content="true")
  match p.condition() {
    Ok(cond_node) =>
      inspect(
        @syntax.IfConditionProj::cast(cond_node) is Some(_),
        content="true",
      )
    _ => abort("expected Ok from condition()")
  }
}
