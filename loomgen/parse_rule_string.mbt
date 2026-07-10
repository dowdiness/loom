///|
/// Mini-parser for the `#loom.rule` EBNF-subset notation (#522, #601).
///
/// Grammar (recursive descent, LL(1)):
/// ```text
///   rule       := pratt_body | alt
///   pratt_body := '@prefix' IDENT pratt_ann*
///   pratt_ann  := '@app' IDENT | '@prec' '[' IDENT (',' IDENT)* ']'
///              | '@skip' '(' IDENT ')'
///   alt        := seq ('|' seq)*
///   seq        := postfix+
///   postfix    := atom ('*' | '+' | '?' | '~' | '!')?

///|   atom       := IDENT | '@' IDENT | '@native' '(' IDENT ')' | '@until' '(' IDENT ('|' IDENT)* ')' | '@error_node' '(' IDENT ',' IDENT ('|' IDENT)* ')' | '(' alt ')'
/// ```
/// An IDENT is resolved to a token terminal or a rule `Ref` later, at lowering
/// time (the notation parser does not know the grammar vocabulary). A leading

///| (`until`, `native`, `prefix`, `app`, `prec`, `skip`). The parser fails closed on any
/// lexical or structural error so an unparseable rule never reaches the emitter.

///|
/// Pratt application production: left-associative juxtaposition over `@prefix`.
struct PrattAppSpec {
  prefix : String
  app_kind : String?
} derive(Eq, Debug)

///|
/// Pratt binary production: infix operators over `@prefix` with optional `@skip`.
struct PrattBinarySpec {
  prefix : String
  ops : Array[String]
  skip : String?
  app_kind : String?
} derive(Eq, Debug)

///|
/// Parsed notation tree. Resolution of `Sym` (terminal vs rule Ref) and the
/// FIRST-set predicates for `Alt`/`Star`/`Plus`/`Opt` are computed downstream.
enum RuleAst {
  Sym(String)
  Frag(String)
  Native(String)
  Seq(Array[RuleAst])
  Alt(Array[RuleAst])
  Star(RuleAst)
  Plus(RuleAst)
  Opt(RuleAst)
  Emit(RuleAst)
  Emitor(RuleAst)
  /// @error_node(Kind, Token) — consume tokens into an ErrorNode of the given
  /// Kind until the sync token is found. Variant form @error_node(Kind, A | B)
  /// accepts any of the listed tokens as the stop condition.
  ErrorNodeUntil(String, Array[String])
  ErrorUntil(Array[String])
  PrattApp(PrattAppSpec)
  PrattBinary(PrattBinarySpec)
} derive(Eq, Debug)

///|
enum RuleTok {
  TIdent(String)
  TFrag(String)
  TNative
  TLParen
  TRParen
  TPipe
  TStar
  TPlus
  TQuest
  TTilde
  TEmitor
  TErrorNode
  TUntil
  TPrefix
  TApp
  TPrec
  TSkip
  TLBracket
  TRBracket
  TComma
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
/// Map a bare `@keyword` name to a reserved Pratt/notation token, or `None` for
/// fragment references (`@fragmentName`).
fn rule_at_keyword(name : String) -> RuleTok? {
  match name {
    "error_node" => Some(TErrorNode)
    "until" => Some(TUntil)
    "native" => Some(TNative)
    "prefix" => Some(TPrefix)
    "app" => Some(TApp)
    "prec" => Some(TPrec)
    "skip" => Some(TSkip)
    _ => None
  }
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
        raise RuleParseError(
          "'@' must be followed by a keyword or fragment name",
        )
      }
      let (name, next) = scan_ident(s, i + 1)
      match rule_at_keyword(name) {
        Some(kw) => toks.push(kw)
        None => toks.push(TFrag(name))
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
        '[' => TLBracket
        ']' => TRBracket
        ',' => TComma
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
/// Parse `@prec[Op, ...]` after the `@prec` token has been consumed.
fn RuleParser::parse_prec_ops(
  self : RuleParser,
) -> Array[String] raise RuleParseError {
  guard self.peek() is Some(TLBracket) else {
    raise RuleParseError("@prec must be followed by '[' operators ']'")
  }
  self.bump()
  guard self.peek() is Some(TIdent(_)) else {
    raise RuleParseError(
      "@prec[] is empty — PrattBinary requires at least one operator",
    )
  }
  let ops : Array[String] = []
  let seen : @hashset.HashSet[String] = @hashset.HashSet([])
  while true {
    match self.peek() {
      Some(TIdent(name)) => {
        self.bump()
        if seen.contains(name) {
          raise RuleParseError(
            "duplicate operator '" + name + "' in @prec[...]",
          )
        }
        seen.add(name)
        ops.push(name)
      }
      _ => raise RuleParseError("@prec[...] must contain token identifiers")
    }
    match self.peek() {
      Some(TComma) => self.bump()
      Some(TRBracket) => {
        self.bump()
        break
      }
      _ => raise RuleParseError("expected ',' or ']' in @prec[...]")
    }
  }
  ops
}

///|
/// Parse `@skip(Tok)` after the `@skip` token has been consumed.
fn RuleParser::parse_skip_tok(self : RuleParser) -> String raise RuleParseError {
  guard self.peek() is Some(TLParen) else {
    raise RuleParseError("@skip must be followed by '(token)'")
  }
  self.bump()
  let tok_name = match self.peek() {
    Some(TIdent(name)) => {
      self.bump()
      name
    }
    _ => raise RuleParseError("@skip() must contain a token identifier")
  }
  guard self.peek() is Some(TRParen) else {
    raise RuleParseError("unbalanced '@skip(' — missing ')'")
  }
  self.bump()
  tok_name
}

///|
/// `pratt_body := '@prefix' IDENT pratt_ann*` — annotation-only production body.
fn RuleParser::parse_pratt_body(
  self : RuleParser,
) -> RuleAst raise RuleParseError {
  guard self.peek() is Some(TPrefix) else {
    raise RuleParseError("Pratt body must begin with '@prefix'")
  }
  self.bump()
  let prefix = match self.peek() {
    Some(TIdent(name)) => {
      self.bump()
      name
    }
    _ => raise RuleParseError("@prefix must be followed by a rule name")
  }
  let mut app_kind : String? = None
  let mut ops : Array[String]? = None
  let mut skip : String? = None
  let mut prec_count = 0
  while self.peek() is Some(tok) {
    match tok {
      TApp => {
        self.bump()
        match self.peek() {
          Some(TIdent(name)) => {
            self.bump()
            app_kind = Some(name)
          }
          _ => raise RuleParseError("@app must be followed by a term name")
        }
      }
      TPrec => {
        prec_count = prec_count + 1
        if prec_count > 1 {
          raise RuleParseError(
            "duplicate '@prec' — only one operator table per Pratt production",
          )
        }
        self.bump()
        ops = Some(self.parse_prec_ops())
      }
      TSkip => {
        self.bump()
        skip = Some(self.parse_skip_tok())
      }
      TPrefix => raise RuleParseError("duplicate '@prefix' in Pratt body")
      _ =>
        raise RuleParseError(
          "unexpected token in Pratt body — Pratt productions contain only '@prefix', '@prec', '@skip', and '@app' annotations",
        )
    }
  }
  match ops {
    Some(op_list) => PrattBinary({ prefix, ops: op_list, skip, app_kind })
    None => {
      if skip is Some(_) {
        raise RuleParseError(
          "@skip is only valid on PrattBinary productions with @prec[...]",
        )
      }
      PrattApp({ prefix, app_kind })
    }
  }
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
/// Reject Pratt reserved tokens inside regular EBNF atoms.
fn pratt_token_in_ebnf_err(tok : RuleTok) -> String {
  match tok {
    TPrefix => "'@prefix'"
    TApp => "'@app'"
    TPrec => "'@prec'"
    TSkip => "'@skip'"
    TLBracket => "'['"
    TRBracket => "']'"
    TComma => "','"
    _ => "a Pratt annotation"
  }
}

///|
/// `atom := IDENT | '@' IDENT | '@native' '(' IDENT ')' | '@until' '(' IDENT ('|' IDENT)* ')' | '(' alt ')'`.
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
    Some(TNative) => {
      self.bump()
      guard self.peek() is Some(TLParen) else {
        raise RuleParseError("'@native' must be followed by '(' name ')'")
      }
      self.bump()
      let name = match self.peek() {
        Some(TIdent(n)) => {
          self.bump()
          n
        }
        _ => raise RuleParseError("@native() must contain an identifier")
      }
      guard self.peek() is Some(TRParen) else {
        raise RuleParseError("unbalanced '@native(' — missing ')'")
      }
      self.bump()
      Native(name)
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
          _ =>
            raise RuleParseError(
              "@until() must contain at least one token identifier",
            )
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
    Some(TErrorNode) => {
      self.bump()
      guard self.peek() is Some(TLParen) else {
        raise RuleParseError(
          "'@error_node' must be followed by '(kind, tokens)'",
        )
      }
      self.bump()
      let kind_name = match self.peek() {
        Some(TIdent(n)) => {
          self.bump()
          n
        }
        _ =>
          raise RuleParseError("@error_node() must contain a kind identifier")
      }
      guard self.peek() is Some(TComma) else {
        raise RuleParseError(
          "@error_node(kind, ...) requires a comma after the kind",
        )
      }
      self.bump()
      let tokens : Array[String] = []
      while true {
        match self.peek() {
          Some(TIdent(name)) => {
            self.bump()
            tokens.push(name)
          }
          _ =>
            raise RuleParseError(
              "@error_node() must contain at least one token identifier after the kind",
            )
        }
        match self.peek() {
          Some(TPipe) => self.bump()
          _ => break
        }
      }
      guard self.peek() is Some(TRParen) else {
        raise RuleParseError("unbalanced '@error_node(' — missing ')'")
      }
      self.bump()
      ErrorNodeUntil(kind_name, tokens)
    }
    Some(TPrefix)
    | Some(TApp)
    | Some(TPrec)
    | Some(TSkip)
    | Some(TLBracket)
    | Some(TRBracket)
    | Some(TComma) =>
      raise RuleParseError(
        pratt_token_in_ebnf_err(self.peek().unwrap()) +
        " is only valid in a production-level Pratt body starting with '@prefix'",
      )
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
      raise RuleParseError(
        "a postfix ('*', '+', '?', '~', '!') has no atom to bind",
      )
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
  let ast = if toks[0] is TPrefix {
    parser.parse_pratt_body() catch {
      RuleParseError(m) => return Err(prefix + m)
    }
  } else {
    match toks[0] {
      TApp | TPrec | TSkip =>
        return Err(
          prefix +
          "Pratt annotations must begin with '@prefix', not '" +
          pratt_token_in_ebnf_err(toks[0]) +
          "'",
        )
      _ =>
        parser.parse_alt() catch {
          RuleParseError(m) => return Err(prefix + m)
        }
    }
  }
  guard parser.pos == toks.length() else {
    return Err(prefix + "trailing tokens after a complete rule")
  }
  Ok(ast)
}
