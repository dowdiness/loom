///|
/// Parse `#loom.*` annotations from annotated MoonBit enums.
enum TokenRole {
  Keyword(String)
  Punct(String)
  Ident
  Literal
  Trivia
  Delimiter
  ErrorToken
  Eof
}

///|
struct VariantDecl {
  name : String
  tag : String?
  attrs : Array[@attribute.Attribute]
  token_role : TokenRole?
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
        let variants = extract_variants(td.components)
        let classified : Array[VariantDecl] = []
        for v in variants {
          match classify_token_role(v) {
            Err(msg) => return Err(msg)
            Ok(role) => classified.push({ ..v, token_role: role })
          }
        }
        // All token variants MUST have a #loom.* annotation
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
fn classify_token_role(variant : VariantDecl) -> Result[TokenRole?, String] {
  let mut assigned : TokenRole? = None
  for attr in variant.attrs {
    let matched = match attr.parsed {
      Some(@attribute.Apply(id, _)) => id
      Some(@attribute.Ident(id)) => id
      _ => continue
    }
    if matched.qual != Some("loom") {
      continue
    }
    let candidate : TokenRole? = match matched.name {
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
