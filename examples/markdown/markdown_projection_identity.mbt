///|
priv enum MarkdownSemanticKey {
  Heading(Int)
  Paragraph
  UnorderedListItem(Bool)
  OrderedListItem(Bool)
  CodeBlock(String)
  Text
  InlineCode
  LinkLabel
  LinkDestination(String)
} derive(Eq, Debug)

///|
priv struct MarkdownNodeId {
  value : String
} derive(Eq, Debug)

///|
fn MarkdownNodeId::new(value : String) -> MarkdownNodeId {
  { value, }
}

///|
priv struct MarkdownProjectionIdentityTracker {
  tracker : @projection.ProjectionIdentityTracker[MarkdownNodeId]
  mut next_id : Int
  mut last_good_candidates : Array[MarkdownIdentityCandidate]?
  mut preview_candidates : Array[MarkdownIdentityCandidate]?
}

///|
fn MarkdownProjectionIdentityTracker::new() -> MarkdownProjectionIdentityTracker {
  {
    tracker: @projection.ProjectionIdentityTracker::new(),
    next_id: 0,
    last_good_candidates: None,
    preview_candidates: None,
  }
}

///|
fn MarkdownProjectionIdentityTracker::realign_success(
  self : MarkdownProjectionIdentityTracker,
  source : String,
  ir : MarkdownIR,
  edit : @core.Edit?,
) -> Array[@projection.StableProjectionLeaf[MarkdownNodeId]] {
  let candidates = markdown_ir_identity_candidates(ir)
  let leaves = candidates.map(candidate => candidate.projection_leaf())
  let baseline = self.tracker.baseline()
  let preview = self.tracker.realign_success_with_optional_edit(
    source,
    leaves,
    fn(_leaf) { self.allocate_id() },
    edit,
  )
  self.preview_candidates = Some(candidates)
  apply_markdown_local_identity_overrides(
    baseline,
    self.last_good_candidates,
    candidates,
    preview,
    fn() { self.allocate_id() },
  )
}

///|
fn MarkdownProjectionIdentityTracker::record_failed_input(
  self : MarkdownProjectionIdentityTracker,
  current_source : String,
  source_before_edit : String?,
  edit : @core.Edit?,
) -> Unit {
  self.preview_candidates = None
  self.tracker.record_failed_input_with_optional_edit(
    current_source, source_before_edit, edit,
  )
}

///|
fn MarkdownProjectionIdentityTracker::commit_success(
  self : MarkdownProjectionIdentityTracker,
  source : String,
  stable : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
) -> Unit {
  self.tracker.commit_success(source, stable)
  self.last_good_candidates = self.preview_candidates
  self.preview_candidates = None
}

///|
fn MarkdownProjectionIdentityTracker::allocate_id(
  self : MarkdownProjectionIdentityTracker,
) -> MarkdownNodeId {
  let id = MarkdownNodeId::new("markdown#" + self.next_id.to_string())
  self.next_id += 1
  id
}

///|
fn MarkdownIdentityCandidate::projection_leaf(
  self : MarkdownIdentityCandidate,
) -> @projection.ProjectionLeaf {
  self.leaf.projection_leaf()
}

///|
fn markdown_candidates_share_context(
  previous : MarkdownIdentityCandidate,
  next : MarkdownIdentityCandidate,
  previous_parent : Int?,
) -> Bool {
  previous.leaf.key == next.leaf.key && previous.parent == previous_parent
}

///|
fn markdown_candidates_share_identity(
  previous : MarkdownIdentityCandidate,
  next : MarkdownIdentityCandidate,
  previous_parent : Int?,
) -> Bool {
  markdown_candidates_share_context(previous, next, previous_parent) &&
  previous.payload == next.payload
}

///|
fn markdown_matching_previous_parent(
  next : MarkdownIdentityCandidate,
  matched_previous : Map[Int, Int],
) -> Int? {
  match next.parent {
    None => None
    Some(parent) => matched_previous.get(parent)
  }
}

///|
fn markdown_matching_context_candidate_count(
  candidates : Array[MarkdownIdentityCandidate],
  next : MarkdownIdentityCandidate,
  previous_parent : Int?,
) -> Int {
  let mut count = 0
  for candidate in candidates {
    if markdown_candidates_share_context(candidate, next, previous_parent) {
      count += 1
    }
  }
  count
}

///|
fn markdown_matching_context_candidate_index(
  candidates : Array[MarkdownIdentityCandidate],
  next : MarkdownIdentityCandidate,
  previous_parent : Int?,
) -> Int? {
  for i, candidate in candidates {
    if markdown_candidates_share_context(candidate, next, previous_parent) {
      return Some(i)
    }
  }
  None
}

///|
fn markdown_matching_candidate_count(
  candidates : Array[MarkdownIdentityCandidate],
  next : MarkdownIdentityCandidate,
  previous_parent : Int?,
) -> Int {
  let mut count = 0
  for candidate in candidates {
    if markdown_candidates_share_identity(candidate, next, previous_parent) {
      count += 1
    }
  }
  count
}

///|
fn markdown_matching_candidate_index(
  candidates : Array[MarkdownIdentityCandidate],
  next : MarkdownIdentityCandidate,
  previous_parent : Int?,
) -> Int? {
  for i, candidate in candidates {
    if markdown_candidates_share_identity(candidate, next, previous_parent) {
      return Some(i)
    }
  }
  None
}

///|
fn markdown_stable_id_is_used_elsewhere(
  leaves : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
  id : MarkdownNodeId,
  except : Int,
) -> Bool {
  for i, leaf in leaves {
    if i != except && leaf.id == id {
      return true
    }
  }
  false
}

///|
fn markdown_stable_id_is_in_baseline(
  baseline : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
  id : MarkdownNodeId,
) -> Bool {
  for leaf in baseline {
    if leaf.id == id {
      return true
    }
  }
  false
}

///|
fn markdown_refresh_preview_id_if_unproven(
  baseline : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
  candidate : MarkdownIdentityCandidate,
  preview : @projection.StableProjectionLeaf[MarkdownNodeId],
  make_id : () -> MarkdownNodeId,
) -> @projection.StableProjectionLeaf[MarkdownNodeId] {
  if !markdown_stable_id_is_in_baseline(baseline, preview.id) {
    return preview
  }
  let leaf = candidate.projection_leaf()
  @projection.StableProjectionLeaf::new(
    leaf.start,
    leaf.end,
    leaf.key,
    make_id(),
  )
}

///|
fn markdown_stable_ids_are_unique(
  leaves : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
) -> Bool {
  for i, leaf in leaves {
    if markdown_stable_id_is_used_elsewhere(leaves, leaf.id, i) {
      return false
    }
  }
  true
}

///|
fn apply_markdown_local_identity_overrides(
  baseline : @projection.ProjectionIdentityBaseline[MarkdownNodeId]?,
  previous : Array[MarkdownIdentityCandidate]?,
  next : Array[MarkdownIdentityCandidate],
  preview : Array[@projection.StableProjectionLeaf[MarkdownNodeId]],
  make_id : () -> MarkdownNodeId,
) -> Array[@projection.StableProjectionLeaf[MarkdownNodeId]] {
  match baseline {
    None => preview
    Some(baseline) =>
      match previous {
        None => preview
        Some(previous) => {
          let previous_stable = baseline.leaves()
          if previous_stable.length() != previous.length() {
            return preview
          }
          let result = preview.copy()
          let matched_previous : Map[Int, Int] = {}
          for next_index, next_candidate in next {
            let previous_parent = markdown_matching_previous_parent(
              next_candidate, matched_previous,
            )
            if next_candidate.parent is Some(_) && previous_parent is None {
              result[next_index] = markdown_refresh_preview_id_if_unproven(
                previous_stable,
                next_candidate,
                result[next_index],
                make_id,
              )
              continue
            }
            let has_unique_payload =
              markdown_matching_candidate_count(
                previous, next_candidate, previous_parent,
              ) ==
                1 &&
              markdown_matching_candidate_count(
                next,
                next_candidate,
                next_candidate.parent,
              ) ==
                1
            if has_unique_payload {
              match
                markdown_matching_candidate_index(
                  previous, next_candidate, previous_parent,
                ) {
                Some(previous_index) => {
                  let previous_id = previous_stable[previous_index].id
                  if result[next_index].id == previous_id {
                    matched_previous[next_index] = previous_index
                  } else if !markdown_stable_id_is_used_elsewhere(
                      result, previous_id, next_index,
                    ) {
                    let next_leaf = next_candidate.projection_leaf()
                    result[next_index] = @projection.StableProjectionLeaf::new(
                      next_leaf.start,
                      next_leaf.end,
                      next_leaf.key,
                      previous_id,
                    )
                    matched_previous[next_index] = previous_index
                  }
                }
                None => ()
              }
            } else {
              if markdown_matching_context_candidate_count(
                previous, next_candidate, previous_parent,
              ) ==
                1 &&
                markdown_matching_context_candidate_count(
                  next,
                  next_candidate,
                  next_candidate.parent,
                ) ==
                  1 {
                match
                  markdown_matching_context_candidate_index(
                    previous, next_candidate, previous_parent,
                  ) {
                  Some(previous_index) =>
                    matched_previous[next_index] = previous_index
                  None => ()
                }
              }
              result[next_index] = markdown_refresh_preview_id_if_unproven(
                previous_stable,
                next_candidate,
                result[next_index],
                make_id,
              )
            }
          }
          if result.length() == next.length() &&
            markdown_stable_ids_are_unique(result) {
            result
          } else {
            preview
          }
        }
      }
  }
}

///|
priv struct MarkdownIdentityLeaf {
  anchor : MarkdownIROrigin
  key : MarkdownSemanticKey
} derive(Eq, Debug)

///|
fn MarkdownIdentityLeaf::new(
  anchor : MarkdownIROrigin,
  key : MarkdownSemanticKey,
) -> MarkdownIdentityLeaf {
  { anchor, key }
}

///|
fn MarkdownIdentityLeaf::projection_leaf(
  self : MarkdownIdentityLeaf,
) -> @projection.ProjectionLeaf {
  @projection.ProjectionLeaf::new(
    self.anchor.start(),
    self.anchor.end(),
    self.key.projection_key(),
  )
}

///|
priv struct MarkdownIdentityCandidate {
  leaf : MarkdownIdentityLeaf
  payload : String
  parent : Int?
}

///|
fn MarkdownIdentityCandidate::new(
  anchor : MarkdownIROrigin,
  key : MarkdownSemanticKey,
  payload : String,
  parent : Int?,
) -> MarkdownIdentityCandidate {
  { leaf: MarkdownIdentityLeaf::new(anchor, key), payload, parent }
}

///|
fn append_key_component(buf : StringBuilder, component : String) -> Unit {
  buf.write_string(component.length().to_string())
  buf.write_string(":")
  buf.write_string(component)
}

///|
fn MarkdownSemanticKey::projection_key(self : MarkdownSemanticKey) -> String {
  let buf = StringBuilder::new()
  match self {
    Heading(depth) => {
      append_key_component(buf, "Heading")
      append_key_component(buf, depth.to_string())
    }
    Paragraph => append_key_component(buf, "Paragraph")
    UnorderedListItem(spread) => {
      append_key_component(buf, "UnorderedListItem")
      append_key_component(buf, spread.to_string())
    }
    OrderedListItem(spread) => {
      append_key_component(buf, "OrderedListItem")
      append_key_component(buf, spread.to_string())
    }
    CodeBlock(language) => {
      append_key_component(buf, "CodeBlock")
      append_key_component(buf, language)
    }
    Text => append_key_component(buf, "Text")
    InlineCode => append_key_component(buf, "InlineCode")
    LinkLabel => append_key_component(buf, "LinkLabel")
    LinkDestination(destination) => {
      append_key_component(buf, "LinkDestination")
      append_key_component(buf, destination)
    }
  }
  buf.to_string()
}

///|
fn normalized_link_label_fingerprint(children : Array[MarkdownIR]) -> String {
  let buf = StringBuilder::new()
  for child in children {
    append_normalized_link_label_node(buf, child)
  }
  buf.to_string()
}


///|
fn append_normalized_link_label_node(
  buf : StringBuilder,
  ir : MarkdownIR,
) -> Unit {
  match ir.node {
    Bold(children, _) | Italic(children, _) =>
      for child in children {
        append_normalized_link_label_node(buf, child)
      }
    _ => append_key_component(buf, normalized_link_label_node_fingerprint(ir))
  }
}

///|
fn normalized_link_label_node_fingerprint(ir : MarkdownIR) -> String {
  let buf = StringBuilder::new()
  match ir.node {
    Text(value) => {
      append_key_component(buf, "Text")
      append_key_component(buf, value)
    }
    InlineCode(value, _) => {
      append_key_component(buf, "InlineCode")
      append_key_component(buf, value)
    }
    HardBreak(_) => append_key_component(buf, "HardBreak")
    Link(children, destination, _, _) => {
      append_key_component(buf, "Link")
      append_key_component(buf, destination)
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    Unsupported(message) => {
      append_key_component(buf, "Unsupported")
      append_key_component(buf, message)
    }
    Raw(value, _) => {
      append_key_component(buf, "Raw")
      append_key_component(buf, value)
    }
    Recovered(message, _) => {
      append_key_component(buf, "Recovered")
      append_key_component(buf, message)
    }
    Document(children) => {
      append_key_component(buf, "Document")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    Heading(depth, children, _) => {
      append_key_component(buf, "Heading")
      append_key_component(buf, depth.to_string())
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    Paragraph(children, _) => {
      append_key_component(buf, "Paragraph")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    BlockQuote(children) => {
      append_key_component(buf, "BlockQuote")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    UnorderedList(children, _, _) => {
      append_key_component(buf, "UnorderedList")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    OrderedList(children, _, _) => {
      append_key_component(buf, "OrderedList")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    ListItem(children, _, _, _) => {
      append_key_component(buf, "ListItem")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    OrderedListItem(children, _, _, _) => {
      append_key_component(buf, "OrderedListItem")
      append_key_component(buf, normalized_link_label_fingerprint(children))
    }
    CodeBlock(language, value, _) => {
      append_key_component(buf, "CodeBlock")
      append_key_component(buf, language)
      append_key_component(buf, value)
    }
    HtmlBlock(value, _) => {
      append_key_component(buf, "HtmlBlock")
      append_key_component(buf, value)
    }
    ThematicBreak => append_key_component(buf, "ThematicBreak")
    Bold(_, _) | Italic(_, _) =>
      abort("formatting wrapper must be erased before fingerprinting")
  }
  buf.to_string()
}

///|
fn markdown_ir_identity_leaves(ir : MarkdownIR) -> Array[MarkdownIdentityLeaf] {
  markdown_ir_identity_candidates(ir).map(candidate => candidate.leaf)
}

///|
fn markdown_ir_identity_candidates(
  ir : MarkdownIR,
) -> Array[MarkdownIdentityCandidate] {
  let candidates = []
  collect_markdown_ir_identity_candidates(ir, candidates, None)
  candidates
}

///|
fn append_markdown_identity_candidate(
  candidates : Array[MarkdownIdentityCandidate],
  origin : MarkdownIROrigin?,
  key : MarkdownSemanticKey,
  payload : String,
  parent : Int?,
) -> Int? {
  match origin {
    Some(anchor) => {
      let index = candidates.length()
      candidates.push(
        MarkdownIdentityCandidate::new(anchor, key, payload, parent),
      )
      Some(index)
    }
    None => None
  }
}

///|
fn markdown_identity_child_context(current : Int?, parent : Int?) -> Int? {
  match current {
    Some(index) => Some(index)
    None => parent
  }
}

///|
fn collect_markdown_ir_identity_candidates(
  ir : MarkdownIR,
  candidates : Array[MarkdownIdentityCandidate],
  parent : Int?,
) -> Unit {
  match ir.node {
    Document(children) =>
      collect_markdown_ir_identity_children(children, candidates, parent)
    Heading(depth, children, content_origin) => {
      let current = append_markdown_identity_candidate(
        candidates,
        content_origin,
        Heading(depth),
        normalized_link_label_fingerprint(children),
        parent,
      )
      collect_markdown_ir_identity_children(
        children,
        candidates,
        markdown_identity_child_context(current, parent),
      )
    }
    Paragraph(children, content_origin) => {
      let current = append_markdown_identity_candidate(
        candidates,
        content_origin,
        Paragraph,
        normalized_link_label_fingerprint(children),
        parent,
      )
      collect_markdown_ir_identity_children(
        children,
        candidates,
        markdown_identity_child_context(current, parent),
      )
    }
    BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _) =>
      collect_markdown_ir_identity_children(children, candidates, parent)
    ListItem(children, spread, content_origin, _) => {
      let current = append_markdown_identity_candidate(
        candidates,
        content_origin,
        UnorderedListItem(spread),
        normalized_link_label_fingerprint(children),
        parent,
      )
      collect_markdown_ir_identity_children(
        children,
        candidates,
        markdown_identity_child_context(current, parent),
      )
    }
    OrderedListItem(children, spread, content_origin, _) => {
      let current = append_markdown_identity_candidate(
        candidates,
        content_origin,
        OrderedListItem(spread),
        normalized_link_label_fingerprint(children),
        parent,
      )
      collect_markdown_ir_identity_children(
        children,
        candidates,
        markdown_identity_child_context(current, parent),
      )
    }
    CodeBlock(language, value, content_origin) =>
      ignore(
        append_markdown_identity_candidate(
          candidates,
          content_origin,
          CodeBlock(language),
          value,
          parent,
        ),
      )
    HtmlBlock(_, _)
    | ThematicBreak
    | HardBreak(_)
    | Raw(_, _)
    | Recovered(_, _)
    | Unsupported(_) => ()
    Text(value) =>
      candidates.push(
        MarkdownIdentityCandidate::new(ir.origin, Text, value, parent),
      )
    Bold(children, _) | Italic(children, _) =>
      collect_markdown_ir_identity_children(children, candidates, parent)
    InlineCode(value, content_origin) =>
      ignore(
        append_markdown_identity_candidate(
          candidates,
          content_origin,
          InlineCode,
          value,
          parent,
        ),
      )
    Link(children, destination, label_origin, destination_origin) => {
      let label = append_markdown_identity_candidate(
        candidates,
        label_origin,
        LinkLabel,
        normalized_link_label_fingerprint(children),
        parent,
      )
      let link_context = markdown_identity_child_context(label, parent)
      ignore(
        append_markdown_identity_candidate(
          candidates,
          destination_origin,
          LinkDestination(destination),
          destination,
          link_context,
        ),
      )
      collect_markdown_ir_identity_children(children, candidates, link_context)
    }
  }
}

///|
fn collect_markdown_ir_identity_children(
  children : Array[MarkdownIR],
  candidates : Array[MarkdownIdentityCandidate],
  parent : Int?,
) -> Unit {
  for child in children {
    collect_markdown_ir_identity_candidates(child, candidates, parent)
  }
}
