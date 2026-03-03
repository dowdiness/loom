// term_convert.mbt — SyntaxNode → Term conversion (view-based, no AstNode).
//
// Primary API (view-based, no AstNode allocation):
//   syntax_node_to_term  — the intended public entry point
//   view_to_term         — recursive helper
//
// Legacy (AstNode-based): the functions below (convert_syntax_node,
// cst_to_ast_node, etc.) are retained for backward compatibility with
// parse_tree, parse_with_error_recovery and their tests. They will be
// deleted once those callers are migrated to the view-based path.

///|
/// Handle multiple children from SourceFile (main expression + error nodes).
fn convert_source_file_children(
  children : Array[@ast.AstNode],
  off : Int,
  counter : Ref[Int],
) -> @ast.AstNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  if children.length() == 0 {
    return @ast.AstNode::error("Empty SourceFile", off, next_id())
  }
  if children.length() == 1 {
    return children[0]
  }
  // Multiple children: find the first non-error child as main, rest as error children
  let main_nodes : Array[@ast.AstNode] = []
  let error_nodes : Array[@ast.AstNode] = []
  for child in children {
    match child.kind {
      @ast.AstKind::Error(_) => error_nodes.push(child)
      _ => main_nodes.push(child)
    }
  }
  if main_nodes.length() > 0 {
    let m = main_nodes[0]
    // Attach any extra main nodes and error nodes as children
    let extra : Array[@ast.AstNode] = []
    for i = 1; i < main_nodes.length(); i = i + 1 {
      extra.push(main_nodes[i])
    }
    extra.append(error_nodes)
    if extra.length() > 0 {
      let all_children : Array[@ast.AstNode] = m.children.copy()
      all_children.append(extra)
      // Extend end to cover all children so the parent span is a superset
      let mut end = m.end
      for child in extra {
        if child.end > end {
          end = child.end
        }
      }
      @ast.AstNode::new(m.kind, m.start, end, next_id(), all_children)
    } else {
      m
    }
    // All children are errors — wrap them under a single error node
    // so none are discarded
  } else {
    let mut start = children[0].start
    let mut end = children[0].end
    for child in children {
      if child.start < start {
        start = child.start
      }
      if child.end > end {
        end = child.end
      }
    }
    @ast.AstNode::new(
      @ast.AstKind::Error("Syntax error"),
      start,
      end,
      next_id(),
      children,
    )
  }
}

///|
/// Convert a SyntaxNode to an AstNode. Uses SyntaxNode's offset-based position
/// computation instead of manual offset tracking.
fn convert_syntax_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @ast.AstNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  let ws = @syntax.WhitespaceToken.to_raw()
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral => {
      let text = node
        .find_token(@syntax.IntToken.to_raw())
        .map(t => t.text())
        .unwrap_or("")
      let value = @strconv.parse_int(text) catch { _ => 0 }
      let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(ws))
      @ast.AstNode::new(
        @ast.AstKind::Int(value),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.VarRef => {
      let name = node
        .find_token(@syntax.IdentToken.to_raw())
        .map(t => t.text())
        .unwrap_or("")
      let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(ws))
      @ast.AstNode::new(
        @ast.AstKind::Var(name),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.LambdaExpr => {
      let param = node
        .find_token(@syntax.IdentToken.to_raw())
        .map(t => t.text())
        .unwrap_or("")
      let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(ws))
      let syntax_children = node.children()
      for child in syntax_children {
        let body = convert_syntax_node(child, counter)
        return @ast.AstNode::new(
          @ast.AstKind::Lam(param),
          tight_start,
          body.end,
          next_id(),
          [body],
        )
      }
      @ast.AstNode::new(
        @ast.AstKind::Lam(param),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.AppExpr => {
      let children : Array[@ast.AstNode] = []
      let syntax_children = node.children()
      for child in syntax_children {
        children.push(convert_syntax_node(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          result = @ast.AstNode::new(
            @ast.AstKind::App,
            result.start,
            children[i].end,
            next_id(),
            [result, children[i]],
          )
        }
        result
      } else if children.length() == 1 {
        children[0]
      } else {
        @ast.AstNode::error("Empty AppExpr", node.start(), next_id())
      }
    }
    @syntax.BinaryExpr => {
      let ops : Array[@ast.Bop] = []
      for elem in node.all_children() {
        match elem {
          @seam.SyntaxElement::Token(t) =>
            if t.kind() == @syntax.PlusToken.to_raw() {
              ops.push(@ast.Bop::Plus)
            } else if t.kind() == @syntax.MinusToken.to_raw() {
              ops.push(@ast.Bop::Minus)
            }
          _ => ()
        }
      }
      let children : Array[@ast.AstNode] = []
      let syntax_children = node.children()
      for child in syntax_children {
        children.push(convert_syntax_node(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() {
            ops[i - 1]
          } else {
            @ast.Bop::Plus
          }
          result = @ast.AstNode::new(
            @ast.AstKind::Bop(op),
            result.start,
            children[i].end,
            next_id(),
            [result, children[i]],
          )
        }
        result
      } else if children.length() == 1 {
        children[0]
      } else {
        @ast.AstNode::error("Empty BinaryExpr", node.start(), next_id())
      }
    }
    @syntax.IfExpr => {
      let (tight_start, _) = node.tight_span(trivia_kind=Some(ws))
      let children : Array[@ast.AstNode] = []
      let syntax_children = node.children()
      for child in syntax_children {
        children.push(convert_syntax_node(child, counter))
      }
      let if_end = if children.length() > 0 {
        children[children.length() - 1].end
      } else {
        node.end()
      }
      @ast.AstNode::new(
        @ast.AstKind::If,
        tight_start,
        if_end,
        next_id(),
        children,
      )
    }
    @syntax.LetExpr => {
      let name = node
        .find_token(@syntax.IdentToken.to_raw())
        .map(t => t.text())
        .unwrap_or("")
      let (tight_start, _) = node.tight_span(trivia_kind=Some(ws))
      let children : Array[@ast.AstNode] = []
      let syntax_children = node.children()
      for child in syntax_children {
        children.push(convert_syntax_node(child, counter))
      }
      let let_end = if children.length() > 0 {
        children[children.length() - 1].end
      } else {
        node.end()
      }
      @ast.AstNode::new(
        @ast.AstKind::Let(name),
        tight_start,
        let_end,
        next_id(),
        children,
      )
    }
    @syntax.ParenExpr => {
      let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(ws))
      let syntax_children = node.children()
      for child in syntax_children {
        let inner = convert_syntax_node(child, counter)
        return @ast.AstNode::new(
          inner.kind,
          tight_start,
          tight_end,
          next_id(),
          inner.children,
        )
      }
      @ast.AstNode::error("Empty ParenExpr", node.start(), next_id())
    }
    @syntax.ErrorNode => {
      let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(ws))
      let parts : Array[String] = []
      for t in node.tokens() {
        if t.kind() != ws && t.text() != "" {
          parts.push(t.text())
        }
      }
      let text = parts.join("")
      let msg = if text != "" {
        "Syntax error: " + text
      } else {
        "Syntax error"
      }
      @ast.AstNode::new(
        @ast.AstKind::Error(msg),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.SourceFile => {
      let syntax_children = node.children()
      let children : Array[@ast.AstNode] = []
      for child in syntax_children {
        children.push(convert_syntax_node(child, counter))
      }
      convert_source_file_children(children, node.start(), counter)
    }
    _ =>
      @ast.AstNode::error(
        "Unexpected node kind: " + node.kind().to_string(),
        node.start(),
        next_id(),
      )
  }
}

///|
/// Convert a SyntaxNode (position-aware CST facade) to an AstNode.
pub fn syntax_node_to_ast_node(
  node : @seam.SyntaxNode,
  node_id_counter : Ref[Int],
) -> @ast.AstNode {
  convert_syntax_node(node, node_id_counter)
}

///|
/// Convert a CstNode to an AstNode. Preserved for backward compatibility.
/// Internally creates a SyntaxNode and delegates to convert_syntax_node.
pub fn cst_to_ast_node(
  cst : @seam.CstNode,
  offset : Int,
  node_id_counter : Ref[Int],
) -> @ast.AstNode {
  let syntax = @seam.SyntaxNode::new(cst, None, offset)
  convert_syntax_node(syntax, node_id_counter)
}

///|
pub fn cst_to_term(cst : @seam.CstNode) -> @ast.Term {
  let node = cst_to_ast_node(cst, 0, Ref::new(0))
  @ast.node_to_term(node)
}

///|
pub fn parse_cst_to_ast_node(source : String) -> @ast.AstNode raise {
  let cst = parse_cst(source)
  cst_to_ast_node(cst, 0, Ref::new(0))
}

///|
/// Convert a SyntaxNode to a Term using typed view types.
/// Replaces the old AstNode-based path: SyntaxNode → AstNode → Term.
/// SourceFile wraps the actual expression in a single child; this function
/// unwraps it automatically.
///
/// **Well-formed parses only.** For error-recovered trees, only the first
/// node child of SourceFile is used; additional error-recovery siblings are
/// silently dropped. `Term` has no Error variant, so partially-recovered
/// expressions cannot be represented in the term tree. Parse errors and
/// recovered error nodes are surfaced via `ReactiveParser::diagnostics()`.
pub fn syntax_node_to_term(root : @seam.SyntaxNode) -> @ast.Term {
  let node = match @syntax.SyntaxKind::from_raw(root.kind()) {
    @syntax.SourceFile =>
      match root.nth_child(0) {
        Some(child) => child
        None => return @ast.Term::Var("<empty>")
      }
    _ => root
  }
  view_to_term(node)
}

///|
fn view_to_term(node : @seam.SyntaxNode) -> @ast.Term {
  match @syntax.SyntaxKind::from_raw(node.kind()) {
    @syntax.IntLiteral =>
      match IntLiteralView::cast(node) {
        Some(v) => @ast.Term::Int(v.value().unwrap_or(0))
        None => @ast.Term::Var("<error>")
      }
    @syntax.VarRef =>
      match VarRefView::cast(node) {
        Some(v) => @ast.Term::Var(v.name())
        None => @ast.Term::Var("<error>")
      }
    @syntax.LambdaExpr =>
      match LambdaExprView::cast(node) {
        Some(v) => {
          let body = match v.body() {
            Some(b) => view_to_term(b)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Lam(v.param(), body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.AppExpr =>
      match AppExprView::cast(node) {
        Some(_) => {
          let children = node.children()
          if children.length() >= 2 {
            let mut result = view_to_term(children[0])
            for i = 1; i < children.length(); i = i + 1 {
              result = @ast.Term::App(result, view_to_term(children[i]))
            }
            result
          } else if children.length() == 1 {
            view_to_term(children[0])
          } else {
            @ast.Term::Var("<error>")
          }
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.BinaryExpr => {
      // BinaryExpr CST is flat: [term, term, ..., term] with operators as tokens.
      // Collect operator tokens in order, then fold-left the node children.
      let ops : Array[@ast.Bop] = []
      for elem in node.all_children() {
        match elem {
          @seam.SyntaxElement::Token(t) =>
            if t.kind() == @syntax.PlusToken.to_raw() {
              ops.push(@ast.Bop::Plus)
            } else if t.kind() == @syntax.MinusToken.to_raw() {
              ops.push(@ast.Bop::Minus)
            }
          _ => ()
        }
      }
      let children = node.children()
      if children.length() >= 2 {
        let mut result = view_to_term(children[0])
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() {
            ops[i - 1]
          } else {
            @ast.Bop::Plus
          }
          result = @ast.Term::Bop(op, result, view_to_term(children[i]))
        }
        result
      } else if children.length() == 1 {
        view_to_term(children[0])
      } else {
        @ast.Term::Var("<error>")
      }
    }
    @syntax.IfExpr =>
      match IfExprView::cast(node) {
        Some(v) => {
          let cond = match v.condition() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let then_ = match v.then_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let else_ = match v.else_branch() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::If(cond, then_, else_)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.LetExpr =>
      match LetExprView::cast(node) {
        Some(v) => {
          let init = match v.init() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          let body = match v.body() {
            Some(n) => view_to_term(n)
            None => @ast.Term::Var("<error>")
          }
          @ast.Term::Let(v.name(), init, body)
        }
        None => @ast.Term::Var("<error>")
      }
    @syntax.ParenExpr =>
      match ParenExprView::cast(node) {
        Some(v) =>
          match v.inner() {
            Some(inner) => view_to_term(inner)
            None => @ast.Term::Var("<error>")
          }
        None => @ast.Term::Var("<error>")
      }
    _ => @ast.Term::Var("<error: " + node.kind().to_string() + ">")
  }
}
