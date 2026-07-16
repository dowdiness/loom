///|
test "MarkdownIR identity leaves: emit semantic anchors in preorder" {
  let heading_origin = MarkdownIROrigin(start=0, end=7)
  let heading_content_origin = MarkdownIROrigin(start=2, end=7)
  let link_origin = MarkdownIROrigin(start=2, end=7)
  let label_origin = MarkdownIROrigin(start=3, end=4)
  let destination_origin = MarkdownIROrigin(start=6, end=7)
  let text_origin = MarkdownIROrigin(start=3, end=4)
  let ir = MarkdownIR::document(
    [
      MarkdownIR::heading(
        1,
        [
          MarkdownIR::link(
            [MarkdownIR::text("x", text_origin)],
            "u",
            link_origin,
            Some(label_origin),
            Some(destination_origin),
          ),
        ],
        heading_origin,
        Some(heading_content_origin),
      ),
    ],
    heading_origin,
  )
  inspect(
    @debug.to_string(markdown_ir_identity_leaves(ir)),
    content=@debug.to_string([
      MarkdownIdentityLeaf::new(
        heading_content_origin,
        MarkdownSemanticKey::Heading(1),
      ),
      MarkdownIdentityLeaf::new(label_origin, MarkdownSemanticKey::LinkLabel),
      MarkdownIdentityLeaf::new(
        destination_origin,
        MarkdownSemanticKey::LinkDestination("u"),
      ),
      MarkdownIdentityLeaf::new(text_origin, MarkdownSemanticKey::Text),
    ]),
  )
}

///|
test "MarkdownIR identity leaves: omit unsafe and non-semantic nodes" {
  let origin = MarkdownIROrigin(start=0, end=1)
  let ir = MarkdownIR::document(
    [
      MarkdownIR::raw("?", origin, []),
      MarkdownIR::recovered(RECOVERED_PARSE_ERROR, origin, []),
      MarkdownIR::unsupported("unsupported", origin),
      MarkdownIR::block_quote([], origin),
    ],
    origin,
  )
  inspect(@debug.to_string(markdown_ir_identity_leaves(ir)), content="[]")
}

///|
test "MarkdownIR identity keys: encode component lengths injectively" {
  let origin = MarkdownIROrigin(start=2, end=8)
  let key = MarkdownSemanticKey::LinkDestination("1:2|3:")
  inspect(key.projection_key(), content="15:LinkDestination6:1:2|3:")
  let leaf = MarkdownIdentityLeaf::new(origin, key).projection_leaf()
  let expected_leaf = @projection.ProjectionLeaf::new(
    2, 8, "15:LinkDestination6:1:2|3:",
  )
  inspect(leaf == expected_leaf, content="true")
  let heading_twelve = MarkdownSemanticKey::Heading(12).projection_key()
  let heading_one = MarkdownSemanticKey::Heading(1).projection_key()
  inspect(heading_twelve != heading_one, content="true")
}

///|
test "MarkdownIR identity keys: link label fingerprint erases formatting only" {
  let text_origin = MarkdownIROrigin(start=0, end=5)
  let wrapper_origin = MarkdownIROrigin(start=0, end=7)
  let plain = [MarkdownIR::text("plain", text_origin)]
  let formatted = [
    MarkdownIR::bold(
      [MarkdownIR::text("plain", text_origin)],
      wrapper_origin,
      Some(text_origin),
    ),
  ]
  let changed = [MarkdownIR::text("changed", text_origin)]
  let plain_fingerprint = normalized_link_label_fingerprint(plain)
  let formatted_fingerprint = normalized_link_label_fingerprint(formatted)
  let changed_fingerprint = normalized_link_label_fingerprint(changed)
  inspect(plain_fingerprint == formatted_fingerprint, content="true")
  inspect(plain_fingerprint != changed_fingerprint, content="true")
}

///|
test "MarkdownIR identity keys: link label fingerprint retains child boundaries" {
  let origin = MarkdownIROrigin(start=0, end=1)
  let link_with_one_child_then_text = [
    MarkdownIR::link(
      [MarkdownIR::text("a", origin)],
      "u",
      origin,
      Some(origin),
      Some(origin),
    ),
    MarkdownIR::text("b", origin),
  ]
  let link_with_two_children = [
    MarkdownIR::link(
      [MarkdownIR::text("a", origin), MarkdownIR::text("b", origin)],
      "u",
      origin,
      Some(origin),
      Some(origin),
    ),
  ]
  let split_fingerprint = normalized_link_label_fingerprint(
    link_with_one_child_then_text,
  )
  let nested_fingerprint = normalized_link_label_fingerprint(
    link_with_two_children,
  )
  inspect(split_fingerprint != nested_fingerprint, content="true")
}

///|
test "MarkdownIR identity leaves: preserve parsed semantic anchor order" {
  let source = "# [*plain*](u)\n"
  let (cst, _) = parse_cst(source)
  let ir = experimental_markdown_ir_from_syntax(@seam.SyntaxNode::from_cst(cst))
  inspect(
    @debug.to_string(markdown_ir_identity_leaves(ir)),
    content=@debug.to_string(
      [
        MarkdownIdentityLeaf::new(
          MarkdownIROrigin(start=2, end=14),
          MarkdownSemanticKey::Heading(1),
        ),
        MarkdownIdentityLeaf::new(
          MarkdownIROrigin(start=3, end=10),
          MarkdownSemanticKey::LinkLabel,
        ),
        MarkdownIdentityLeaf::new(
          MarkdownIROrigin(start=12, end=13),
          MarkdownSemanticKey::LinkDestination("u"),
        ),
        MarkdownIdentityLeaf::new(
          MarkdownIROrigin(start=4, end=9),
          MarkdownSemanticKey::Text,
        ),
      ],
    ),
  )
}
