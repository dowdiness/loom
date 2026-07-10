///|
/// Phase 1 (#601): Pratt notation parsing — positive shapes and fail-closed errors.

///|
test "parse_rule_string: @prefix Atom yields PrattAppSpec" {
  match parse_rule_string("@prefix Atom", "AppExpr") {
    Ok(PrattApp({ prefix: "Atom", app_kind: None })) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: PrattBinary with prec and skip" {
  match
    parse_rule_string(
      "@prefix AppExpr @prec[Plus, Minus] @skip(Newline)", "BinaryExpr",
    ) {
    Ok(
      PrattBinary(
        {
          prefix: "AppExpr",
          ops: ["Plus", "Minus"],
          skip: Some("Newline"),
          app_kind: None,
        }
      )
    ) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @app override on PrattApp" {
  match parse_rule_string("@prefix Atom @app AppExpr", "Wrapper") {
    Ok(PrattApp({ prefix: "Atom", app_kind: Some("AppExpr") })) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string rejects mixed Pratt and EBNF" {
  match parse_rule_string("Foo @prefix Atom", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(
        m.contains("only valid in a production-level Pratt body"),
        content="true",
      )
  }
}

///|
test "parse_rule_string rejects paren-wrapped Pratt body" {
  match parse_rule_string("(@prefix Atom)", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(
        m.contains("only valid in a production-level Pratt body"),
        content="true",
      )
  }
}

///|
test "parse_rule_string rejects postfix on Pratt annotation" {
  match parse_rule_string("@prefix Atom*", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("unexpected token in Pratt body"), content="true")
  }
}

///|
test "parse_rule_string rejects pipe in Pratt body" {
  match parse_rule_string("@prefix Atom | Foo", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("unexpected token in Pratt body"), content="true")
  }
}

///|
test "parse_rule_string rejects duplicate @prec" {
  match parse_rule_string("@prefix AppExpr @prec[Plus] @prec[Minus]", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("duplicate '@prec'"), content="true")
  }
}

///|
test "parse_rule_string rejects @prec without @prefix" {
  match parse_rule_string("@prec[Plus]", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("must begin with '@prefix'"), content="true")
  }
}

///|
test "parse_rule_string rejects @skip on PrattApp" {
  match parse_rule_string("@prefix Atom @skip(Newline)", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(
        m.contains("only valid on PrattBinary productions"),
        content="true",
      )
  }
}

///|
test "parse_rule_string rejects empty @prec" {
  match parse_rule_string("@prefix AppExpr @prec[]", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("empty"), content="true")
  }
}

///|
test "parse_rule_string rejects duplicate operator in @prec" {
  match parse_rule_string("@prefix AppExpr @prec[Plus, Plus]", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("duplicate operator"), content="true")
  }
}

///|
test "parse_rule_string rejects leading @app without @prefix" {
  match parse_rule_string("@app AppExpr", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("must begin with '@prefix'"), content="true")
  }
}

///|
test "parse_rule_string: @native(ident) atom" {
  match parse_rule_string("@native(parse_tag_open)", "Element") {
    Ok(Native("parse_tag_open")) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @native(ident) in Seq" {
  match
    parse_rule_string(
      "LAngle @native(parse_tag_open) Attr* @native(parse_children_or_void) CloseTag",
      "Element",
    ) {
    Ok(
      Seq(
        [
          Sym("LAngle"),
          Native("parse_tag_open"),
          Star(Sym("Attr")),
          Native("parse_children_or_void"),
          Sym("CloseTag"),
        ]
      )
    ) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @native(ident) in Alt" {
  match parse_rule_string("Foo | @native(emit_flat)", "Rule") {
    Ok(Alt([Sym("Foo"), Native("emit_flat")])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @native(ident) as trailing fallthrough" {
  match parse_rule_string("Foo | Bar | @native(fallback)", "Rule") {
    Ok(Alt([Sym("Foo"), Sym("Bar"), Native("fallback")])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @native() empty parens rejected" {
  match parse_rule_string("@native()", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("must contain an identifier"), content="true")
  }
}

///|
test "parse_rule_string: @native without parens rejected" {
  match parse_rule_string("@native", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(
        m.contains("'@native' must be followed by '(' name ')'"),
        content="true",
      )
  }
}

///|
test "parse_rule_string: bare @native not confused with fragment" {
  match parse_rule_string("@nativeX", "Bad") {
    Ok(Frag("nativeX")) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(_) => abort("expected '@nativeX' to parse as a fragment")
  }
}

///|
test "parse_rule_string: @error_node(Kind, Token) yields ErrorNodeUntil" {
  match parse_rule_string("@error_node(ErrorNode, EOF)", "SourceFile") {
    Ok(ErrorNodeUntil("ErrorNode", ["EOF"])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @error_node(Kind, A | B) with multi-token sync" {
  match
    parse_rule_string("@error_node(ErrorNode, Semicolon | EOF)", "SourceFile") {
    Ok(ErrorNodeUntil("ErrorNode", ["Semicolon", "EOF"])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @error_node(Kind, A | B | C) with three sync tokens" {
  match parse_rule_string("@error_node(ErrorNode, A | B | C)", "SourceFile") {
    Ok(ErrorNodeUntil("ErrorNode", ["A", "B", "C"])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: @error_node() missing content rejected" {
  match parse_rule_string("@error_node()", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("must contain a kind identifier"), content="true")
  }
}

///|
test "parse_rule_string: @error_node(Kind) missing comma rejected" {
  match parse_rule_string("@error_node(ErrorNode)", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("requires a comma after the kind"), content="true")
  }
}

///|
test "parse_rule_string: @error_node(, Token) missing kind rejected" {
  match parse_rule_string("@error_node(, EOF)", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("must contain a kind identifier"), content="true")
  }
}

///|
test "parse_rule_string: @error_node(Kind,) missing tokens rejected" {
  match parse_rule_string("@error_node(ErrorNode,)", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(
        m.contains("must contain at least one token identifier after the kind"),
        content="true",
      )
  }
}

///|
test "parse_rule_string: @error_node(Kind, Token, Token) extra comma rejected" {
  match parse_rule_string("@error_node(ErrorNode, EOF,)", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("unbalanced '@error_node('"), content="true")
  }
}

///|
test "parse_rule_string: Token~>Token yields ExpectSkip" {
  match parse_rule_string("A~>B", "Rule") {
    Ok(ExpectSkip("A", "B")) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: Token~>Token in Seq context" {
  match parse_rule_string("A~>B C", "Rule") {
    Ok(Seq([ExpectSkip("A", "B"), Sym("C")])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: Token~>Token in Alt context" {
  match parse_rule_string("A~>B | C", "Rule") {
    Ok(Alt([ExpectSkip("A", "B"), Sym("C")])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: ~> at start rejected" {
  match parse_rule_string("~>A", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(
        m.contains("has no atom to bind") || m.contains("unexpected"),
        content="true",
      )
  }
}

///|
test "parse_rule_string: compound atom as skip rejected" {
  match parse_rule_string("(A | B)~>C", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("requires a simple token name"), content="true")
  }
}

// ── SeparatedList ({Sep}) syntax (#604) ─────────────────────────────────

///|
test "parse_rule_string: Expr{Sep} yields SeparatedList" {
  match parse_rule_string("Expr{Comma}", "Rule") {
    Ok(SeparatedList("Expr", "Comma")) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: Expr{Sep} in Seq context" {
  match parse_rule_string("Expr{Comma} Eof", "Rule") {
    Ok(Seq([SeparatedList("Expr", "Comma"), Sym("Eof")])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: Expr{Sep} in Alt context" {
  match parse_rule_string("Expr{Comma} | Single", "Rule") {
    Ok(Alt([SeparatedList("Expr", "Comma"), Sym("Single")])) => ()
    Ok(other) => abort("unexpected ast: " + @debug.to_string(other))
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "parse_rule_string: {Sep} at start rejected (no atom)" {
  match parse_rule_string("{Comma}", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("has no atom to bind"), content="true")
  }
}

///|
test "parse_rule_string: compound atom in {Sep} rejected" {
  match parse_rule_string("(A | B){Comma}", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("requires a simple rule name"), content="true")
  }
}

///|
test "parse_rule_string: empty braces rejected" {
  match parse_rule_string("Foo{}", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) =>
      inspect(m.contains("must contain a token identifier"), content="true")
  }
}

///|
test "parse_rule_string: unclosed brace rejected" {
  match parse_rule_string("Foo{Comma", "Bad") {
    Ok(_) => abort("expected rejection")
    Err(m) => inspect(m.contains("must be closed with"), content="true")
  }
}
