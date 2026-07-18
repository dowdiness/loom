///|
/// Whitebox tests for #521 lexer generation: golden snapshot of the emitter and
/// the generation-time validation errors.

///|
/// Read a fixture file, trying both `fixtures/X` and `loomgen/fixtures/X` so
/// the test works from both `loomgen/` and workspace root `loom/`.
fn read_fixture(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ =>
      @fs.read_file_to_string("loomgen/" + path) catch {
        _ => abort("cannot read " + path)
      }
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
test "emit_lexer rejects a token with no pattern/punct/custom_lex or default role pattern" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.delimiter
      #|  Bare
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
test "emit_lexer preserves declaration order for multiple custom hooks" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.custom_lex("lex_first")
      #|  First
      #|  #loom.literal
      #|  #loom.custom_lex("lex_second")
      #|  Second
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
  inspect(
    generated.contains(
      "match lex_first(source, pos) {\n    Done => ()\n    other => return other\n  }\n  // custom_lex hook — expected signature: (String, Int) -> @core.LexStep[T]\n  match lex_second(source, pos)",
    ),
    content="true",
  )
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
/// CodeRabbit review (emit_lexer.mbt:83): a #loom.keyword variant is
/// post-classified from the #loom.ident regex match and never lexed directly, so
/// a #loom.custom_lex on it is meaningless and rejected (it would otherwise flow
/// into codegen and never run).
test "parse_annotations rejects #loom.custom_lex on a #loom.keyword variant" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.keyword("let")
      #|  #loom.custom_lex("lex_let")
      #|  Let
      #|  #loom.eof
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
/// leading anchor binds the ENTIRE pattern, not just its first piece. The wrap is
/// the structural guarantee and is emitted for every pattern.
test "emit_lexer wraps the whole pattern in ^(?:..)" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("foo")
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
  inspect(generated.contains("re\"^(?:foo)\""), content="true")
  // The bare-anchored form (no non-capturing wrap) must NOT appear.
  inspect(generated.contains("re\"^foo\""), content="false")
}

///|
/// Codex review (emit_lexer.mbt:196): regex alternation is leftmost-match, not
/// longest-match — `re"^(?:foo|foobar)"` returns the FIRST branch (`foo`, len 3),
/// not the longest. The longest-match lexer would then split a `foobar` token, so
/// alternation is rejected at validation. A `|` inside a character class is a
/// literal, not an operator, and stays accepted.
test "parse_annotations rejects alternation in #loom.pattern" {
  let alt_src = fn(pat : String) -> String {
    "#loom.token\npub(all) enum T {\n  #loom.literal\n  #loom.pattern(\"" +
    pat +
    "\")\n  Tok\n  #loom.eof\n  E\n} derive(Eq)"
  }
  expect_parse_err(alt_src("foo|bar"), "alternation")
  expect_parse_err(alt_src("foo|foobar"), "alternation")
  match parse_annotations(alt_src("[a|b]+")) {
    Ok(_) => ()
    Err(m) => abort("expected [a|b]+ accepted, got: " + m)
  }
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

///|
/// Review P2-A: lazy quantifiers (`*?`, `+?`, `??`, `{m,n}?`) match minimally,
/// which is incompatible with a longest-match lexer (`[0-9]+?` would split `123`
/// into three tokens). They are rejected at generation time.
test "parse_annotations rejects lazy quantifiers" {
  let body = fn(pat : String) -> String {
    "#loom.token\npub(all) enum T {\n  #loom.literal\n  #loom.pattern(\"" +
    pat +
    "\")\n  Tok\n  #loom.eof\n  E\n} derive(Eq)"
  }
  expect_parse_err(body("[0-9]+?"), "lazy quantifier")
  expect_parse_err(body("a*?"), "lazy quantifier")
  expect_parse_err(body("x??"), "lazy quantifier")
  expect_parse_err(body("[0-9]{1,3}?"), "lazy quantifier")
  // Greedy / non-lazy forms stay accepted (a `?`-quantifier or `(..)?` group is
  // not a lazy modifier).
  match parse_annotations(body("a?b")) {
    Ok(_) => ()
    Err(m) => abort("expected a?b accepted, got: " + m)
  }
  match parse_annotations(body("(ab)?baz")) {
    Ok(_) => ()
    Err(m) => abort("expected (ab)?baz accepted, got: " + m)
  }
}

///|
/// Review P2-B: a pattern that statically matches exactly one character (`.`,
/// `[0-9]`) makes MoonBit's `... as m` binder a `Char`, which has no `.length()`.
/// The emitter computes the span from the `after=` remainder instead, so the
/// generated lexer type-checks for single-character patterns.
test "emit_lexer computes span via after= (no Char-typed .length() binder)" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern(".")
      #|  Dot
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(generated.contains("after=rest"), content="true")
  inspect(generated.contains("view.length() - rest.length()"), content="true")
  // The Char-fragile `as m` / `m.length()` form must NOT be emitted.
  inspect(generated.contains("m.length()"), content="false")
}

///|
/// Review (escapes): Perl-style character-class escapes (`\d`, `\D`, `\s`, `\S`,
/// `\w`, `\W`) are rejected by the re dialect, so emitting them verbatim would
/// produce a non-compiling lexer. Reject them at generation time, pointing to the
/// POSIX-class equivalents. `\x41` and literal escapes stay accepted.
test "parse_annotations rejects Perl character-class escapes" {
  let body = fn(pat : String) -> String {
    "#loom.token\npub(all) enum T {\n  #loom.literal\n  #loom.pattern(\"" +
    pat +
    "\")\n  Tok\n  #loom.eof\n  E\n} derive(Eq)"
  }
  expect_parse_err(body("\\d+"), "character-class escape")
  expect_parse_err(body("\\s"), "character-class escape")
  expect_parse_err(body("\\w"), "character-class escape")
  expect_parse_err(body("\\D"), "character-class escape")
  // Hex escape and literal escapes remain accepted.
  match parse_annotations(body("\\x41")) {
    Ok(_) => ()
    Err(m) => abort("expected \\x41 accepted, got: " + m)
  }
}

///|
/// Review (counted quantifier): an unterminated `{` (e.g. `a{2`) is rejected by
/// the re dialect, so it must not be emitted. A complete `{m,n}` stays accepted.
test "parse_annotations rejects an unterminated counted quantifier" {
  let body = fn(pat : String) -> String {
    "#loom.token\npub(all) enum T {\n  #loom.literal\n  #loom.pattern(\"" +
    pat +
    "\")\n  Tok\n  #loom.eof\n  E\n} derive(Eq)"
  }
  expect_parse_err(body("a{2"), "unterminated counted quantifier")
  match parse_annotations(body("a{2,4}")) {
    Ok(_) => ()
    Err(m) => abort("expected a{2,4} accepted, got: " + m)
  }
}

///|
/// Review (keyword payload): keywords are post-classified as nullary constructors
/// (`"let" => Let`), so a payload-bearing keyword variant would emit a call the
/// generated lexer cannot type-check — rejected.
test "emit_lexer rejects a payload-bearing #loom.keyword variant" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  #loom.pattern("[a-z]+")
      #|  Id
      #|  #loom.keyword("let")
      #|  Let(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) => inspect(msg.contains("constructor arguments"), content="true")
    Ok(_) => abort("expected payload-bearing-keyword rejection")
  }
}

// ── Default pattern tests (#635) ───────────────────────────────────────

///|
test "emit_lexer generates default ident pattern for bare #loom.ident" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  Ident
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  // The default ident pattern should be [a-zA-Z_][a-zA-Z0-9_]*
  // Escape the backslash characters in the MoonBit string: [a-zA-Z_][a-zA-Z0-9_]*
  inspect(
    generated.contains("re\"^(?:[a-zA-Z_][a-zA-Z0-9_]*)\""),
    content="true",
  )
}

///|
test "emit_lexer generates default trivia pattern for bare #loom.trivia" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.trivia
      #|  Whitespace
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  inspect(generated.contains("re\"^(?:[ \\t\\r\\n]+)\""), content="true")
}

///|
test "emit_lexer generates default literal pattern for bare #loom.literal" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  Number
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  // The default literal pattern [0-9]+(\.[0-9]+)? appears as \. in the re literal
  inspect(generated.contains("re\"^(?:[0-9]+(\\.[0-9]+)?)\""), content="true")
}

///|
test "emit_lexer keyword classification works with default-pattern ident" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  Ident
      #|  #loom.keyword("let")
      #|  Let
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  // Should have keyword classification: best_ident + keyword match
  inspect(generated.contains("best_ident = true"), content="true")
  inspect(generated.contains("\"let\" => Let"), content="true")
}

///|
test "emit_lexer golden matches fixtures/default_lex_fixture.g.mbt" {
  let src = read_fixture("fixtures/default_lex_fixture.mbt")
  let golden = read_fixture("fixtures/default_lex_fixture.g.mbt")
  let te = token_enum_of(src)
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(m) => abort("emit failed: " + m)
  }
  assert_eq(generated, golden)
}

// ── #561 line_pattern / line_mode tests ──────────────────────────────

///|
/// Helper: parse a fixture file that has both #loom.token and #loom.term enums.
fn full_enums_of(src : String) -> (EnumDecl, EnumDecl) {
  match parse_annotations(src) {
    Ok(a) =>
      (
        match a.token_enum {
          Some(te) => te
          None => abort("no token enum parsed")
        },
        match a.term_enum {
          Some(te) => te
          None => abort("no term enum parsed")
        },
      )
    Err(m) => abort("parse failed: " + m)
  }
}

///|
/// Extract the full `fn NAME(...) { ... }` block starting at `start` (the index
/// of `fn NAME`), matching braces so nested bodies are included. Order-independent:
/// the result is the single function that begins at `start`, regardless of where
/// it sits relative to other functions.
fn extract_fn_block(src : String, start : Int) -> String {
  let rel = src[start:].find("{")
  guard rel is Some(r) else { return "" }
  let mut depth = 0
  let mut i = start + r
  let n = src.length()
  while i < n {
    let ch = src[i]
    if ch == '{' {
      depth = depth + 1
    } else if ch == '}' {
      depth = depth - 1
      if depth == 0 {
        return src[start:i + 1].to_owned()
      }
    }
    i = i + 1
  }
  src[start:].to_owned()
}

///|
test "emit_line_lexer generates line-mode lexer functions for line_pattern tokens" {
  let src = read_fixture("fixtures/line_pattern_fixture.mbt")
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("emit_line_lexer returned None")
  }
  // Should contain the lex_line_start function
  // Should contain custom_lex call for HeadingMarker
  inspect(
    generated.contains("lex_heading_marker(source, pos, len)"),
    content="true",
  )
  // Should contain pattern checks for each line_pattern token
  inspect(generated.contains("ListMarkerDash"), content="true")
  inspect(generated.contains("ListMarkerStar"), content="true")
  inspect(generated.contains("ListMarkerPlus"), content="true")
  inspect(generated.contains("ThematicBreak"), content="true")
  inspect(generated.contains("BlockQuoteMarker"), content="true")
  // Should contain the regex patterns
  inspect(generated.contains("re\"^"), content="true")
  inspect(generated.contains("#{1,6} "), content="true")
  // Check ListMarkerDash uses escaped hyphen in regex
  inspect(generated.contains("\\- "), content="true")
  // Should NOT contain Inline mode function (only LineStart has #loom.line_mode)
  inspect(generated.contains("fn lex_inline"), content="false")
  // Should return Done when pos >= length
  inspect(generated.contains("return (Done, LineStart)"), content="true")
  // The fixture declares a fallback for LineStart.
  inspect(generated.contains("return lex_inline(source, pos)"), content="true")
  inspect(
    generated.contains("Not a block-level token (line_pattern)"),
    content="false",
  )
}

///|
test "emit_line_lexer emits generated_lex_<mode> helpers, not lex_<mode>" {
  let src = read_fixture("fixtures/line_pattern_fixture.mbt")
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("emit_line_lexer returned None")
  }
  // Generated line helpers use the `generated_lex_<mode>` prefix so they do not
  // collide with the user-owned `lex_<mode>` override points in the skeleton.
  inspect(generated.contains("fn generated_lex_line_start"), content="true")
  inspect(generated.contains("fn lex_line_start"), content="false")
}

///|
test "emit_line_lexer returns None when no line_pattern variants exist" {
  let src = read_fixture("fixtures/pattern_lexer_fixture.mbt")
  match parse_annotations(src) {
    Ok(a) =>
      match a.token_enum {
        Some(te) => {
          let result = emit_line_lexer(te, a.term_enum, "@core")
          guard result is None else {
            fail("expected None for pattern-only fixture")
          }
        }
        None => abort("no token enum")
      }
    Err(m) => abort("parse failed: " + m)
  }
}

///|
test "emit_line_lexer returns None when no term enum has line_mode" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("^test")
    #|  TestToken
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("Inline")
    #|  SomeNode
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, term_enum) = full_enums_of(src)
  guard emit_line_lexer(te, Some(term_enum), "@core") is None else {
    fail("expected None when no mode has line_mode")
  }
}

///|
test "parse_annotations rejects #loom.line_pattern with #loom.keyword" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.keyword("let")
    #|  #loom.line_pattern("^let")
    #|  Let
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Err(msg) => inspect(msg.contains("#loom.keyword"), content="true")
    Ok(_) => abort("expected rejection")
  }
}

///|
test "parse_annotations rejects #loom.line_pattern with #loom.error" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("^test")
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  expect_parse_err(src, "#loom.error")
}

///|
test "parse_annotations rejects #loom.line_pattern with #loom.ident" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("^test")
    #|  #loom.ident
    #|  Ident
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  expect_parse_err(src, "#loom.ident")
}

///|
test "parse_annotations rejects both #loom.pattern and #loom.line_pattern" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("^>")
    #|  #loom.pattern("^>")
    #|  BlockQuoteMarker
    #|} derive(Eq)
  expect_parse_err(
    src, "variant BlockQuoteMarker has both #loom.pattern and #loom.line_pattern; a token cannot be produced by both the character-level and line-mode lexer",
  )
}

///|
test "parse_annotations rejects nullable #loom.line_pattern" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("a*")
    #|  A
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Err(msg) => inspect(msg.contains("nullable"), content="true")
    Ok(_) => abort("expected rejection")
  }
}

///|
test "parse_annotations rejects #loom.line_pattern on #loom.eof" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("^test")
    #|  Test
    #|  #loom.eof
    #|  #loom.line_pattern("^$")
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Err(msg) => inspect(msg.contains("#loom.eof"), content="true")
    Ok(_) => abort("expected rejection")
  }
}

///|
test "parse_annotations rejects #loom.line_pattern with payload but no #loom.custom_lex" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("#{1,6} ")
    #|  HeadingMarker(Int)
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
  match parse_annotations(src) {
    Err(msg) => inspect(msg.contains("#loom.custom_lex"), content="true")
    Ok(_) =>
      abort(
        "expected rejection for payload-carrying line_pattern without custom_lex",
      )
  }
}

///|
test "emit_line_lexer golden matches fixtures/line_pattern_fixture.g.mbt" {
  let src = read_fixture("fixtures/line_pattern_fixture.mbt")
  let golden = read_fixture("fixtures/line_pattern_fixture.g.mbt")
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("emit_line_lexer returned None")
  }
  assert_eq(generated, golden)
}

///|

///|
test "emit_line_lexer emits declared fallback for line-mode no-match" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern(">")
    #|  BlockQuoteMarker
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  #loom.fallback_lex("lex_inline")
    #|  Heading
    #|  #loom.leaf
    #|  #loom.lexmode("BlockQuoteLineStart")
    #|  #loom.line_mode
    #|  BlockQuote
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("emit_line_lexer returned None")
  }
  let line_start_idx = generated.find("fn generated_lex_line_start")
  let bq_start_idx = generated.find("fn generated_lex_block_quote_line_start")
  guard line_start_idx is Some(ls) && bq_start_idx is Some(bq) else {
    fail("expected both line-mode functions in output")
  }
  let line_start_section = extract_fn_block(generated, ls)
  let bq_section = extract_fn_block(generated, bq)
  inspect(
    line_start_section.contains("return lex_inline(source, pos)"),
    content="true",
  )
  inspect(
    line_start_section.contains("Not a block-level token (line_pattern)"),
    content="false",
  )
  inspect(
    bq_section.contains("return lex_inline(source, pos)"),
    content="false",
  )
  inspect(
    bq_section.contains("Not a block-level token (line_pattern)"),
    content="true",
  )
}

///|
test "parse_annotations rejects fallback_lex on token variants" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.line_pattern(">")
      #|  #loom.fallback_lex("lex_inline")
      #|  BlockQuoteMarker
      #|  #loom.error
      #|  Error(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "only valid on #loom.term variants",
  )
}

///|
test "parse_annotations rejects fallback_lex without line_mode" {
  expect_parse_err(
    (
      #|#loom.term
      #|pub(all) enum Term {
      #|  #loom.leaf
      #|  #loom.lexmode("LineStart")
      #|  #loom.fallback_lex("lex_inline")
      #|  Node
      #|  #loom.root
      #|  Root
      #|  #loom.errornode
      #|  ErrorNode
      #|} derive(Eq)
    ),
    "without #loom.line_mode",
  )
}

///|
test "parse_annotations validates fallback_lex function references" {
  let source = fn(name : String) -> String {
    "#loom.term\npub(all) enum Term {\n" +
    "  #loom.leaf\n" +
    "  #loom.lexmode(\"LineStart\")\n" +
    "  #loom.line_mode\n" +
    "  #loom.fallback_lex(\"" +
    name +
    "\")\n" +
    "  Node\n" +
    "  #loom.root\n" +
    "  Root\n" +
    "  #loom.errornode\n" +
    "  ErrorNode\n" +
    "} derive(Eq)"
  }
  expect_parse_err(source("bad name)"), "not a valid function name")
  expect_parse_err(source("a..b"), "not a valid function name")
  match parse_annotations(source("@pkg.fn")) {
    Ok(a) =>
      match a.term_enum {
        Some(term) =>
          match term.variants[0].fallback_lex {
            Some(name) => inspect(name, content="@pkg.fn")
            None => abort("fallback_lex metadata missing")
          }
        None => abort("term enum missing")
      }
    Err(msg) => abort("qualified fallback_lex was rejected: " + msg)
  }
}

///|
test "parse_annotations rejects conflicting mode fallbacks" {
  expect_parse_err(
    (
      #|#loom.term
      #|pub(all) enum Term {
      #|  #loom.leaf
      #|  #loom.lexmode("LineStart")
      #|  #loom.line_mode
      #|  #loom.fallback_lex("lex_inline")
      #|  First
      #|  #loom.leaf
      #|  #loom.lexmode("LineStart")
      #|  #loom.line_mode
      #|  #loom.fallback_lex("lex_other")
      #|  Second
      #|  #loom.root
      #|  Root
      #|  #loom.errornode
      #|  ErrorNode
      #|} derive(Eq)
    ),
    "conflicting #loom.fallback_lex",
  )
}

///|
test "emit_line_lexer accepts #loom.line_pattern with #loom.custom_lex" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("#{1,6} ")
    #|  #loom.custom_lex("lex_heading")
    #|  HeadingMarker(Int)
    #|  #loom.line_pattern(">")
    #|  BlockQuoteMarker
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  Heading
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(value) => value
    None => fail("expected Some for valid line_pattern with custom_lex")
  }
  inspect(generated.contains("lex_heading(source, pos, len)"), content="true")
  inspect(generated.contains("next_offset=pos + len"), content="true")
}

///|
test "emit_line_lexer rejects malformed fully annotated payload" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("(#{1,6}) ")
    #|  #loom.payload("$1 +")
    #|  HeadingMarker(Int)
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  Heading
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, _) = full_enums_of(src)
  let candidates = collect_line_patterns(te).unwrap()
  let mut raised = false
  emit_mode_line_lexer(
    StringBuilder(),
    "LineStart",
    candidates,
    "T",
    "@core",
    "generated_line_start",
    None,
  ) catch {
    PayloadExprError::Invalid(_) => raised = true
    _ => raised = true
  }
  inspect(raised, content="true")
}

///|
test "emit_line_lexer filters candidates by mode via lexmode_name" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("#{1,6} ")
    #|  HeadingMarker
    #|  #loom.line_pattern(">")
    #|  #loom.lexmode("BlockQuoteLineStart")
    #|  BlockQuoteMarker
    #|  #loom.line_pattern("--- ")
    #|  ThematicBreak
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  Heading
    #|  #loom.leaf
    #|  #loom.lexmode("BlockQuoteLineStart")
    #|  #loom.line_mode
    #|  BlockQuote
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("emit_line_lexer returned None")
  }
  // lex_line_start should include HeadingMarker and ThematicBreak (no lexmode constraint)
  inspect(generated.contains("HeadingMarker"), content="true")
  inspect(generated.contains("ThematicBreak"), content="true")
  // lex_line_start should NOT include BlockQuoteMarker (assigned to BlockQuoteLineStart)
  // Check that lex_line_start function body contains neither the name nor its pattern
  inspect(generated.contains("fn generated_lex_line_start"), content="true")
  inspect(
    generated.contains("fn generated_lex_block_quote_line_start"),
    content="true",
  )
  // BlockQuoteMarker should only appear in the block_quote_line_start function.
  let line_start_idx = generated.find("fn generated_lex_line_start")
  let bq_start_idx = generated.find("fn generated_lex_block_quote_line_start")
  guard line_start_idx is Some(ls) && bq_start_idx is Some(bq) else {
    fail("expected both lex functions in output")
  }
  let line_start_section = extract_fn_block(generated, ls)
  inspect(line_start_section.contains("BlockQuoteMarker"), content="false")
  let bq_section = extract_fn_block(generated, bq)
  inspect(bq_section.contains("BlockQuoteMarker"), content="true")
  // Neither mode declares a fallback, so each mode retains Invalid handling.
  inspect(
    line_start_section.contains("Not a block-level token (line_pattern)"),
    content="true",
  )
  inspect(
    bq_section.contains("Not a block-level token (line_pattern)"),
    content="true",
  )
}

///|
test "line_lexer_shares_syntax_output accepts equivalent package directories" {
  assert_true(line_lexer_shares_syntax_output("line_lexer.g.mbt", "."))
  assert_true(
    line_lexer_shares_syntax_output("./syntax/line_lexer.g.mbt", "syntax/"),
  )
  assert_true(
    line_lexer_shares_syntax_output(
      "syntax/nested/line_lexer.g.mbt", "syntax/nested",
    ),
  )
  assert_true(
    line_lexer_shares_syntax_output("/abs/path/line_lexer.g.mbt", "/abs/path"),
  )
}

///|
test "line_lexer_shares_syntax_output rejects other package directories" {
  assert_true(
    !line_lexer_shares_syntax_output("token/line_lexer.g.mbt", "syntax"),
  )
  assert_true(!line_lexer_shares_syntax_output("/line_lexer.g.mbt", "/"))
}

///|
test "emit_line_lexer inlines fully annotated payloads" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("(#{1,6}) ")
    #|  #loom.payload("$1.length()")
    #|  HeadingMarker(Int)
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  Heading
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("expected line lexer")
  }
  inspect(generated.contains("HeadingMarker(\n"), content="true")
  inspect(
    generated.contains("m.group(1).unwrap_or(\"\").length()"),
    content="true",
  )
  let (_, diagnostics) = @parser.parse_string(generated)
  inspect(diagnostics.length(), content="0")
}

///|
test "emit_line_lexer keeps None arm inside payload match" {
  let src =
    #|#loom.token
    #|pub(all) enum T {
    #|  #loom.line_pattern("(a+)")
    #|  #loom.payload("$1.length() // line")
    #|  A(Int)
    #|  #loom.error
    #|  Error(String)
    #|  #loom.eof
    #|  E
    #|} derive(Eq)
    #|#loom.term
    #|pub(all) enum Term {
    #|  #loom.leaf
    #|  #loom.lexmode("LineStart")
    #|  #loom.line_mode
    #|  ANode
    #|  #loom.root
    #|  Root
    #|  #loom.errornode
    #|  ErrorNode
    #|} derive(Eq)
  let (te, term_enum) = full_enums_of(src)
  let generated = match emit_line_lexer(te, Some(term_enum), "@core") {
    Some(s) => s
    None => abort("expected line lexer")
  }
  inspect(generated.contains("    }\n    None => ()\n  }"), content="true")
  let (_, diagnostics) = @parser.parse_string(generated)
  inspect(diagnostics.length(), content="0")
}

///|
test "parse_annotations rejects payload-bearing punctuation" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.punct("+")
      #|  #loom.payload("$0.to_owned()")
      #|  Plus(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "punct",
  )
}

///|
test "emit_lexer preserves payload line comments before delimiters" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(a)")
      #|  #loom.payload("$1.to_owned() // trim")
      #|  A(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(msg) => abort(msg)
  }
  inspect(generated.contains("A(\n"), content="true")
  let (_, diagnostics) = @parser.parse_string(generated)
  inspect(diagnostics.length(), content="0")
}

///|
test "emit_lexer keeps multi-field payload comments parseable" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(a)(b)")
      #|  #loom.payload("$1.to_owned() // first")
      #|  #loom.payload("$2.to_owned()")
      #|  Pair(String, String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(msg) => abort(msg)
  }
  let (_, diagnostics) = @parser.parse_string(generated)
  inspect(diagnostics.length(), content="0")
  inspect(generated.contains("Pair(\n"), content="true")
}

///|
test "emit_lexer inlines fully annotated payload pattern" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("([a-z]+)")
      #|  #loom.payload("$1.to_owned()")
      #|  Word(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  let generated = match emit_lexer(te, "@core", "step_lex") {
    Ok(s) => s
    Err(msg) => abort(msg)
  }
  inspect(generated.contains("Word(\n"), content="true")
  inspect(
    generated.contains("m.group(1).unwrap_or(\"\").to_owned()"),
    content="true",
  )
  let (_, diagnostics) = @parser.parse_string(generated)
  inspect(diagnostics.length(), content="0")
}

///|
test "parse_annotations rejects payload capture overflow" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(a)")
      #|  #loom.payload("$2")
      #|  Word(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "references capture group $2",
  )
}

///|
test "emit_lexer rejects payload capture overflow in a default pattern" {
  let te = token_enum_of(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.ident
      #|  #loom.payload("$1")
      #|  Ident(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
  )
  match emit_lexer(te, "@core", "step_lex") {
    Err(msg) =>
      inspect(msg.contains("references capture group $1"), content="true")
    Ok(_) => abort("expected default-pattern capture overflow rejection")
  }
}

///|
test "parse_annotations rejects payload without one string argument" {
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(a)")
      #|  #loom.payload
      #|  Word(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "requires exactly 1 string argument",
  )
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(a)")
      #|  #loom.payload(123)
      #|  Word(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "invalid arguments for #loom.payload",
  )
  expect_parse_err(
    (
      #|#loom.token
      #|pub(all) enum T {
      #|  #loom.literal
      #|  #loom.pattern("(a)")
      #|  #loom.payload("a", "b")
      #|  Word(String)
      #|  #loom.eof
      #|  E
      #|} derive(Eq)
    ),
    "requires exactly 1 string argument",
  )
}

///|
test "parse_annotations rejects payload on term variants" {
  expect_parse_err(
    (
      #|#loom.term
      #|pub(all) enum Term {
      #|  #loom.leaf
      #|  #loom.payload("$1")
      #|  Node
      #|} derive(Eq)
    ),
    "cannot have #loom.payload",
  )
}
