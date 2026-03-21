// Tests for Lambda Calculus Parser
// Based on ReScript Parser_test.res implementation

// ===== Parser Tests =====

///|
test "parse simple integer" {
  let expr = parse("42")
  let printed = @ast.print_term(expr)
  inspect(printed, content="42")
}

///|
test "parse simple variable" {
  let expr = parse("x")
  let printed = @ast.print_term(expr)
  inspect(printed, content="x")
}

///|
test "parse identity function" {
  let expr = parse("λx.x")
  let printed = @ast.print_term(expr)
  inspect(printed, content="(λx. x)")
}

///|
test "parse plus binary operator" {
  let expr = parse("1 + 2")
  let printed = @ast.print_term(expr)
  inspect(printed, content="(1 + 2)")
}

///|
test "parse minus binary operator" {
  let expr = parse("5 - 2")
  let printed = @ast.print_term(expr)
  inspect(printed, content="(5 - 2)")
}

///|
test "parse complex binary operators" {
  let expr = parse("10 - 5 + 2")
  let printed = @ast.print_term(expr)
  inspect(printed, content="((10 - 5) + 2)")
}

///|
test "parse parenthesized expression" {
  let expr = parse("(x)")
  let printed = @ast.print_term(expr)
  inspect(printed, content="x")
}

///|
test "parse nested lambda" {
  let expr = parse("λf.λx.x")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λf"), content="true")
  inspect(printed.contains("λx"), content="true")
}

///|
test "parse simple application" {
  let expr = parse("f x")
  let printed = @ast.print_term(expr)
  inspect(printed, content="(f x)")
}

///|
test "parse multiple applications" {
  let expr = parse("f x y")
  let printed = @ast.print_term(expr)
  inspect(printed, content="((f x) y)")
}

///|
test "parse if-then-else" {
  let expr = parse("if x then y else z")
  let printed = @ast.print_term(expr)
  inspect(printed, content="if x then y else z")
}

///|
test "parse complex if expression" {
  let expr = parse("if 1 + 2 then 3 else 4")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("if"), content="true")
  inspect(printed.contains("then"), content="true")
  inspect(printed.contains("else"), content="true")
}

///|
test "parse lambda with binary operation in body" {
  let expr = parse("λx.x + 1")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λx"), content="true")
  inspect(printed.contains("+"), content="true")
}

///|
test "parse application with lambda" {
  let expr = parse("(λx.x) y")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λx"), content="true")
  inspect(printed.contains("y"), content="true")
}

///|
test "parse nested parentheses" {
  let expr = parse("((x))")
  let printed = @ast.print_term(expr)
  inspect(printed, content="x")
}

///|
test "parse complex nested expression" {
  let expr = parse("(λf.(λx.(f (f x))))")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λf"), content="true")
  inspect(printed.contains("λx"), content="true")
}

// ===== Error Handling Tests =====

///|
test "parse error - missing parameter after lambda" {
  let should_error = try {
    let _expr = parse("λ.x")
    false
  } catch {
    _ => true
  }
  inspect(
    should_error,
    content=(
      #|true
    ),
  )
}

///|
test "parse error - missing dot after lambda parameter" {
  let should_error = try {
    let _expr = parse("λx")
    false
  } catch {
    _ => true
  }
  inspect(
    should_error,
    content=(
      #|true
    ),
  )
}

///|
test "parse error - unmatched left paren" {
  let should_error = try {
    let _expr = parse("(x")
    false
  } catch {
    _ => true
  }
  inspect(
    should_error,
    content=(
      #|true
    ),
  )
}

///|
test "parse error - unmatched right paren" {
  let should_error = try {
    let _expr = parse("x)")
    false
  } catch {
    _ => true
  }
  inspect(
    should_error,
    content=(
      #|true
    ),
  )
}

///|
test "parse error - missing then in if" {
  let should_error = try {
    let _expr = parse("if x else y")
    false
  } catch {
    _ => true
  }
  inspect(
    should_error,
    content=(
      #|true
    ),
  )
}

///|
test "parse error - missing else in if" {
  let should_error = try {
    let _expr = parse("if x then y")
    false
  } catch {
    _ => true
  }
  inspect(
    should_error,
    content=(
      #|true
    ),
  )
}

// ===== Edge Case Tests =====

///|
test "parse single character identifier" {
  let expr = parse("a")
  let printed = @ast.print_term(expr)
  inspect(printed, content="a")
}

///|
test "parse long identifier" {
  let expr = parse("variableName123")
  let printed = @ast.print_term(expr)
  inspect(printed, content="variableName123")
}

///|
test "parse zero" {
  let expr = parse("0")
  let printed = @ast.print_term(expr)
  inspect(printed, content="0")
}

///|
test "parse large integer" {
  let expr = parse("999999")
  let printed = @ast.print_term(expr)
  inspect(printed, content="999999")
}

///|
test "parse lambda with backslash" {
  let expr = parse("\\x.x")
  let printed = @ast.print_term(expr)
  inspect(printed, content="(λx. x)")
}

///|
test "parse application chain" {
  let expr = parse("a b c d")
  let printed = @ast.print_term(expr)
  inspect(printed, content="(((a b) c) d)")
}

///|
test "parse mixed operators and applications" {
  let expr = parse("f x + g y")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("f"), content="true")
  inspect(printed.contains("x"), content="true")
  inspect(printed.contains("+"), content="true")
  inspect(printed.contains("g"), content="true")
  inspect(printed.contains("y"), content="true")
}

///|
test "parse complex expression with all features" {
  let expr = parse("(λf.λx.if f x then x + 1 else x - 1)")
  let printed = @ast.print_term(expr)
  inspect(printed.contains("λf"), content="true")
  inspect(printed.contains("λx"), content="true")
  inspect(printed.contains("if"), content="true")
  inspect(printed.contains("then"), content="true")
  inspect(printed.contains("else"), content="true")
  inspect(printed.contains("+"), content="true")
  inspect(printed.contains("-"), content="true")
}

///|
test "parse let expression" {
  let expr = parse("let x = 1\nx") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(expr),
    content=(
      #|let x = 1
      #|x
    ),
  )
}

///|
test "parse let with binary op in body" {
  let expr = parse("let x = 3\nx + 1") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(expr),
    content=(
      #|let x = 3
      #|(x + 1)
    ),
  )
}

///|
test "parse nested let" {
  let expr = parse("let x = 1\nlet y = 2\nx + y") catch {
    _ => abort("parse failed")
  }
  inspect(
    @ast.print_term(expr),
    content=(
      #|let x = 1
      #|let y = 2
      #|(x + y)
    ),
  )
}

///|
test "parse let with lambda" {
  let expr = parse("let f = λx.x\nf 42") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(expr),
    content=(
      #|let f = (λx. x)
      #|(f 42)
    ),
  )
}

///|
test "parse_term: two defs produce Module with Unit body" {
  let (term, diagnostics) = parse_term("let id = 1\nlet const = 2")
  inspect(diagnostics.length(), content="0")
  inspect(
    @ast.print_term(term),
    content=(
      #|let id = 1
      #|let const = 2
    ),
  )
}

///|
test "parse_term: def + final expression" {
  let (term, diagnostics) = parse_term("let id = 1\nid")
  inspect(diagnostics.length(), content="0")
  inspect(
    @ast.print_term(term),
    content=(
      #|let id = 1
      #|id
    ),
  )
}

///|
test "parse_term: leading newline before def + final expression" {
  let (term, diagnostics) = parse_term("\nlet id = 1\nid")
  inspect(diagnostics.length(), content="0")
  inspect(
    @ast.print_term(term),
    content=(
      #|let id = 1
      #|id
    ),
  )
}

///|
test "parse_term: single expression (no defs)" {
  let (term, diagnostics) = parse_term("42")
  inspect(diagnostics.length(), content="0")
  inspect(@ast.print_term(term), content="42")
}

///|
test "parse_term: let-expression (no defs)" {
  let (term, diagnostics) = parse_term("let x = 1 in x")
  inspect(
    diagnostics.length(),
    content=(
      #|1
    ),
  )
  inspect(
    @ast.print_term(term),
    content=(
      #|let x = 1
      #|<error: unknown node kind: ErrorToken>
    ),
  )
}

///|
test "parse_term: multiline let-expression (no defs)" {
  let (term, diagnostics) = parse_term("let x = 1\nin x")
  inspect(
    diagnostics.length(),
    content=(
      #|1
    ),
  )
  inspect(
    @ast.print_term(term),
    content=(
      #|let x = 1
      #|<error: unknown node kind: ErrorToken>
    ),
  )
}

///|
test "parse_term: multiline binary expression (no defs)" {
  let (term, diagnostics) = parse_term("1\n+2")
  inspect(diagnostics.length(), content="0")
  inspect(@ast.print_term(term), content="(1 + 2)")
}

///|
test "parse_term: multiline application (no defs)" {
  let (term, diagnostics) = parse_term("f\nx")
  inspect(diagnostics.length(), content="0")
  inspect(
    @ast.print_term(term),
    content=(
      #|(f x)
    ),
  )
}

///|
test "parse_term: missing newline between defs reports diagnostic" {
  let (_, diagnostics) = parse_term("let a = 1 let b = 2")
  inspect(diagnostics.length() > 0, content="true")
  inspect(
    diagnostics[0].message,
    content=(
      #|Expected newline between top-level definitions
    ),
  )
}

///|
test "parse_term: empty file" {
  let (term, diagnostics) = parse_term("")
  inspect(diagnostics.length(), content="0")
  inspect(@ast.print_term(term), content="()")
}

///|
test "parse_term: interleaved defs and expressions" {
  let (term, diagnostics) = parse_term("let x = 1\nx\nlet y = 2\ny")
  inspect(
    diagnostics.length(),
    content=(
      #|1
    ),
  )
  inspect(
    @ast.print_term(term),
    content=(
      #|let x = 1
      #|x
    ),
  )
}
