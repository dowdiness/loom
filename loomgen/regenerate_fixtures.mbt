///| Regenerate fixture `.g.mbt` files from the current

///| EBNF-to-IR lowering.

///|
/// Usage: `moon run loomgen --target native -- --regenerate-fixtures`

///|
/// Build both generated outputs for the compiled line-lexer regression fixture.
/// The existing skeleton supplies its handwritten inline fallback; only Loom's
/// historical line-mode stub may be replaced by a generated delegate.
fn build_line_lexer_regression_outputs(
  source : String,
  existing_skeleton : String,
) -> Result[(String, String), String] {
  let annotations = match parse_annotations(source) {
    Ok(annotations) => annotations
    Err(msg) => return Err(msg)
  }
  guard annotations.token_enum is Some(token_enum) else {
    return Err("line_lexer_src.mbt has no #loom.token enum")
  }
  guard annotations.term_enum is Some(term_enum) else {
    return Err("line_lexer_src.mbt has no #loom.term enum")
  }
  match emit_line_lexer(token_enum, Some(term_enum), "@core") {
    None => Err("emit_line_lexer returned None")
    Some(line_lexer) => {
      let line_modes = collect_line_lexer_modes(Some(term_enum))
      if line_modes.length() == 0 {
        Err("line_lexer_src.mbt has no #loom.line_mode variants")
      } else {
        Ok(
          (
            line_lexer,
            integrate_line_lexer_skeleton(
              existing_skeleton, line_modes, "Token", "@core",
            ),
          ),
        )
      }
    }
  }
}

///|
fn read_regeneration_fixture(path : String) -> Result[String, String] {
  let content = @fs.read_file_to_string(path) catch {
    _ => return Err("failed to read " + path)
  }
  Ok(content)
}

///|
fn write_regeneration_fixture(
  path : String,
  content : String,
) -> Result[Unit, String] {
  @fs.write_string_to_file(path, content) catch {
    _ => return Err("failed to write " + path)
  }
  println("  " + path)
  Ok(())
}

///|
/// Regenerate the compiled fixture and report any unavailable source, skeleton,
/// or output so the CLI can fail instead of silently accepting stale artifacts.
fn regenerate_line_lexer_regression_fixture(
  source_path : String,
  line_lexer_path : String,
  skeleton_path : String,
) -> Result[Unit, String] {
  let source = match read_regeneration_fixture(source_path) {
    Ok(source) => source
    Err(msg) => return Err(msg)
  }
  let skeleton = match read_regeneration_fixture(skeleton_path) {
    Ok(skeleton) => skeleton
    Err(msg) => return Err(msg)
  }
  match build_line_lexer_regression_outputs(source, skeleton) {
    Err(msg) => Err(msg)
    Ok((line_lexer, integrated_skeleton)) =>
      match write_regeneration_fixture(line_lexer_path, line_lexer) {
        Err(msg) => Err(msg)
        Ok(_) => write_regeneration_fixture(skeleton_path, integrated_skeleton)
      }
  }
}

///|
fn regenerate_grammar_ir_fixture(
  source_path : String,
  output_path : String,
  grammar_name : String,
) -> Result[Unit, String] {
  let source = match read_regeneration_fixture(source_path) {
    Ok(source) => source
    Err(msg) => return Err(msg)
  }
  let annotations = match parse_annotations(source) {
    Ok(annotations) => annotations
    Err(msg) => return Err(source_path + " — " + msg)
  }
  guard annotations.token_enum is Some(token_enum) else {
    return Err(source_path + " has no #loom.token enum")
  }
  guard annotations.term_enum is Some(term_enum) else {
    return Err(source_path + " has no #loom.term enum")
  }
  match
    emit_grammar_ir(
      term_enum, token_enum, "@token", "@syntax", "@grammar", grammar_name,
    ) {
    Err(msg) => Err("emitter — " + msg)
    Ok(content) => write_regeneration_fixture(output_path, content)
  }
}

///|
fn regenerate_line_pattern_fixture(
  source_path : String,
  output_path : String,
) -> Result[Unit, String] {
  let source = match read_regeneration_fixture(source_path) {
    Ok(source) => source
    Err(msg) => return Err(msg)
  }
  let annotations = match parse_annotations(source) {
    Ok(annotations) => annotations
    Err(msg) => return Err(source_path + " — " + msg)
  }
  guard annotations.token_enum is Some(token_enum) else {
    return Err(source_path + " has no #loom.token enum")
  }
  guard annotations.term_enum is Some(term_enum) else {
    return Err(source_path + " has no #loom.term enum")
  }
  match emit_line_lexer(token_enum, Some(term_enum), "@core") {
    None => Err("emit_line_lexer returned None")
    Some(content) => write_regeneration_fixture(output_path, content)
  }
}

///|
/// Regenerate every committed Loomgen fixture. Any read, parse, emit, or write
/// failure is returned to the CLI so a successful process exit proves that the
/// generated artifacts were refreshed.
fn regenerate_fixtures() -> Result[Unit, String] {
  match
    regenerate_grammar_ir_fixture(
      "loomgen/fixtures/error_node_fixture.mbt", "loomgen/fixtures/error_node_fixture.g.mbt",
      "error_node_grammar_ir",
    ) {
    Err(msg) => Err(msg)
    Ok(_) =>
      match
        regenerate_grammar_ir_fixture(
          "loomgen/fixtures/rule_grammar_fixture.mbt", "loomgen/fixtures/rule_grammar_fixture.g.mbt",
          "mini_grammar_ir",
        ) {
        Err(msg) => Err(msg)
        Ok(_) =>
          match
            regenerate_grammar_ir_fixture(
              "loomgen/fixtures/separated_list_fixture.mbt", "loomgen/fixtures/separated_list_fixture.g.mbt",
              "separated_list_grammar_ir",
            ) {
            Err(msg) => Err(msg)
            Ok(_) =>
              match
                regenerate_line_pattern_fixture(
                  "loomgen/fixtures/line_pattern_fixture.mbt", "loomgen/fixtures/line_pattern_fixture.g.mbt",
                ) {
                Err(msg) => Err(msg)
                Ok(_) =>
                  regenerate_line_lexer_regression_fixture(
                    "fixtures/line_lexer_regression/src/line_lexer_src.mbt", "fixtures/line_lexer_regression/line_lexer.g.mbt",
                    "fixtures/line_lexer_regression/lexer_skeleton.g.mbt",
                  )
              }
          }
      }
  }
}
