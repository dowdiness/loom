///|
/// Parse `#loom.*` annotations from annotated MoonBit enums.

///|
enum ViewCardinality {
  ViewOne
  ViewOptional
  ViewZeroOrMore
  ViewOneOrMore
}

///|
/// Role classification for annotated enum variants (token roles and term roles).
enum SyntaxRole {
  // Token roles
  Keyword(String)
  Punct(String)
  Ident
  Literal
  Trivia
  Delimiter
  ErrorToken
  Eof
  // Term (CST node) roles
  Leaf
  Node
  ErrorNode
  Root
  View(String, String, ViewCardinality)
}

///|
struct VariantDecl {
  name : String
  role : SyntaxRole?
  attrs : Array[@attribute.Attribute]
  arg_count : Int
  kind_override : String?
  is_void : Bool
  is_rawtext : Bool
  // Lexer-generation modifiers (#521). `pattern` carries an opaque MoonBit `re`
  // dialect regex emitted verbatim into an anchored `re"^..."` literal;
  // `custom_lex` names a hand-written `(String, Int) -> LexStep[Token]` escape hatch.
  pattern : String?
  custom_lex : String?
  lexmode_name : String?
  // #522. `rule` carries the raw EBNF-subset string from `#loom.rule("...")` on a
  // #loom.term variant; the GrammarIr emitter lowers it to a `@grammar.Expr`.
  rule : String?
}

///|
struct EnumDecl {
  name : String
  variants : Array[VariantDecl]
}

///|
struct AnnotatedEnums {
  token_enum : EnumDecl?
  term_enum : EnumDecl?
}

///|
fn parse_annotations(source : String) -> Result[AnnotatedEnums, String] {
  // Normalize: split lines with multiple #-delimited annotations onto separate lines.
  // The MoonBit parser does not split on '#' within a line, so
  // "#deprecated #loom.node Br" and "#loom.void #loom.node Br" both lose annotations.
  // Iteratively split at each # boundary until every annotation is on its own line.
  let normalized = normalize_anno_lines(source)
  let (impls, diagnostics) = @parser.parse_string(normalized)
  if diagnostics.length() > 0 {
    let msgs = diagnostics.map(fn(r) { r.loc.to_string() + ": " + r.msg })
    return Err(msgs.join("; "))
  }
  let mut token_enum : EnumDecl? = None
  let mut term_enum : EnumDecl? = None
  for toplevel in impls {
    match toplevel {
      @syntax.TopTypeDef(td) => {
        let is_token = has_loom_attr("token", td.attrs)
        let is_term = has_loom_attr("term", td.attrs)
        if !is_token && !is_term {
          continue
        }
        // Reject #loom.token AND #loom.term on the same enum
        if is_token && is_term {
          return Err(
            "enum " +
            td.tycon +
            " has both " +
            "#" +
            "loom.token and " +
            "#" +
            "loom.term",
          )
        }
        let variants = extract_variants(td.components)
        let classified : Array[VariantDecl] = []
        for v in variants {
          match classify_role(v) {
            Err(msg) => return Err(msg)
            Ok(role) => classified.push({ ..v, role, })
          }
        }
        // Cross-role validation: token enums can't have term roles, term enums can't have token roles.
        let is_role_valid = fn(r : SyntaxRole?, for_token : Bool) -> Bool {
          match r {
            None => true
            Some(
              Keyword(_)
              | Punct(_)
              | Ident
              | Literal
              | Trivia
              | Delimiter
              | ErrorToken
              | Eof
            ) => for_token
            Some(Leaf | Node | ErrorNode | Root | View(_, _, _)) => !for_token
          }
        }
        for v in classified {
          if !is_role_valid(v.role, is_token) {
            let kind = if is_token { "token" } else { "term" }
            return Err(
              "variant " +
              v.name +
              " has role incompatible with #loom." +
              kind +
              " enum",
            )
          }
        }
        if is_token {
          for v in classified {
            if v.role is None {
              return Err(
                "variant " +
                v.name +
                " in #loom.token enum is missing a #loom.* annotation",
              )
            }
          }
          for v in classified {
            if v.is_void {
              return Err(
                "token variant " + v.name + " cannot have #loom.void annotation",
              )
            }
            if v.is_rawtext {
              return Err(
                "token variant " +
                v.name +
                " cannot have #loom.rawtext annotation",
              )
            }
            if v.lexmode_name is Some(_) {
              return Err(
                "token variant " +
                v.name +
                " cannot have #loom.lexmode annotation",
              )
            }
            if v.rule is Some(_) {
              return Err(
                "token variant " +
                v.name +
                " cannot have #loom.rule annotation (#loom.rule is only valid on #loom.term variants)",
              )
            }
          }
          // Lexer-generation: #loom.pattern is only meaningful for real
          // scanning roles. Keywords are post-classified from the identifier
          // match, EOF is handled at scanner entry, and the error token is the
          // no-match fallback — none of them may carry their own pattern. A
          // nullable pattern would emit a zero-width producer, so reject it.
          for v in classified {
            match v.pattern {
              Some(p) => {
                match v.role {
                  Some(Keyword(_)) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has #loom.pattern together with #loom.keyword; keywords are post-classified from the identifier match and must not carry a pattern",
                    )
                  Some(Eof) =>
                    return Err(
                      "#loom.eof variant " +
                      v.name +
                      " cannot have #loom.pattern",
                    )
                  Some(ErrorToken) =>
                    return Err(
                      "#loom.error variant " +
                      v.name +
                      " cannot have #loom.pattern; the error token is the no-match fallback",
                    )
                  _ => ()
                }
                if malformed_re(p) is Some(reason) {
                  return Err(
                    "token variant " +
                    v.name +
                    " has a malformed #loom.pattern \"" +
                    p +
                    "\": " +
                    reason +
                    ". This would emit a regex that fails to compile in the generated lexer.",
                  )
                }
                if unsupported_re_construct(p) is Some(reason) {
                  return Err(
                    "token variant " +
                    v.name +
                    " has an unsupported #loom.pattern \"" +
                    p +
                    "\": " +
                    reason +
                    ". loomgen's #loom.pattern supports literals, escapes, character classes [..], plain groups (..), anchors ^ $, and quantifiers * + ? {m,n}.",
                  )
                }
                if is_nullable_pattern(p) {
                  return Err(
                    "token variant " +
                    v.name +
                    " has a nullable #loom.pattern \"" +
                    p +
                    "\" that can match the empty string; this would produce a zero-width token. Rewrite it with a required atom (e.g. + instead of *).",
                  )
                }
              }
              None => ()
            }
          }
          // #loom.custom_lex is a HOW-to-lex override on a role-bearing token.
          // It is meaningless on the EOF sentinel (detected at scanner entry,
          // never lexed), and its argument is emitted verbatim as a call, so it
          // must name a callable lex function.
          for v in classified {
            match v.custom_lex {
              Some(fn_name) => {
                if v.role is Some(Eof) {
                  return Err(
                    "#loom.eof variant " +
                    v.name +
                    " cannot have #loom.custom_lex; EOF is detected at scanner entry, not lexed",
                  )
                }
                if v.role is Some(Keyword(_)) {
                  return Err(
                    "#loom.keyword variant " +
                    v.name +
                    " cannot have #loom.custom_lex; keywords are post-classified from the #loom.ident match, never lexed directly",
                  )
                }
                if !is_valid_lex_fn_name(fn_name) {
                  return Err(
                    "token variant " +
                    v.name +
                    " has #loom.custom_lex(\"" +
                    fn_name +
                    "\") whose argument is not a valid function name; expected an identifier or @pkg.identifier path",
                  )
                }
              }
              None => ()
            }
          }
        }
        // All term variants MUST have a #loom.* annotation
        if is_term {
          for v in classified {
            if v.role is None {
              return Err(
                "variant " +
                v.name +
                " in #loom.term enum is missing a #loom.* annotation",
              )
            }
          }
        }
        // Reject multiple ErrorNode variants — from_raw fallback would be ambiguous
        if is_term {
          let mut error_count = 0
          for v in classified {
            match v.role {
              Some(ErrorNode) => error_count = error_count + 1
              _ => ()
            }
          }
          if error_count > 1 {
            return Err(
              "#loom.term enum has multiple #loom.errornode variants; at most one allowed",
            )
          }
        }
        // Reject #loom.void AND #loom.rawtext on the same variant (contradictory)
        if is_term {
          for v in classified {
            if v.is_void && v.is_rawtext {
              return Err(
                "variant " +
                v.name +
                " has both #loom.void and #loom.rawtext; at most one allowed",
              )
            }
          }
        }
        // Reject #loom.eof variants with payload arguments
        if is_token {
          for v in classified {
            if v.role is Some(Eof) && v.arg_count > 0 {
              return Err(
                "#loom.eof variant " +
                v.name +
                " must not have constructor arguments",
              )
            }
          }
        }
        // Cross-variant view target validation
        if is_term {
          let view_targets : Map[(String, String), Bool] = Map([])
          let variant_names : @hashset.HashSet[String] = @hashset.HashSet([])
          for v in classified {
            variant_names.add(v.name)
          }
          for v in classified {
            match v.role {
              Some(View(target, property, _)) => {
                if !variant_names.contains(target) {
                  return Err(
                    "#loom.view on " +
                    v.name +
                    " targets unknown variant \"" +
                    target +
                    "\"",
                  )
                }
                // Validate target variant is a node-like role (Node or Root), not Leaf, ErrorNode, or View
                let mut target_role_ok = false
                for tv in classified {
                  if tv.name == target {
                    match tv.role {
                      Some(Node) | Some(Root) => target_role_ok = true
                      _ => ()
                    }
                  }
                }
                if !target_role_ok {
                  return Err(
                    "#loom.view on " +
                    v.name +
                    " targets \"" +
                    target +
                    "\" which is not a node/root variant",
                  )
                }
                // Reject duplicate (target, property) pairs
                let pair = (target, property)
                if view_targets.contains(pair) {
                  return Err(
                    "#loom.view on " +
                    v.name +
                    " has duplicate (target, property) pair (\"" +
                    target +
                    "\", \"" +
                    property +
                    "\")",
                  )
                }
                view_targets.set(pair, true)
              }
              _ => ()
            }
          }
        }
        if is_token {
          if token_enum is Some(_) {
            return Err("multiple " + "#" + "loom.token enums found")
          }
          token_enum = Some({ name: td.tycon, variants: classified })
        }
        if is_term {
          if term_enum is Some(_) {
            return Err("multiple " + "#" + "loom.term enums found")
          }
          term_enum = Some({ name: td.tycon, variants: classified })
        }
      }
      _ => ()
    }
  }
  Ok({ token_enum, term_enum })
}

///|
/// Prepass: split lines with multiple #-delimited annotations onto separate lines.
/// The MoonBit parser does not split on '#' within a line, so
/// "#deprecated #loom.node Br" loses everything after the first #.
/// Only processes lines whose trimmed form starts with # (annotation lines).
/// Splits one # boundary per iteration until every annotation is on its own line.
fn normalize_anno_lines(source : String) -> String {
  let raw_lines = source.split("\n").to_array()
  let mut in_lines : Array[String] = raw_lines.map(fn(s) { s.to_owned() })
  let mut changed = true
  while changed {
    changed = false
    let out_lines : Array[String] = []
    for line in in_lines {
      let trimmed = line.trim()
      if trimmed.has_prefix("#") {
        let parts : Array[String] = line
          .split("#")
          .to_array()
          .map(fn(s) { s.to_owned() })
        if parts.length() > 2 {
          let indent = parts[0]
          let first_anno = parts[1]
          // Don't split when the # is inside a string literal or trailing // comment.
          let quote_count = first_anno.split("\"").to_array().length() - 1
          let comment_parts = first_anno.split("//").to_array()
          let has_comment = comment_parts.length() > 1
          if quote_count % 2 == 1 || has_comment {
            // Inside string (e.g. #loom.punct("#")) or after // comment
            out_lines.push(line)
          } else {
            let trimmed_anno = first_anno.trim().to_owned()
            // Build rest by rejoining parts[2:] with #
            let mut rest = ""
            for i in 2..<parts.length() {
              if i > 2 {
                rest = rest + "#"
              }
              rest = rest + parts[i]
            }
            out_lines.push(indent + "#" + trimmed_anno)
            out_lines.push(indent + "#" + rest)
            changed = true
          }
        } else {
          out_lines.push(line)
        }
      } else {
        out_lines.push(line)
      }
    }
    in_lines = out_lines
  }
  in_lines.join("\n")
}

///|
fn has_loom_attr(
  name : String,
  attrs : @list.List[@attribute.Attribute],
) -> Bool {
  for attr in attrs {
    match attr.parsed {
      Some(@attribute.Ident(id) | @attribute.Apply(id, _)) =>
        if id.qual == Some("loom") && id.name == name {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn extract_variants(comp : @syntax.TypeDesc) -> Array[VariantDecl] {
  match comp {
    @syntax.Variant(constrs) | @syntax.ExtensibleEnum(constrs) =>
      constrs
      .map(fn(cd) {
        // Find kind_override from any annotation on this variant
        let mut kind_override : String? = None
        // Detect #loom.void, #loom.rawtext, and #loom.lexmode modifier annotations
        let mut is_void = false
        let mut is_rawtext = false
        // Detect #loom.pattern and #loom.custom_lex lexer-generation modifiers.
        let mut pattern : String? = None
        let mut custom_lex : String? = None
        let mut lexmode_name : String? = None
        let mut rule : String? = None
        for attr in cd.attrs {
          let ko = find_literal_kind_override(attr.parsed)
          if ko is Some(_) {
            kind_override = ko
          }
          match attr.parsed {
            Some(@attribute.Ident(id) | @attribute.Apply(id, _)) if id.qual ==
              Some("loom") =>
              if id.name == "void" {
                is_void = true
              } else if id.name == "rawtext" {
                is_rawtext = true
              } else if id.name == "pattern" {
                pattern = first_string_from_apply(attr.parsed)
              } else if id.name == "custom_lex" {
                custom_lex = first_string_from_apply(attr.parsed)
              } else if id.name == "lexmode" {
                // Extract the mode name from #loom.lexmode("Name")
                lexmode_name = first_string_from_apply(attr.parsed)
              } else if id.name == "rule" {
                // Extract the EBNF-subset string from #loom.rule("...")
                rule = first_string_from_apply(attr.parsed)
              }
            _ => ()
          }
        }
        let arg_count = match cd.args {
          Some(args) => args.length()
          None => 0
        }
        {
          name: cd.name.name,
          attrs: cd.attrs.to_array(),
          role: None,
          arg_count,
          kind_override,
          is_void,
          is_rawtext,
          pattern,
          custom_lex,
          lexmode_name,
          rule,
        }
      })
      .to_array()
    _ => []
  }
}

///|
/// Extract the first string positional argument from a loom annotation.
fn first_string_from_apply(parsed : @attribute.Expr?) -> String? {
  match parsed {
    Some(@attribute.Apply(_, props)) =>
      match props.head() {
        Some(@attribute.Expr(@attribute.String(lit))) => Some(lit.to_string())
        _ => None
      }
    _ => None
  }
}

///|
/// Conservatively decide whether a `#loom.pattern` regex can match the empty
/// string. The argument is the raw pattern body (MoonBit `re` dialect) WITHOUT
/// the generator's leading `^` anchor.
///
/// Soundness requirement: NEVER return `false` for a genuinely nullable
/// pattern — a false negative ships a lexer that can emit a zero-width token
/// and stall. Over-rejecting some safe-but-complex patterns is acceptable; the
/// caller's error message tells the author to add an explicit required atom.
///
/// A pattern is nullable when it has no *required* atom at the top level: the
/// empty string `""`, an all-optional sequence like `[a-z]*` or `(foo)?`, or a
/// top-level alternation `a|b` where some branch is nullable.
fn is_nullable_pattern(pattern : String) -> Bool {
  if pattern.length() == 0 {
    return true
  }
  let (nullable, _) = nullable_alt(pattern, 0)
  nullable
}

///|
/// Parse a top-level alternation `seq ( '|' seq )*` from `pos`, stopping at an
/// unmatched ')' or end of input. Nullable iff ANY branch is nullable.
fn nullable_alt(p : String, pos : Int) -> (Bool, Int) {
  let (first, next) = nullable_seq(p, pos)
  let mut result = first
  let mut i = next
  while i < p.length() && p[i] == '|' {
    let (branch, after) = nullable_seq(p, i + 1)
    result = result || branch
    i = after
  }
  (result, i)
}

///|
/// Parse a concatenation of quantified atoms until '|', ')', or end. An empty
/// sequence is nullable; otherwise nullable iff EVERY atom is optional.
fn nullable_seq(p : String, pos : Int) -> (Bool, Int) {
  let mut i = pos
  let mut all_optional = true
  while i < p.length() && p[i] != '|' && p[i] != ')' {
    let (atom_nullable, after_atom) = nullable_atom(p, i)
    let (quant_nullable, after_quant) = apply_quantifier(
      atom_nullable, p, after_atom,
    )
    if !quant_nullable {
      all_optional = false
    }
    i = after_quant
  }
  (all_optional, i)
}

///|
/// Parse a single atom (literal, escape, char class, group, or zero-width
/// anchor) and return (atom_is_nullable, next_pos) BEFORE any quantifier.
fn nullable_atom(p : String, pos : Int) -> (Bool, Int) {
  let c = p[pos]
  if c == '\\' {
    // Escaped char consumes one literal character — not nullable. (Zero-width
    // escapes like \b are not analyzed; they are nonsensical in token patterns.)
    let next = if pos + 1 < p.length() { pos + 2 } else { pos + 1 }
    (false, next)
  } else if c == '^' || c == '$' {
    // Zero-width anchor matches the empty string.
    (true, pos + 1)
  } else if c == '[' {
    // Char class matches exactly one character — not nullable. `class_end`
    // finds the true closing `]`, accounting for `\]` escapes and POSIX
    // elements like `[:digit:]` whose inner `]` must not close the class early.
    (false, class_end(p, pos))
  } else if c == '(' {
    let (inner, after) = nullable_alt(p, pos + 1)
    let next = if after < p.length() && p[after] == ')' {
      after + 1
    } else {
      after
    }
    (inner, next)
  } else {
    // Ordinary literal character.
    (false, pos + 1)
  }
}

///|
/// Apply a trailing quantifier to an atom's nullability. `*` and `?` make the
/// atom optional; `+` preserves it; `{m,n}` is optional iff its lower bound is
/// zero or absent. No quantifier leaves the atom's nullability unchanged. A
/// lazy modifier (a `?` immediately after the quantifier, e.g. `a*?`) is
/// consumed without changing nullability — otherwise it would be mis-read as a
/// separate optional atom and a genuinely nullable pattern (`a*?`) would be
/// classified non-nullable.
fn apply_quantifier(atom_nullable : Bool, p : String, pos : Int) -> (Bool, Int) {
  if pos >= p.length() {
    return (atom_nullable, pos)
  }
  let (nullable, next) = match p[pos] {
    '*' | '?' => (true, pos + 1)
    '+' => (atom_nullable, pos + 1)
    '{' => {
      // {min,max}: nullable iff min is zero or absent.
      let mut j = pos + 1
      let mut min_is_zero = true
      while j < p.length() && p[j] >= '0' && p[j] <= '9' {
        if p[j] != '0' {
          min_is_zero = false
        }
        j = j + 1
      }
      while j < p.length() && p[j] != '}' {
        j = j + 1
      }
      let after_brace = if j < p.length() { j + 1 } else { j }
      (min_is_zero || atom_nullable, after_brace)
    }
    // No quantifier — return immediately without consuming a following char.
    _ => return (atom_nullable, pos)
  }
  // Consume a lazy `?` modifier on the quantifier just parsed.
  if next < p.length() && p[next] == '?' {
    (nullable, next + 1)
  } else {
    (nullable, next)
  }
}

///|
/// If a well-formed POSIX class element `[:name:]` (non-empty alphabetic name)
/// opens at `pos` (which must point at the `[` and `p[pos+1]` must be `:`),
/// return the index just past its `:]`. Otherwise return `None` — the `[` is an
/// ordinary class member, not a POSIX element. This lookahead prevents a bare
/// `[:` inside a class (e.g. `[a[:z]`) from being mistaken for a POSIX element
/// and scanning past the real closing `]`.
fn posix_element_end(p : String, pos : Int) -> Int? {
  let start = pos + 2
  let mut j = start
  while j < p.length() && p[j] != ':' && p[j] != ']' {
    j = j + 1
  }
  if j > start && j + 1 < p.length() && p[j] == ':' && p[j + 1] == ']' {
    Some(j + 2)
  } else {
    None
  }
}

///|
/// Find the index just past the closing `]` of the character class that opens at
/// `pos` (which must point at the `[`). Skips `\]` escapes and well-formed POSIX
/// elements like `[:digit:]` — whose inner `]` is NOT the class terminator — so
/// a class is always treated as exactly one consuming atom. Returns `p.length()`
/// for an unterminated class. Shared by the nullability analyzer, the
/// unsupported-construct scan, and the structural validator so all agree on
/// class boundaries.
fn class_end(p : String, pos : Int) -> Int {
  let mut j = pos + 1
  while j < p.length() && p[j] != ']' {
    if p[j] == '\\' {
      j = j + 2
    } else if p[j] == '[' &&
      j + 1 < p.length() &&
      p[j + 1] == ':' &&
      posix_element_end(p, j) is Some(after) {
      j = after
    } else {
      j = j + 1
    }
  }
  if j < p.length() {
    j + 1
  } else {
    j
  }
}

///|
/// Detect structurally malformed `#loom.pattern` regex: unbalanced parentheses,
/// an unterminated character class, or a trailing unescaped backslash. The
/// generator emits the pattern verbatim into `re"^(?:PATTERN)"`, so a malformed
/// pattern produces a `lexer.g.mbt` that compiles "successfully" at generation
/// time but fails the user's later `moon build` with a cryptic regex error — and
/// the `(?:...)` wrapper turns a stray `)` / trailing `\` into an unbalanced or
/// unterminated group. Reusing `class_end` keeps class boundaries consistent
/// with the other scanners. Returns `Some(reason)` when malformed.
fn malformed_re(p : String) -> String? {
  let mut i = 0
  let mut depth = 0
  while i < p.length() {
    let c = p[i]
    if c == '\\' {
      if i + 1 >= p.length() {
        return Some("pattern ends with an unescaped backslash")
      }
      i = i + 2
    } else if c == '[' {
      let end = class_end(p, i)
      // class_end returns p.length() (with no closing ']') for an unterminated
      // class; a terminated class ends one past a ']'.
      if end > p.length() || p[end - 1] != ']' {
        return Some("unterminated character class '['")
      }
      i = end
    } else if c == '(' {
      depth = depth + 1
      i = i + 1
    } else if c == ')' {
      if depth == 0 {
        return Some("unbalanced ')'")
      }
      depth = depth - 1
      i = i + 1
    } else if c == '{' {
      // A counted quantifier must close; the re dialect errors on an unterminated
      // `{` (e.g. `a{2`). Scan for the closing `}`.
      let mut j = i + 1
      while j < p.length() && p[j] != '}' {
        j = j + 1
      }
      if j >= p.length() {
        return Some("unterminated counted quantifier '{'")
      }
      i = j + 1
    } else {
      i = i + 1
    }
  }
  if depth != 0 {
    return Some("unbalanced '(' (" + depth.to_string() + " unclosed)")
  }
  None
}

///|
/// Detect `#loom.pattern` constructs outside loomgen's supported `re` subset.
/// Returns `Some(reason)` for an unsupported construct, `None` otherwise.
///
/// The MoonBit `re` dialect rejects zero-width assertion escapes (`\b`, `\A`,
/// ...) and lookaround at compile time, so emitting them would fail inside the
/// generated lexer rather than here. Non-capturing `(?:...)` groups DO compile,
/// but the nullability analyzer reads the `?:` prefix as two literal atoms and
/// cannot soundly classify them. Rejecting every `(?...)` group and zero-width
/// assertion escape keeps the analyzer's domain exactly the subset it is
/// provably sound on, and turns a cryptic downstream compile error into a clear
/// generation-time message.
///
/// Character classes are skipped wholesale via `class_end` so a `(` or `\b`
/// *inside* `[...]` — where it is an ordinary class member — is not mistaken for
/// an unsupported construct, and POSIX elements like `[:digit:]` do not desync
/// the scan.
fn unsupported_re_construct(p : String) -> String? {
  let mut i = 0
  while i < p.length() {
    let c = p[i]
    if c == '\\' {
      if i + 1 < p.length() {
        match p[i + 1] {
          'b' | 'B' | 'A' | 'z' | 'Z' | 'G' =>
            return Some(
              "zero-width assertion escape " +
              p[i:i + 2].to_owned() +
              " is not supported by the re dialect",
            )
          // Perl-style character-class shorthands are rejected by the re dialect
          // (it errors, not just deprecates), so they would emit a lexer that
          // fails to compile. Point to the POSIX-class equivalents.
          'd' | 'D' | 's' | 'S' | 'w' | 'W' =>
            return Some(
              "character-class escape " +
              p[i:i + 2].to_owned() +
              " is not supported by the re dialect; use a POSIX class such as [[:digit:]], [[:space:]], or [[:alnum:]]",
            )
          _ => ()
        }
      }
      i = i + 2
    } else if c == '[' {
      i = class_end(p, i)
    } else if c == '(' && i + 1 < p.length() && p[i + 1] == '?' {
      return Some(
        "(?...) groups (non-capturing, flags, or lookaround) are not supported; use a plain group (..)",
      )
    } else if (c == '*' || c == '+' || c == '?' || c == '}') &&
      i + 1 < p.length() &&
      p[i + 1] == '?' {
      // A `?` immediately after a quantifier is a LAZY modifier (`*?`, `+?`,
      // `??`, `{m,n}?`). Lazy = minimal match, which is incompatible with a
      // longest-match lexer: `[0-9]+?` would match a single digit and split
      // `123` into three tokens. Reject it (the re dialect would otherwise
      // accept it and silently mis-tokenize).
      return Some(
        "lazy quantifier '" +
        p[i:i + 2].to_owned() +
        "' is not supported; a longest-match lexer requires greedy quantifiers",
      )
    } else if c == '|' {
      // Alternation is leftmost-match, not longest-match: in `re"^(?:foo|foobar)"`
      // the engine returns the FIRST matching branch (`foo`, len 3), not the
      // longest (`foobar`). The generated lexer's longest-match comparison only
      // sees that short length, so a single token is silently split. (A `|`
      // inside a character class is literal and skipped via class_end above;
      // an escaped `\|` is skipped via the `\\` branch.) Reject the operator.
      return Some(
        "alternation '|' is not supported; regex alternation is leftmost-match, not longest-match, so a branch that is a prefix of a later branch would under-match and split tokens. Use separate token variants or a character class",
      )
    } else {
      i = i + 1
    }
  }
  None
}

///|
/// Is `name` a syntactically valid lex-hook reference — a bare identifier or an
/// `@pkg.identifier` path? `#loom.custom_lex(name)` is emitted verbatim as a
/// function call, so anything else would inject broken (or arbitrary) source
/// into the generated lexer.
///
/// Grammar: an optional leading `@`, then one or more `.`-separated segments,
/// each a non-empty identifier (first char a letter or `_`, rest alphanumeric
/// or `_`). This rejects a leading digit (`3lex`), a bare/empty segment (`@`,
/// `a.`, `a..b`), and any stray punctuation — all of which the old char-whitelist
/// admitted and then emitted as a non-compiling call.
fn is_valid_lex_fn_name(name : String) -> Bool {
  let mut i = 0
  if i < name.length() && name[i] == '@' {
    i = i + 1
  }
  let mut seen_segment = false
  while i < name.length() {
    // Segment must start with a letter or '_'.
    let start = name[i]
    let starts_ident = (start >= 'a' && start <= 'z') ||
      (start >= 'A' && start <= 'Z') ||
      start == '_'
    if !starts_ident {
      return false
    }
    i = i + 1
    while i < name.length() {
      let c = name[i]
      let is_ident_char = (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_'
      if !is_ident_char {
        break
      }
      i = i + 1
    }
    seen_segment = true
    // After a segment, accept end-of-name or a single '.' before the next.
    if i < name.length() {
      if name[i] != '.' {
        return false
      }
      i = i + 1
      if i >= name.length() {
        return false // trailing '.'
      }
    }
  }
  seen_segment
}

///|
/// Extract the nth positional string argument from a loom annotation (0-indexed).
fn nth_string_from_apply(parsed : @attribute.Expr?, index : Int) -> String? {
  match parsed {
    Some(@attribute.Apply(_, props)) => {
      let mut i = 0
      for prop in props {
        if i == index {
          match prop {
            @attribute.Expr(@attribute.String(lit)) =>
              return Some(lit.to_string())
            _ => return None
          }
        }
        i = i + 1
      }
      None
    }
    _ => None
  }
}

///|
/// Extract the kind name override from a `#loom.literal` annotation.
/// Only `#loom.literal("IntToken")` supports positional kind override.
fn find_literal_kind_override(parsed : @attribute.Expr?) -> String? {
  match parsed {
    Some(@attribute.Apply(id, _)) if id.qual == Some("loom") &&
      id.name == "literal" => first_string_from_apply(parsed)
    _ => None
  }
}

///|
/// Count all arguments (positional + KV) in a loom annotation.
fn count_apply_args(parsed : @attribute.Expr?) -> Int {
  match parsed {
    Some(@attribute.Apply(_, props)) => props.length()
    _ => 0
  }
}

///|
/// Classify a variant's #loom.* annotation into a SyntaxRole.
/// Returns None for unannotated variants; caller validates completeness.
let nullary_role_map : Map[String, SyntaxRole] = Map([
  ("ident", Ident),
  ("trivia", Trivia),
  ("delimiter", Delimiter),
  ("error", ErrorToken),
  ("eof", Eof),
  ("leaf", Leaf),
  ("node", Node),
  ("errornode", ErrorNode),
  ("root", Root),
])

///|
fn classify_role(variant : VariantDecl) -> Result[SyntaxRole?, String] {
  let mut assigned : SyntaxRole? = None
  for attr in variant.attrs {
    let matched = match attr.parsed {
      Some(@attribute.Apply(id, _)) => id
      Some(@attribute.Ident(id)) => id
      _ => {
        // attr.parsed is None when MoonBit parser rejects argument syntax.
        // Check raw text to detect attempted #loom.* annotations.
        if attr.raw.has_prefix("#loom.") {
          // Extract annotation name from e.g. "#loom.literal(42)"
          let name_start = 6 // length of "#loom."
          let paren_pos = attr.raw.find("(")
          let end = match paren_pos {
            Some(p) => p
            None => attr.raw.length()
          }
          let ann_name = attr.raw[name_start:end].to_owned()
          return Err(
            "invalid arguments for #loom." + ann_name + " on " + variant.name,
          )
        }
        continue
      }
    }
    if matched.qual != Some("loom") {
      continue
    }
    let candidate : SyntaxRole? = match matched.name {
      "keyword" => {
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.keyword on " + variant.name + " requires exactly 1 argument",
          )
        }
        match first_string_from_apply(attr.parsed) {
          Some(s) => Some(Keyword(s))
          None =>
            return Err(
              "#loom.keyword on " + variant.name + " requires a string argument",
            )
        }
      }
      "punct" => {
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.punct on " + variant.name + " requires exactly 1 argument",
          )
        }
        match first_string_from_apply(attr.parsed) {
          Some(s) => Some(Punct(s))
          None =>
            return Err(
              "#loom.punct on " + variant.name + " requires a string argument",
            )
        }
      }
      "literal" => {
        let n = count_apply_args(attr.parsed)
        if n > 1 {
          return Err(
            "#loom.literal on " + variant.name + " accepts at most 1 argument",
          )
        }
        if n == 1 && first_string_from_apply(attr.parsed) is None {
          return Err(
            "#loom.literal on " +
            variant.name +
            " argument must be a string literal",
          )
        }
        Some(Literal)
      }
      "view" => {
        let n = count_apply_args(attr.parsed)
        if n < 2 {
          return Err(
            "#loom.view on " +
            variant.name +
            " requires at least 2 string arguments (target, property)",
          )
        }
        if n > 3 {
          return Err(
            "#loom.view on " +
            variant.name +
            " accepts at most 3 arguments (target, property, cardinality)",
          )
        }
        let target_node = match nth_string_from_apply(attr.parsed, 0) {
          Some(s) => s
          None =>
            return Err(
              "#loom.view on " +
              variant.name +
              " first argument must be a string literal (target node)",
            )
        }
        let property_name = match nth_string_from_apply(attr.parsed, 1) {
          Some(s) => s
          None =>
            return Err(
              "#loom.view on " +
              variant.name +
              " second argument must be a string literal (property name)",
            )
        }
        // Validate property_name is a non-empty valid MoonBit identifier (alphanumeric + underscores)
        {
          if property_name.length() == 0 {
            return Err(
              "#loom.view on " +
              variant.name +
              " property name must not be empty",
            )
          }
          let first = property_name[0]
          if !(first >= 'a' && first <= 'z') &&
            !(first >= 'A' && first <= 'Z') &&
            first != '_' {
            return Err(
              "#loom.view on " +
              variant.name +
              " property name \"" +
              property_name +
              "\" is not a valid MoonBit identifier",
            )
          }
          for i = 1; i < property_name.length(); i = i + 1 {
            let c = property_name[i]
            if !(c >= 'a' && c <= 'z') &&
              !(c >= 'A' && c <= 'Z') &&
              !(c >= '0' && c <= '9') &&
              c != '_' {
              return Err(
                "#loom.view on " +
                variant.name +
                " property name \"" +
                property_name +
                "\" is not a valid MoonBit identifier",
              )
            }
          }
        }
        let cardinality = if n == 3 {
          match nth_string_from_apply(attr.parsed, 2) {
            Some(s) =>
              match s {
                "optional" => ViewOptional
                "zero_or_more" => ViewZeroOrMore
                "one_or_more" => ViewOneOrMore
                "one" => ViewOne
                _ =>
                  return Err(
                    "#loom.view on " +
                    variant.name +
                    " third argument must be \"optional\", \"zero_or_more\", \"one_or_more\", or \"one\"",
                  )
              }
            None =>
              return Err(
                "#loom.view on " +
                variant.name +
                " third argument must be a string literal",
              )
          }
        } else {
          ViewOne
        }
        Some(View(target_node, property_name, cardinality))
      }
      "void" | "rawtext" => {
        // Modifier only — skip role assignment.
        // Validate that no arguments are given (these are bare annotations).
        if count_apply_args(attr.parsed) > 0 {
          return Err(
            "#loom." +
            matched.name +
            " on " +
            variant.name +
            " does not accept arguments",
          )
        }
        continue
      }
      "rule" => {
        // Grammar-generation modifier (#522) — skip role assignment, but require
        // exactly one string argument (the EBNF-subset rule body). The node kind
        // comes from the separate #loom.node/#loom.root/#loom.leaf role.
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.rule on " +
            variant.name +
            " requires exactly 1 string argument",
          )
        }
        if first_string_from_apply(attr.parsed) is None {
          return Err(
            "#loom.rule on " +
            variant.name +
            " argument must be a string literal",
          )
        }
        continue
      }
      "pattern" | "custom_lex" => {
        // Lexer-generation modifier — skip role assignment, but require
        // exactly one string argument (the regex body / function name).
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom." +
            matched.name +
            " on " +
            variant.name +
            " requires exactly 1 string argument",
          )
        }
        if first_string_from_apply(attr.parsed) is None {
          return Err(
            "#loom." +
            matched.name +
            " on " +
            variant.name +
            " argument must be a string literal",
          )
        }
        continue
      }
      "lexmode" => {
        // Modifier only — skip role assignment.
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.lexmode on " +
            variant.name +
            " requires exactly 1 string argument (mode name)",
          )
        }
        let mode_name = match first_string_from_apply(attr.parsed) {
          Some(name) => name
          None =>
            return Err(
              "#loom.lexmode on " +
              variant.name +
              " argument must be a string literal",
            )
        }
        if mode_name.length() == 0 {
          return Err(
            "#loom.lexmode on " + variant.name + " mode name must not be empty",
          )
        }
        let first = mode_name[0]
        if !(first >= 'A' && first <= 'Z') {
          return Err(
            "#loom.lexmode on " +
            variant.name +
            " mode name \"" +
            mode_name +
            "\" must start with an uppercase letter",
          )
        }
        for i = 1; i < mode_name.length(); i = i + 1 {
          let c = mode_name[i]
          if !(c >= 'a' && c <= 'z') &&
            !(c >= 'A' && c <= 'Z') &&
            !(c >= '0' && c <= '9') {
            return Err(
              "#loom.lexmode on " +
              variant.name +
              " mode name \"" +
              mode_name +
              "\" contains invalid character '" +
              c.to_string() +
              "'",
            )
          }
        }
        continue
      }
      _ =>
        match nullary_role_map.get(matched.name) {
          Some(role) => {
            if count_apply_args(attr.parsed) > 0 {
              return Err(
                "#loom." +
                matched.name +
                " on " +
                variant.name +
                " does not accept arguments",
              )
            }
            Some(role)
          }
          None =>
            return Err(
              "unknown #loom." + matched.name + " annotation on " + variant.name,
            )
        }
    }
    if assigned is Some(_) {
      return Err(
        "variant " + variant.name + " has conflicting #loom.* annotations",
      )
    }
    assigned = candidate
  }
  Ok(assigned)
}
