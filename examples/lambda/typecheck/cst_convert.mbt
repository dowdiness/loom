// cst_convert.mbt — CST (SyntaxNode) → Type and TypedTerm conversion.
//
// Two public entry points:
//   type_of_node(n)    — converts a type-position subtree to Type
//   convert_from_cst(n) — converts an expression subtree to TypedTerm,
//                         preserving lambda type annotations that the
//                         Term-based convert() cannot (always emits None).

///|
/// True when the subtree rooted at `n` contains any ErrorNode or ErrorToken
/// (the parser's two error-recovery markers). `seam.SyntaxNode::contains_errors`
/// walks both nodes and tokens — important because the parser's
/// `emit_error_placeholder()` produces a zero-width *token*, not a node.
fn subtree_has_errors(n : @seam.SyntaxNode) -> Bool {
  n.contains_errors(
    @syntax.SyntaxKind::ErrorNode.to_raw(),
    @syntax.SyntaxKind::ErrorToken.to_raw(),
  )
}

///|
/// Convert a type-position CST subtree into a `Type`.
/// Returns `TError` for unrecognized kinds or any subtree containing an
/// ErrorNode or ErrorToken.
pub fn type_of_node(n : @seam.SyntaxNode) -> Type {
  if subtree_has_errors(n) {
    return TError
  }
  match @syntax.SyntaxKind::from_raw(n.kind()) {
    TypeInt => TInt
    TypeUnit => TUnit
    TypeArrow =>
      // TypeArrow has two type children: lhs and rhs.
      match n.children() {
        [lhs, rhs, ..] => TArrow(type_of_node(lhs), type_of_node(rhs))
        _ => TError
      }
    _ => TError
  }
}

///|
/// Convert a CST SyntaxNode into a TypedTerm.
/// Preserves lambda type annotations (which Term-based convert() cannot).
pub fn convert_from_cst(n : @seam.SyntaxNode) -> TypedTerm {
  match @syntax.SyntaxKind::from_raw(n.kind()) {
    @syntax.SyntaxKind::SourceFile => convert_source_file(n)
    @syntax.SyntaxKind::IntLiteral => {
      let value = match
        n.direct_token_of_kind(@syntax.SyntaxKind::IntToken.to_raw()) {
        None => 0
        Some(t) => @string.parse_int(t.text()) catch { _ => 0 }
      }
      TypedTerm::Int(value)
    }
    @syntax.SyntaxKind::VarRef =>
      match n.direct_token_of_kind(@syntax.SyntaxKind::IdentToken.to_raw()) {
        Some(t) => TypedTerm::Var(t.text())
        None => TypedTerm::Error("malformed variable reference: missing name")
      }
    @syntax.SyntaxKind::HoleLiteral => TypedTerm::Hole(0)
    @syntax.SyntaxKind::ErrorNode => TypedTerm::Error("error node")
    @syntax.SyntaxKind::LambdaExpr => convert_lambda(n)
    @syntax.SyntaxKind::AppExpr =>
      match n.nth_child(0) {
        None => TypedTerm::Error("missing function in application")
        Some(func_node) =>
          n
          .children_from(1)
          .fold(init=convert_from_cst(func_node), (result, arg) => {
            TypedTerm::App(result, convert_from_cst(arg))
          })
      }
    @syntax.SyntaxKind::BinaryExpr => {
      let (children, all_tokens) = n.nodes_and_tokens()
      let ops = all_tokens
        .iter()
        .filter_map(t => {
          if t.kind() == @syntax.PlusToken.to_raw() {
            Some(@ast.Bop::Plus)
          } else if t.kind() == @syntax.MinusToken.to_raw() {
            Some(@ast.Bop::Minus)
          } else {
            None
          }
        })
        .to_array()
      match children {
        [first, _, ..] => {
          let expected_ops = children.length() - 1
          if ops.length() < expected_ops {
            TypedTerm::Error("missing binary operator")
          } else if ops.length() > expected_ops {
            TypedTerm::Error("excess binary operator(s)")
          } else {
            children
            .iter()
            .drop(1)
            .zip(ops.iter())
            .fold(init=convert_from_cst(first), (result, pair) => {
              TypedTerm::Bop(pair.1, result, convert_from_cst(pair.0))
            })
          }
        }
        [only] => convert_from_cst(only)
        [] => TypedTerm::Error("empty BinaryExpr")
      }
    }
    @syntax.SyntaxKind::IfExpr => {
      let children = n.children()
      let cond = children
        .get(0)
        .map_or(TypedTerm::Error("missing if condition"), convert_from_cst)
      let then_ = children
        .get(1)
        .map_or(TypedTerm::Error("missing then branch"), convert_from_cst)
      let else_ = children
        .get(2)
        .map_or(TypedTerm::Error("missing else branch"), convert_from_cst)
      TypedTerm::If(cond, then_, else_)
    }
    @syntax.SyntaxKind::ParenExpr =>
      n
      .nth_child(0)
      .map_or(TypedTerm::Error("empty parentheses"), convert_from_cst)
    @syntax.SyntaxKind::BlockExpr => convert_block_expr(n)
    @syntax.SyntaxKind::IfCondition
    | @syntax.SyntaxKind::IfThen
    | @syntax.SyntaxKind::IfElse
    | @syntax.SyntaxKind::LambdaBody =>
      match n.nth_child(0) {
        Some(child) => convert_from_cst(child)
        None => TypedTerm::Error("empty wrapper node")
      }
    _ => TypedTerm::Error("unhandled CST kind")
  }
}

///|
/// LambdaExpr → TypedTerm::Lam, with explicit detection of the parser's
/// error-recovery placeholder for a missing parameter name. Without this
/// check, `\. 1` silently becomes `Lam("", None, Int(1))`.
fn convert_lambda(n : @seam.SyntaxNode) -> TypedTerm {
  let children = n.children()
  let body_node = children
    .iter()
    .find_first(c => {
      let kind = @syntax.SyntaxKind::from_raw(c.kind())
      kind != @syntax.SyntaxKind::ParamList &&
      kind != @syntax.SyntaxKind::TypeAnnot
    })
  let body = match body_node {
    Some(b) => convert_function_body(b)
    None => TypedTerm::Error("missing lambda body")
  }
  match
    children
    .iter()
    .find_first(c => {
      @syntax.SyntaxKind::from_raw(c.kind()) == @syntax.SyntaxKind::ParamList
    }) {
    Some(param_list) => {
      let params = convert_param_list(param_list)
      if params.is_empty() || subtree_has_errors(param_list) {
        TypedTerm::Error("malformed lambda: missing parameter name")
      } else {
        params.rev_fold(init=body, (result, param) => {
          let (name, annot) = param
          TypedTerm::Lam(name, annot, result)
        })
      }
    }
    None => convert_legacy_lambda(n, body)
  }
}

///|
fn convert_legacy_lambda(n : @seam.SyntaxNode, body : TypedTerm) -> TypedTerm {
  let ident = n.direct_token_of_kind(@syntax.SyntaxKind::IdentToken.to_raw())
  let annot_node = n
    .children()
    .iter()
    .find_first(c => {
      @syntax.SyntaxKind::from_raw(c.kind()) == @syntax.SyntaxKind::TypeAnnot
    })
  match ident {
    None => TypedTerm::Error("malformed lambda: missing parameter name")
    Some(t) => {
      let annot = match annot_node {
        None => None
        Some(ann) => {
          let cs = ann.children()
          if cs.length() == 0 {
            Some(TError)
          } else {
            Some(type_of_node(cs[0]))
          }
        }
      }
      TypedTerm::Lam(t.text(), annot, body)
    }
  }
}

///|
/// Collect LetDef entries and trailing expression from a node's children.
/// Shared by SourceFile and BlockExpr conversion.
///
/// If multiple non-LetDef children appear, only the first becomes the body;
/// subsequent ones are inspected for error markers and, if any are present,
/// the body is rewritten as `TypedTerm::Error` so the typechecker surfaces a
/// diagnostic instead of silently dropping the trailing junk.
///
/// Returns `(defs, Some(body))` when a body child was present, or
/// `(defs, None)` when no trailing expression was found. Callers
/// distinguish the two — BlockExpr treats `(empty, None)` as an error
/// ("empty block"), whereas SourceFile accepts an empty source as Unit.
fn collect_typed_defs_and_body(
  node : @seam.SyntaxNode,
) -> (Array[(String, TypedTerm)], TypedTerm?) {
  let children = node.children()
  let defs = children
    .iter()
    .filter_map(child => {
      match @syntax.SyntaxKind::from_raw(child.kind()) {
        @syntax.SyntaxKind::LetDef => Some(convert_let_def_entry(child))
        _ => None
      }
    })
    .to_array()
  let body_index = children.search_by(child => {
    @syntax.SyntaxKind::from_raw(child.kind()) != @syntax.SyntaxKind::LetDef
  })
  let body = body_index.map(index => convert_from_cst(children[index]))
  let trailing_error = body_index.map_or(false, index => {
    children
    .iter()
    .drop(index + 1)
    .any(child => {
      @syntax.SyntaxKind::from_raw(child.kind()) != @syntax.SyntaxKind::LetDef &&
      subtree_has_errors(child)
    })
  })
  let final_body = if trailing_error {
    Some(TypedTerm::Error("trailing junk after expression"))
  } else {
    body
  }
  (defs, final_body)
}

///|
/// Handle a SourceFile: collect LetDef entries and trailing expression,
/// building a Module when defs are present. An empty source file is legal
/// (produces `Unit`).
fn convert_source_file(n : @seam.SyntaxNode) -> TypedTerm {
  let (defs, body_opt) = collect_typed_defs_and_body(n)
  let body = body_opt.unwrap_or(TypedTerm::Unit)
  if defs.is_empty() {
    body
  } else {
    TypedTerm::Module(defs, body)
  }
}

///|
/// Handle a BlockExpr: same collection as SourceFile, but an empty block
/// `{}` is not legal lambda-calculus syntax. The parser reports "empty
/// block" as a parser diagnostic without inserting an error node/token,
/// so the convert step must emit `TypedTerm::Error` to keep the
/// typechecker from silently accepting `{}`.
fn convert_block_expr(n : @seam.SyntaxNode) -> TypedTerm {
  let (defs, body_opt) = collect_typed_defs_and_body(n)
  match body_opt {
    None =>
      if defs.is_empty() {
        TypedTerm::Error("empty block")
      } else {
        // `{ fn x() { 1 } }` — defs only, no trailing expression. Matches
        // the Term-based convert's behaviour of wrapping in Module with
        // a Unit body; typecheck will flag the missing body if needed.
        TypedTerm::Module(defs, TypedTerm::Unit)
      }
    Some(body) =>
      if defs.is_empty() {
        body
      } else {
        TypedTerm::Module(defs, body)
      }
  }
}

///|
/// Convert brace-delimited function/arrow bodies without adding a Module
/// wrapper around a plain expression body.
fn convert_function_body(n : @seam.SyntaxNode) -> TypedTerm {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.SyntaxKind::BlockExpr {
    convert_block_expr(n)
  } else {
    convert_from_cst(n)
  }
}

///|
/// Convert a LetDef CST node to (name, TypedTerm) pair.
/// Handles both value form (`let a = 1`) and param-list form
/// (`fn f(x : Int) { x }`).
///
/// Returns `(name, TypedTerm::Error)` when the parser inserted an error
/// placeholder for the function name or for a parameter (e.g. `fn f(,) { 1 }`
/// or `let () = 1`). The name field preserves the
/// original identifier text (or `""` if the name itself was an error
/// placeholder) so left-to-right definition order is retained in Module.
fn convert_let_def_entry(n : @seam.SyntaxNode) -> (String, TypedTerm) {
  let ident = n.direct_token_of_kind(@syntax.SyntaxKind::IdentToken.to_raw())
  let children = n.children()
  let param_list = children
    .iter()
    .filter(c => {
      @syntax.SyntaxKind::from_raw(c.kind()) == @syntax.SyntaxKind::ParamList
    })
    .last()
  let init = children
    .iter()
    .find_first(c => {
      @syntax.SyntaxKind::from_raw(c.kind()) != @syntax.SyntaxKind::ParamList
    })
  // Missing name: parser inserted an error-placeholder token where the
  // identifier should be (`let = 1`, `let (x) = x`). Surface as Error so
  // typecheck reports a diagnostic instead of binding the empty name.
  match ident {
    None => ("", TypedTerm::Error("malformed let definition: missing name"))
    Some(t) => {
      let name = t.text()
      let init_term = match init {
        Some(e) => convert_function_body(e)
        None => TypedTerm::Error("missing LetDef init")
      }
      let body = match param_list {
        None => init_term
        Some(pl) => {
          let params = convert_param_list(pl)
          if subtree_has_errors(pl) {
            TypedTerm::Error("malformed param list")
          } else {
            params.rev_fold(init=init_term, (body, param) => {
              let (nm, ann) = param
              TypedTerm::Lam(nm, ann, body)
            })
          }
        }
      }
      (name, body)
    }
  }
}

///|
/// Walk a ParamList's all_children(), pairing IdentTokens with optionally-following
/// TypeAnnot nodes. Returns [(name, annot?), ...].
fn convert_param_list(pl : @seam.SyntaxNode) -> Array[(String, Type?)] {
  let result : Array[(String, Type?)] = []
  let mut pending_name : String? = None
  let mut pending_annot : Type? = None
  for elem in pl.all_children() {
    match elem {
      @seam.SyntaxElement::Token(t) => {
        let kind = @syntax.SyntaxKind::from_raw(t.kind())
        if kind == @syntax.SyntaxKind::IdentToken {
          // Flush previous pending param if any
          match pending_name {
            Some(nm) => {
              result.push((nm, pending_annot))
              pending_annot = None
            }
            None => ()
          }
          pending_name = Some(t.text())
        } else if kind == @syntax.SyntaxKind::CommaToken ||
          kind == @syntax.SyntaxKind::RightParenToken {
          // Flush on comma or closing paren
          match pending_name {
            Some(nm) => {
              result.push((nm, pending_annot))
              pending_name = None
              pending_annot = None
            }
            None => ()
          }
        }
      }
      @seam.SyntaxElement::Node(node) => {
        let kind = @syntax.SyntaxKind::from_raw(node.kind())
        if kind == @syntax.SyntaxKind::TypeAnnot {
          let cs = node.children()
          pending_annot = if cs.length() == 0 {
            Some(TError)
          } else {
            Some(type_of_node(cs[0]))
          }
        }
      }
    }
  }
  // Flush any remaining pending param
  match pending_name {
    Some(nm) => result.push((nm, pending_annot))
    None => ()
  }
  result
}
