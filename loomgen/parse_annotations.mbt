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
  // #561. `line_pattern` carries a regex matched against a whole line (rest-of-line
  // from current position to newline). Only valid in token variants consumed by a
  // `#loom.line_mode` lexmode's generated lexer function.
  line_pattern : String?
  // #561. `line_mode` marks that the lexmode referenced by `#loom.lexmode(...)` on
  // this term variant is line-oriented (dispatches on full lines, not individual
  // characters). Only valid on term variants alongside `#loom.lexmode("ModeName")`.
  line_mode : Bool
  // Names the hand-written lexer used when a line-mode lexer finds no match.
  fallback_lex : String?
  // #627. `is_sync` carries the bool from `#loom.recovery("sync")` on a
  // #loom.token variant — marks the variant as an error-recovery synchronization point.
  is_sync : Bool
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
          // A token cannot be produced by both the character-level and line-mode
          // lexer; reject the ambiguous combination instead of silently ignoring
          // the character-level pattern.
          for v in classified {
            if v.pattern is Some(_) && v.line_pattern is Some(_) {
              return Err(
                "variant " +
                v.name +
                " has both #loom.pattern and #loom.line_pattern; a token cannot be produced by both the character-level and line-mode lexer",
              )
            }
          }
          for v in classified {
            // #loom.line_pattern tokens are produced by the line-mode lexer;
            // they don't need a scanning role annotation.
            if v.line_pattern is Some(_) {
              continue
            }
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
            // #loom.line_pattern tokens may carry #loom.lexmode to associate
            // them with a line_mode lexmode.
            if v.lexmode_name is Some(_) && v.line_pattern is None {
              return Err(
                "token variant " +
                v.name +
                " cannot have #loom.lexmode annotation without #loom.line_pattern",
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
                match validate_pattern(p) {
                  Err(Malformed(_, reason)) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has a malformed #loom.pattern \"" +
                      p +
                      "\": " +
                      reason +
                      ". This would emit a regex that fails to compile in the generated lexer.",
                    )
                  Err(Unsupported(_, reason)) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has an unsupported #loom.pattern \"" +
                      p +
                      "\": " +
                      reason +
                      ". loomgen's #loom.pattern supports literals, escapes, character classes [..], plain groups (..), anchors ^ $, and quantifiers * + ? {m,n}.",
                    )
                  Ok(true) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has a nullable #loom.pattern \"" +
                      p +
                      "\" that can match the empty string; this would produce a zero-width token. Rewrite it with a required atom (e.g. + instead of *).",
                    )
                  Ok(false) => ()
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
          // #561: #loom.line_pattern validation — similar to #loom.pattern but
          // for line-level patterns. line_pattern tokens may carry constructor
          // arguments (payload extracted by #loom.custom_lex).
          for v in classified {
            match v.line_pattern {
              Some(p) => {
                match v.role {
                  Some(Keyword(_)) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has #loom.line_pattern together with #loom.keyword; keywords are post-classified and must not carry a line pattern",
                    )
                  Some(Eof) =>
                    return Err(
                      "#loom.eof variant " +
                      v.name +
                      " cannot have #loom.line_pattern",
                    )
                  Some(ErrorToken) =>
                    return Err(
                      "#loom.error variant " +
                      v.name +
                      " cannot have #loom.line_pattern; the error token is the no-match fallback",
                    )
                  Some(Ident) =>
                    return Err(
                      "#loom.ident variant " +
                      v.name +
                      " cannot have #loom.line_pattern; line patterns are for block-level tokens, not identifiers",
                    )
                  _ => ()
                }
                match validate_pattern(p) {
                  Err(Malformed(_, reason)) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has a malformed #loom.line_pattern \"" +
                      p +
                      "\": " +
                      reason +
                      ". This would emit a regex that fails to compile in the generated line lexer.",
                    )
                  Err(Unsupported(_, reason)) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has an unsupported #loom.line_pattern \"" +
                      p +
                      "\": " +
                      reason +
                      ". loomgen's #loom.line_pattern supports literals, escapes, character classes [..], plain groups (..), anchors ^ $, and quantifiers * + ? {m,n}.",
                    )
                  Ok(true) =>
                    return Err(
                      "token variant " +
                      v.name +
                      " has a nullable #loom.line_pattern \"" +
                      p +
                      "\" that can match the empty string; this would produce a zero-width token. Rewrite it with a required atom (e.g. + instead of *).",
                    )
                  Ok(false) => ()
                }
              }
              None => ()
            }
          }
          // #561: #loom.line_mode is only valid on term variants alongside
          // #loom.lexmode. Validate on token enums.
          for v in classified {
            if v.line_mode {
              return Err(
                "token variant " +
                v.name +
                " cannot have #loom.line_mode; #loom.line_mode is only valid on #loom.term variants",
              )
            }
          }
          for v in classified {
            if v.fallback_lex is Some(_) {
              return Err(
                "token variant " +
                v.name +
                " cannot have #loom.fallback_lex; it is only valid on #loom.term variants",
              )
            }
          }
          // #561: #loom.line_pattern must be paired with #loom.custom_lex when the
          // token variant has constructor arguments. line_pattern tokens with args
          // need a custom_lex to extract the payload.
          for v in classified {
            match v.line_pattern {
              Some(_) if v.arg_count > 0 && v.custom_lex is None =>
                return Err(
                  "token variant " +
                  v.name +
                  " has constructor arguments and #loom.line_pattern but no #loom.custom_lex; the generated line lexer needs a custom_lex function to extract the payload from the match text",
                )
              _ => ()
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
        if is_term {
          for v in classified {
            if v.is_sync {
              return Err(
                "term variant " +
                v.name +
                " cannot have #loom.recovery annotation (#loom.recovery is only valid on #loom.token variants)",
              )
            }
          }
        }
        // A line-oriented term mode must name its lexmode explicitly.
        // A term variant may declare one fallback function for its mode.
        // Every declaration for a mode must use the same function name.
        if is_term {
          for v in classified {
            if v.line_mode && v.lexmode_name is None {
              return Err(
                "term variant " +
                v.name +
                " has #loom.line_mode without #loom.lexmode; #loom.line_mode must accompany a #loom.lexmode(\"ModeName\") annotation",
              )
            }
            match v.fallback_lex {
              Some(_) if !v.line_mode =>
                return Err(
                  "term variant " +
                  v.name +
                  " has #loom.fallback_lex without #loom.line_mode",
                )
              Some(_) if v.lexmode_name is None =>
                return Err(
                  "term variant " +
                  v.name +
                  " has #loom.fallback_lex without #loom.lexmode",
                )
              _ => ()
            }
          }
          let fallback_by_mode : Map[String, (String, String)] = Map([])
          for v in classified {
            match (v.lexmode_name, v.fallback_lex) {
              (Some(mode), Some(fallback)) =>
                match fallback_by_mode.get(mode) {
                  Some((previous_variant, previous_fallback)) if previous_fallback !=
                    fallback =>
                    return Err(
                      "term variants " +
                      previous_variant +
                      " and " +
                      v.name +
                      " have conflicting #loom.fallback_lex names for mode " +
                      mode,
                    )
                  None => fallback_by_mode.set(mode, (v.name, fallback))
                  _ => ()
                }
              _ => ()
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
        let mut line_pattern : String? = None
        let mut lexmode_name : String? = None
        let mut fallback_lex : String? = None
        let mut rule : String? = None
        let mut is_sync = false
        let mut line_mode = false
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
              } else if id.name == "recovery" {
                is_sync = true
              } else if id.name == "line_pattern" {
                line_pattern = first_string_from_apply(attr.parsed)
              } else if id.name == "line_mode" {
                line_mode = true
              } else if id.name == "fallback_lex" {
                fallback_lex = first_string_from_apply(attr.parsed)
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
          line_pattern,
          line_mode,
          fallback_lex,
          is_sync,
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


fn validate_pattern(pattern : String) -> Result[Bool, PatternError] {
  match parse_pattern(pattern) {
    Ok(parsed) =>
      match parsed.lazy_quantifier() {
        Some(quantifier) =>
          Err(
            Unsupported(
              0,
              "lazy quantifier '" +
              quantifier +
              "' is not supported; a longest-match lexer requires greedy quantifiers",
            ),
          )
        None => Ok(parsed.is_nullable())
      }
    Err(error) => Err(error)
  }
}

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
  match parse_pattern(pattern) {
    Ok(parsed) => parsed.is_nullable()
    Err(_) => true
  }
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
    Some(@attribute.Apply(_, props)) =>
      match props.nth(index) {
        Some(@attribute.Expr(@attribute.String(lit))) => Some(lit.to_string())
        _ => None
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
      "recovery" => {
        // #627: mark a token variant as a synchronization point for error recovery.
        // Exactly 1 string argument required; the only supported value is "sync".
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.recovery on " +
            variant.name +
            " requires exactly 1 string argument (e.g. #loom.recovery(\"sync\"))",
          )
        }
        match first_string_from_apply(attr.parsed) {
          Some(mode) =>
            if mode != "sync" {
              return Err(
                "#loom.recovery on " +
                variant.name +
                " only supports mode \"sync\", got \"" +
                mode +
                "\"",
              )
            }
          None =>
            return Err(
              "#loom.recovery on " +
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
      "line_pattern" => {
        // Modifier only — skip role assignment.
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.line_pattern on " +
            variant.name +
            " requires exactly 1 string argument (regex pattern)",
          )
        }
        if first_string_from_apply(attr.parsed) is None {
          return Err(
            "#loom.line_pattern on " +
            variant.name +
            " argument must be a string literal",
          )
        }
        continue
      }
      "fallback_lex" => {
        // Modifier only — skip role assignment.
        if count_apply_args(attr.parsed) != 1 {
          return Err(
            "#loom.fallback_lex on " +
            variant.name +
            " requires exactly 1 string argument (function name)",
          )
        }
        let fn_name = match first_string_from_apply(attr.parsed) {
          Some(name) => name
          None =>
            return Err(
              "#loom.fallback_lex on " +
              variant.name +
              " argument must be a string literal",
            )
        }
        if !is_valid_lex_fn_name(fn_name) {
          return Err(
            "variant " +
            variant.name +
            " has #loom.fallback_lex(\"" +
            fn_name +
            "\") whose argument is not a valid function name; expected an identifier or @pkg.identifier path",
          )
        }
        continue
      }
      "line_mode" => {
        // Modifier only — skip role assignment.
        if count_apply_args(attr.parsed) > 0 {
          return Err(
            "#loom.line_mode on " + variant.name + " does not accept arguments",
          )
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
