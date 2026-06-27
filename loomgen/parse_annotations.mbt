///|
/// Parse `#loom.*` annotations from annotated MoonBit enums.

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
}

///|
struct VariantDecl {
  name : String
  tag : String?
  token_role : SyntaxRole?
  attrs : Array[@attribute.Attribute]
  arg_count : Int
  kind_override : String?
}

///|
struct EnumDecl {
  name : String
  attrs : Array[@attribute.Attribute]
  variants : Array[VariantDecl]
  is_token : Bool
}

///|
struct AnnotatedEnums {
  token_enum : EnumDecl?
  term_enum : EnumDecl?
}

///|
fn parse_annotations(source : String) -> Result[AnnotatedEnums, String] {
  let (impls, diagnostics) = @parser.parse_string(source)
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
            "enum " + td.tycon + " has both " + "#" + "loom.token and " + "#" + "loom.term",
          )
        }
        let variants = extract_variants(td.components)
        let classified : Array[VariantDecl] = []
        for v in variants {
          match classify_token_role(v) {
            Err(msg) => return Err(msg)
            Ok(role) => classified.push({ ..v, token_role: role })
          }
        }
        // Cross-role validation: token enums can't have term roles, term enums can't have token roles.
        let is_role_valid = fn(r : SyntaxRole?, for_token : Bool) -> Bool {
          match r {
            None => true
            Some(Keyword(_) | Punct(_) | Ident | Literal | Trivia | Delimiter | ErrorToken | Eof) =>
              for_token
            Some(Leaf | Node | ErrorNode | Root) => !for_token
          }
        }
        for v in classified {
          if !is_role_valid(v.token_role, is_token) {
            let kind = if is_token { "token" } else { "term" }
            return Err(
              "variant " + v.name + " has role incompatible with #loom." + kind + " enum",
            )
          }
        }
        if is_token {
          for v in classified {
            if v.token_role is None {
              return Err(
                "variant " +
                v.name +
                " in #loom.token enum is missing a #loom.* annotation",
              )
            }
          }
        }
        // All term variants MUST have a #loom.* annotation
        if is_term {
          for v in classified {
            if v.token_role is None {
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
            match v.token_role {
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
        if is_token {
          if token_enum is Some(_) {
            return Err("multiple " + "#" + "loom.token enums found")
          }
          token_enum = Some({
            name: td.tycon,
            attrs: td.attrs.to_array(),
            variants: classified,
            is_token,
          })
        }
        if is_term {
          if term_enum is Some(_) {
            return Err("multiple " + "#" + "loom.term enums found")
          }
          term_enum = Some({
            name: td.tycon,
            attrs: td.attrs.to_array(),
            variants: classified,
            is_token: false,
          })
        }
      }
      _ => ()
    }
  }
  Ok({ token_enum, term_enum })
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
        let tag_str = match cd.tag {
          Some((t, _)) => Some(t)
          None => None
        }
        // Find kind_override from any annotation on this variant
        let mut kind_override : String? = None
        for attr in cd.attrs {
          let ko = find_literal_kind_override(attr.parsed)
          if ko is Some(_) {
            kind_override = ko
          }
        }
        // Compute arg_count from constructor args (if present)
        let arg_count = match cd.args {
          Some(args) => args.length()
          None => 0
        }
        {
          name: cd.name.name,
          tag: tag_str,
          attrs: cd.attrs.to_array(),
          token_role: None,
          arg_count,
          kind_override,
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
/// Extract the kind name override from a `#loom.literal` annotation.
/// Only `#loom.literal("IntToken")` supports positional kind override.
fn find_literal_kind_override(parsed : @attribute.Expr?) -> String? {
  match parsed {
    Some(@attribute.Apply(id, props)) if id.qual == Some("loom") &&
      id.name == "literal" =>
      match props.head() {
        Some(@attribute.Expr(@attribute.String(lit))) => Some(lit.to_string())
        _ => None
      }
    _ => None
  }
}

///|
/// Classify a variant's #loom.* annotation into a SyntaxRole.
/// Returns None for unannotated variants; caller validates completeness.
fn classify_token_role(variant : VariantDecl) -> Result[SyntaxRole?, String] {
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
      "keyword" =>
        match first_string_from_apply(attr.parsed) {
          Some(s) => Some(Keyword(s))
          None =>
            return Err(
              "#loom.keyword on " + variant.name + " requires a string argument",
            )
        }
      "punct" =>
        match first_string_from_apply(attr.parsed) {
          Some(s) => Some(Punct(s))
          None =>
            return Err(
              "#loom.punct on " + variant.name + " requires a string argument",
            )
        }
      "ident" => Some(Ident)
      "literal" => Some(Literal)
      "trivia" => Some(Trivia)
      "delimiter" => Some(Delimiter)
      "error" => Some(ErrorToken)
      "eof" => Some(Eof)
      "leaf" => Some(Leaf)
      "node" => Some(Node)
      "errornode" => Some(ErrorNode)
      "root" => Some(Root)
      _ => continue
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
