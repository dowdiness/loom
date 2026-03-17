// Phase 4: Subtree Reuse Correctness Tests
//
// These tests verify the Phase 4 exit criteria for subtree reuse:
// - Incremental parse ALWAYS matches full reparse (correctness invariant)
// - Parser handles various edit patterns correctly
// - Edge cases at grammar boundaries are handled
//
// Note on reuse rate: Lambda calculus trees are left-leaning (binary expression
// chains, nested lambdas), so the tree spine must be rebuilt for most edits.
// Reuse benefits are more visible with Phase 5's let bindings which create
// independent subtrees. These tests focus on CORRECTNESS, not reuse rate.

// ============================================================================
// Section 1: Reuse Rate on Larger Inputs
// ============================================================================

///|
test "phase4: correctness on 50+ token input - localized edit" {
  // Build a larger input: "a + b + c + ... + z" (26 letters, 51 tokens)
  // Note: Lambda calculus trees are left-leaning, so even localized edits
  // may require rebuilding the entire spine. This test verifies CORRECTNESS
  // (incremental == full parse), not reuse rate.
  let mut source = "a"
  let letters = [
    "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q",
    "r", "s", "t", "u", "v", "w", "x", "y", "z",
  ]
  for letter in letters {
    source = source + " + " + letter
  }
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Edit only the last letter "z" -> "1"
  let len = source.length()
  let edit = @core.Edit::replace(len - 1, len, len)
  let new_source = source[0:len - 1].to_string() + "1"
  let incr_tree = parser.edit(edit, new_source)
  let full_tree = parse(new_source) catch { _ => abort("parse failed") }

  // Core invariant: incremental must match full reparse
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: reuse on application chain" {
  // Application chain: "f a b c d e" (6 identifiers forming App(App(...)))
  let source = "f a b c d e"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Edit only the last identifier "e" -> "x"
  let edit = @core.Edit::replace(10, 11, 11)
  let incr_tree = parser.edit(edit, "f a b c d x")
  let full_tree = parse("f a b c d x") catch { _ => abort("parse failed") }

  // Must match full reparse
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: reuse on nested lambdas" {
  // Nested lambdas: "\a.\b.\c.\d.x"
  let source = "λa.λb.λc.λd.x"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Edit only the body "x" -> "y"
  let len = source.length()
  let edit = @core.Edit::replace(len - 1, len, len)
  let incr_tree = parser.edit(edit, "λa.λb.λc.λd.y")
  let full_tree = parse("λa.λb.λc.λd.y") catch {
    _ => abort("parse failed")
  }

  // Must match full reparse
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: reuse preserves correctness on complex expression" {
  let source = "λf.λx.if f x then x + 1 else x - 1"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Edit only the "1" in "x + 1" -> "2"
  // Positions are source code-unit offsets (λ = 1 code unit)
  // "x + 1" is at position 18-23, "1" is at position 22
  let edit = @core.Edit::replace(22, 23, 23)
  let new_source = "λf.λx.if f x then x + 2 else x - 1"
  let incr_tree = parser.edit(edit, new_source)
  let full_tree = parse(new_source) catch { _ => abort("parse failed") }

  // Must match full reparse
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

// ============================================================================
// Section 2: Correctness on Edit Boundaries
// ============================================================================

///|
test "phase4: edit at binary operator boundary" {
  let source = "a + b - c"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Change "-" to "+"
  let edit = @core.Edit::replace(6, 7, 7)
  let incr_tree = parser.edit(edit, "a + b + c")
  let full_tree = parse("a + b + c") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: edit changes structure - app to binary" {
  // This tests the trailing context check from ROADMAP 4.2.1
  let source = "x + y z" // Bop(Plus, x, App(y, z))
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Change space to " - " making it "x + y - z"
  // This changes the structure entirely
  let edit = @core.Edit::replace(5, 6, 8)
  let incr_tree = parser.edit(edit, "x + y - z")
  let full_tree = parse("x + y - z") catch { _ => abort("parse failed") }

  // Must match full reparse - trailing context check should prevent false reuse
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: edit changes app to standalone var" {
  let source = "f x" // App(f, x)
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Delete " x" making it just "f"
  let edit = @core.Edit::delete(1, 3)
  let incr_tree = parser.edit(edit, "f")
  let full_tree = parse("f") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: edit extends expression" {
  let source = "x" // Var(x)
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Append " y" making it "x y"
  let edit = @core.Edit::insert(1, 2)
  let incr_tree = parser.edit(edit, "x y")
  let full_tree = parse("x y") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

// ============================================================================
// Section 3: Reuse Across Multiple Edits
// ============================================================================

///|
test "phase4: multiple sequential edits maintain correctness" {
  let parser = @loom.new_imperative_parser("a + b + c", lambda_grammar)
  let _ = parser.parse()

  // Edit 1: change "a" to "1"
  let edit1 = @core.Edit::replace(0, 1, 1)
  let tree1 = parser.edit(edit1, "1 + b + c")
  let full1 = parse("1 + b + c") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(tree1),
    content=@ast.print_term(full1),
  )

  // Edit 2: change "b" to "2"
  let edit2 = @core.Edit::replace(4, 5, 5)
  let tree2 = parser.edit(edit2, "1 + 2 + c")
  let full2 = parse("1 + 2 + c") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(tree2),
    content=@ast.print_term(full2),
  )

  // Edit 3: change "c" to "3"
  let edit3 = @core.Edit::replace(8, 9, 9)
  let tree3 = parser.edit(edit3, "1 + 2 + 3")
  let full3 = parse("1 + 2 + 3") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(tree3),
    content=@ast.print_term(full3),
  )
}

///|
test "phase4: typing simulation - building expression char by char" {
  // Simulate typing "1 + 2" starting from "1"
  // (Avoid incomplete lambda expressions which produce errors)
  let parser = @loom.new_imperative_parser("1", lambda_grammar)
  let _ = parser.parse()

  // Type " +"
  let edit1 = @core.Edit::insert(1, 2)
  let tree1 = parser.edit(edit1, "1 +")
  // Intermediate state may have errors, just check it parses
  let _ = tree1

  // Type " 2"
  let edit2 = @core.Edit::insert(3, 2)
  let tree2 = parser.edit(edit2, "1 + 2")
  let full = parse("1 + 2") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(tree2),
    content=@ast.print_term(full),
  )
}

// ============================================================================
// Section 4: Edge Cases
// ============================================================================

///|
test "phase4: empty to non-empty" {
  // Note: empty string may cause issues, start with minimal valid input
  let parser = @loom.new_imperative_parser("x", lambda_grammar)
  let _ = parser.parse()

  // Replace with completely different expression
  let edit = @core.Edit::replace(0, 1, 13)
  let incr_tree = parser.edit(edit, "λf.λx.f (f x)")
  let full_tree = parse("λf.λx.f (f x)") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: whitespace-only changes" {
  let source = "x+y"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Add spaces: "x + y"
  let edit = @core.Edit::replace(0, 3, 5)
  let incr_tree = parser.edit(edit, "x + y")
  let full_tree = parse("x + y") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: parentheses changes" {
  let source = "x + y"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Wrap in parens: "(x + y)"
  let edit = @core.Edit::replace(0, 5, 7)
  let incr_tree = parser.edit(edit, "(x + y)")
  let full_tree = parse("(x + y)") catch { _ => abort("parse failed") }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: if-then-else edit in condition" {
  let source = "if x then 1 else 2"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Change condition "x" to "y"
  let edit = @core.Edit::replace(3, 4, 4)
  let incr_tree = parser.edit(edit, "if y then 1 else 2")
  let full_tree = parse("if y then 1 else 2") catch {
    _ => abort("parse failed")
  }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}

///|
test "phase4: if-then-else edit in else branch" {
  let source = "if x then 1 else 2"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Change else branch "2" to "3"
  let edit = @core.Edit::replace(17, 18, 18)
  let incr_tree = parser.edit(edit, "if x then 1 else 3")
  let full_tree = parse("if x then 1 else 3") catch {
    _ => abort("parse failed")
  }
  inspect(
    @ast.print_term(incr_tree),
    content=@ast.print_term(full_tree),
  )
}
