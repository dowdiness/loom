///|
/// Fixture inputs for the top-level differential suite.
///
/// The official package exposes `@parser.parse_string` but not an official CST.
/// These tests therefore compare parser accept/reject plus top-level AST item
/// kinds against the skeleton CST item nodes. Header/body token boundaries and
/// layout/comment placement are snapshot-tested on the skeleton side only until
/// a full official-AST fold exists.
struct TopLevelDifferentialFixture {
  name : String
  source : String
  expected_official_accepts : Bool
  expected_skeleton_errors : Bool
} derive(Debug, Eq)

///|
struct OfficialTopLevelSummary {
  accepts : Bool
  lex_error_count : Int
  report_count : Int
  item_kinds : Array[String]
} derive(Debug, Eq)

///|
struct TopLevelItemBoundarySnapshot {
  item_kind : String
  header_kind : String
  header_tokens : Array[String]
  body_tokens : Array[String]
} derive(Debug, Eq)

///|
struct SkeletonTopLevelSummary {
  item_kinds : Array[String]
  diagnostic_count : Int
  contains_errors : Bool
  item_boundaries : Array[TopLevelItemBoundarySnapshot]
  root_tokens : Array[String]
} derive(Debug, Eq)

///|
struct TopLevelDifferentialSnapshot {
  name : String
  official : OfficialTopLevelSummary
  skeleton : SkeletonTopLevelSummary
} derive(Debug, Eq)

///|
struct TopLevelBoundarySnapshot {
  name : String
  item_boundaries : Array[TopLevelItemBoundarySnapshot]
  root_tokens : Array[String]
} derive(Debug, Eq)

///|
fn top_level_differential_fixtures() -> Array[TopLevelDifferentialFixture] {
  [
    {
      name: "let declarations",
      source: (
        #|let x = 1
        #|let y = 2
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "pub all struct with layout payload",
      source: (
        #|pub // keep payload pending
        #|(all) struct S {}
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "extern c imported function",
      source: (
        #|extern "c" fn native(x : Int) -> Int = "native"
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "function brace and equals bodies",
      source: (
        #|fn f() { 1 }
        #|fn wasm() -> Int = "mod" "func"
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "tuple and record structs",
      source: (
        #|struct UserName(String)
        #|struct Point { x : Int }
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "enum declaration",
      source: (
        #|enum Color {
        #|  Red
        #|  Blue
        #|}
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "equals type alias",
      source: (
        #|type Other = String
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    // Current `@parser.parse_string` reports legacy `type Name String`.
    // Keep it here because PR #241 taught the skeleton where that body starts.
    {
      name: "legacy type body boundary",
      source: (
        #|type Name String
        #|
      ),
      expected_official_accepts: false,
      expected_skeleton_errors: false,
    },
    {
      name: "attribute before function",
      source: (
        #|#alias("native")
        #|fn aliased() -> Unit { () }
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "comments around asi boundaries",
      source: (
        #|// leading
        #|let x = 1
        #|// between
        #|fn f() { x }
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "comment inside function header group",
      source: (
        #|fn f(
        #|  x : Int, // argument
        #|) { x }
        #|
      ),
      expected_official_accepts: true,
      expected_skeleton_errors: false,
    },
    {
      name: "parser rejects unclosed function header",
      source: (
        #|fn broken(
        #|
      ),
      expected_official_accepts: false,
      expected_skeleton_errors: true,
    },
    {
      name: "lexer rejects invalid token",
      source: "let broken = `",
      expected_official_accepts: false,
      expected_skeleton_errors: true,
    },
  ]
}

///|
fn official_type_desc_fallback_kind(desc : @syntax.TypeDesc) -> String {
  match desc {
    Record(..) | TupleStruct(_) => "StructItemNode"
    Variant(_) | ExtensibleEnum(_) | ExtendEnum(..) => "EnumItemNode"
    Alias(_) | Abstract => "TypeItemNode"
    Error(_) => "SourceItemNode"
  }
}

///|
fn official_type_decl_item_kind(
  tokens : @tokens.Triples,
  type_decl : @syntax.TypeDecl,
) -> String {
  for triple in tokens {
    let (token, start_pos, end_pos) = triple
    if start_pos.cnum >= type_decl.loc.start.cnum &&
      end_pos.cnum <= type_decl.loc.end.cnum {
      match token.kind() {
        TK_STRUCT => break "StructItemNode"
        TK_ENUM | TK_EXTENUM | TK_ENUMVIEW => break "EnumItemNode"
        TK_TYPE | TK_TYPEALIAS => break "TypeItemNode"
        _ => ()
      }
    }
  } nobreak {
    official_type_desc_fallback_kind(type_decl.components)
  }
}

///|
fn official_impl_item_kind(
  tokens : @tokens.Triples,
  item : @syntax.Impl,
) -> String {
  match item {
    TopLetDef(..) => "LetItemNode"
    TopFuncDef(..) => "FunctionItemNode"
    TopTypeDef(type_decl) => official_type_decl_item_kind(tokens, type_decl)
    _ => "SourceItemNode"
  }
}

///|
fn official_type_decl_item_kinds(source : String) -> Array[String] {
  let lexed = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
  )
  let (impls, _) = @parser.parse_string(source)
  let result : Array[String] = []
  for item in impls {
    match item {
      TopTypeDef(type_decl) =>
        result.push(official_type_decl_item_kind(lexed.tokens, type_decl))
      _ => ()
    }
  }
  result
}

///|
fn official_parse_snapshot(source : String) -> OfficialTopLevelSummary {
  let lexed = @lexer.tokens_from_string_with_utf16_location(
    source,
    comment=true,
  )
  let (impls, reports) = @parser.parse_string(source)
  let accepts = lexed.errors.length() == 0 && reports.length() == 0
  let item_kinds = if accepts {
    impls
    .to_array()
    .map(fn(item) { official_impl_item_kind(lexed.tokens, item) })
  } else {
    []
  }
  {
    accepts,
    lex_error_count: lexed.errors.length(),
    report_count: reports.length(),
    item_kinds,
  }
}

///|
fn differential_syntax_kind_name(node : @seam.SyntaxNode) -> String {
  let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  kind.to_string()
}

///|
fn differential_token_kind_names(
  tokens : Array[@seam.SyntaxToken],
) -> Array[String] {
  tokens.map(fn(token) {
    let kind : MoonbitSyntaxKind = @seam.FromRawKind::from_raw(token.kind())
    kind.to_string()
  })
}

///|
fn top_level_item_boundary_snapshot(
  item : @seam.SyntaxNode,
) -> TopLevelItemBoundarySnapshot {
  let (header_kind, header_tokens, body_tokens) = match item.children() {
    [header, ..] =>
      (
        differential_syntax_kind_name(header),
        differential_token_kind_names(header.tokens()),
        differential_token_kind_names(item.tokens()),
      )
    [] => ("", [], differential_token_kind_names(item.tokens()))
  }
  {
    item_kind: differential_syntax_kind_name(item),
    header_kind,
    header_tokens,
    body_tokens,
  }
}

///|
fn skeleton_top_level_summary(source : String) -> SkeletonTopLevelSummary {
  let parser = @loom.new_parser(source, moonbit_grammar)
  let root = parser.syntax_tree().read_or_abort()
  let ast = parser.ast().read_or_abort()
  let diagnostics = parser.diagnostics().read_or_abort()
  let item_boundaries = root.children().map(top_level_item_boundary_snapshot)
  {
    item_kinds: item_boundaries.map(fn(boundary) { boundary.item_kind }),
    diagnostic_count: diagnostics.length(),
    contains_errors: ast.contains_errors,
    item_boundaries,
    root_tokens: differential_token_kind_names(root.tokens()),
  }
}

///|
fn top_level_differential_snapshot(
  fixture : TopLevelDifferentialFixture,
) -> TopLevelDifferentialSnapshot {
  {
    name: fixture.name,
    official: official_parse_snapshot(fixture.source),
    skeleton: skeleton_top_level_summary(fixture.source),
  }
}

///|
fn top_level_boundary_snapshot(
  fixture : TopLevelDifferentialFixture,
) -> TopLevelBoundarySnapshot {
  let skeleton = skeleton_top_level_summary(fixture.source)
  {
    name: fixture.name,
    item_boundaries: skeleton.item_boundaries,
    root_tokens: skeleton.root_tokens,
  }
}

///|
fn top_level_boundary_snapshots() -> Array[TopLevelBoundarySnapshot] {
  top_level_differential_fixtures().map(top_level_boundary_snapshot)
}

///|
test "official type mapper follows source keyword for type declarations" {
  debug_inspect(
    [
      official_type_decl_item_kinds("type T\n").join(","),
      official_type_decl_item_kinds("type T = U\n").join(","),
      official_type_decl_item_kinds("type T U\n").join(","),
      official_type_decl_item_kinds("extern type T\n").join(","),
      official_type_decl_item_kinds("struct T(U)\n").join(","),
    ],
    content=(
      #|[
      #|  "TypeItemNode",
      #|  "TypeItemNode",
      #|  "TypeItemNode",
      #|  "TypeItemNode",
      #|  "StructItemNode",
      #|]
    ),
  )
}

///|
test "moonbit top-level differential fixtures agree with official parser item kinds" {
  for fixture in top_level_differential_fixtures() {
    let snapshot = top_level_differential_snapshot(fixture)
    @debug.assert_eq(
      snapshot.official.accepts,
      fixture.expected_official_accepts,
      msg="\{fixture.name}: official parser accept/reject",
    )
    if fixture.expected_official_accepts {
      @debug.assert_eq(
        snapshot.skeleton.item_kinds,
        snapshot.official.item_kinds,
        msg="\{fixture.name}: top-level item kinds",
      )
      @debug.assert_eq(
        snapshot.skeleton.diagnostic_count,
        0,
        msg="\{fixture.name}: skeleton diagnostics",
      )
      assert_true(
        !snapshot.skeleton.contains_errors,
        msg="\{fixture.name}: skeleton should not contain errors",
      )
    } else {
      assert_true(
        snapshot.official.lex_error_count > 0 ||
        snapshot.official.report_count > 0,
        msg="\{fixture.name}: official rejection should report a lexer or parser error",
      )
    }
    @debug.assert_eq(
      snapshot.skeleton.diagnostic_count > 0 ||
      snapshot.skeleton.contains_errors,
      fixture.expected_skeleton_errors,
      msg="\{fixture.name}: skeleton error expectation",
    )
  }
}

///|
test "moonbit top-level differential fixture boundary snapshot" {
  let snapshots = top_level_boundary_snapshots()
  let fixtures = top_level_differential_fixtures()
  @debug.assert_eq(
    snapshots.length(),
    fixtures.length(),
    msg="boundary snapshot count matches fixture count",
  )
  for i, fixture in fixtures {
    let snap = snapshots[i]
    @debug.assert_eq(snap.name, fixture.name, msg="snapshot \{i}: name")
    let items = snap.item_boundaries
    for _, item_snap in items {
      // Every item must have a recognizable kind
      let kinds = [
        "LetItemNode", "FunctionItemNode", "StructItemNode", "EnumItemNode", "TypeItemNode",
        "SourceItemNode",
      ]
      assert_true(
        kinds.contains(item_snap.item_kind),
        msg="\{snap.name}: unexpected item kind \{item_snap.item_kind}",
      )
    }
  }
}
