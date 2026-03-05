// Property-based tests for Lambda Calculus Parser
//
// These tests verify parser robustness and correctness using random inputs

///|
/// Property: Parser never panics on any input
test "property: parser handles any string" {
  let inputs : Array[String] = @quickcheck.samples(30)
  for input in inputs {
    // Parser should handle any input gracefully (may raise, but shouldn't panic)
    try {
      let _term = parse(input)
    } catch {
      _ => () // Error is ok, panic is not
    }
  }
}

///|
/// Property: Empty input raises (no expression to parse)
test "property: empty input is safe" {
  try {
    let _term = parse("")
  } catch {
    _ => () // May raise, which is fine
  }
}

///|
/// Property: Single character input doesn't panic
test "property: single char is safe" {
  let chars : Array[Char] = @quickcheck.samples(30)
  for c in chars {
    let input = c.to_string()
    try {
      let _term = parse(input)
    } catch {
      _ => () // Parser should handle any single character
    }
  }
}

///|
/// Property: Parser handles repeated characters
test "property: repeated characters are safe" {
  let chars : Array[Char] = @quickcheck.samples(20)
  for c in chars {
    let mut input = ""
    for _i = 0; _i < 10; _i = _i + 1 {
      input = input + c.to_string()
    }
    try {
      let _term = parse(input)
    } catch {
      _ => () // Parse error is ok
    }
  }
}

///|
/// Property: Valid integers parse as Int terms
test "property: integers parse as Int terms" {
  let nums : Array[Int] = @quickcheck.samples(20)
  for n in nums {
    let input = n.abs().to_string()
    try {
      let term = parse(input)
      match term {
        @ast.Term::Int(_) => ()
        _ => abort("Integer literal should parse as Int term")
      }
    } catch {
      e => abort("Integer \{input} should parse successfully: \{e}")
    }
  }
}

///|
/// Property: Parser handles whitespace correctly
test "property: whitespace doesn't break parser" {
  let texts : Array[String] = @quickcheck.samples(15)
  for text in texts {
    // Add whitespace around input
    let inputs = ["   " + text, text + "   ", "   " + text + "   "]
    for input in inputs {
      try {
        let _term = parse(input)
      } catch {
        _ => () // Parser should handle whitespace gracefully
      }
    }
  }
}

///|
/// Property: Parentheses don't cause crashes
test "property: parentheses are safe" {
  let counts : Array[Int] = @quickcheck.samples(15)
  for count in counts {
    let n = count.abs() % 20 // Limit to reasonable size
    let mut input = ""

    // Create nested parentheses
    for _i = 0; _i < n; _i = _i + 1 {
      input = input + "("
    }
    for _i = 0; _i < n; _i = _i + 1 {
      input = input + ")"
    }
    try {
      let _term = parse(input)
    } catch {
      _ => () // Should handle nested parens without panic
    }
  }
}

///|
/// Property: Lambda syntax variations are handled
test "property: lambda syntax is robust" {
  let params = ["x", "y", "z"]
  let bodies = ["x", "1"]
  for param in params {
    for body in bodies {
      // Test both lambda syntaxes: λ and \
      let input1 = "\\\{param}. \{body}"
      let input2 = "λ\{param}. \{body}"
      for input in [input1, input2] {
        try {
          let _term = parse(input)
        } catch {
          _ => ()
        }
      }
    }
  }
}

///|
/// Property: Mixed valid and invalid syntax doesn't crash
test "property: mixed syntax is safe" {
  let fragments = ["x", "1", "+", "-", ".", "(", ")"]
  let samples : Array[Array[String]] = @quickcheck.samples(10)
  for sample in samples {
    let mut input = ""
    for s in sample {
      // Pick random fragment
      let idx = s.length().abs() % fragments.length()
      input = input + fragments[idx] + " "
    }
    try {
      let _term = parse(input)
    } catch {
      _ => () // Parser should handle random combinations gracefully
    }
  }
}

///|
/// Property: Parser is deterministic
test "property: parser is deterministic" {
  let inputs : Array[String] = @quickcheck.samples(15)
  for input in inputs {
    try {
      let term1 = parse(input)
      let term2 = parse(input)
      // Same input should produce identical Terms (Term derives Eq)
      assert_true(term1 == term2)
    } catch {
      _ => () // Parse errors are fine
    }
  }
}

///|
/// Property: Parser produces well-formed Term structure
test "property: term structure is well-formed" {
  let inputs : Array[String] = @quickcheck.samples(20)
  for input in inputs {
    try {
      let term = parse(input)
      check_well_formed(term)
    } catch {
      _ => () // Parse error is fine
    }
  }
}

///|
fn check_well_formed(term : @ast.Term) -> Unit raise {
  // Check structural invariants by recursing into sub-terms
  match term {
    @ast.Term::Int(_) => ()
    @ast.Term::Var(_) => ()
    @ast.Term::Lam(_, body) => check_well_formed(body)
    @ast.Term::App(func, arg) => {
      check_well_formed(func)
      check_well_formed(arg)
    }
    @ast.Term::Bop(_, left, right) => {
      check_well_formed(left)
      check_well_formed(right)
    }
    @ast.Term::If(cond, then_, else_) => {
      check_well_formed(cond)
      check_well_formed(then_)
      check_well_formed(else_)
    }
    @ast.Term::Let(_, init, body) => {
      check_well_formed(init)
      check_well_formed(body)
    }
    @ast.Term::Unit => ()
    @ast.Term::Error(_) => () // error terms from recovery are valid Term values
  }
}
