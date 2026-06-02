# `dowdiness/graph-dsl`

A checked Loom example for **source-map-backed graph authoring**. The language is
small on purpose: each line binds a graph node, calls a constructor, optionally
names an output, and stores parameters that a graph UI can edit by source range.

```text
osc = sine(freq: 440Hz, wave: "saw") -> audio
filter = lowpass(input: osc, cutoff: 1200Hz, mode: warm)
```

The source text remains canonical. UI graph operations lower to text
replacements, the parser reparses, and projection returns explicit token roles so
callers do not need to match parser-internal token names.

## Token roles

`GraphTokenRole` distinguishes node binding names, constructor names, parameter
names, input references, output markers/output names, numeric parameters, units,
string fields, and enum fields.

```mbt check
///|
test "README token roles preserve source ranges" {
  let source = "osc = sine(freq: 440Hz, wave: \"saw\") -> audio"
  let doc = match project_graph_source(source) {
    Ok(doc) => doc
    Err(messages) => abort(messages.join("; "))
  }
  let number = doc.tokens_for_role(NumericParameter)[0]
  inspect(number.text(), content="440")
  inspect(number.start(), content="17")
  inspect(number.end(), content="20")
  let unit = doc.tokens_for_role(Unit)[0]
  inspect(unit.text(), content="Hz")
  inspect(unit.start(), content="20")
  inspect(unit.end(), content="22")
  inspect(doc.tokens_for_role(OutputMarker)[0].text(), content="->")
}
```

## Lowering graph operations to text edits

The lowering helpers return `LoweredGraphEdit`: concrete replacements,
`new_source`, and a single `incremental_edit` when the operation is one
contiguous edit suitable for `Parser::apply_edit`. The helpers reject edits that
would knowingly generate invalid DSL tokens, such as non-numeric parameter text
or duplicate node bindings.

```mbt check
///|
test "README lower numeric parameter" {
  let doc = match project_graph_source("osc = sine(freq: 440Hz)") {
    Ok(doc) => doc
    Err(messages) => abort(messages.join("; "))
  }
  let lowered = match doc.lower_set_numeric("osc", "freq", "880") {
    Some(edit) => edit
    None => abort("expected lowered edit")
  }
  let replacements = lowered.replacements()
  inspect(replacements[0].start(), content="17")
  inspect(replacements[0].old_len(), content="3")
  inspect(lowered.incremental_edit() is Some(_), content="true")
  inspect(lowered.new_source(), content="osc = sine(freq: 880Hz)")
}
```

Multi-range operations, such as renaming a binding and all input references to
it, intentionally return `incremental_edit = None`; callers can apply the
`new_source` through `set_source`.

## Last-good authoring attachment

`GraphAttachment` follows the checked last-good pattern: build one
`@loom.new_parser`, derive projection attempts on `parser.runtime()`, keep a
persistent `@incr.Watch`, and update cached last-good state only after parser and
projection success.

```mbt check
///|
test "README last-good graph projection" {
  let attachment = GraphAttachment::GraphAttachment("osc = sine(freq: 440Hz)")
  inspect(attachment.state(), content="Current")
  attachment.set_source("osc = sine(freq: )")
  inspect(attachment.state(), content="ParserBlocked")
  inspect(!attachment.diagnostics().is_empty(), content="true")
  inspect(attachment.last_good() is Some(_), content="true")
  attachment.set_source("osc = sine(input: missing)")
  inspect(attachment.state(), content="ProjectionBlocked")
  inspect(!attachment.diagnostics().is_empty(), content="true")
  inspect(attachment.last_good() is Some(_), content="true")
}
```

## Running

```bash
cd examples/graph-dsl
moon test
```

## Related Loom APIs

- [`@loom.new_parser`](../../loom/) — unified parser surface used by the
  attachment.
- [`docs/api/projection-guide.md`](../../docs/api/projection-guide.md) — direct
  CST shape validation and stable projection identity.
- [`docs/api/last-good-semantic-attachment.md`](../../docs/api/last-good-semantic-attachment.md)
  — the last-good state policy this example follows.
