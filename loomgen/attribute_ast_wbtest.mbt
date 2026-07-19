///|
/// Minimal MoonBit parser fixture for the proposed enum-level
/// `#loom.token_set(name, Variant, ...)` syntax.
///
/// This deliberately tests the dependency parser directly rather than
/// `parse_annotations`, because #loom.token_set is not implemented yet.
test "attribute AST preserves enum-level identifier arguments" {
  let src =
    #|#loom.token_set(value_start, LBrace, LBracket)
    #|#loom.token
    #|pub(all) enum Token {
    #|  LBrace
    #|  LBracket
    #|}
  let (impls, diagnostics) = @parser.parse_string(src)
  inspect(diagnostics.length(), content="0")
  let mut found = false
  for toplevel in impls {
    match toplevel {
      @syntax.TopTypeDef(td) =>
        for attr in td.attrs {
          match attr.parsed {
            Some(@attribute.Apply(id, props)) if id.qual == Some("loom") &&
              id.name == "token_set" => {
              found = true
              inspect(props.length(), content="3")
              match props.nth(0) {
                Some(@attribute.Expr(@attribute.Ident(arg))) =>
                  inspect(arg.name, content="value_start")
                _ => abort("token-set name was not preserved as an identifier")
              }
              match props.nth(1) {
                Some(@attribute.Expr(@attribute.Ident(arg))) =>
                  inspect(arg.name, content="LBrace")
                _ =>
                  abort(
                    "first token-set member was not preserved as an identifier",
                  )
              }
              match props.nth(2) {
                Some(@attribute.Expr(@attribute.Ident(arg))) =>
                  inspect(arg.name, content="LBracket")
                _ =>
                  abort(
                    "second token-set member was not preserved as an identifier",
                  )
              }
            }
            _ => ()
          }
        }
      _ => ()
    }
  }
  assert_true(found)
}

///|
/// Integration contract for loomgen: enum-level token sets are collected with
/// their identifier names and referenced token variants.
test "parse_annotations collects token set declarations" {
  let src =
    #|#loom.token_set(value_start, LBrace, LBracket)
    #|#loom.token
    #|pub(all) enum Token {
    #|  #loom.punct("{")
    #|  LBrace
    #|  #loom.punct("[")
    #|  LBracket
    #|}
  match parse_annotations(src) {
    Ok(a) =>
      match a.token_enum {
        Some(te) => {
          inspect(te.token_sets.length(), content="1")
          let set = te.token_sets[0]
          inspect(set.name, content="value_start")
          debug_inspect(set.variants, content="[\"LBrace\", \"LBracket\"]")
        }
        None => abort("expected token enum")
      }
    Err(msg) => abort("parse failed: " + msg)
  }
}

///|
fn expect_token_set_parse_err(src : String, needle : String) -> Unit {
  match parse_annotations(src) {
    Err(msg) =>
      if !msg.contains(needle) {
        abort("expected error containing \"" + needle + "\", got: " + msg)
      }
    Ok(_) =>
      abort("expected token-set parse failure containing \"" + needle + "\"")
  }
}

///|
test "parse_annotations rejects invalid token-set declarations" {
  expect_token_set_parse_err(
    (
      #|#loom.token_set(value_start, Missing)
      #|#loom.token
      #|pub(all) enum Token {
      #|  #loom.punct("{")
      #|  LBrace
      #|}
    ),
    "unknown token variant",
  )
  expect_token_set_parse_err(
    (
      #|#loom.token_set(value_start, LBrace, LBrace)
      #|#loom.token
      #|pub(all) enum Token {
      #|  #loom.punct("{")
      #|  LBrace
      #|}
    ),
    "more than once",
  )
  expect_token_set_parse_err(
    (
      #|#loom.token_set(value_start)
      #|#loom.token
      #|pub(all) enum Token {
      #|  #loom.punct("{")
      #|  LBrace
      #|}
    ),
    "at least one variant",
  )
  expect_token_set_parse_err(
    (
      #|#loom.token_set
      #|#loom.token
      #|pub(all) enum Token {
      #|  #loom.punct("{")
      #|  LBrace
      #|}
    ),
    "requires a name",
  )
  expect_token_set_parse_err(
    (
      #|#loom.token_set(sync_point, LBrace)
      #|#loom.token
      #|pub(all) enum Token {
      #|  #loom.punct("{")
      #|  LBrace
      #|}
    ),
    "is_sync_point",
  )
}

///|
test "parse_annotations rejects token sets outside token enums" {
  expect_token_set_parse_err(
    (
      #|#loom.token_set(value_start, LBrace)
      #|#loom.term
      #|pub(all) enum Term {
      #|  #loom.root
      #|  Root
      #|}
    ),
    "only valid on #loom.token",
  )
  expect_token_set_parse_err(
    (
      #|#loom.token_set(value_start, LBrace)
      #|pub(all) enum Other {
      #|  #loom.punct("{")
      #|  LBrace
      #|}
    ),
    "only valid on #loom.token",
  )
}
