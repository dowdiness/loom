///|
fn parsed_markdown_identity_leaves(
  source : String,
) -> Array[MarkdownIdentityLeaf] raise {
  let (cst, _) = parse_cst(source)
  let ir = experimental_markdown_ir_from_syntax(@seam.SyntaxNode::from_cst(cst))
  markdown_ir_identity_leaves(ir)
}

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
    content=@debug.to_string([
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
    ]),
  )
}

///|
test "MarkdownIR identity leaves: anchor parsed paragraph and list item payloads" {
  inspect(
    @debug.to_string(parsed_markdown_identity_leaves("text\n")),
    content=@debug.to_string([
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=0, end=4),
        MarkdownSemanticKey::Paragraph,
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=0, end=4),
        MarkdownSemanticKey::Text,
      ),
    ]),
  )
  inspect(
    @debug.to_string(parsed_markdown_identity_leaves("- text\n")),
    content=@debug.to_string([
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=2, end=6),
        MarkdownSemanticKey::UnorderedListItem(false),
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=2, end=6),
        MarkdownSemanticKey::Paragraph,
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=2, end=6),
        MarkdownSemanticKey::Text,
      ),
    ]),
  )
  inspect(
    @debug.to_string(parsed_markdown_identity_leaves("1. text\n")),
    content=@debug.to_string([
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=3, end=7),
        MarkdownSemanticKey::OrderedListItem(false),
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=3, end=7),
        MarkdownSemanticKey::Paragraph,
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=3, end=7),
        MarkdownSemanticKey::Text,
      ),
    ]),
  )
}

///|
test "MarkdownIR identity leaves: anchor parsed code payloads" {
  inspect(
    @debug.to_string(parsed_markdown_identity_leaves("```rust\ncode\n```\n")),
    content=@debug.to_string([
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=8, end=12),
        MarkdownSemanticKey::CodeBlock("rust"),
      ),
    ]),
  )
  inspect(
    @debug.to_string(parsed_markdown_identity_leaves("`span`\n")),
    content=@debug.to_string([
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=0, end=6),
        MarkdownSemanticKey::Paragraph,
      ),
      MarkdownIdentityLeaf::new(
        MarkdownIROrigin(start=1, end=5),
        MarkdownSemanticKey::InlineCode,
      ),
    ]),
  )
}

///|
fn parsed_markdown_ir(source : String) -> MarkdownIR raise {
  let (cst, _) = parse_cst(source)
  experimental_markdown_ir_from_syntax(@seam.SyntaxNode::from_cst(cst))
}

///|
fn stable_markdown_identity_ids(
  leaves : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
) -> Array[String] {
  leaves.map(leaf => leaf.id.value)
}


///|
fn successful_identity_transition(
  initial_source : String,
  next_source : String,
  edit : @core.Edit?,
) -> (Array[String], Array[String]) raise {
  let tracker = MarkdownProjectionIdentityTracker::new()
  let initial = tracker.realign_success(
    initial_source,
    parsed_markdown_ir(initial_source),
    None,
  )
  tracker.commit_success(initial_source, initial)
  let next = tracker.realign_success(
    next_source,
    parsed_markdown_ir(next_source),
    edit,
  )
  (stable_markdown_identity_ids(initial), stable_markdown_identity_ids(next))
}

///|
test "MarkdownIR identity tracker: formatting a link label preserves semantic identities" {
  let tracker = MarkdownProjectionIdentityTracker::new()
  let plain_source = "[plain](u)\n"
  let plain = tracker.realign_success(
    plain_source,
    parsed_markdown_ir(plain_source),
    None,
  )
  tracker.commit_success(plain_source, plain)
  let formatted_source = "[**plain**](u)\n"
  let formatted = tracker.realign_success(
    formatted_source,
    parsed_markdown_ir(formatted_source),
    None,
  )
  inspect(
    stable_markdown_identity_ids(formatted),
    content="[markdown#0, markdown#1, markdown#2, markdown#3]",
  )
}

///|
test "MarkdownIR identity tracker: changed link label receives a fresh id" {
  let tracker = MarkdownProjectionIdentityTracker::new()
  let plain_source = "[plain](u)\n"
  let plain = tracker.realign_success(
    plain_source,
    parsed_markdown_ir(plain_source),
    None,
  )
  tracker.commit_success(plain_source, plain)
  let changed_source = "[changed](u)\n"
  let changed = tracker.realign_success(
    changed_source,
    parsed_markdown_ir(changed_source),
    None,
  )
  inspect(changed[1].id.value == "markdown#1", content="false")
}

///|
test "MarkdownIR identity tracker: surface rewrites preserve unchanged payload ids" {
  let (atx, setext) = successful_identity_transition(
    "# Title\n",
    "Title\n=====\n",
    Some(@core.Edit::new(0, 8, 12)),
  )
  inspect(atx == setext, content="true")
  let (dash, star) = successful_identity_transition(
    "- item\n",
    "* item\n",
    Some(@core.Edit::new(0, 1, 1)),
  )
  inspect(dash == star, content="true")
  let (backtick, tilde) = successful_identity_transition(
    "```\ncode\n```\n",
    "~~~\ncode\n~~~\n",
    None,
  )
  inspect(backtick.length() == tilde.length(), content="true")
  inspect(backtick == tilde, content="true")
}

///|
test "MarkdownIR identity tracker: distinct list payloads survive a surface rewrite" {
  let (dash, star) = successful_identity_transition(
    "- first\n- second\n",
    "* first\n* second\n",
    None,
  )
  inspect(dash == star, content="true")
}


///|
test "MarkdownIR identity tracker: sibling reorders reallocate moved payload ids" {
  let (before, after) = successful_identity_transition(
    "- first\n- second\n",
    "- second\n- first\n",
    None,
  )
  inspect(before[0] == after[0], content="false")
  inspect(before[0] == after[2], content="false")
  inspect(before[1] == after[1], content="false")
  inspect(before[1] == after[3], content="false")
}

///|
test "MarkdownIR identity tracker: duplicate list siblings remain ambiguous" {
  let (dash, star) = successful_identity_transition(
    "- same\n* same\n",
    "* same\n- same\n",
    None,
  )
  for id in star {
    for previous_id in dash {
      inspect(id == previous_id, content="false")
    }
  }
}
///|
test "MarkdownIR identity matching: duplicate payloads remain ambiguous" {
  let origin = MarkdownIROrigin(start=0, end=1)
  let first = MarkdownIdentityCandidate::new(
    origin,
    MarkdownSemanticKey::Text,
    "first",
    None,
  )
  let second = MarkdownIdentityCandidate::new(
    origin,
    MarkdownSemanticKey::Text,
    "second",
    None,
  )
  let duplicate = MarkdownIdentityCandidate::new(
    origin,
    MarkdownSemanticKey::Text,
    "first",
    None,
  )
  inspect(
    markdown_matching_candidate_count([first, second], first, None),
    content="1",
  )
  inspect(
    markdown_matching_candidate_count([first, duplicate], first, None),
    content="2",
  )
}

///|
test "MarkdownIR identity tracker: semantic changes reset their owner" {
  let (heading, deeper_heading) = successful_identity_transition(
    "# Title\n",
    "## Title\n",
    Some(@core.Edit::new(1, 0, 1)),
  )
  inspect(heading[0] == deeper_heading[0], content="false")
  let (named_code, other_code) = successful_identity_transition(
    "```rust\ncode\n```\n",
    "```moonbit\ncode\n```\n",
    None,
  )
  inspect(named_code[0] == other_code[0], content="false")
  let (title, renamed) = successful_identity_transition(
    "# Title\n",
    "# Renamed\n",
    Some(@core.Edit::new(2, 5, 7)),
  )
  inspect(title[0] == renamed[0], content="false")
  let (link_before, link_after) = successful_identity_transition(
    "[label](one)\n",
    "[label](two)\n",
    Some(@core.Edit::new(8, 3, 3)),
  )
  inspect(link_before[1] == link_after[1], content="true")
  inspect(link_before[2] == link_after[2], content="false")
}

///|
test "MarkdownIR identity tracker: failed input retains the last-good baseline" {
  let tracker = MarkdownProjectionIdentityTracker::new()
  let source = "# Title\n"
  let initial = tracker.realign_success(
    source,
    parsed_markdown_ir(source),
    None,
  )
  tracker.commit_success(source, initial)
  let malformed = "# Title\n["
  tracker.record_failed_input(
    malformed,
    Some(source),
    Some(@core.Edit::new(8, 0, 1)),
  )
  let recovered = tracker.realign_success(
    source,
    parsed_markdown_ir(source),
    None,
  )
  inspect(
    stable_markdown_identity_ids(initial) ==
    stable_markdown_identity_ids(recovered),
    content="true",
  )
}

