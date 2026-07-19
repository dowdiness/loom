///|
/// Parser for the standalone `.loomgrammar` file (#523) — the scale-up from
/// `#loom.rule` annotation strings to a dedicated grammar file for languages with
/// more than a handful of productions.
///
/// The file uses the SAME notation subset as `#loom.rule` (`Seq`, `Choice` via
/// `|`, `Ref`, `*`/`+`/`?`, terminal refs, `@fragment` refs) and produces the same
/// `RuleAst`, so the entire recursive-descent body parser (`RuleParser::parse_alt`
/// and friends in `parse_rule_string.mbt`) is reused verbatim. What the file adds
/// over an annotation string is purely lexical:
///
/// ```text
///   grammar := production*
///   production := IDENT '=' alt          // '=' separates a name from its body
///   alt        := '|'? seq ('|' seq)*    // a leading '|' is allowed for multi-line layout
/// ```
///
/// plus `//` line comments and multi-line bodies (newlines are whitespace). A body
/// runs from its `=` to the next `IDENT '='` header (two-token lookahead) or EOF,
/// which is unambiguous because `=` never appears inside the notation. Errors carry
/// the production's line so diagnostics point at file positions, not annotation
/// offsets. The parser fails closed: any lexical or structural error aborts the
/// whole file rather than emitting a partial grammar.

///|
/// A file-level token: either a reused `#loom.rule` body token, or the `=` that
/// separates a production name from its body. Kept distinct from `RuleTok` so the
/// shared notation token type is not polluted with a file-only separator.
enum GFileTok {
  GRule(RuleTok)
  GAssign
} derive(Eq, Debug)

///|
/// A lexed file token tagged with its 1-based source line, for file-position
/// diagnostics.
struct GFileLexed {
  tok : GFileTok
  line : Int
} derive(Eq, Debug)

///|
suberror GrammarFileError {
  GrammarFileError(String)
}

///|
/// `"line N: "` — the file-position prefix shared by every `.loomgrammar`
/// diagnostic. (The file path is prepended by the caller, which knows it.)
fn grammar_file_loc(line : Int) -> String {
  "line " + line.to_string() + ": "
}

///|
/// Human-readable description of a file token for "expected … found X" messages.
fn describe_gfile_tok(t : GFileTok) -> String {
  match t {
    GAssign => "'='"
    GRule(TIdent(n)) => "identifier '" + n + "'"
    GRule(TFrag(n)) => "fragment '@" + n + "'"
    GRule(TNative) => "'@native()'"
    GRule(TLParen) => "'('"
    GRule(TRParen) => "')'"
    GRule(TPipe) => "'|'"
    GRule(TStar) => "'*'"
    GRule(TPlus) => "'+'"
    GRule(TQuest) => "'?'"
    GRule(TTilde) => "'~'"
    GRule(TEmitor) => "'!'"
    GRule(TExpectSkip) => "'~>'"
    GRule(TUntil) => "'@until()'"
    GRule(TErrorNode) => "'@error_node()'"
    GRule(TPrefix) => "'@prefix'"
    GRule(TApp) => "'@app'"
    GRule(TPrec) => "'@prec'"
    GRule(TSkip) => "'@skip'"
    GRule(TLBracket) => "'['"
    GRule(TRBracket) => "']'"
    GRule(TLBrace) => "'{'"
    GRule(TRBrace) => "'}'"
    GRule(TComma) => "','"
  }
}

///|
/// Tokenize a `.loomgrammar` source into `(token, line)` pairs, skipping
/// whitespace and `//` line comments. Reuses the rule-notation character classes
/// and `scan_ident`; the only file-level additions are the `=` separator and
/// comments. Fails closed on any unexpected character.
fn tokenize_grammar_file(
  src : String,
) -> Array[GFileLexed] raise GrammarFileError {
  let toks : Array[GFileLexed] = []
  let mut i = 0
  let mut line = 1
  let len = src.length()
  while i < len {
    let c = src[i]
    if c == '\n' {
      line = line + 1
      i = i + 1
    } else if c == ' ' || c == '\t' || c == '\r' {
      i = i + 1
    } else if c == '/' && i + 1 < len && src[i + 1] == '/' {
      // `//` line comment — skip to (but not past) the newline; the loop's
      // newline arm advances `line`.
      i = i + 2
      while i < len && src[i] != '\n' {
        i = i + 1
      }
    } else if c == '=' {
      toks.push({ tok: GAssign, line })
      i = i + 1
    } else if is_rule_ident_start(c) {
      let (name, next) = scan_ident(src, i)
      toks.push({ tok: GRule(TIdent(name)), line })
      i = next
    } else if c == '@' {
      if i + 1 >= len || !is_rule_ident_start(src[i + 1]) {
        raise GrammarFileError(
          grammar_file_loc(line) + "'@' must be followed by a fragment name",
        )
      }
      let (name, next) = scan_ident(src, i + 1)
      match rule_at_keyword(name) {
        Some(kw) => toks.push({ tok: GRule(kw), line })
        None => toks.push({ tok: GRule(TFrag(name)), line })
      }
      i = next
    } else {
      let rt = match c {
        '(' => TLParen
        ')' => TRParen
        '|' => TPipe
        '*' => TStar
        '+' => TPlus
        '?' => TQuest
        '~' =>
          if i + 1 < len && src[i + 1] == '>' {
            i = i + 1
            TExpectSkip
          } else {
            TTilde
          }
        '!' => TEmitor
        '{' => TLBrace
        '}' => TRBrace
        '[' => TLBracket
        ']' => TRBracket
        ',' => TComma
        _ =>
          raise GrammarFileError(
            grammar_file_loc(line) +
            "unexpected character '" +
            src[i:i + 1].to_owned() +
            "' in grammar file",
          )
      }
      toks.push({ tok: GRule(rt), line })
      i = i + 1
    }
  }
  toks
}

///|
/// Whether `lexed[k]` begins a new production header — an `IDENT` immediately
/// followed by `=`. This two-token lookahead is what delimits one production's
/// body from the next, and is unambiguous because `=` never appears inside a body.
fn is_header_at(lexed : Array[GFileLexed], k : Int) -> Bool {
  k + 1 < lexed.length() &&
  lexed[k].tok is GRule(TIdent(_)) &&
  lexed[k + 1].tok == GAssign
}

///|
/// Whether `lexed[k]` is the first token on its physical source line.
/// Indentation is allowed; only the line transition matters.
fn is_first_token_on_line(lexed : Array[GFileLexed], k : Int) -> Bool {
  k == 0 || lexed[k - 1].line < lexed[k].line
}

///|
/// Whether `lexed[k]` begins a new production header for body delimiting.
/// A physical-line boundary takes precedence over whole-file parenthesis
/// matching, so malformed parentheses cannot attribute a later production to
/// the preceding one.
fn is_body_boundary_at(lexed : Array[GFileLexed], k : Int) -> Bool {
  is_first_token_on_line(lexed, k) && is_header_at(lexed, k)
}

///|
/// Parse a complete `.loomgrammar` source into an ordered list of
/// `(name, body, line)` productions, reusing the `#loom.rule` body parser. Returns
/// a fail-closed error message (with a `line N:` prefix) on any problem. The order
/// is preserved so downstream GrammarIr emission is deterministic.
fn parse_grammar_file(
  src : String,
) -> Result[Array[(String, RuleAst, Int)], String] {
  let lexed = tokenize_grammar_file(src) catch {
    GrammarFileError(m) => return Err(m)
  }
  guard lexed.length() > 0 else {
    return Err(
      "grammar file has no productions (expected at least one 'Name = body')",
    )
  }
  let prods : Array[(String, RuleAst, Int)] = []
  let seen : @hashset.HashSet[String] = @hashset.HashSet([])
  let mut i = 0
  let n = lexed.length()
  while i < n {
    // Header: IDENT '='.
    let (name, name_line) = match lexed[i] {
      { tok: GRule(TIdent(nm)), line } => (nm, line)
      { tok, line } =>
        return Err(
          grammar_file_loc(line) +
          "expected a production name, found " +
          describe_gfile_tok(tok),
        )
    }
    guard i + 1 < n && lexed[i + 1].tok == GAssign else {
      return Err(
        grammar_file_loc(name_line) +
        "expected '=' after production name '" +
        name +
        "'",
      )
    }
    guard !seen.contains(name) else {
      return Err(
        grammar_file_loc(name_line) +
        "duplicate production '" +
        name +
        "' — each rule name must be unique in a grammar file",
      )
    }
    seen.add(name)
    // Body: every token from after the '=' up to the next production header or
    // EOF. A header at the first token of a physical line is a boundary even
    // inside an open group; same-line `IDENT '='` pairs remain body tokens.
    let body : Array[RuleTok] = []
    let mut j = i + 2
    while j < n {
      if is_body_boundary_at(lexed, j) {
        break
      }
      match lexed[j].tok {
        GRule(rt) => body.push(rt)
        GAssign =>
          return Err(
            grammar_file_loc(lexed[j].line) +
            "unexpected '=' inside the body of production '" +
            name +
            "'",
          )
      }
      j = j + 1
    }
    guard body.length() > 0 else {
      return Err(
        grammar_file_loc(name_line) +
        "production '" +
        name +
        "' has an empty body",
      )
    }
    // A body consisting solely of a leading '|' is also empty — the pipe is
    // optional layout sugar, not an alternative, so nothing follows it.
    guard !(body.length() == 1 && body[0] is TPipe) else {
      return Err(
        grammar_file_loc(name_line) +
        "production '" +
        name +
        "' has an empty body",
      )
    }
    // Reuse the #522 / #601 body parser. A leading '|' (allowed for multi-line
    // alternation layout) is skipped by starting the parser past it. Pratt
    // bodies (`@prefix ...`) use the dedicated `parse_pratt_body` path.
    let parser = RuleParser(body)
    let start_pos = if body[0] is TPipe { 1 } else { 0 }
    parser.pos = start_pos
    let ast = if body.length() > start_pos && body[start_pos] is TPrefix {
      parser.parse_pratt_body() catch {
        RuleParseError(m) =>
          return Err(
            grammar_file_loc(name_line) + "in production '" + name + "': " + m,
          )
      }
    } else {
      parser.parse_alt() catch {
        RuleParseError(m) =>
          return Err(
            grammar_file_loc(name_line) + "in production '" + name + "': " + m,
          )
      }
    }
    guard parser.pos == body.length() else {
      return Err(
        grammar_file_loc(name_line) +
        "in production '" +
        name +
        "': trailing tokens after a complete rule",
      )
    }
    prods.push((name, ast, name_line))
    i = j
  }
  Ok(prods)
}
