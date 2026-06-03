///|
const SAMPLE_SOURCE = "osc = sine(freq: 440Hz, wave: \"saw\") -> audio\nfilter = lowpass(input: osc, cutoff: 1200Hz, mode: warm)"

///|
fn assert_true(value : Bool) -> Unit {
  if !value {
    abort("expected true")
  }
}

///|
fn ok_doc(result : Result[GraphDoc, Array[String]]) -> GraphDoc {
  match result {
    Ok(doc) => doc
    Err(messages) => abort("expected graph doc, got: " + messages.join("; "))
  }
}

///|
fn ok_current(result : Result[GraphDoc, String]) -> GraphDoc {
  match result {
    Ok(doc) => doc
    Err(message) => abort("expected current graph doc, got: " + message)
  }
}

///|
fn ok_lowered(edit : LoweredGraphEdit?) -> LoweredGraphEdit {
  match edit {
    Some(edit) => edit
    None => abort("expected lowered graph edit")
  }
}

///|
fn triples(tokens : Array[GraphToken]) -> Array[(String, Int, Int)] {
  tokens.map(fn(token) { (token.text(), token.start(), token.end()) })
}

///|
fn node_id(doc : GraphDoc, binding : String) -> String {
  match doc.find_node(binding) {
    Some(node) => node.id()
    None => abort("missing node: " + binding)
  }
}

///|
test "projection exposes explicit token roles with source ranges" {
  let doc = ok_doc(project_graph_source(SAMPLE_SOURCE))
  @debug.assert_eq(triples(doc.tokens_for_role(NodeBindingName)), [
    ("osc", 0, 3),
    ("filter", 46, 52),
  ])
  @debug.assert_eq(triples(doc.tokens_for_role(ConstructorName)), [
    ("sine", 6, 10),
    ("lowpass", 55, 62),
  ])
  @debug.assert_eq(triples(doc.tokens_for_role(NumericParameter)), [
    ("440", 17, 20),
    ("1200", 83, 87),
  ])
  @debug.assert_eq(triples(doc.tokens_for_role(Unit)), [
    ("Hz", 20, 22),
    ("Hz", 87, 89),
  ])
  @debug.assert_eq(triples(doc.tokens_for_role(StringField)), [
    ("\"saw\"", 30, 35),
  ])
  @debug.assert_eq(triples(doc.tokens_for_role(OutputMarker)), [("->", 37, 39)])
  @debug.assert_eq(triples(doc.tokens_for_role(OutputName)), [("audio", 40, 45)])
  @debug.assert_eq(triples(doc.tokens_for_role(InputReference)), [
    ("osc", 70, 73),
  ])
  @debug.assert_eq(triples(doc.tokens_for_role(EnumField)), [("warm", 97, 101)])
}

///|
test "lower numeric parameter to one exact Edit and preserve neighboring ranges" {
  let doc = ok_doc(project_graph_source(SAMPLE_SOURCE))
  let lowered = ok_lowered(doc.lower_set_numeric("osc", "freq", "880"))
  @debug.assert_eq(lowered.replacements().length(), 1)
  @debug.assert_eq(lowered.replacements()[0].start(), 17)
  @debug.assert_eq(lowered.replacements()[0].old_len(), 3)
  match lowered.incremental_edit() {
    Some(edit) => {
      @debug.assert_eq(edit.start, 17)
      @debug.assert_eq(edit.old_len, 3)
      @debug.assert_eq(edit.new_len, 3)
    }
    None => abort("single-token replacement should expose an incremental edit")
  }
  let updated = ok_doc(project_graph_source(lowered.new_source()))
  @debug.assert_eq(triples(updated.tokens_for_role(NumericParameter)), [
    ("880", 17, 20),
    ("1200", 83, 87),
  ])
  @debug.assert_eq(triples(updated.tokens_for_role(Unit)), [
    ("Hz", 20, 22),
    ("Hz", 87, 89),
  ])
}

///|
test "rename binding lowers to binding and input-reference replacements" {
  let doc = ok_doc(project_graph_source(SAMPLE_SOURCE))
  let lowered = ok_lowered(doc.lower_rename_node_binding("osc", "lfo"))
  @debug.assert_eq(lowered.replacements().length(), 2)
  assert_true(lowered.incremental_edit() is None)
  @debug.assert_eq(lowered.replacements()[0].start(), 0)
  @debug.assert_eq(lowered.replacements()[1].start(), 70)
  let renamed = ok_doc(project_graph_source(lowered.new_source()))
  @debug.assert_eq(triples(renamed.tokens_for_role(NodeBindingName)), [
    ("lfo", 0, 3),
    ("filter", 46, 52),
  ])
  @debug.assert_eq(triples(renamed.tokens_for_role(InputReference)), [
    ("lfo", 70, 73),
  ])
}

///|
test "add connection lowers to insertion before call close paren" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let doc = ok_doc(project_graph_source(source))
  let lowered = ok_lowered(doc.lower_add_connection("meter", "osc"))
  @debug.assert_eq(lowered.replacements().length(), 1)
  @debug.assert_eq(lowered.replacements()[0].start(), 38)
  @debug.assert_eq(lowered.replacements()[0].old_len(), 0)
  @debug.assert_eq(lowered.replacements()[0].new_text(), "input: osc")
  let updated = ok_doc(project_graph_source(lowered.new_source()))
  @debug.assert_eq(triples(updated.tokens_for_role(InputReference)), [
    ("osc", 38 + "input: ".length(), 38 + "input: osc".length()),
  ])
}

///|
fn assert_remove_connection_source(
  source : String,
  expected : String,
) -> Unit raise {
  let doc = ok_doc(project_graph_source(source))
  let lowered = ok_lowered(
    doc.lower_remove_connection("target", "input", "osc"),
  )
  @debug.assert_eq(lowered.replacements().length(), 1)
  @debug.assert_eq(lowered.replacements()[0].new_text(), "")
  @debug.assert_eq(lowered.new_source(), expected)
  let updated = ok_doc(project_graph_source(lowered.new_source()))
  assert_true(updated.find_node("osc") is Some(_))
  assert_true(updated.find_node("target") is Some(_))
  @debug.assert_eq(updated.nodes().length(), doc.nodes().length())
  @debug.assert_eq(triples(updated.tokens_for_role(InputReference)), [])
}

///|
test "remove connection lowers first input-reference parameter deletion" {
  assert_remove_connection_source(
    "osc = sine()\ntarget = blend(input: osc, gain: 1, mode: warm)", "osc = sine()\ntarget = blend(gain: 1, mode: warm)",
  )
}

///|
test "remove connection lowers middle input-reference parameter deletion" {
  assert_remove_connection_source(
    "osc = sine()\ntarget = blend(gain: 1, input: osc, mode: warm)", "osc = sine()\ntarget = blend(gain: 1, mode: warm)",
  )
}

///|
test "remove connection lowers trailing input-reference parameter deletion" {
  assert_remove_connection_source(
    "osc = sine()\ntarget = blend(gain: 1, input: osc)", "osc = sine()\ntarget = blend(gain: 1)",
  )
}

///|
test "remove connection lowers sole input-reference parameter deletion" {
  assert_remove_connection_source(
    "osc = sine()\ntarget = blend( input: osc )", "osc = sine()\ntarget = blend()",
  )
}

///|
test "remove connection consumes sole parameter trailing comma" {
  assert_remove_connection_source(
    "osc = sine()\ntarget = blend(input: osc,)", "osc = sine()\ntarget = blend()",
  )
}

///|
test "remove connection consumes trailing parameter trailing comma" {
  assert_remove_connection_source(
    "osc = sine()\ntarget = blend(gain: 1, input: osc,)", "osc = sine()\ntarget = blend(gain: 1)",
  )
}

///|
test "remove connection preserves non-matching input-reference parameters" {
  let source = "osc = sine()\nlfo = sine()\ntarget = blend(input: osc, from: lfo)"
  let doc = ok_doc(project_graph_source(source))
  let lowered = ok_lowered(
    doc.lower_remove_connection("target", "input", "osc"),
  )
  @debug.assert_eq(
    lowered.new_source(),
    "osc = sine()\nlfo = sine()\ntarget = blend(from: lfo)",
  )
  let updated = ok_doc(project_graph_source(lowered.new_source()))
  @debug.assert_eq(
    updated.tokens_for_role(InputReference).map(fn(token) { token.text() }),
    ["lfo"],
  )
}

///|
test "insert new node binding lowers to append insertion" {
  let doc = ok_doc(project_graph_source(SAMPLE_SOURCE))
  let lowered = ok_lowered(doc.lower_insert_node_binding("reverb", "plate"))
  @debug.assert_eq(lowered.replacements().length(), 1)
  @debug.assert_eq(lowered.replacements()[0].start(), SAMPLE_SOURCE.length())
  @debug.assert_eq(lowered.replacements()[0].old_len(), 0)
  @debug.assert_eq(lowered.replacements()[0].new_text(), "\nreverb = plate()")
  let updated = ok_doc(project_graph_source(lowered.new_source()))
  @debug.assert_eq(triples(updated.tokens_for_role(NodeBindingName)), [
    ("osc", 0, 3),
    ("filter", 46, 52),
    ("reverb", 103, 109),
  ])
}

///|
test "lowering rejects edits that would generate invalid graph source" {
  let doc = ok_doc(project_graph_source(SAMPLE_SOURCE))
  assert_true(doc.lower_set_numeric("osc", "freq", "880Hz") is None)
  assert_true(doc.lower_rename_node_binding("osc", "bad name") is None)
  assert_true(doc.lower_rename_node_binding("osc", "filter") is None)
  assert_true(doc.lower_add_connection("filter", "osc") is None)
  assert_true(doc.lower_add_connection("filter", "missing") is None)
  assert_true(doc.lower_remove_connection("filter", "input", "missing") is None)
  assert_true(doc.lower_remove_connection("filter", "cutoff", "osc") is None)
  assert_true(doc.lower_insert_node_binding("osc", "plate") is None)
  assert_true(doc.lower_insert_node_binding("bad name", "plate") is None)
}

///|
test "public accessors return defensive array copies" {
  let doc = ok_doc(project_graph_source(SAMPLE_SOURCE))
  let tokens = doc.tokens()
  let token_count = tokens.length()
  tokens.push(tokens[0])
  @debug.assert_eq(doc.tokens().length(), token_count)

  let node = match doc.find_node("osc") {
    Some(node) => node
    None => abort("missing osc")
  }
  let params = node.params()
  let param_count = params.length()
  params.push(params[0])
  @debug.assert_eq(node.params().length(), param_count)

  let lowered = ok_lowered(doc.lower_set_numeric("osc", "freq", "880"))
  let replacements = lowered.replacements()
  replacements.push(replacements[0])
  @debug.assert_eq(lowered.replacements().length(), 1)
}

///|
test "attachment retains last good projection across parser and projection failures" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  inspect(attachment.state(), content="Current")
  @debug.assert_eq(attachment.diagnostics(), [])
  let good = ok_current(attachment.current_result())

  attachment.set_source("osc = sine(freq: )")
  inspect(attachment.state(), content="ParserBlocked")
  assert_true(!attachment.diagnostics().is_empty())
  assert_true(attachment.current_result() is Err(_))
  assert_true(attachment.last_good() == Some(good))

  attachment.set_source("osc = sine(input: missing)")
  inspect(attachment.state(), content="ProjectionBlocked")
  assert_true(!attachment.diagnostics().is_empty())
  assert_true(attachment.current_result() is Err(_))
  assert_true(attachment.last_good() == Some(good))
}

///|
test "attachment apply_edit preserves node identity for unchanged graph nodes" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let before = ok_current(attachment.current_result())
  let osc_id = node_id(before, "osc")
  let filter_id = node_id(before, "filter")
  let lowered = ok_lowered(before.lower_set_numeric("osc", "freq", "880"))
  let edit = match lowered.incremental_edit() {
    Some(edit) => edit
    None => abort("expected exact edit")
  }
  attachment.apply_edit(edit, lowered.new_source())
  inspect(attachment.state(), content="Current")
  let after = ok_current(attachment.current_result())
  @debug.assert_eq(node_id(after, "osc"), osc_id)
  @debug.assert_eq(node_id(after, "filter"), filter_id)
}
