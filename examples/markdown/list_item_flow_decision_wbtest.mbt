///|
fn list_item_flow_decision_name(decision : ListItemFlowDecision) -> String {
  match decision {
    Stop => "stop"
    IndentedCode => "indented-code"
    NestedList => "nested-list"
    PrefixedBlock => "prefixed-block"
    PrefixedParagraph => "prefixed-paragraph"
  }
}

///|
fn assert_list_item_flow_decision(
  current : Token,
  next : Token,
  indent : Int?,
  context : ListItemFlowContext,
  code_indent : Int,
  expected : String,
) -> Unit raise {
  inspect(
    list_item_flow_decision_name(
      decide_list_item_indented_flow(
        current, next, indent, context, code_indent, false,
      ),
    ),
    content=expected,
  )
}

///|
fn assert_prefixed_list_item_block_decision(
  current : Token,
  next : Token,
  indent : Int,
  context : ListItemFlowContext,
  code_indent : Int,
  expected : String,
) -> Unit raise {
  inspect(
    list_item_flow_decision_name(
      decide_list_item_indented_flow(
        current,
        next,
        Some(indent),
        context,
        code_indent,
        true,
      ),
    ),
    content=expected,
  )
}

///|
test "list-item indented-flow decision matrix" {
  let context = ListItemFlowContext::{
    content_indent: 4,
    marker_end_column: 4,
    allow_ordered_marker: true,
  }
  // Non-indentation and below-content indentation stop before token dispatch.
  assert_list_item_flow_decision(
    Text("body"),
    Text("next"),
    None,
    context,
    8,
    "stop",
  )
  assert_list_item_flow_decision(
    Indentation("   "),
    Text("next"),
    Some(3),
    context,
    8,
    "stop",
  )
  // Content indentation owns nested markers and all other prefixed blocks.
  assert_list_item_flow_decision(
    Indentation("    "),
    ListMarker,
    Some(4),
    context,
    8,
    "nested-list",
  )
  assert_list_item_flow_decision(
    Indentation("    "),
    OrderedListMarker(OrderedListMarker(start=1, delimiter=Period)),
    Some(4),
    context,
    8,
    "nested-list",
  )
  assert_list_item_flow_decision(
    Indentation("    "),
    HeadingMarker(2),
    Some(4),
    context,
    8,
    "prefixed-block",
  )
  assert_list_item_flow_decision(
    Indentation("       "),
    Text("body"),
    Some(7),
    context,
    8,
    "prefixed-paragraph",
  )
  assert_list_item_flow_decision(
    Indentation("    "),
    ThematicBreak,
    Some(4),
    context,
    8,
    "prefixed-block",
  )
  assert_list_item_flow_decision(
    Indentation("    "),
    BlockQuoteMarker,
    Some(4),
    context,
    8,
    "prefixed-paragraph",
  )
  assert_prefixed_list_item_block_decision(
    Indentation("    "),
    BlockQuoteMarker,
    4,
    context,
    8,
    "prefixed-block",
  )
  assert_list_item_flow_decision(
    Indentation("    "),
    CodeFenceOpen(3, ""),
    Some(4),
    context,
    8,
    "prefixed-block",
  )
  assert_list_item_flow_decision(
    Indentation("    "),
    HtmlBlockOpen("<div>"),
    Some(4),
    context,
    8,
    "prefixed-block",
  )
  // The code threshold is inclusive and has precedence at the boundary.
  assert_list_item_flow_decision(
    Indentation("        "),
    Text("body"),
    Some(8),
    context,
    8,
    "indented-code",
  )
}
