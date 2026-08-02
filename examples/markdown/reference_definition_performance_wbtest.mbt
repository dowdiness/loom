///|
fn consecutive_reference_definitions_source(count : Int) -> String {
  let builder = StringBuilder::StringBuilder()
  for i = 0; i < count; i = i + 1 {
    builder.write_string("[label-")
    builder.write_string(i.to_string())
    builder.write_string("]: /destination-")
    builder.write_string(i.to_string())
    builder.write_char('\n')
  }
  builder.to_string()
}

///|
fn benchmark_consecutive_reference_definition_tokenize(
  b : @bench.T,
  count : Int,
) -> Unit {
  let source = consecutive_reference_definitions_source(count)
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
fn benchmark_consecutive_reference_definition_parse(
  b : @bench.T,
  count : Int,
) -> Unit {
  let source = consecutive_reference_definitions_source(count)
  let source_id = @core.SourceId("markdown-reference-definition-performance")
  b.bench(fn() {
    let parsed = parse_cst(source_id, source) catch {
      _ => abort("reference-definition parse failed")
    }
    b.keep(parsed)
  })
}

///|
fn consecutive_reference_definition_lookahead_work(
  count : Int,
) -> (Int, Int, Int) raise {
  let source = consecutive_reference_definitions_source(count)
  let tokens = tokenize(source)
  let starts = @core.build_starts(tokens)
  let mut token_index = 0
  let mut definitions = 0
  let mut inspected = 0
  while token_index < tokens.length() && tokens[token_index].token != EOF {
    let candidate_start = token_index
    let cursor = new_reference_definition_cursor(offset => {
      let index = candidate_start + offset
      if index >= tokens.length() {
        None
      } else {
        match tokens[index].token {
          EOF | BlankLine => None
          _ =>
            Some(
              source.view(
                start_offset=starts[index],
                end_offset=starts[index] + tokens[index].len,
              ),
            )
        }
      }
    })
    let outcome = scan_reference_definition_cursor(cursor)
    inspected = inspected + cursor.inspected
    match outcome {
      ReferenceDefinitionFound(definition) => {
        let definition_end = starts[candidate_start] + definition.end
        while token_index < tokens.length() &&
              starts[token_index] < definition_end {
          token_index = token_index + 1
        }
        definitions = definitions + 1
      }
      _ => abort("adversarial corpus must contain only reference definitions")
    }
  }
  (definitions, inspected, source.length())
}

///|
test "reference definition: consecutive lookahead work is prefix-linear" {
  let (small_count, small_work, small_length) = consecutive_reference_definition_lookahead_work(
    32,
  )
  let (large_count, large_work, large_length) = consecutive_reference_definition_lookahead_work(
    64,
  )
  inspect(small_count, content="32")
  inspect(large_count, content="64")
  assert_true(small_work <= small_length + small_count)
  assert_true(large_work <= large_length + large_count)
  assert_true(large_work <= small_work * 2 + 64)
}

///|
test "reference definition: consecutive 256 tokenize" (b : @bench.T) {
  benchmark_consecutive_reference_definition_tokenize(b, 256)
}

///|
test "reference definition: consecutive 256 parse" (b : @bench.T) {
  benchmark_consecutive_reference_definition_parse(b, 256)
}

///|
test "reference definition: consecutive 1024 parse" (b : @bench.T) {
  benchmark_consecutive_reference_definition_parse(b, 1024)
}
