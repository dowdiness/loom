///|
pub struct SourceReplacement {
  priv start : Int
  priv old_len : Int
  priv new_text : String
} derive(Eq, Debug)

///|
fn SourceReplacement::SourceReplacement(
  start~ : Int,
  old_len~ : Int,
  new_text~ : String,
) -> SourceReplacement {
  { start, old_len, new_text }
}

///|
pub fn SourceReplacement::start(self : SourceReplacement) -> Int {
  self.start
}

///|
pub fn SourceReplacement::old_len(self : SourceReplacement) -> Int {
  self.old_len
}

///|
pub fn SourceReplacement::new_text(self : SourceReplacement) -> String {
  self.new_text
}

///|
pub fn SourceReplacement::old_end(self : SourceReplacement) -> Int {
  self.start + self.old_len
}

///|
pub fn SourceReplacement::edit(self : SourceReplacement) -> @loom.Edit {
  @loom.Edit::new(self.start, self.old_len, self.new_text.length())
}

///|
pub struct LoweredGraphEdit {
  priv replacements : Array[SourceReplacement]
  priv new_source : String
  priv incremental_edit : @loom.Edit?
} derive(Eq, Debug)

///|
fn LoweredGraphEdit::LoweredGraphEdit(
  replacements~ : Array[SourceReplacement],
  new_source~ : String,
  incremental_edit~ : @loom.Edit?,
) -> LoweredGraphEdit {
  { replacements: replacements.copy(), new_source, incremental_edit }
}

///|
pub fn LoweredGraphEdit::replacements(
  self : LoweredGraphEdit,
) -> Array[SourceReplacement] {
  self.replacements.copy()
}

///|
pub fn LoweredGraphEdit::new_source(self : LoweredGraphEdit) -> String {
  self.new_source
}

///|
pub fn LoweredGraphEdit::incremental_edit(
  self : LoweredGraphEdit,
) -> @loom.Edit? {
  self.incremental_edit
}

///|
fn compare_replacement_start(
  a : SourceReplacement,
  b : SourceReplacement,
) -> Int {
  if a.start < b.start {
    -1
  } else if a.start > b.start {
    1
  } else if a.old_end() < b.old_end() {
    -1
  } else if a.old_end() > b.old_end() {
    1
  } else {
    0
  }
}

///|
fn compare_replacement_start_desc(
  a : SourceReplacement,
  b : SourceReplacement,
) -> Int {
  0 - compare_replacement_start(a, b)
}

///|
fn sorted_replacements(
  replacements : Array[SourceReplacement],
) -> Array[SourceReplacement] {
  let ordered = replacements.copy()
  ordered.sort_by(compare_replacement_start)
  ordered
}

///|
fn apply_replacements(
  source : String,
  replacements : Array[SourceReplacement],
) -> String? {
  let ordered = replacements.copy()
  ordered.sort_by(compare_replacement_start_desc)
  let source_len = source.length()
  let mut next_start = source_len
  let mut result = source
  for replacement in ordered {
    let old_end = replacement.old_end()
    if replacement.start < 0 ||
      replacement.old_len < 0 ||
      old_end > source_len ||
      old_end > next_start {
      return None
    }
    result = result[:replacement.start].to_owned() +
      replacement.new_text +
      result[old_end:].to_owned()
    next_start = replacement.start
  }
  Some(result)
}

///|
fn lowered_from_replacements(
  source : String,
  replacements : Array[SourceReplacement],
) -> LoweredGraphEdit? {
  if replacements.is_empty() {
    return None
  }
  let ordered = sorted_replacements(replacements)
  match apply_replacements(source, ordered) {
    Some(new_source) => {
      let incremental_edit = if ordered.length() == 1 {
        Some(ordered[0].edit())
      } else {
        None
      }
      Some(
        LoweredGraphEdit(replacements=ordered, new_source~, incremental_edit~),
      )
    }
    None => None
  }
}

///|
fn lexes_as_single_token(text : String, expected : Token) -> Bool {
  if text.length() == 0 {
    return false
  }
  match graph_step_lexer(text, 0) {
    Produced(info, next_offset~) if info.token == expected &&
      next_offset == text.length() =>
      match graph_step_lexer(text, next_offset) {
        Done => true
        _ => false
      }
    _ => false
  }
}

///|
fn is_identifier_text(text : String) -> Bool {
  lexes_as_single_token(text, Identifier)
}

///|
fn is_number_text(text : String) -> Bool {
  lexes_as_single_token(text, Number)
}

///|
fn replacement_for_token(
  token : GraphToken,
  new_text : String,
) -> SourceReplacement {
  SourceReplacement(
    start=token.start,
    old_len=token.end - token.start,
    new_text~,
  )
}

///|
fn find_param(node : GraphNode, name : String) -> GraphParam? {
  for param in node.params {
    if param.name == name {
      return Some(param)
    }
  }
  None
}

///|
fn first_token_with_role(
  tokens : Array[GraphToken],
  role : GraphTokenRole,
) -> GraphToken? {
  for token in tokens {
    if token.role == role {
      return Some(token)
    }
  }
  None
}

///|
fn horizontal_space(code_unit : UInt16) -> Bool {
  code_unit == ' ' || code_unit == '\t'
}

///|
fn param_start_after_lparen_space(source : String, start : Int) -> Int {
  let mut cursor = start
  while cursor > 0 && horizontal_space(source[cursor - 1]) {
    cursor -= 1
  }
  if cursor > 0 && source[cursor - 1] == '(' {
    cursor
  } else {
    start
  }
}

///|
fn param_end_before_rparen_space(source : String, end : Int) -> Int {
  let mut cursor = end
  while cursor < source.length() && horizontal_space(source[cursor]) {
    cursor += 1
  }
  if cursor < source.length() && source[cursor] == ')' {
    return cursor
  }
  if cursor < source.length() && source[cursor] == ',' {
    cursor += 1
    while cursor < source.length() && horizontal_space(source[cursor]) {
      cursor += 1
    }
    if cursor < source.length() && source[cursor] == ')' {
      return cursor
    }
  }
  end
}

///|
fn graph_param_text_end(param : GraphParam) -> Int? {
  if param.value_tokens.is_empty() {
    return None
  }
  let mut end = param.name_token.end
  for token in param.value_tokens {
    if token.end > end {
      end = token.end
    }
  }
  Some(end)
}

///|
fn graph_param_input_reference(param : GraphParam) -> String? {
  if param.value_kind != InputRef {
    return None
  }
  match first_token_with_role(param.value_tokens, InputReference) {
    Some(token) => Some(token.text)
    None => None
  }
}

///|
fn connection_param_index(
  params : Array[GraphParam],
  parameter : String,
  input_ref : String,
) -> Int? {
  for index, param in params {
    if param.name == parameter &&
      graph_param_input_reference(param) == Some(input_ref) {
      return Some(index)
    }
  }
  None
}

///|
fn removal_replacement_for_param(
  source : String,
  params : Array[GraphParam],
  index : Int,
) -> SourceReplacement? {
  if index < 0 || index >= params.length() {
    return None
  }
  let param = params[index]
  let param_start = if index == 0 {
    param_start_after_lparen_space(source, param.name_token.start)
  } else {
    param.name_token.start
  }
  let param_end = match graph_param_text_end(param) {
    Some(end) =>
      if index + 1 < params.length() {
        end
      } else {
        param_end_before_rparen_space(source, end)
      }
    None => return None
  }
  let (start, end) = if index + 1 < params.length() {
    (param_start, params[index + 1].name_token.start)
  } else if index > 0 {
    match graph_param_text_end(params[index - 1]) {
      Some(previous_end) => (previous_end, param_end)
      None => return None
    }
  } else {
    (param_start, param_end)
  }
  if start > end {
    None
  } else {
    Some(SourceReplacement(start~, old_len=end - start, new_text=""))
  }
}

///|
/// Lower a parameter edit such as `freq: 440Hz` → `freq: 880Hz`.
///
/// Only the numeric token is replaced; a following unit token keeps its source
/// range and text. Invalid numeric token text is rejected instead of generating
/// parser-invalid source.
pub fn GraphDoc::lower_set_numeric(
  self : GraphDoc,
  binding : String,
  parameter : String,
  new_number : String,
) -> LoweredGraphEdit? {
  if !is_number_text(new_number) {
    return None
  }
  let node = match self.find_node(binding) {
    Some(node) => node
    None => return None
  }
  let param = match find_param(node, parameter) {
    Some(param) => param
    None => return None
  }
  let token = match
    first_token_with_role(param.value_tokens, NumericParameter) {
    Some(token) => token
    None => return None
  }
  lowered_from_replacements(self.source(), [
    replacement_for_token(token, new_number),
  ])
}

///|
/// Lower a rename by replacing the binding token and every input-reference token
/// that points at the old binding. Because this can be a multi-range edit,
/// `incremental_edit` is `None` unless only one token changed; callers should
/// use `set_source` for the multi-edit path.
pub fn GraphDoc::lower_rename_node_binding(
  self : GraphDoc,
  old_name : String,
  new_name : String,
) -> LoweredGraphEdit? {
  if old_name == new_name || !is_identifier_text(new_name) {
    return None
  }
  if self.find_node(new_name) is Some(_) {
    return None
  }
  let replacements : Array[SourceReplacement] = []
  let mut found_binding = false
  for node in self.nodes() {
    if node.binding == old_name {
      found_binding = true
      replacements.push(replacement_for_token(node.binding_token, new_name))
    }
    for param in node.params {
      if param.value_kind == InputRef {
        for token in param.value_tokens {
          if token.role == InputReference && token.text == old_name {
            replacements.push(replacement_for_token(token, new_name))
          }
        }
      }
    }
  }
  if !found_binding {
    return None
  }
  lowered_from_replacements(self.source(), replacements)
}

///|
/// Lower an edge insertion by adding an `input: <binding>` argument before the
/// constructor call's closing parenthesis. The source binding must exist, and
/// this minimal example rejects a second `input` argument rather than emitting a
/// duplicate edge slot.
pub fn GraphDoc::lower_add_connection(
  self : GraphDoc,
  binding : String,
  input_ref : String,
) -> LoweredGraphEdit? {
  if !is_identifier_text(input_ref) || self.find_node(input_ref) is None {
    return None
  }
  let node = match self.find_node(binding) {
    Some(node) => node
    None => return None
  }
  if find_param(node, "input") is Some(_) {
    return None
  }
  let prefix = if node.connection_separator { ", " } else { "" }
  let text = prefix + "input: " + input_ref
  lowered_from_replacements(self.source(), [
    SourceReplacement(
      start=node.argument_insert_offset,
      old_len=0,
      new_text=text,
    ),
  ])
}

///|
/// Lower an edge removal by deleting the matching input-reference parameter from
/// the target binding's constructor call. The target node and source binding
/// must both exist, and only the parameter whose name and input-reference token
/// match is removed; all graph node bindings remain in the generated source.
pub fn GraphDoc::lower_remove_connection(
  self : GraphDoc,
  binding : String,
  parameter : String,
  input_ref : String,
) -> LoweredGraphEdit? {
  if !is_identifier_text(parameter) ||
    !is_identifier_text(input_ref) ||
    self.find_node(input_ref) is None {
    return None
  }
  let node = match self.find_node(binding) {
    Some(node) => node
    None => return None
  }
  let index = match connection_param_index(node.params, parameter, input_ref) {
    Some(index) => index
    None => return None
  }
  let replacement = match
    removal_replacement_for_param(self.source(), node.params, index) {
    Some(replacement) => replacement
    None => return None
  }
  lowered_from_replacements(self.source(), [replacement])
}

///|
/// Lower a new graph node insertion by appending a fresh binding line. Binding
/// and constructor names must be lexical identifiers, and duplicate bindings are
/// rejected before source is generated.
pub fn GraphDoc::lower_insert_node_binding(
  self : GraphDoc,
  binding : String,
  constructor_name : String,
) -> LoweredGraphEdit? {
  if !is_identifier_text(binding) ||
    !is_identifier_text(constructor_name) ||
    self.find_node(binding) is Some(_) {
    return None
  }
  let line = binding + " = " + constructor_name + "()"
  let insert_text = if self.source().length() == 0 ||
    self.source().has_suffix("\n") {
    line
  } else {
    "\n" + line
  }
  lowered_from_replacements(self.source(), [
    SourceReplacement(
      start=self.source().length(),
      old_len=0,
      new_text=insert_text,
    ),
  ])
}
