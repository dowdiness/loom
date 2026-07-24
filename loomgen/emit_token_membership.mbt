///|
/// Emit shared token membership functions for named sets and recovery sets.

///|
fn emit_token_membership_function(
  token_type : String,
  function_name : String,
  variants : Array[VariantDecl],
  doc : String?,
) -> String {
  let b = StringBuilder()
  b.write_string("///|\n")
  match doc {
    Some(text) => b.write_string("/// " + text + "\n")
    None => ()
  }
  let argument_name = if variants.length() == 0 { "_token" } else { "token" }
  b.write_string(
    "pub fn " +
    function_name +
    "(" +
    argument_name +
    " : " +
    token_type +
    ") -> Bool {\n",
  )
  if variants.length() == 0 {
    b.write_string("  false\n")
  } else {
    b.write_string("  match token {\n")
    let arms = variants.map(v => pattern_for(v, false)).join(" | ") + " => true"
    b.write_string("    " + arms + "\n")
    b.write_string("    _ => false\n")
    b.write_string("  }\n")
  }
  b.write_string("}\n")
  b.to_string()
}

///|
fn emit_token_membership(token_enum : EnumDecl) -> String {
  let b = StringBuilder()
  for token_set in token_enum.token_sets {
    let selected : Array[VariantDecl] = []
    for variant_name in token_set.variants {
      for variant in token_enum.variants {
        if variant.name == variant_name {
          selected.push(variant)
        }
      }
    }
    b.write_string(
      emit_token_membership_function(
        token_enum.name,
        "is_" + token_set.name,
        selected,
        None,
      ),
    )
  }
  b.to_string()
}
