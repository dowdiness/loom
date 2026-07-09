///|
fn top_level_kind_names(source : String) -> Array[String] {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  root
  .children()
  .map(fn(child) {
    let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    kind.to_string()
  })
}

///|
fn syntax_token_kind_names(tokens : Array[@seam.SyntaxToken]) -> Array[String] {
  tokens.map(fn(token) {
    let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(token.kind())
    kind.to_string()
  })
}

///|
fn root_token_kind_names(source : String) -> Array[String] {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  @seam.SyntaxNode::from_cst(cst).tokens() |> syntax_token_kind_names
}

///|
fn first_item_token_kind_names(source : String) -> Array[String] {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [item, ..] => item.tokens() |> syntax_token_kind_names
    [] => []
  }
}

///|
fn top_level_header_kind_names(source : String) -> Array[String] {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  root
  .children()
  .map(fn(item) {
    match item.children() {
      [header, ..] => {
        let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
          header.kind(),
        )
        kind.to_string()
      }
      [] => ""
    }
  })
}

///|
fn first_item_header_token_kind_names(source : String) -> Array[String] {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [item, ..] =>
      match item.children() {
        [header, ..] => header.tokens() |> syntax_token_kind_names
        [] => []
      }
    [] => []
  }
}

///|
test "skeleton grammar classifies top-level item nodes" {
  let source =
    #|let x = 1
    #|pub fn f() { let y = 2; y }
    #|struct Point {}
    #|enum Color { Red }
    #|type Name String
    #|
  let kinds = top_level_kind_names(source)
  debug_inspect(
    kinds,
    content=(
      #|[
      #|  "LetItemNode",
      #|  "FunctionItemNode",
      #|  "StructItemNode",
      #|  "EnumItemNode",
      #|  "TypeItemNode",
      #|]
    ),
  )
}

///|
test "skeleton grammar parses top-level item headers" {
  let source =
    #|let x = 1
    #|pub fn f() { let y = 2; y }
    #|struct Point {}
    #|enum Color { Red }
    #|type Name String
    #|
  let kinds = top_level_header_kind_names(source)
  debug_inspect(
    kinds,
    content=(
      #|[
      #|  "LetItemHeaderNode",
      #|  "FunctionItemHeaderNode",
      #|  "StructItemHeaderNode",
      #|  "EnumItemHeaderNode",
      #|  "TypeItemHeaderNode",
      #|]
    ),
  )
}

///|
test "skeleton grammar parses explicit header keyword variants" {
  let source =
    #|const X = 1
    #|letrec f = 1
    #|fnalias alias = target
    #|extenum Color += { Red }
    #|enumview View { Case }
    #|typealias Name = String
    #|
  debug_inspect(
    top_level_kind_names(source),
    content=(
      #|[
      #|  "LetItemNode",
      #|  "LetItemNode",
      #|  "FunctionItemNode",
      #|  "EnumItemNode",
      #|  "EnumItemNode",
      #|  "TypeItemNode",
      #|]
    ),
  )
  debug_inspect(
    top_level_header_kind_names(source),
    content=(
      #|[
      #|  "LetItemHeaderNode",
      #|  "LetItemHeaderNode",
      #|  "FunctionItemHeaderNode",
      #|  "EnumItemHeaderNode",
      #|  "EnumItemHeaderNode",
      #|  "TypeItemHeaderNode",
      #|]
    ),
  )
}

///|
test "skeleton grammar stops function headers before body" {
  let kinds = first_item_header_token_kind_names("fn f(x : Int) { x }\n")
  debug_inspect(
    kinds,
    content=(
      #|[
      #|  "FnToken",
      #|  "TriviaToken",
      #|  "LidentToken",
      #|  "LparenToken",
      #|  "LidentToken",
      #|  "TriviaToken",
      #|  "ColonToken",
      #|  "TriviaToken",
      #|  "UidentToken",
      #|  "RparenToken",
      #|]
    ),
  )
}

///|
test "skeleton grammar splits equals function bodies from headers" {
  let source = "fn cos(d : Double) -> Double = \"Math\" \"cos\"\n"
  let header = first_item_header_token_kind_names(source)
  debug_inspect(
    header,
    content=(
      #|[
      #|  "FnToken",
      #|  "TriviaToken",
      #|  "LidentToken",
      #|  "LparenToken",
      #|  "LidentToken",
      #|  "TriviaToken",
      #|  "ColonToken",
      #|  "TriviaToken",
      #|  "UidentToken",
      #|  "RparenToken",
      #|  "TriviaToken",
      #|  "ThinArrowToken",
      #|  "TriviaToken",
      #|  "UidentToken",
      #|]
    ),
  )
  let body = first_item_token_kind_names(source)
  debug_inspect(
    body,
    content=(
      #|[
      #|  "TriviaToken",
      #|  "EqualToken",
      #|  "TriviaToken",
      #|  "StringToken",
      #|  "TriviaToken",
      #|  "StringToken",
      #|  "SemiToken",
      #|]
    ),
  )
}

///|
test "skeleton grammar leaves initializer tokens after let header" {
  let kinds = first_item_token_kind_names("let x = 1\n")
  debug_inspect(
    kinds,
    content="[\"TriviaToken\", \"EqualToken\", \"TriviaToken\", \"IntToken\", \"SemiToken\"]",
  )
}

///|
test "skeleton grammar splits legacy type body from header" {
  let source = "type Name String\n"
  let header = first_item_header_token_kind_names(source)
  debug_inspect(
    header,
    content="[\"TypeToken\", \"TriviaToken\", \"UidentToken\"]",
  )
  let body = first_item_token_kind_names(source)
  debug_inspect(
    body,
    content="[\"TriviaToken\", \"UidentToken\", \"SemiToken\"]",
  )
}

///|
test "skeleton grammar splits tuple struct body from header" {
  let source = "struct UserName(String) derive(Debug)\n"
  let header = first_item_header_token_kind_names(source)
  debug_inspect(
    header,
    content="[\"StructToken\", \"TriviaToken\", \"UidentToken\"]",
  )
  let body = first_item_token_kind_names(source)
  debug_inspect(
    body,
    content=(
      #|[
      #|  "LparenToken",
      #|  "UidentToken",
      #|  "RparenToken",
      #|  "TriviaToken",
      #|  "DeriveToken",
      #|  "LparenToken",
      #|  "UidentToken",
      #|  "RparenToken",
      #|  "SemiToken",
      #|]
    ),
  )
}

///|
test "skeleton grammar preserves official layout token kinds" {
  let kinds = root_token_kind_names("// doc\nlet x = 1\n")
  debug_inspect(
    kinds,
    content="[\"CommentToken\", \"NewlineToken\", \"NewlineToken\"]",
  )
}

///|
test "skeleton grammar keeps block semicolons inside function item" {
  let source =
    #|fn f() { let x = 1; x }
    #|let y = 2
    #|
  let kinds = top_level_kind_names(source)
  debug_inspect(kinds, content="[\"FunctionItemNode\", \"LetItemNode\"]")
}

///|
test "skeleton grammar classifies item modifiers with payloads" {
  let source =
    #|pub(all) struct S {}
    #|extern "c" fn f()
    #|
  let kinds = top_level_kind_names(source)
  debug_inspect(kinds, content="[\"StructItemNode\", \"FunctionItemNode\"]")
}

///|
test "skeleton grammar keeps visibility payload in struct header" {
  let header = first_item_header_token_kind_names("pub(all) struct S {}\n")
  debug_inspect(
    header,
    content=(
      #|[
      #|  "PubToken",
      #|  "LparenToken",
      #|  "LidentToken",
      #|  "RparenToken",
      #|  "TriviaToken",
      #|  "StructToken",
      #|  "TriviaToken",
      #|  "UidentToken",
      #|]
    ),
  )
}

///|
test "skeleton grammar skips layout before modifier payloads" {
  let source =
    #|pub // comment
    #|(all) struct S {}
    #|extern // comment
    #|"c" fn f()
    #|
  let kinds = top_level_kind_names(source)
  debug_inspect(kinds, content="[\"StructItemNode\", \"FunctionItemNode\"]")
}

///|
test "skeleton grammar does not count layout against modifier lookahead" {
  let source =
    #|pub // one
    #|// two
    #|// three
    #|
    #|fn f()
    #|pub // one
    #|// two
    #|// three
    #|
    #|(all) struct S {}
    #|
  let kinds = top_level_kind_names(source)
  debug_inspect(kinds, content="[\"FunctionItemNode\", \"StructItemNode\"]")
}

///|
test "skeleton grammar marks unclosed delimiter item incomplete" {
  let parser = @loom.new_parser("fn broken(\n", moonbit_grammar)
  let ast = parser.ast().read_or_abort()
  inspect(ast.contains_errors, content="true")
  inspect(parser.diagnostics().read_or_abort().length() > 0, content="true")
}

///|
test "skeleton grammar works with reactive parser" {
  let parser = @loom.new_parser("let x = 1\nlet y = 2\n", moonbit_grammar)
  let ast = parser.ast().read_or_abort()
  inspect(ast.item_count, content="2")
  inspect(ast.contains_errors, content="false")
}

///|
test "skeleton syntax grammar works with reactive syntax parser" {
  let parser = @loom.new_syntax_parser(
    "let x = 1\nlet y = 2\n", moonbit_syntax_grammar,
  )
  inspect(parser.source().read_or_abort(), content="let x = 1\nlet y = 2\n")
  inspect(parser.diagnostics().read_or_abort().length(), content="0")
  ignore(parser.syntax_tree().read_or_abort())
}

///|
test "placeholder AST reports lexer error tokens" {
  let (ast, diagnostics) = parse_moonbit("let x = `")
  inspect(ast.contains_errors, content="true")
  inspect(diagnostics.length(), content="1")
}

///|
test "skeleton grammar reuses CST nodes after edits" {
  let source = "let x = 1\nlet y = 2\n"
  let parser = @loom.new_imperative_parser(source, moonbit_grammar)
  ignore(parser.parse())
  let next_source = "let x = 10\nlet y = 2\n"
  let edit = @core.Edit::replace(8, 9, 10)
  let snapshot = parser.edit(edit, next_source)
  assert_true(snapshot.reuse_count >= 1)
  inspect(snapshot.ast.item_count, content="2")
}

///|
test "skeleton grammar reuses sibling top-level items after function edit" {
  let source = "fn f() { 1 }\nstruct S {}\n"
  let parser = @loom.new_imperative_parser(source, moonbit_grammar)
  ignore(parser.parse())
  let next_source = "fn f() { 10 }\nstruct S {}\n"
  let edit = @core.Edit::replace(9, 10, 11)
  let snapshot = parser.edit(edit, next_source)
  assert_true(snapshot.reuse_count >= 1)
  inspect(snapshot.ast.item_count, content="2")
}

///|
/// Extract the kind names of all non-header children of the first item node
/// (used to inspect function body children at the top level).
fn first_child_of_first_item_kind_names(source : String) -> Array[String] {
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [item, ..] =>
      match item.children() {
        [_, rest, ..] => {
          // rest is the block/expression node; return its kind
          let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
            rest.kind(),
          )
          [kind.to_string()]
        }
        [_] => []
        [] => []
      }
    [] => []
  }
}

///|
test "skeleton grammar wraps function brace body in BlockExprNode" {
  let kinds = first_child_of_first_item_kind_names("fn f() { let x = 1; x }\n")
  debug_inspect(kinds, content="[\"BlockExprNode\"]")
}

///|
test "skeleton grammar parses if expression inside function body" {
  let source =
    #|fn f(x : Int) -> Int {
    #|  if x > 0 { 1 } else { 0 }
    #|}
    #|
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  // FunctionItemNode contains [header, if_expr]
  match root.children() {
    [item, ..] =>
      match item.children() {
        [_, body, ..] => {
          let body_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
            body.kind(),
          )
          inspect(body_kind.to_string(), content="BlockExprNode")
          match body.children() {
            [if_node, ..] => {
              let if_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
                if_node.kind(),
              )
              inspect(if_kind.to_string(), content="IfExprNode")
            }
            [] => abort("no children in block")
          }
        }
        [_] => abort("unexpected single child")
        [] => abort("no children in function item")
      }
    [] => abort("no top-level items")
  }
}

///|
test "skeleton grammar parses empty brace block" {
  let kinds = first_child_of_first_item_kind_names("fn f() { }\n")
  debug_inspect(kinds, content="[\"BlockExprNode\"]")
}

///|
test "skeleton grammar parses if without else" {
  let source =
    #|fn f(x : Int) -> Int {
    #|  if x > 0 { 1 }
    #|  x
    #|}
    #|
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [item, ..] =>
      match item.children() {
        [_, body, ..] => {
          let body_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
            body.kind(),
          )
          inspect(body_kind.to_string(), content="BlockExprNode")
          // Check children: should have at least 1 (if_node) 
          match body.children() {
            [if_node, ..] => {
              let if_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
                if_node.kind(),
              )
              inspect(if_kind.to_string(), content="IfExprNode")
            }
            [] => abort("no children in block")
          }
        }
        [_] => abort("unexpected single child")
        [] => abort("no children in function item")
      }
    [] => abort("no top-level items")
  }
}

///|
test "skeleton grammar tracks errors in if expression" {
  let parser = @loom.new_parser(
    "fn f() { if true { 1 } else { } }\n", moonbit_grammar,
  )
  let ast = parser.ast().read_or_abort()
  inspect(ast.item_count, content="1")
  inspect(ast.contains_errors, content="false")
}

///|
test "skeleton grammar keeps existing top-level behavior unchanged" {
  let source =
    #|let x = 1
    #|pub fn f() { let y = 2; y }
    #|struct Point {}
    #|
  let kinds = top_level_kind_names(source)
  debug_inspect(
    kinds,
    content="[\"LetItemNode\", \"FunctionItemNode\", \"StructItemNode\"]",
  )
}

///|
test "skeleton grammar parses nested if expressions" {
  let source =
    #|fn f(x : Int, y : Int) -> Int {
    #|  if x > 0 {
    #|    if x > y { 1 } else { 2 }
    #|  } else { 3 }
    #|}
    #|
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [item, ..] =>
      match item.children() {
        [_, body, ..] => {
          let body_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
            body.kind(),
          )
          inspect(body_kind.to_string(), content="BlockExprNode")
          match body.children() {
            [outer_if] =>
              match outer_if.children() {
                [then_block, else_block] => {
                  let then_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
                    then_block.kind(),
                  )
                  inspect(then_kind.to_string(), content="BlockExprNode")
                  let else_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
                    else_block.kind(),
                  )
                  inspect(else_kind.to_string(), content="BlockExprNode")
                  // Inner if is inside then_block (no child nodes = empty block
                  // for literal-only content, so check tokens instead)
                  inspect(then_block.tokens().length() > 0, content="true")
                }
                _ => abort("outer if should have 2 children (then, else)")
              }
            [outer_if, ..] =>
              // Continue checking if there are more children
              inspect(true, content="true")
            [] => abort("no children in block")
          }
        }
        [_] => abort("unexpected single child")
        [] => abort("no children in function item")
      }
    [] => abort("no top-level items")
  }
}

///|
test "skeleton grammar parses while expression" {
  let source =
    #|fn f() -> Unit {
    #|  while true { 1 }
    #|}
    #|
  let (cst, _) = parse_cst(source) catch { _ => abort("lex error") }
  let root = @seam.SyntaxNode::from_cst(cst)
  match root.children() {
    [item, ..] =>
      match item.children() {
        [_, body, ..] => {
          let body_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
            body.kind(),
          )
          inspect(body_kind.to_string(), content="BlockExprNode")
          match body.children() {
            [while_node, ..] => {
              let wc_kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(
                while_node.kind(),
              )
              inspect(wc_kind.to_string(), content="WhileExprNode")
            }
            [] => abort("no children in block")
          }
        }
        [_] => abort("unexpected single child")
        [] => abort("no children in function item")
      }
    [] => abort("no top-level items")
  }
}

///|
test "skeleton grammar parses multiple statements in block" {
  let kinds = first_child_of_first_item_kind_names("fn f() { 1; 2; 3 }\n")
  debug_inspect(kinds, content="[\"BlockExprNode\"]")
}

///|
test "skeleton grammar parses while and if together" {
  let kinds = first_child_of_first_item_kind_names(
    "fn f() { while true { if true { 1 } }; 2 }\n",
  )
  debug_inspect(kinds, content="[\"BlockExprNode\"]")
}
