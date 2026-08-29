///|
/// Opaque MarkdownIR kinds that the checked canonical formatter cannot prove
/// semantically round-trippable.
pub(all) enum MarkdownIRCanonicalOpaqueKind {
  Raw
  Recovered
  Unsupported
} derive(Eq, Debug)

///|
/// Structured failure returned by checked canonical MarkdownIR formatting.
pub(all) enum MarkdownIRCanonicalFormatFailure {
  ExpectedDocument
  OpaqueNode(MarkdownIRCanonicalOpaqueKind, MarkdownIROrigin?)
  Unrepresentable
  SearchLimitExceeded(observed~ : Int, limit~ : Int)
} derive(Eq, Debug)

///|
fn MarkdownIRCanonicalOpaqueKind::label(
  self : MarkdownIRCanonicalOpaqueKind,
) -> String {
  match self {
    MarkdownIRCanonicalOpaqueKind::Raw => "Raw"
    MarkdownIRCanonicalOpaqueKind::Recovered => "Recovered"
    MarkdownIRCanonicalOpaqueKind::Unsupported => "Unsupported"
  }
}

///|
fn MarkdownIRCanonicalFormatFailure::diagnostic(
  self : MarkdownIRCanonicalFormatFailure,
) -> String {
  match self {
    ExpectedDocument => "checked canonical formatting requires a Document root"
    OpaqueNode(kind, origin) => {
      let buf = StringBuilder::StringBuilder()
      buf.write_string("checked canonical formatting rejects opaque ")
      buf.write_string(kind.label())
      match origin {
        Some(origin) => {
          buf.write_string(" at ")
          buf.write_string(origin.start().to_string())
          buf.write_string("..")
          buf.write_string(origin.end().to_string())
        }
        None => ()
      }
      buf.to_string()
    }
    Unrepresentable =>
      "no candidate in the canonical formatting grammar preserved document semantics"
    SearchLimitExceeded(observed~, limit~) => {
      let buf = StringBuilder::StringBuilder()
      buf.write_string("canonical formatting search limit exceeded: observed ")
      buf.write_string(observed.to_string())
      buf.write_string(", limit ")
      buf.write_string(limit.to_string())
      buf.to_string()
    }
  }
}

///|
priv enum MarkdownIRCanonicalSemantic {
  SemanticDocument(Array[MarkdownIRCanonicalSemantic])
  SemanticHeading(Int, Array[MarkdownIRCanonicalSemantic])
  SemanticParagraph(Array[MarkdownIRCanonicalSemantic])
  SemanticBlockQuote(Array[MarkdownIRCanonicalSemantic])
  SemanticUnorderedList(Array[MarkdownIRCanonicalSemantic], Bool)
  SemanticOrderedList(Array[MarkdownIRCanonicalSemantic], Bool, Int)
  SemanticListItem(Array[MarkdownIRCanonicalSemantic], Bool, Bool?)
  SemanticOrderedListItem(Array[MarkdownIRCanonicalSemantic], Bool, Bool?)
  SemanticCodeBlock(String, String)
  SemanticHtmlBlock(String)
  SemanticThematicBreak
  SemanticText(String)
  SemanticBold(Array[MarkdownIRCanonicalSemantic])
  SemanticItalic(Array[MarkdownIRCanonicalSemantic])
  SemanticInlineCode(String)
  SemanticLink(Array[MarkdownIRCanonicalSemantic], String, String?)
  SemanticImage(Array[MarkdownIRCanonicalSemantic], String, String?)
  SemanticAutolink(AutolinkKind, String, String)
  SemanticInlineHtml(String)
  SemanticSoftBreak
  SemanticHardBreak
} derive(Eq, Debug)

///|
fn markdown_ir_canonical_semantic_children(
  children : Array[MarkdownIR],
) -> Array[MarkdownIRCanonicalSemantic]? {
  let result : Array[MarkdownIRCanonicalSemantic] = []
  let mut text_buf = StringBuilder::StringBuilder()
  let mut has_text = false
  for child in children {
    match child.node {
      Text(value) => {
        text_buf.write_string(value)
        has_text = true
      }
      _ => {
        if has_text {
          result.push(SemanticText(text_buf.to_string()))
          text_buf = StringBuilder::StringBuilder()
          has_text = false
        }
        match markdown_ir_canonical_semantic(child) {
          Some(semantic) => result.push(semantic)
          None => return None
        }
      }
    }
  }
  if has_text {
    result.push(SemanticText(text_buf.to_string()))
  }
  Some(result)
}

///|
fn markdown_ir_canonical_semantic(
  ir : MarkdownIR,
) -> MarkdownIRCanonicalSemantic? {
  match ir.node {
    Document(children) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticDocument(children))
        None => None
      }
    Heading(depth, children, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticHeading(depth, children))
        None => None
      }
    Paragraph(children, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticParagraph(children))
        None => None
      }
    BlockQuote(children) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticBlockQuote(children))
        None => None
      }
    UnorderedList(children, spread, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticUnorderedList(children, spread))
        None => None
      }
    OrderedList(children, spread, marker) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => {
          let start = match marker {
            Some(marker) => marker.start()
            None => 1
          }
          Some(SemanticOrderedList(children, spread, start))
        }
        None => None
      }
    ListItem(children, spread, _, _, task) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) =>
          Some(
            SemanticListItem(children, spread, task.map(task => task.checked())),
          )
        None => None
      }
    OrderedListItem(children, spread, _, _, task) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) =>
          Some(
            SemanticOrderedListItem(
              children,
              spread,
              task.map(task => task.checked()),
            ),
          )
        None => None
      }
    CodeBlock(info, value, _) => Some(SemanticCodeBlock(info, value))
    HtmlBlock(value, _) => Some(SemanticHtmlBlock(value))
    ThematicBreak => Some(SemanticThematicBreak)
    Text(value) => Some(SemanticText(value))
    ReferenceLinkOpener => Some(SemanticText("["))
    Bold(children, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticBold(children))
        None => None
      }
    Italic(children, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticItalic(children))
        None => None
      }
    InlineCode(value, _) => Some(SemanticInlineCode(value))
    Link(children, destination, title, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticLink(children, destination, title))
        None => None
      }
    Image(children, destination, title, _) =>
      match markdown_ir_canonical_semantic_children(children) {
        Some(children) => Some(SemanticImage(children, destination, title))
        None => None
      }
    Autolink(kind, display, destination, _, _) =>
      Some(SemanticAutolink(kind, display, destination))
    InlineHtml(value, _) => Some(SemanticInlineHtml(value))
    SoftBreak(_) => Some(SemanticSoftBreak)
    HardBreak(_, _) => Some(SemanticHardBreak)
    Unsupported(_) | Raw(_, _) | Recovered(_, _) => None
  }
}

///|
fn markdown_ir_first_canonical_opaque(
  ir : MarkdownIR,
) -> (MarkdownIRCanonicalOpaqueKind, MarkdownIROrigin?)? {
  match ir.node {
    Raw(_, _) =>
      return Some((MarkdownIRCanonicalOpaqueKind::Raw, Some(ir.origin)))
    Recovered(_, _) =>
      return Some((MarkdownIRCanonicalOpaqueKind::Recovered, Some(ir.origin)))
    Unsupported(_) =>
      return Some((MarkdownIRCanonicalOpaqueKind::Unsupported, Some(ir.origin)))
    _ => ()
  }
  match ir.node {
    Document(children)
    | Heading(_, children, _)
    | Paragraph(children, _)
    | BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _)
    | ListItem(children, _, _, _, _)
    | OrderedListItem(children, _, _, _, _)
    | Bold(children, _)
    | Italic(children, _)
    | Link(children, _, _, _)
    | Image(children, _, _, _) =>
      for child in children {
        match markdown_ir_first_canonical_opaque(child) {
          Some(found) => return Some(found)
          None => ()
        }
      }
    CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | ThematicBreak
    | Text(_)
    | ReferenceLinkOpener
    | InlineCode(_, _)
    | Autolink(_, _, _, _, _)
    | InlineHtml(_, _)
    | SoftBreak(_)
    | HardBreak(_, _)
    | Unsupported(_)
    | Raw(_, _)
    | Recovered(_, _) => ()
  }
  None
}

///|
priv struct MarkdownIRCanonicalFormatLimits {
  max_container_candidates : Int
  max_container_expansions : Int
  max_document_candidates_per_container : Int
  max_document_expansions_per_container : Int
}

///|
const MARKDOWN_CANONICAL_CONTAINER_CANDIDATE_LIMIT = 256

///|
const MARKDOWN_CANONICAL_CONTAINER_EXPANSION_LIMIT = 512

///|
const MARKDOWN_CANONICAL_DOCUMENT_CANDIDATES_PER_CONTAINER = 256

///|
const MARKDOWN_CANONICAL_DOCUMENT_EXPANSIONS_PER_CONTAINER = 512

///|
fn markdown_ir_canonical_default_limits() -> MarkdownIRCanonicalFormatLimits {
  markdown_ir_canonical_limits(
    max_container_candidates=MARKDOWN_CANONICAL_CONTAINER_CANDIDATE_LIMIT,
    max_container_expansions=MARKDOWN_CANONICAL_CONTAINER_EXPANSION_LIMIT,
    max_document_candidates_per_container=MARKDOWN_CANONICAL_DOCUMENT_CANDIDATES_PER_CONTAINER,
    max_document_expansions_per_container=MARKDOWN_CANONICAL_DOCUMENT_EXPANSIONS_PER_CONTAINER,
  )
}

///|
fn markdown_ir_canonical_limits(
  max_container_candidates~ : Int,
  max_container_expansions~ : Int,
  max_document_candidates_per_container~ : Int,
  max_document_expansions_per_container~ : Int,
) -> MarkdownIRCanonicalFormatLimits {
  guard max_container_candidates > 0 &&
    max_container_expansions > 0 &&
    max_document_candidates_per_container > 0 &&
    max_document_expansions_per_container > 0 else {
    abort("canonical formatting limits must be positive")
  }
  {
    max_container_candidates,
    max_container_expansions,
    max_document_candidates_per_container,
    max_document_expansions_per_container,
  }
}

///|
priv struct MarkdownIRCanonicalChoiceAlternative {
  value : String
  growth : Int
  encoding_rank : Int
  marker_rank : Int
}

///|
fn markdown_ir_canonical_choice(
  value : String,
  growth? : Int = 0,
  encoding_rank? : Int = 0,
  marker_rank? : Int = 0,
) -> MarkdownIRCanonicalChoiceAlternative {
  { value, growth, encoding_rank, marker_rank }
}

///|
fn markdown_ir_canonical_append_choice(
  choices : Array[MarkdownIRCanonicalChoiceAlternative],
  choice : MarkdownIRCanonicalChoiceAlternative,
) -> Unit {
  if !choices.any(existing => existing.value == choice.value) {
    choices.push(choice)
  }
}

///|
fn markdown_ir_canonical_hex_digit(value : Int) -> Char {
  match value {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    15 => 'f'
    _ => abort("hex digit out of range")
  }
}

///|
fn markdown_ir_canonical_write_numeric_reference(
  buf : StringBuilder,
  ch : Char,
) -> Unit {
  let code = ch.to_int()
  buf.write_string("&#x")
  if code >= 16 {
    buf.write_char(markdown_ir_canonical_hex_digit(code / 16))
  }
  buf.write_char(markdown_ir_canonical_hex_digit(code % 16))
  buf.write_char(';')
}

///|
fn markdown_ir_canonical_backslash_text(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    if ch.is_ascii_punctuation() {
      buf.write_char('\\')
    }
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_reference_sensitive(ch : Char) -> Bool {
  match ch {
    '*' | '_' | '`' | '[' | ']' | '(' | ')' | '!' | '\\' | '&' | '<' | '>' =>
      true
    _ => false
  }
}

///|
fn markdown_ir_canonical_reference_text(value : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for ch in value {
    if markdown_ir_canonical_reference_sensitive(ch) {
      markdown_ir_canonical_write_numeric_reference(buf, ch)
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_compare_choice(
  left : MarkdownIRCanonicalChoiceAlternative,
  right : MarkdownIRCanonicalChoiceAlternative,
) -> Int {
  let growth = left.growth.compare(right.growth)
  if growth != 0 {
    return growth
  }
  let encoding = left.encoding_rank.compare(right.encoding_rank)
  if encoding != 0 {
    return encoding
  }
  let marker = left.marker_rank.compare(right.marker_rank)
  if marker != 0 {
    return marker
  }
  String::compare(left.value, right.value)
}

///|
fn markdown_ir_canonical_text_choices(
  value : String,
) -> Array[MarkdownIRCanonicalChoiceAlternative] {
  let choices = [markdown_ir_canonical_choice(value)]
  let escaped = markdown_ir_canonical_backslash_text(value)
  markdown_ir_canonical_append_choice(
    choices,
    markdown_ir_canonical_choice(
      escaped,
      growth=escaped.length() - value.length(),
      encoding_rank=1,
    ),
  )
  let referenced = markdown_ir_canonical_reference_text(value)
  markdown_ir_canonical_append_choice(
    choices,
    markdown_ir_canonical_choice(
      referenced,
      growth=referenced.length() - value.length(),
      encoding_rank=2,
    ),
  )
  choices.sort_by(markdown_ir_canonical_compare_choice)
  choices
}

///|
fn markdown_ir_canonical_italic_choices() -> Array[
  MarkdownIRCanonicalChoiceAlternative,
] {
  [
    markdown_ir_canonical_choice("*"),
    markdown_ir_canonical_choice("_", marker_rank=1),
  ]
}

///|
fn markdown_ir_canonical_bold_choices() -> Array[
  MarkdownIRCanonicalChoiceAlternative,
] {
  [
    markdown_ir_canonical_choice("**"),
    markdown_ir_canonical_choice("__", marker_rank=1),
  ]
}

///|
priv struct MarkdownIRCanonicalChoicePlan {
  containers : Array[Array[Int]]
  container_nodes : Array[MarkdownIR]
  radices : Array[Int]
  site_container_indices : Array[Int]
}

///|
fn markdown_ir_collect_inline_choice_radices(
  ir : MarkdownIR,
  radices : Array[Int],
) -> Unit {
  match ir.node {
    Text(value) => {
      let count = markdown_ir_canonical_text_choices(value).length()
      if count > 1 {
        radices.push(count)
      }
    }
    ReferenceLinkOpener => {
      let count = markdown_ir_canonical_text_choices("[").length()
      if count > 1 {
        radices.push(count)
      }
    }
    Bold(children, _) => {
      radices.push(2)
      for child in children {
        markdown_ir_collect_inline_choice_radices(child, radices)
      }
    }
    Italic(children, _) => {
      radices.push(2)
      for child in children {
        markdown_ir_collect_inline_choice_radices(child, radices)
      }
    }
    Link(children, _, _, _) =>
      for child in children {
        markdown_ir_collect_inline_choice_radices(child, radices)
      }
    Image(children, _, _, _) =>
      for child in children {
        markdown_ir_collect_inline_choice_radices(child, radices)
      }
    InlineCode(_, _)
    | Autolink(_, _, _, _, _)
    | InlineHtml(_, _)
    | SoftBreak(_)
    | HardBreak(_, _) => ()
    Document(_)
    | Heading(_, _, _)
    | Paragraph(_, _)
    | BlockQuote(_)
    | UnorderedList(_, _, _)
    | OrderedList(_, _, _)
    | ListItem(_, _, _, _, _)
    | OrderedListItem(_, _, _, _, _)
    | CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | ThematicBreak
    | Unsupported(_)
    | Raw(_, _)
    | Recovered(_, _) => ()
  }
}

///|
fn markdown_ir_collect_block_choice_containers(
  ir : MarkdownIR,
  containers : Array[Array[Int]],
  container_nodes : Array[MarkdownIR],
) -> Unit {
  match ir.node {
    Heading(_, children, _) | Paragraph(children, _) => {
      let radices : Array[Int] = []
      for child in children {
        markdown_ir_collect_inline_choice_radices(child, radices)
      }
      containers.push(radices)
      container_nodes.push(ir)
    }
    Document(children)
    | BlockQuote(children)
    | UnorderedList(children, _, _)
    | OrderedList(children, _, _)
    | ListItem(children, _, _, _, _)
    | OrderedListItem(children, _, _, _, _) =>
      for child in children {
        markdown_ir_collect_block_choice_containers(
          child, containers, container_nodes,
        )
      }
    Text(_)
    | ReferenceLinkOpener
    | Bold(_, _)
    | Italic(_, _)
    | InlineCode(_, _)
    | Link(_, _, _, _)
    | Image(_, _, _, _)
    | Autolink(_, _, _, _, _)
    | InlineHtml(_, _)
    | SoftBreak(_)
    | HardBreak(_, _) => {
      let radices : Array[Int] = []
      markdown_ir_collect_inline_choice_radices(ir, radices)
      containers.push(radices)
      container_nodes.push(ir)
    }
    CodeBlock(_, _, _)
    | HtmlBlock(_, _)
    | ThematicBreak
    | Unsupported(_)
    | Raw(_, _)
    | Recovered(_, _) => ()
  }
}

///|
fn markdown_ir_canonical_choice_plan(
  ir : MarkdownIR,
) -> MarkdownIRCanonicalChoicePlan {
  let containers : Array[Array[Int]] = []
  let container_nodes : Array[MarkdownIR] = []
  markdown_ir_collect_block_choice_containers(ir, containers, container_nodes)
  let radices : Array[Int] = []
  let site_container_indices : Array[Int] = []
  for container_index, container in containers {
    for radix in container {
      radices.push(radix)
      site_container_indices.push(container_index)
    }
  }
  { containers, container_nodes, radices, site_container_indices }
}

///|
fn markdown_ir_canonical_limited_product(
  left : Int,
  right : Int,
  limit : Int,
) -> Int {
  if left > limit / right {
    limit + 1
  } else {
    left * right
  }
}

///|
fn markdown_ir_canonical_document_search_limits(
  plan : MarkdownIRCanonicalChoicePlan,
  limits : MarkdownIRCanonicalFormatLimits,
) -> (Int, Int) {
  let container_count = if plan.containers.length() > 0 {
    plan.containers.length()
  } else {
    1
  }
  let document_candidate_limit = markdown_ir_canonical_limited_product(
    limits.max_document_candidates_per_container,
    container_count,
    2147483646,
  )
  let document_expansion_limit = markdown_ir_canonical_limited_product(
    limits.max_document_expansions_per_container,
    container_count,
    2147483646,
  )
  (document_candidate_limit, document_expansion_limit)
}

///|
priv struct MarkdownIRCanonicalAssignmentReader {
  assignment : Array[Int]
  mut index : Int
  mut growth : Int
  mut encoding_rank : Int
  mut marker_rank : Int
}

///|
fn MarkdownIRCanonicalAssignmentReader::MarkdownIRCanonicalAssignmentReader(
  assignment : Array[Int],
) -> MarkdownIRCanonicalAssignmentReader {
  { assignment, index: 0, growth: 0, encoding_rank: 0, marker_rank: 0 }
}

///|
fn MarkdownIRCanonicalAssignmentReader::choose(
  self : MarkdownIRCanonicalAssignmentReader,
  choices : Array[MarkdownIRCanonicalChoiceAlternative],
) -> String {
  guard choices.length() > 0 else {
    abort("canonical choice list must not be empty")
  }
  let selected = if choices.length() == 1 {
    0
  } else {
    let selected = match self.assignment.get(self.index) {
      Some(selected) => selected
      None => abort("canonical assignment ended before rendering completed")
    }
    self.index = self.index + 1
    selected
  }
  guard selected >= 0 && selected < choices.length() else {
    abort("canonical assignment choice is out of range")
  }
  let choice = choices[selected]
  self.growth = self.growth + choice.growth
  self.encoding_rank = self.encoding_rank + choice.encoding_rank
  self.marker_rank = self.marker_rank + choice.marker_rank
  choice.value
}

///|
fn markdown_ir_canonical_candidate_inline_text(
  children : Array[MarkdownIR],
  reader : MarkdownIRCanonicalAssignmentReader,
) -> String {
  let buf = StringBuilder::StringBuilder()
  for child in children {
    buf.write_string(
      markdown_ir_canonical_candidate_format_with_list_marker(
        child,
        Dash,
        reader,
      ),
    )
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_candidate_nested_flow_child(
  child : MarkdownIR,
  list_marker : UnorderedListMarker,
  previous_nested_marker : UnorderedListMarker?,
  reader : MarkdownIRCanonicalAssignmentReader,
) -> (String, UnorderedListMarker?) {
  let (marker, next_previous) = match child.node {
    UnorderedList(_, _, surface_marker) => {
      let marker = match previous_nested_marker {
        Some(previous_marker) =>
          boundary_preserving_list_marker(previous_marker, surface_marker)
        None => list_marker
      }
      (marker, Some(marker))
    }
    _ => (list_marker, None)
  }
  let buf = StringBuilder::StringBuilder()
  buf.write_char('\n')
  buf.write_string(
    indent_canonical_block(
      markdown_ir_canonical_candidate_format_with_list_marker(
        child, marker, reader,
      ),
      "  ",
    ),
  )
  (buf.to_string(), next_previous)
}

///|
fn markdown_ir_canonical_candidate_nested_flow_children(
  children : ArrayView[MarkdownIR],
  list_marker : UnorderedListMarker,
  reader : MarkdownIRCanonicalAssignmentReader,
) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut previous_nested_marker : UnorderedListMarker? = None
  for child in children {
    let (rendered, next_previous) = markdown_ir_canonical_candidate_nested_flow_child(
      child, list_marker, previous_nested_marker, reader,
    )
    buf.write_string(rendered)
    previous_nested_marker = next_previous
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_candidate_list_item_flow(
  marker_text : String,
  children : Array[MarkdownIR],
  task : MarkdownIRTask?,
  list_marker : UnorderedListMarker,
  reader : MarkdownIRCanonicalAssignmentReader,
) -> String {
  let buf = StringBuilder::StringBuilder()
  buf.write_string(marker_text)
  buf.write_char(' ')
  match task {
    Some(task) => buf.write_string(if task.checked() { "[x] " } else { "[ ] " })
    None => ()
  }
  match children {
    [] => ()
    [first, .. rest] => {
      buf.write_string(
        markdown_ir_canonical_candidate_format_with_list_marker(
          first, list_marker, reader,
        ),
      )
      buf.write_string(
        markdown_ir_canonical_candidate_nested_flow_children(
          rest, list_marker, reader,
        ),
      )
    }
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_candidate_list_children(
  children : Array[MarkdownIR],
  list_marker : UnorderedListMarker,
  reader : MarkdownIRCanonicalAssignmentReader,
) -> String {
  let buf = StringBuilder::StringBuilder()
  for index, child in children {
    if index > 0 {
      buf.write_char('\n')
    }
    buf.write_string(
      markdown_ir_canonical_candidate_format_with_list_marker(
        child, list_marker, reader,
      ),
    )
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_candidate_document_format(
  children : Array[MarkdownIR],
  reader : MarkdownIRCanonicalAssignmentReader,
) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut previous_list_marker : UnorderedListMarker? = None
  for index, child in children {
    if index > 0 {
      buf.write_string("\n\n")
    }
    match child.node {
      UnorderedList(_, _, surface_marker) => {
        let marker = match previous_list_marker {
          Some(previous_marker) =>
            boundary_preserving_list_marker(previous_marker, surface_marker)
          None => Dash
        }
        buf.write_string(
          markdown_ir_canonical_candidate_format_with_list_marker(
            child, marker, reader,
          ),
        )
        previous_list_marker = Some(marker)
      }
      OrderedList(_, _, _) => {
        buf.write_string(
          markdown_ir_canonical_candidate_format_with_list_marker(
            child,
            Dash,
            reader,
          ),
        )
        previous_list_marker = None
      }
      _ => {
        buf.write_string(
          markdown_ir_canonical_candidate_format_with_list_marker(
            child,
            Dash,
            reader,
          ),
        )
        previous_list_marker = None
      }
    }
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_candidate_format_with_list_marker(
  ir : MarkdownIR,
  list_marker : UnorderedListMarker,
  reader : MarkdownIRCanonicalAssignmentReader,
) -> String {
  match ir.node {
    Document(children) =>
      markdown_ir_canonical_candidate_document_format(children, reader)
    Heading(depth, children, _) => {
      let buf = StringBuilder::StringBuilder()
      buf.write_string("#".repeat(depth))
      buf.write_char(' ')
      buf.write_string(
        markdown_ir_canonical_candidate_inline_text(children, reader),
      )
      buf.to_string()
    }
    Paragraph(children, _) =>
      markdown_ir_canonical_candidate_inline_text(children, reader)
    BlockQuote(children) =>
      indent_canonical_block(
        markdown_ir_canonical_candidate_document_format(children, reader),
        "> ",
      )
    UnorderedList(children, _, _) =>
      markdown_ir_canonical_candidate_list_children(
        children, list_marker, reader,
      )
    OrderedList(children, _, _) =>
      markdown_ir_canonical_candidate_list_children(
        children, list_marker, reader,
      )
    ListItem(children, _, _, _, task) =>
      markdown_ir_canonical_candidate_list_item_flow(
        list_marker.text(),
        children,
        task,
        list_marker,
        reader,
      )
    OrderedListItem(children, _, _, marker, task) => {
      let marker_text = match marker {
        Some(marker) => marker.text()
        None => "1."
      }
      markdown_ir_canonical_candidate_list_item_flow(
        marker_text, children, task, list_marker, reader,
      )
    }
    CodeBlock(info, value, _) => code_block_markdown(info, value)
    HtmlBlock(value, _) => value
    ThematicBreak => "---"
    Text(value) => reader.choose(markdown_ir_canonical_text_choices(value))
    ReferenceLinkOpener =>
      reader.choose(markdown_ir_canonical_text_choices("["))
    SoftBreak(_) => "\n"
    HardBreak(surface, _) => hard_break_surface_text(surface)
    Bold(children, _) => {
      let delimiter = reader.choose(markdown_ir_canonical_bold_choices())
      let buf = StringBuilder::StringBuilder()
      buf.write_string(delimiter)
      buf.write_string(
        markdown_ir_canonical_candidate_inline_text(children, reader),
      )
      buf.write_string(delimiter)
      buf.to_string()
    }
    Italic(children, _) => {
      let delimiter = reader.choose(markdown_ir_canonical_italic_choices())
      let buf = StringBuilder::StringBuilder()
      buf.write_string(delimiter)
      buf.write_string(
        markdown_ir_canonical_candidate_inline_text(children, reader),
      )
      buf.write_string(delimiter)
      buf.to_string()
    }
    InlineCode(value, _) => inline_code_markdown(value)
    Link(children, destination, title, _) => {
      let buf = StringBuilder::StringBuilder()
      buf.write_char('[')
      buf.write_string(
        markdown_ir_canonical_candidate_inline_text(children, reader),
      )
      buf.write_string("](")
      buf.write_string(destination)
      buf.write_string(markdown_link_title_suffix(title))
      buf.write_char(')')
      buf.to_string()
    }
    Image(children, destination, title, _) => {
      let buf = StringBuilder::StringBuilder()
      buf.write_string("![")
      buf.write_string(
        markdown_ir_canonical_candidate_inline_text(children, reader),
      )
      buf.write_string("](")
      buf.write_string(destination)
      buf.write_string(markdown_link_title_suffix(title))
      buf.write_char(')')
      buf.to_string()
    }
    Autolink(_, display, _, _, _) => "<" + display + ">"
    InlineHtml(value, _) => value
    Unsupported(message) => {
      let buf = StringBuilder::StringBuilder()
      buf.write_string("<!-- unsupported MarkdownIR: ")
      buf.write_string(message)
      buf.write_string(" -->")
      buf.to_string()
    }
    Raw(value, _) => value
    Recovered(value, _) => value
  }
}

///|
priv struct MarkdownIRCanonicalCandidate {
  markdown : String
  growth : Int
  encoding_rank : Int
  marker_rank : Int
}

///|
fn markdown_ir_canonical_compare_candidate(
  left : MarkdownIRCanonicalCandidate,
  right : MarkdownIRCanonicalCandidate,
) -> Int {
  let growth = left.growth.compare(right.growth)
  if growth != 0 {
    return growth
  }
  let encoding = left.encoding_rank.compare(right.encoding_rank)
  if encoding != 0 {
    return encoding
  }
  let marker = left.marker_rank.compare(right.marker_rank)
  if marker != 0 {
    return marker
  }
  String::compare(left.markdown, right.markdown)
}

///|
priv struct MarkdownIRCanonicalPrimary {
  growth : Int
  encoding_rank : Int
  marker_rank : Int
} derive(Eq)

///|
fn MarkdownIRCanonicalCandidate::primary(
  self : MarkdownIRCanonicalCandidate,
) -> MarkdownIRCanonicalPrimary {
  {
    growth: self.growth,
    encoding_rank: self.encoding_rank,
    marker_rank: self.marker_rank,
  }
}

///|
fn markdown_ir_canonical_compare_primary(
  left : MarkdownIRCanonicalPrimary,
  right : MarkdownIRCanonicalPrimary,
) -> Int {
  let growth = left.growth.compare(right.growth)
  if growth != 0 {
    return growth
  }
  let encoding = left.encoding_rank.compare(right.encoding_rank)
  if encoding != 0 {
    return encoding
  }
  left.marker_rank.compare(right.marker_rank)
}

///|
fn markdown_ir_canonical_compare_assignment(
  left : Array[Int],
  right : Array[Int],
) -> Int {
  let common = left.length().min(right.length())
  for index = 0; index < common; index = index + 1 {
    let compared = left[index].compare(right[index])
    if compared != 0 {
      return compared
    }
  }
  left.length().compare(right.length())
}

///|
priv struct MarkdownIRCanonicalSearchNode {
  assignment : Array[Int]
  candidate : MarkdownIRCanonicalCandidate
}

///|
fn markdown_ir_canonical_compare_search_node(
  left : MarkdownIRCanonicalSearchNode,
  right : MarkdownIRCanonicalSearchNode,
) -> Int {
  let candidate = markdown_ir_canonical_compare_candidate(
    left.candidate,
    right.candidate,
  )
  if candidate != 0 {
    return candidate
  }
  markdown_ir_canonical_compare_assignment(left.assignment, right.assignment)
}

///|
fn markdown_ir_canonical_frontier_last_has_primary(
  frontier : Array[MarkdownIRCanonicalSearchNode],
  primary : MarkdownIRCanonicalPrimary,
) -> Bool {
  match frontier.last() {
    Some(node) => node.candidate.primary() == primary
    None => false
  }
}

///|
fn markdown_ir_canonical_render_search_node(
  ir : MarkdownIR,
  plan : MarkdownIRCanonicalChoicePlan,
  assignment : Array[Int],
) -> MarkdownIRCanonicalSearchNode {
  let reader = MarkdownIRCanonicalAssignmentReader::MarkdownIRCanonicalAssignmentReader(
    assignment,
  )
  let markdown = markdown_ir_canonical_candidate_format_with_list_marker(
    ir,
    Dash,
    reader,
  )
  guard reader.index == plan.radices.length() else {
    abort("canonical assignment was not consumed exactly")
  }
  {
    assignment,
    candidate: {
      markdown,
      growth: reader.growth,
      encoding_rank: reader.encoding_rank,
      marker_rank: reader.marker_rank,
    },
  }
}

///|
fn markdown_ir_canonical_assignment_seen(
  assignments : Array[Array[Int]],
  assignment : Array[Int],
) -> Bool {
  assignments.any(existing => existing == assignment)
}

///|
fn markdown_ir_canonical_project_assignment(
  assignment : Array[Int],
  site_container_indices : Array[Int],
  container_index : Int,
) -> Array[Int] {
  let projected : Array[Int] = []
  for site_index, site_container_index in site_container_indices {
    if site_container_index == container_index {
      projected.push(assignment[site_index])
    }
  }
  projected
}

///|
fn markdown_ir_canonical_render_container_markdown(
  plan : MarkdownIRCanonicalChoicePlan,
  container_index : Int,
  projected_assignment : Array[Int],
) -> String {
  let reader = MarkdownIRCanonicalAssignmentReader::MarkdownIRCanonicalAssignmentReader(
    projected_assignment,
  )
  let markdown = markdown_ir_canonical_candidate_format_with_list_marker(
    plan.container_nodes[container_index],
    Dash,
    reader,
  )
  guard reader.index == plan.containers[container_index].length() else {
    abort("canonical container assignment was not consumed exactly")
  }
  markdown
}

///|
fn markdown_ir_canonical_copy_assignment_sets(
  sets : Array[Array[Array[Int]]],
) -> Array[Array[Array[Int]]] {
  sets.map(set => set.copy())
}

///|
fn markdown_ir_canonical_copy_string_sets(
  sets : Array[Array[String]],
) -> Array[Array[String]] {
  sets.map(set => set.copy())
}

///|
priv struct MarkdownIRCanonicalBlockedSearch {
  candidate : MarkdownIRCanonicalCandidate
  failure : MarkdownIRCanonicalFormatFailure
}

///|
fn markdown_ir_canonical_record_blocked(
  blocked : MarkdownIRCanonicalBlockedSearch?,
  node : MarkdownIRCanonicalSearchNode,
  failure : MarkdownIRCanonicalFormatFailure,
) -> MarkdownIRCanonicalBlockedSearch? {
  let next = { candidate: node.candidate, failure }
  match blocked {
    None => Some(next)
    Some(current) =>
      if markdown_ir_canonical_compare_candidate(
          next.candidate,
          current.candidate,
        ) <
        0 {
        Some(next)
      } else {
        blocked
      }
  }
}

///|
priv struct MarkdownIRCanonicalSearchState {
  plan : MarkdownIRCanonicalChoicePlan
  frontier : Array[MarkdownIRCanonicalSearchNode]
  seen_assignments : Array[Array[Int]]
  container_seen_markdown : Array[Array[String]]
  container_expanded_assignments : Array[Array[Array[Int]]]
  seen_markdown : Array[String]
  expansions : Int
  document_expansion_limit : Int
  max_container_candidates : Int
  max_container_expansions : Int
  blocked : MarkdownIRCanonicalBlockedSearch?
}

///|
priv enum MarkdownIRCanonicalSearchStep {
  CandidateLayer(
    MarkdownIRCanonicalSearchState,
    Array[MarkdownIRCanonicalCandidate]
  )
  Exhausted(MarkdownIRCanonicalSearchState)
  ExpansionLimited(
    MarkdownIRCanonicalSearchState,
    MarkdownIRCanonicalFormatFailure
  )
}

///|
fn markdown_ir_canonical_search_start(
  ir : MarkdownIR,
  limits : MarkdownIRCanonicalFormatLimits,
) -> MarkdownIRCanonicalSearchState {
  let plan = markdown_ir_canonical_choice_plan(ir)
  let (_, document_expansion_limit) = markdown_ir_canonical_document_search_limits(
    plan, limits,
  )
  let assignment = Array::make(plan.radices.length(), 0)
  let root = markdown_ir_canonical_render_search_node(ir, plan, assignment)
  let container_seen_markdown : Array[Array[String]] = []
  let container_expanded_assignments : Array[Array[Array[Int]]] = []
  for container_index, container in plan.containers {
    let seen : Array[String] = []
    if container.length() > 0 {
      let projected = markdown_ir_canonical_project_assignment(
        assignment,
        plan.site_container_indices,
        container_index,
      )
      seen.push(
        markdown_ir_canonical_render_container_markdown(
          plan, container_index, projected,
        ),
      )
    }
    container_seen_markdown.push(seen)
    container_expanded_assignments.push([])
  }
  {
    plan,
    frontier: [root],
    seen_assignments: [assignment],
    container_seen_markdown,
    container_expanded_assignments,
    seen_markdown: [],
    expansions: 1,
    document_expansion_limit,
    max_container_candidates: limits.max_container_candidates,
    max_container_expansions: limits.max_container_expansions,
    blocked: None,
  }
}

///|
fn markdown_ir_canonical_search_state(
  base : MarkdownIRCanonicalSearchState,
  frontier : Array[MarkdownIRCanonicalSearchNode],
  seen_assignments : Array[Array[Int]],
  container_seen_markdown : Array[Array[String]],
  container_expanded_assignments : Array[Array[Array[Int]]],
  seen_markdown : Array[String],
  expansions : Int,
  blocked : MarkdownIRCanonicalBlockedSearch?,
) -> MarkdownIRCanonicalSearchState {
  {
    plan: base.plan,
    frontier,
    seen_assignments,
    container_seen_markdown,
    container_expanded_assignments,
    seen_markdown,
    expansions,
    document_expansion_limit: base.document_expansion_limit,
    max_container_candidates: base.max_container_candidates,
    max_container_expansions: base.max_container_expansions,
    blocked,
  }
}

///|
fn markdown_ir_canonical_search_next_layer(
  state : MarkdownIRCanonicalSearchState,
  ir : MarkdownIR,
) -> MarkdownIRCanonicalSearchStep {
  let frontier = state.frontier.copy()
  let seen_assignments = state.seen_assignments.copy()
  let container_seen_markdown = markdown_ir_canonical_copy_string_sets(
    state.container_seen_markdown,
  )
  let container_expanded_assignments = markdown_ir_canonical_copy_assignment_sets(
    state.container_expanded_assignments,
  )
  let seen_markdown = state.seen_markdown.copy()
  let mut expansions = state.expansions
  let mut blocked = state.blocked
  while true {
    frontier.sort_by(fn(left, right) {
      markdown_ir_canonical_compare_search_node(right, left)
    })
    let first = match frontier.last() {
      Some(first) => first
      None => {
        let done = markdown_ir_canonical_search_state(
          state, frontier, seen_assignments, container_seen_markdown, container_expanded_assignments,
          seen_markdown, expansions, blocked,
        )
        return match blocked {
          Some(blocked) => ExpansionLimited(done, blocked.failure)
          None => Exhausted(done)
        }
      }
    }
    match blocked {
      Some(blocked_entry) if markdown_ir_canonical_compare_candidate(
          blocked_entry.candidate,
          first.candidate,
        ) <
        0 => {
        let stopped = markdown_ir_canonical_search_state(
          state,
          frontier,
          seen_assignments,
          container_seen_markdown,
          container_expanded_assignments,
          seen_markdown,
          expansions,
          Some(blocked_entry),
        )
        return ExpansionLimited(stopped, blocked_entry.failure)
      }
      _ => ()
    }
    let layer_primary = first.candidate.primary()
    let layer : Array[MarkdownIRCanonicalCandidate] = []
    while markdown_ir_canonical_frontier_last_has_primary(
            frontier, layer_primary,
          ) {
      let node = match frontier.pop() {
        Some(node) => node
        None => abort("canonical search frontier changed during layer closure")
      }
      layer.push(node.candidate)
      let container_allowed = Array::make(state.plan.containers.length(), true)
      for site_index, radix in state.plan.radices {
        let next_value = node.assignment[site_index] + 1
        if next_value >= radix {
          continue
        }
        let container_index = state.plan.site_container_indices[site_index]
        if container_allowed[container_index] {
          let projection = markdown_ir_canonical_project_assignment(
            node.assignment,
            state.plan.site_container_indices,
            container_index,
          )
          if !markdown_ir_canonical_assignment_seen(
              container_expanded_assignments[container_index],
              projection,
            ) {
            if container_expanded_assignments[container_index].length() >=
              state.max_container_expansions {
              container_allowed[container_index] = false
            } else {
              container_expanded_assignments[container_index].push(projection)
            }
          }
        }
        let next_assignment = node.assignment.copy()
        next_assignment[site_index] = next_value
        if markdown_ir_canonical_assignment_seen(
            seen_assignments, next_assignment,
          ) {
          continue
        }
        let next_node = markdown_ir_canonical_render_search_node(
          ir,
          state.plan,
          next_assignment,
        )
        if !container_allowed[container_index] {
          blocked = markdown_ir_canonical_record_blocked(
            blocked,
            next_node,
            SearchLimitExceeded(
              observed=state.max_container_expansions + 1,
              limit=state.max_container_expansions,
            ),
          )
          continue
        }
        let next_projection = markdown_ir_canonical_project_assignment(
          next_assignment,
          state.plan.site_container_indices,
          container_index,
        )
        let next_container_markdown = markdown_ir_canonical_render_container_markdown(
          state.plan,
          container_index,
          next_projection,
        )
        let container_candidate_is_new = !container_seen_markdown[container_index].any(markdown => {
            markdown == next_container_markdown
          },
        )
        if container_candidate_is_new &&
          container_seen_markdown[container_index].length() >=
          state.max_container_candidates {
          blocked = markdown_ir_canonical_record_blocked(
            blocked,
            next_node,
            SearchLimitExceeded(
              observed=state.max_container_candidates + 1,
              limit=state.max_container_candidates,
            ),
          )
          continue
        }
        if expansions >= state.document_expansion_limit {
          blocked = markdown_ir_canonical_record_blocked(
            blocked,
            next_node,
            SearchLimitExceeded(
              observed=state.document_expansion_limit + 1,
              limit=state.document_expansion_limit,
            ),
          )
          continue
        }
        if container_candidate_is_new {
          container_seen_markdown[container_index].push(next_container_markdown)
        }
        seen_assignments.push(next_assignment)
        frontier.push(next_node)
        expansions = expansions + 1
      }
      frontier.sort_by(fn(left, right) {
        markdown_ir_canonical_compare_search_node(right, left)
      })
    }
    layer.sort_by(markdown_ir_canonical_compare_candidate)
    let unique : Array[MarkdownIRCanonicalCandidate] = []
    for candidate in layer {
      let is_before_blocked = match blocked {
        Some(blocked_entry) => {
          let compared = markdown_ir_canonical_compare_candidate(
            candidate,
            blocked_entry.candidate,
          )
          compared < 0 || candidate.markdown == blocked_entry.candidate.markdown
        }
        None => true
      }
      if is_before_blocked &&
        !seen_markdown.any(markdown => markdown == candidate.markdown) {
        seen_markdown.push(candidate.markdown)
        unique.push(candidate)
      }
    }
    let next = markdown_ir_canonical_search_state(
      state, frontier, seen_assignments, container_seen_markdown, container_expanded_assignments,
      seen_markdown, expansions, blocked,
    )
    if unique.length() > 0 {
      return CandidateLayer(next, unique)
    }
    match blocked {
      Some(blocked_entry) if markdown_ir_canonical_compare_primary(
          blocked_entry.candidate.primary(),
          layer_primary,
        ) <=
        0 => return ExpansionLimited(next, blocked_entry.failure)
      _ => ()
    }
  }
  abort("unreachable canonical search state")
}
