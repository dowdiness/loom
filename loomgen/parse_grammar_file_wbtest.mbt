///|
/// Whitebox tests for #523: the standalone `.loomgrammar` file parser. It reuses
/// the `#loom.rule` notation (`RuleAst` + `parse_alt`) but adds a file-level
/// tokenizer with line spans, `=` production headers, `//` comments, and
/// multi-line bodies.

///|
/// RED (#523): the smallest possible grammar file — one production, no comments,
/// single line — must parse to one `(name, RuleAst, line)` entry whose body is the
/// same tree the equivalent `#loom.rule("LParen RParen")` annotation would yield.
/// The file separator is a single `=` (matching the issue's format), not `:=`.
test "parse_grammar_file parses the smallest single production" {
  let prods = match parse_grammar_file("Parens = LParen RParen") {
    Ok(p) => p
    Err(m) => abort("parse failed: " + m)
  }
  inspect(prods.length(), content="1")
  let (name, body, line) = prods[0]
  inspect(name, content="Parens")
  inspect(line, content="1")
  @debug.assert_eq(body, Seq([Sym("LParen"), Sym("RParen")]))
}

///|
/// The file format's reasons to exist over annotation strings: `//` comments,
/// multi-line bodies (newlines are whitespace), and a leading `|` on the first
/// alternative so alternatives line up vertically. The two productions must parse
/// to the same trees their single-line annotation equivalents would.
test "parse_grammar_file handles comments, multi-line bodies, and leading-pipe alternation" {
  let src =
    #|// Root rule
    #|Items = Item* Eof
    #|
    #|Item =
    #|  | A   // first alternative
    #|  | B
  let prods = match parse_grammar_file(src) {
    Ok(p) => p
    Err(m) => abort("parse failed: " + m)
  }
  inspect(prods.length(), content="2")
  let (n0, b0, l0) = prods[0]
  let (n1, b1, l1) = prods[1]
  inspect(n0, content="Items")
  inspect(l0, content="2")
  @debug.assert_eq(b0, Seq([Star(Sym("Item")), Sym("Eof")]))
  inspect(n1, content="Item")
  inspect(l1, content="4")
  @debug.assert_eq(b1, Alt([Sym("A"), Sym("B")]))
}

///|
/// Fail closed on a duplicate production name. The productions are an ordered
/// list, so a silent second entry would shadow the first at GrammarIr build time
/// (the `Map` it feeds would keep whichever wins) — a classic silent-overwrite
/// trap. Reject it at parse time instead.
test "parse_grammar_file rejects a duplicate production name" {
  let src =
    #|Foo = A
    #|Foo = B
  match parse_grammar_file(src) {
    Ok(_) => abort("expected a duplicate-name rejection, got Ok")
    Err(m) => inspect(m.contains("duplicate production 'Foo'"), content="true")
  }
}

///|
/// A production whose `=` is immediately followed by the next header has an empty
/// body and must be rejected (an empty production cannot lower to an `Expr`).
test "parse_grammar_file rejects an empty production body" {
  let src =
    #|A =
    #|B = C
  match parse_grammar_file(src) {
    Ok(_) => abort("expected an empty-body rejection, got Ok")
    Err(m) =>
      inspect(m.contains("production 'A' has an empty body"), content="true")
  }
}

///|
/// A body consisting only of a leading `|` (e.g. `A = |`) is effectively empty
/// and must report "empty body", not the inner-parser "empty sequence" message.
test "parse_grammar_file rejects a lone-pipe body as empty" {
  match parse_grammar_file("A = |") {
    Ok(_) => abort("expected an empty-body rejection, got Ok")
    Err(m) =>
      inspect(m.contains("production 'A' has an empty body"), content="true")
  }
}

///|
/// A stray `=` inside a body (not part of a `IDENT =` header) is malformed.
test "parse_grammar_file rejects a stray '=' inside a body" {
  match parse_grammar_file("A = = B") {
    Ok(_) => abort("expected a stray-'=' rejection, got Ok")
    Err(m) =>
      inspect(
        m.contains("unexpected '=' inside the body of production 'A'"),
        content="true",
      )
  }
}

///|
/// A production name not followed by `=` is a malformed header.
test "parse_grammar_file rejects a header with no '='" {
  match parse_grammar_file("A B") {
    Ok(_) => abort("expected a missing-'=' rejection, got Ok")
    Err(m) =>
      inspect(
        m.contains("expected '=' after production name 'A'"),
        content="true",
      )
  }
}

///|
/// Body-internal notation errors propagate through the reused `RuleParser`, tagged
/// with the production name and line (file-position diagnostics, the format's whole
/// point) — not an annotation offset.
test "parse_grammar_file reports a body parse error with production and line" {
  let src =
    #|Ok = A
    #|Bad = ( B
  match parse_grammar_file(src) {
    Ok(_) => abort("expected an unbalanced-paren rejection, got Ok")
    Err(m) => {
      inspect(m.contains("line 2:"), content="true")
      inspect(m.contains("in production 'Bad'"), content="true")
      inspect(m.contains("unbalanced '('"), content="true")
    }
  }
}

///|
/// An unexpected character fails closed at tokenization, with its line.
test "parse_grammar_file rejects an unexpected character" {
  match parse_grammar_file("A = B ; C") {
    Ok(_) => abort("expected an unexpected-character rejection, got Ok")
    Err(m) => inspect(m.contains("unexpected character ';'"), content="true")
  }
}

///|
/// A file with no productions (empty or comment-only) is rejected, not silently
/// accepted as an empty grammar.
test "parse_grammar_file rejects a comment-only file" {
  match parse_grammar_file("// just a note\n// and another") {
    Ok(_) => abort("expected a no-productions rejection, got Ok")
    Err(m) =>
      inspect(m.contains("grammar file has no productions"), content="true")
  }
}
