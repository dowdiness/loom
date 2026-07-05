///|
/// Mini-parser for the `#loom.rule` EBNF-subset notation (#522).
///
/// Grammar (recursive descent, LL(1)):
/// ```text
///   rule    := alt
///   alt     := seq ('|' seq)*
///   seq     := postfix+
///   postfix := atom ('*' | '+' | '?' | '~' | '!')?
///   atom    := IDENT | '@' IDENT | '@until' '(' IDENT ('|' IDENT)* ')' | '(' alt ')'
/// ```
/// An IDENT is resolved to a token terminal or a rule `Ref` later, at lowering
/// time (the notation parser does not know the grammar vocabulary). A leading
/// `@` marks a hand-authored fragment reference. The parser fails closed on any
/// lexical or structural error so an unparseable rule never reaches the emitter.

///|
/// Parsed notation tree. Resolution of `Sym` (terminal vs rule Ref) and the
/// FIRST-set predicates for `Alt`/`Star`/`Plus`/`Opt` are computed downstream.
enum RuleAst {
  Sym(String)
  Frag(String)
  Seq(Array[RuleAst])
  Alt(Array[RuleAst])
  Star(RuleAst)
  Plus(RuleAst)
  Opt(RuleAst)
  Emit(RuleAst)
  Emitor(RuleAst)
  ErrorUntil(Array[String])
} derive(Eq, Debug)

///|
enum RuleTok {
  TIdent(String)
  TFrag(String)
  TLParen
  TRParen
  TPipe
  TStar
  TPlus
  TQuest
  TTilde
  TEmitor
  TUntil
} derive(Eq, Debug)

///|
suberror RuleParseError {
  RuleParseError(String)
}

///|
/// Whether `s` is a valid (ASCII) MoonBit value identifier: non-empty, a leading
/// letter or `_`, then letters/digits/`_`. Used to validate `--language` before
/// it is spliced into a generated `pub let <lang>_grammar_ir` name.
fn is_mbt_identifier(s : String) -> Bool {
  guard s.length() > 0 && is_rule_ident_start(s[0]) else { return false }
  for i in 1..<s.length() {
    if !is_rule_ident_char(s[i]) {
      return false
    }
  }
  true
}

///|
/// Scan an identifier starting at `pos` (which satisfies `is_rule_ident_start`),
/// returning the identifier text and the index just past it.
fn scan_ident(s : String, pos : Int) -> (String, Int) {
  let mut i = pos + 1
  while i < s.length() && is_rule_ident_char(s[i]) {
    i = i + 1
  }
  (s[pos:i].to_owned(), i)
}

///|
/// Tokenize a rule string, or fail closed on an unexpected character.
fn tokenize_rule(s : String) -> Array[RuleTok] raise RuleParseError {
  let toks : Array[RuleTok] = []
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i = i + 1
    } else if is_rule_ident_start(c) {
      let (name, next) = scan_ident(s, i)
      toks.push(TIdent(name))
      i = next
    } else if c == '@' {
      if i + 1 >= s.length() || !is_rule_ident_start(s[i + 1]) {
        raise RuleParseError("'@' must be followed by a keyword or fragment name")
      }
      let (name, next) = scan_ident(s, i + 1)
      if name == "until" {
        toks.push(TUntil)
      } else {
        toks.push(TFrag(name))
      }
      i = next
    } else {
      let tok = match c {
        '(' => TLParen
        ')' => TRParen
        '|' => TPipe
        '*' => TStar
        '+' => TPlus
        '?' => TQuest
        '~' => TTilde
        '!' => TEmitor
        _ =>
          raise RuleParseError(
            "unexpected character '" + s[i:i + 1].to_owned() + "' in rule",
          )
      }
      toks.push(tok)
      i = i + 1
    }
  }
  toks
}

///|
struct RuleParser {
  toks : Array[RuleTok]
  mut pos : Int
}

///|
/// A fresh parser positioned at the first token.
fn RuleParser::RuleParser(toks : Array[RuleTok]) -> RuleParser {
  { toks, pos: 0 }
}

///|
fn RuleParser::peek(self : RuleParser) -> RuleTok? {
  if self.pos < self.toks.length() {
    Some(self.toks[self.pos])
  } else {
    None
  }
}

///|
fn RuleParser::bump(self : RuleParser) -> Unit {
  self.pos = self.pos + 1
}

///|
/// `alt := seq ('|' seq)*` — one or more `|`-separated sequences.
fn RuleParser::parse_alt(self : RuleParser) -> RuleAst raise RuleParseError {
  let branches = [self.parse_seq()]
  while self.peek() is Some(TPipe) {
    self.bump()
    branches.push(self.parse_seq())
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alt(branches)
  }
}

///|
/// `seq := postfix+` — juxtaposition until `|`, `)`, or end of input. An empty
/// sequence (e.g. `()` or `(|A)`) is a structural error.
fn RuleParser::parse_seq(self : RuleParser) -> RuleAst raise RuleParseError {
  let items : Array[RuleAst] = []
  while not_seq_terminator(self.peek()) {
    items.push(self.parse_postfix())
  }
  if items.length() == 0 {
    raise RuleParseError("empty sequence (a rule fragment has no atoms)")
  }
  if items.length() == 1 {
    items[0]
  } else {
    Seq(items)
  }
}

///|
fn not_seq_terminator(tok : RuleTok?) -> Bool {
  match tok {
    None | Some(TPipe) | Some(TRParen) => false
    _ => true
  }
}

///|
/// `postfix := atom ('*' | '+' | '?' | '~' | '!')?` — at most one postfix.
fn RuleParser::parse_postfix(self : RuleParser) -> RuleAst raise RuleParseError {
  let atom = self.parse_atom()
  match self.peek() {
    Some(TStar) => {
      self.bump()
      Star(atom)
    }
    Some(TPlus) => {
      self.bump()
      Plus(atom)
    }
    Some(TQuest) => {
      self.bump()
      Opt(atom)
    }
    Some(TTilde) => {
      self.bump()
      Emit(atom)
    }
    Some(TEmitor) => {
      self.bump()
      Emitor(atom)
    }
    _ => atom
  }
}

///|
/// `atom := IDENT | '@' IDENT | '@until' '(' IDENT ('|' IDENT)* ')' | '(' alt ')'`.
fn RuleParser::parse_atom(self : RuleParser) -> RuleAst raise RuleParseError {
  match self.peek() {
    Some(TIdent(name)) => {
      self.bump()
      Sym(name)
    }
    Some(TFrag(name)) => {
      self.bump()
      Frag(name)
    }
    Some(TUntil) => {
      self.bump()
      guard self.peek() is Some(TLParen) else {
        raise RuleParseError("'@until' must be followed by '(' tokens ')'")
      }
      self.bump()
      let tokens : Array[String] = []
      while true {
        match self.peek() {
          Some(TIdent(name)) => {
            self.bump()
            tokens.push(name)
          }
          _ => {
            raise RuleParseError(
              "@until() must contain at least one token identifier",
            )
          }
        }
        match self.peek() {
          Some(TPipe) => self.bump()
          _ => break
        }
      }
      guard self.peek() is Some(TRParen) else {
        raise RuleParseError("unbalanced '@until(' — missing ')'")
      }
      self.bump()
      ErrorUntil(tokens)
    }
    Some(TLParen) => {
      self.bump()
      let inner = self.parse_alt()
      guard self.peek() is Some(TRParen) else {
        raise RuleParseError("unbalanced '(' — missing ')'")
      }
      self.bump()
      inner
    }
    Some(TStar) | Some(TPlus) | Some(TQuest) | Some(TTilde) | Some(TEmitor) =>
      raise RuleParseError("a postfix ('*', '+', '?', '~', '!') has no atom to bind")
    Some(TPipe) => raise RuleParseError("unexpected '|' with no left side")
    Some(TRParen) => raise RuleParseError("unexpected ')'")
    None => raise RuleParseError("unexpected end of rule")
  }
}

///|
/// Parse a complete `#loom.rule` string into a `RuleAst`, or return a
/// fail-closed error message. `where_` names the variant for diagnostics.
fn parse_rule_string(rule : String, where_ : String) -> Result[RuleAst, String] {
  let prefix = "#loom.rule on " + where_ + ": "
  let toks = tokenize_rule(rule) catch {
    RuleParseError(m) => return Err(prefix + m)
  }
  guard toks.length() > 0 else { return Err(prefix + "rule string is empty") }
  let parser = RuleParser(toks)
  let ast = parser.parse_alt() catch {
    RuleParseError(m) => return Err(prefix + m)
  }
  guard parser.pos == toks.length() else {
    return Err(prefix + "trailing tokens after a complete rule")
  }
  Ok(ast)
}
