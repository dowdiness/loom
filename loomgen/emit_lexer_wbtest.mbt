///|
/// Whitebox tests for #521 lexer generation: golden snapshot of the emitter and
/// the generation-time validation errors.

///|
fn read_fixture(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => abort("cannot read " + path)
  }
}

///|
/// Parse an inline annotated source and return its token enum, or abort.
fn token_enum_of(src : String) -> EnumDecl {
  match parse_annotations(src) {
    Ok(a) =>
      match a.token_enum {
        Some(te) => te
        None => abort("no token enum parsed")
      }
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "emit_lexer golden matches fixtures/pattern_lexer_fixture.g.mbt" {
  let src = read_fixture("fixtures/pattern_lexer_fixture.mbt")
  let golden = read_fixture("fixtures/pattern_lexer_fixture.g.mbt")
  let te = token_enum_of(src)
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  assert_eq(generated, golden)
}

///|
test "parse_annotations rejects a nullable #loom.pattern" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.ident
    #|  #loom.pattern("a*")
    #|  Id
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Err(msg) => inspect(msg.contains("nullable"), content="true")
    Ok(_) => abort("expected nullable-pattern rejection")
  }
}

///|
test "emit_lexer rejects #loom.keyword without a #loom.ident source" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.keyword("if")
      #|  If
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) =>
      inspect(msg.contains("no pattern-backed #loom.ident"), content="true")
    Ok(_) => abort("expected keyword-without-ident rejection")
  }
}

///|
test "emit_lexer rejects a token with no pattern/punct/custom_lex" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  Num
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) => inspect(msg.contains("cannot produce"), content="true")
    Ok(_) => abort("expected unlexable-variant rejection")
  }
}

///|
test "emit_lexer rejects a #loom.pattern containing a double-quote" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("a\"b")
      #|  Q
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) => inspect(msg.contains("double-quote"), content="true")
    Ok(_) => abort("expected double-quote rejection")
  }
}

///|
/// #loom.custom_lex is a modifier on a role-bearing variant (the role gives it a
/// kind for token_impls; custom_lex overrides only HOW it is lexed). The emitted
/// lexer calls the named hook before the regex pass and falls through on `Done`.
test "emit_lexer wires a #loom.custom_lex hook before the regex pass" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.custom_lex("lex_thing")
      #|  Thing
      #|  #loom.ident
      #|  #loom.pattern("[a-zA-Z_]+")
      #|  Name
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  // The custom hook is called, and its non-Done result short-circuits.
  inspect(generated.contains("match lex_thing(source, pos)"), content="true")
  inspect(generated.contains("other => return other"), content="true")
  // The custom_lex variant does NOT also get a regex branch.
  inspect(generated.contains("Some(Thing)"), content="false")
}

///|
/// Assert that `parse_annotations(src)` fails with an error containing `needle`.
fn expect_parse_err(src : String, needle : String) -> Unit {
  match parse_annotations(src) {
    Err(msg) =>
      if !msg.contains(needle) {
        abort("expected error containing \"" + needle + "\", got: " + msg)
      }
    Ok(_) => abort("expected a parse error containing \"" + needle + "\"")
  }
}

///|
/// #1 (Codex review): loomgen rejects #loom.pattern constructs outside its
/// supported `re` subset at generation time — non-capturing/flag/lookaround
/// `(?...)` groups and zero-width assertion escapes (`\b`, `\A`, ...). These
/// either mis-classify under the nullability analyzer (`(?:a?)`) or fail to
/// compile in the generated lexer (`\b`); rejecting them here turns both into a
/// clear generation-time message.
test "parse_annotations rejects a (?:..) non-capturing group pattern" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(?:ab)+")
      #|  Pair
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "(?...) groups",
  )
}

///|
test "parse_annotations rejects a zero-width assertion escape pattern" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  #loom.pattern("\bfoo")
      #|  Id
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "zero-width assertion escape",
  )
}

///|
/// Positive control: a plain `(..)` group is INSIDE the supported subset and
/// must still be accepted — the rejection above is specific to `(?...)`.
test "parse_annotations accepts a plain (..) group pattern" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.literal
    #|  #loom.pattern("(ab)+")
    #|  Pair
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Ok(_) => ()
    Err(m) => abort("expected plain group (ab)+ to be accepted, got: " + m)
  }
}

///|
/// #3 (Codex review): #loom.custom_lex on the EOF sentinel is rejected — EOF is
/// detected at scanner entry, never lexed, so a custom EOF hook could otherwise
/// produce EOF mid-input.
test "parse_annotations rejects #loom.custom_lex on the #loom.eof variant" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.eof
      #|  #loom.custom_lex("lex_eof")
      #|  E
      #|} derive(Eq)
    ),
    "cannot have #loom.custom_lex",
  )
}

///|
/// #4 (Codex review): the #loom.custom_lex argument is emitted verbatim as a
/// call, so a non-identifier is rejected at generation time rather than
/// producing broken (or injected) source in the generated lexer.
test "parse_annotations rejects an invalid #loom.custom_lex function name" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.custom_lex("bad name)")
      #|  Thing
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "not a valid function name",
  )
}

///|
/// Positive control: a qualified `@pkg.fn` path is a valid lex-hook reference.
test "parse_annotations accepts a qualified @pkg.fn custom_lex name" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.literal
    #|  #loom.custom_lex("@css.lex_url")
    #|  Url
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Ok(_) => ()
    Err(m) => abort("expected @css.lex_url to be accepted, got: " + m)
  }
}

///|
/// P1 (PR review): the emitted regex wraps the whole pattern in `^(?:..)` so the
/// anchor binds EVERY top-level alternation branch. `re"^foo|bar"` parses as
/// `(^foo)|(bar)`, and search-based `=~` would match the unanchored `bar`
/// mid-view (advancing the cursor over the wrong span).
test "emit_lexer anchors the whole pattern, including alternation" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("foo|bar")
      #|  Word
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(generated.contains("re\"^(?:foo|bar)\""), content="true")
  // The partially-anchored form must NOT appear.
  inspect(generated.contains("re\"^foo|bar\""), content="false")
}

///|
/// P2 (PR review): keywords are post-classified from the #loom.ident REGEX
/// match, so a #loom.custom_lex identifier — which short-circuits before the
/// regex pass and never sets best_ident — cannot back keyword classification.
/// Reject it at generation time rather than silently emitting a lexer that
/// returns `Ident` for `let`.
test "emit_lexer rejects #loom.keyword when the #loom.ident is custom_lex'd" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  #loom.custom_lex("lex_ident")
      #|  Id
      #|  #loom.keyword("let")
      #|  Let
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) =>
      inspect(msg.contains("pattern-backed #loom.ident"), content="true")
    Ok(_) => abort("expected keyword-without-pattern-backed-ident rejection")
  }
}

///|
/// Review #1: structurally malformed patterns (unbalanced parens, unterminated
/// class, trailing backslash) are rejected at generation time instead of being
/// emitted verbatim into `re"^(?:..)"` and failing the user's later build.
test "parse_annotations rejects structurally malformed patterns" {
  let body = fn(pat : String) -> String {
    "#loom.token\npub(all) enum T {\n  #loom.literal\n  #loom.pattern(\"" +
    pat +
    "\")\n  Tok\n  #loom.eof\n  E\n} derive(Eq)"
  }
  expect_parse_err(body("a)b"), "malformed") // stray ')'
  expect_parse_err(body("(a"), "malformed") // unclosed '('
  expect_parse_err(body("[abc"), "malformed") // unterminated class
}

///|
/// Review #2: a bare `[:` inside a class (not a real POSIX element) must not
/// scan past the class's real `]`. Before the fix `[a[:z](?:x)` swallowed the
/// `(?:` and slipped past the unsupported-construct guard; now the `(?:` is seen
/// and rejected.
test "parse_annotations: false-POSIX class does not hide a later (?:..)" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("[a[:z](?:x)")
      #|  Tok
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "(?...) groups",
  )
}

///|
/// Review #3: a #loom.custom_lex argument that is not a valid identifier/path
/// (leading digit, stray punctuation, trailing/empty segment) is rejected rather
/// than emitted as a non-compiling call.
test "parse_annotations rejects invalid custom_lex names (leading digit, etc.)" {
  let body = fn(name : String) -> String {
    "#loom.token\npub(all) enum T {\n  #loom.literal\n  #loom.custom_lex(\"" +
    name +
    "\")\n  Tok\n  #loom.eof\n  E\n} derive(Eq)"
  }
  expect_parse_err(body("3lex"), "not a valid function name") // leading digit
  expect_parse_err(body("a..b"), "not a valid function name") // empty segment
  expect_parse_err(body("a."), "not a valid function name") // trailing dot
}

///|
/// Review #5: a #loom.punct whose text equals a #loom.keyword shadows it (punct
/// wins longest-match), so the keyword would never be produced — rejected.
test "emit_lexer rejects a #loom.punct that shadows a #loom.keyword" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.punct("let")
      #|  LetPunct
      #|  #loom.ident
      #|  #loom.pattern("[a-z]+")
      #|  Id
      #|  #loom.keyword("let")
      #|  Let
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) =>
      inspect(msg.contains("identical to #loom.keyword"), content="true")
    Ok(_) => abort("expected punct-shadows-keyword rejection")
  }
}

///|
/// Review #5: with keywords present, more than one pattern-backed #loom.ident
/// makes keyword post-classification ambiguous (single best_ident flag).
test "emit_lexer rejects multiple pattern-backed idents alongside keywords" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  #loom.pattern("[a-z]+")
      #|  Lower
      #|  #loom.ident
      #|  #loom.pattern("[A-Z]+")
      #|  Upper
      #|  #loom.keyword("let")
      #|  Let
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) =>
      inspect(msg.contains("more than one pattern-backed"), content="true")
    Ok(_) => abort("expected multiple-ident rejection")
  }
}
