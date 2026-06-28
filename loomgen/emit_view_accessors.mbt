///|
/// Emit `views.g.mbt` — typed per-target projection accessor structs for each
/// `#loom.view` annotation in a `#loom.term` enum.
///
/// For each target node with one or more `#loom.view` edges, generates:
///   - A `*Proj` struct wrapping `@seam.SyntaxNode`
///   - A `cast` function to narrow a SyntaxNode to that projection
///   - Named accessor methods that wrap projection_shape helpers

///|
/// Generate view accessor content for a `#loom.term` enum.
/// Returns the file content (or empty string when there are no View variants).
fn emit_view_accessors(
  term_enum : EnumDecl,
  syntax_type_name : String,
) -> String {
  // Collect all View variants, grouped by target.
  // Each group entry is (variant_name, property_name, cardinality).
  let view_groups : Map[String, Array[(String, String, ViewCardinality)]] = Map([],
  )
  for v in term_enum.variants {
    match v.role {
      Some(View(target, property, cardinality)) => {
        let entry = (v.name, property, cardinality)
        match view_groups.get(target) {
          Some(arr) => arr.push(entry)
          None => view_groups.set(target, [entry])
        }
      }
      _ => ()
    }
  }

  if view_groups.length() == 0 {
    return ""
  }

  let b = StringBuilder::new()
  b.write_string("///|\n")
  b.write_string(
    "/// Generated typed projection accessors from #loom.view annotations.\n",
  )

  // Sort targets for deterministic output
  let sorted_targets = view_groups.keys().to_array()
  sorted_targets.sort()

  for target in sorted_targets {
    let edges = view_groups.get(target).unwrap()
    // Sort edges by property name (tuple index 1) for deterministic output
    edges.sort_by(fn(a, b) {
      if a.1 < b.1 {
        -1
      } else if a.1 > b.1 {
        1
      } else {
        0
      }
    })
    let view_struct_name = target + "Proj"

    // Struct
    b.write_string("\n///|\n")
    b.write_string("pub struct ")
    b.write_string(view_struct_name)
    b.write_string(" {\n  node : @seam.SyntaxNode\n}\n")

    // cast
    b.write_string("\n///|\n")
    b.write_string("pub fn ")
    b.write_string(view_struct_name)
    b.write_string("::cast(n : @seam.SyntaxNode) -> ")
    b.write_string(view_struct_name)
    b.write_string("? {\n")
    b.write_string("  if ")
    b.write_string(syntax_type_name)
    b.write_string("::from_raw(n.kind()) == ")
    b.write_string(target)
    b.write_string(" {\n")
    b.write_string("    Some({ node: n })\n")
    b.write_string("  } else {\n    None\n  }\n}\n")

    // AstView impl
    b.write_string("\n///|\n")
    b.write_string("pub impl @seam.AstView for ")
    b.write_string(view_struct_name)
    b.write_string(" with fn syntax_node(self) {\n  self.node\n}\n")

    // Accessor methods
    for edge in edges {
      let (variant_name, property_name, cardinality) = edge
      let (helper_name, raw_return_type) = match cardinality {
        ViewOne => ("required_direct_child_of_kind", "@seam.SyntaxNode")
        ViewOptional => ("optional_direct_child_of_kind", "@seam.SyntaxNode?")
        ViewZeroOrMore => ("direct_children_of_kind", "Array[@seam.SyntaxNode]")
        ViewOneOrMore =>
          ("required_direct_children_of_kind", "Array[@seam.SyntaxNode]")
      }
      let return_wrapper = match cardinality {
        ViewOne | ViewOptional | ViewOneOrMore =>
          "Result[" + raw_return_type + ", @seam.ProjectionShapeError]"
        ViewZeroOrMore => raw_return_type
      }
      let cardinality_desc = match cardinality {
        ViewOne => "exactly one " + variant_name
        ViewOptional => "at most one " + variant_name
        ViewZeroOrMore => "zero or more " + variant_name
        ViewOneOrMore => "at least one " + variant_name
      }
      let default_message = "\"view " +
        target +
        "." +
        property_name +
        " expects " +
        cardinality_desc +
        "\""

      b.write_string("\n///|\n")
      b.write_string("pub fn ")
      b.write_string(view_struct_name)
      b.write_string("::")
      b.write_string(property_name)
      b.write_string("(\n  self : ")
      b.write_string(view_struct_name)
      b.write_string(",\n  message? : String = ")
      b.write_string(default_message)
      b.write_string(",\n) -> ")
      b.write_string(return_wrapper)
      b.write_string(" {\n")

      if cardinality is ViewZeroOrMore {
        b.write_string("  self.node.")
        b.write_string(helper_name)
        b.write_string("(")
        b.write_string(variant_name)
        b.write_string(".to_raw())\n")
      } else {
        b.write_string("  self.node.")
        b.write_string(helper_name)
        b.write_string("(")
        b.write_string(variant_name)
        b.write_string(".to_raw(), message=message)\n")
      }

      b.write_string("}\n")
    }
  }

  b.to_string()
}
