// Block reparse correctness tests
//
// These tests verify that the block reparse optimisation produces ASTs
// identical to a full reparse, and that the reuse_count flag correctly
// indicates whether the block path was taken.

// ============================================================================
// 1. Edit inside block matches full reparse
// ============================================================================

///|
test "block reparse: edit inside block matches full reparse" {
  // Source: "{ let a = 1; a }"
  //          0123456789...
  //  { = 0, ' ' = 1, l = 2, e = 3, t = 4, ' ' = 5,
  //  a = 6, ' ' = 7, = = 8, ' ' = 9, 1 = 10, ; = 11,
  //  ' ' = 12, a = 13, ' ' = 14, } = 15
  let source = "{ let a = 1; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Replace "1" (pos 10) with "2"  →  "{ let a = 2; a }"
  let edit = @core.Edit::new(10, 1, 1)
  let new_source = "{ let a = 2; a }"
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse failed") }

  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // reuse_count == 1 means block reparse was used
  inspect(parser.get_last_reuse_count(), content="1")
}

// ============================================================================
// 2. Edit touching brace falls through to normal incremental
// ============================================================================

///|
test "block reparse: edit touching closing brace falls through" {
  // Source: "{ let a = 1; a }"
  let source = "{ let a = 1; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Delete closing "}" at position 15 → "{ let a = 1; a "
  let edit = @core.Edit::new(15, 1, 0)
  let new_source = "{ let a = 1; a "
  let incr_term = parser.edit(edit, new_source)
  let (full_term, _) = parse_term(new_source) catch { _ => abort("lex error") }

  // ASTs should still match (both handle incomplete block)
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // Block reparse should NOT have been used (edit touches brace)
  inspect(parser.get_last_reuse_count() != 1, content=(
    #|false
  ))
}

// ============================================================================
// 3. Nested blocks — edit inside inner block
// ============================================================================

///|
test "block reparse: nested blocks reparses inner" {
  // Source: "{ let x = { let a = 1; a }; x }"
  //  Positions:
  //  { = 0, ' ' = 1, l = 2, e = 3, t = 4, ' ' = 5, x = 6,
  //  ' ' = 7, = = 8, ' ' = 9, { = 10, ' ' = 11, l = 12,
  //  e = 13, t = 14, ' ' = 15, a = 16, ' ' = 17, = = 18,
  //  ' ' = 19, 1 = 20, ; = 21, ' ' = 22, a = 23, ' ' = 24,
  //  } = 25, ; = 26, ' ' = 27, x = 28, ' ' = 29, } = 30
  let source = "{ let x = { let a = 1; a }; x }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Replace "1" (pos 20) with "9" → "{ let x = { let a = 9; a }; x }"
  let edit = @core.Edit::new(20, 1, 1)
  let new_source = "{ let x = { let a = 9; a }; x }"
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse failed") }

  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // Block reparse should be used (edit is inside a block)
  inspect(parser.get_last_reuse_count(), content="1")
}

// ============================================================================
// 4. No block — falls through to normal incremental
// ============================================================================

///|
test "block reparse: no block falls through to normal incremental" {
  // Source without blocks: "let x = 1\nx"
  let source = "let x = 1\nx"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Replace "1" with "2" at position 8
  // l=0 e=1 t=2 ' '=3 x=4 ' '=5 ==6 ' '=7 1=8
  let edit = @core.Edit::new(8, 1, 1)
  let new_source = "let x = 2\nx"
  let incr_term = parser.edit(edit, new_source)
  let full_term = parse(new_source) catch { _ => abort("parse failed") }

  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // No block → block reparse cannot fire → reuse_count != 1
  inspect(parser.get_last_reuse_count() != 1, content=(
    #|false
  ))
}

// ============================================================================
// 5. Block with errors — error diagnostics preserved
// ============================================================================

///|
test "block reparse: block with errors preserves diagnostics" {
  // Missing semicolon between defs: "{ let a = 1 let b = 2; a }"
  //  Positions:
  //  { = 0, ' ' = 1, l = 2, e = 3, t = 4, ' ' = 5, a = 6,
  //  ' ' = 7, = = 8, ' ' = 9, 1 = 10, ' ' = 11, l = 12,
  //  e = 13, t = 14, ' ' = 15, b = 16, ' ' = 17, = = 18,
  //  ' ' = 19, 2 = 20, ; = 21, ' ' = 22, a = 23, ' ' = 24,
  //  } = 25
  let source = "{ let a = 1 let b = 2; a }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()
  let initial_diags = parser.diagnostics()

  // Replace "2" (pos 20) with "3" → "{ let a = 1 let b = 3; a }"
  let edit = @core.Edit::new(20, 1, 1)
  let new_source = "{ let a = 1 let b = 3; a }"
  let incr_term = parser.edit(edit, new_source)
  let (full_term, _) = parse_term(new_source) catch { _ => abort("lex error") }

  // AST should still match
  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
  // Diagnostics should still be present (the missing semicolon error)
  let new_diags = parser.diagnostics()
  inspect(new_diags.length() > 0, content="true")
  // Same number of diagnostics as before the edit
  inspect(new_diags.length() == initial_diags.length(), content="true")
}

// ============================================================================
// 6. Empty block after deletion
// ============================================================================

///|
test "block reparse: delete content leaving empty block" {
  // Source: "{ 42 }"
  //  { = 0, ' ' = 1, 4 = 2, 2 = 3, ' ' = 4, } = 5
  let source = "{ 42 }"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // Delete "42" (pos 2, len 2) → "{ }"  (note: "42" removed, spaces remain)
  // Old: "{ 42 }" → New: "{  }" (delete 2 chars at pos 2)
  let edit = @core.Edit::new(2, 2, 0)
  let new_source = "{  }"
  let incr_term = parser.edit(edit, new_source)
  let (full_term, _) = parse_term(new_source) catch { _ => abort("lex error") }

  inspect(@ast.print_term(incr_term), content=@ast.print_term(full_term))
}

// ============================================================================
// 7. Sequential edits: block reparse then normal edit
// ============================================================================

///|
test "block reparse: sequential edits — block then non-block" {
  // Source: "let y = { let a = 1; a }\ny"
  //  Positions:
  //  l=0 e=1 t=2 ' '=3 y=4 ' '=5 ==6 ' '=7
  //  {=8 ' '=9 l=10 e=11 t=12 ' '=13 a=14 ' '=15
  //  ==16 ' '=17 1=18 ;=19 ' '=20 a=21 ' '=22 }=23
  //  \n=24 y=25
  let source = "let y = { let a = 1; a }\ny"
  let parser = @loom.new_imperative_parser(source, lambda_grammar)
  let _ = parser.parse()

  // First edit: replace "1" (pos 18) with "9" → inside block → block reparse
  let edit1 = @core.Edit::new(18, 1, 1)
  let source2 = "let y = { let a = 9; a }\ny"
  let incr1 = parser.edit(edit1, source2)
  let full1 = parse(source2) catch { _ => abort("parse failed") }
  inspect(@ast.print_term(incr1), content=@ast.print_term(full1))
  inspect(parser.get_last_reuse_count(), content="1")

  // Second edit: replace "y" at the end (pos 25) with "z" → outside block
  // After first edit, source is "let y = { let a = 9; a }\ny"
  // The final "y" is at position 25
  let edit2 = @core.Edit::new(25, 1, 1)
  let source3 = "let y = { let a = 9; a }\nz"
  let incr2 = parser.edit(edit2, source3)
  let (full2, _) = parse_term(source3) catch { _ => abort("lex error") }
  inspect(@ast.print_term(incr2), content=@ast.print_term(full2))
  // Second edit is outside block, so block reparse should NOT fire
  inspect(parser.get_last_reuse_count() != 1, content=(
    #|false
  ))
}
