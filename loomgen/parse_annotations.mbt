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
  _tag : String?
  role : SyntaxRole?
  attrs : Array[@attribute.Attribute]
  arg_count : Int
  kind_override : String?
  is_void : Bool
  is_rawtext : Bool
}

///|
struct EnumDecl {
  name : String
  _attrs : Array[@attribute.Attribute]
  variants : Array[VariantDecl]
  _is_token : Bool
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
          token_enum = Some({
            name: td.tycon,
            _attrs: td.attrs.to_array(),
            variants: classified,
            _is_token: is_token,
          })
        }
        if is_term {
          if term_enum is Some(_) {
            return Err("multiple " + "#" + "loom.term enums found")
          }
          term_enum = Some({
            name: td.tycon,
            _attrs: td.attrs.to_array(),
            variants: classified,
            _is_token: false,
          })
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
        let parts : Array[String] = line.split("#").to_array().map(fn(s) { s.to_owned() })
        if parts.length() > 2 {
          let indent = parts[0]
          let first_anno = parts[1]
          // Only split when the # boundary is NOT inside a string literal.
          // Count quotes in the content before the second # — odd = inside string.
          let quote_count = first_anno.split("\"").to_array().length() - 1
          if quote_count % 2 == 1 {
            // Inside a string — don't split (e.g. #loom.punct("#"))
            out_lines.push(line)
          } else {
            let trimmed_anno = first_anno.trim().to_owned()
            // Build rest by rejoining parts[2:] with #
            let mut rest = ""
            for i in 2..<parts.length() {
              if i > 2 { rest = rest + "#" }
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
        let tag_str = match cd.tag {
          Some((t, _)) => Some(t)
          None => None
        }
        // Find kind_override from any annotation on this variant
        let mut kind_override : String? = None
        // Detect #loom.void and #loom.rawtext modifier annotations
        let mut is_void = false
        let mut is_rawtext = false
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
          _tag: tag_str,
          attrs: cd.attrs.to_array(),
          role: None,
          arg_count,
          kind_override,
          is_void,
          is_rawtext,
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
      _ => continue
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
