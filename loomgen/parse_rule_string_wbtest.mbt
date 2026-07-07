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
