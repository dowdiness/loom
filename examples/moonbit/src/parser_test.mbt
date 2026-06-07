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
