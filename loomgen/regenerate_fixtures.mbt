///| Regenerate fixture `.g.mbt` files from the current

///| EBNF-to-IR lowering.

///|
/// Usage: `moon run loomgen --target native -- --regenerate-fixtures`
pub fn regenerate_fixtures() -> Unit {
  // ------ error_node_fixture.g.mbt (IR-level fixture) ------
  // Reads the EBNS fixture, parses annotations, and emits the IR through
  // emit_grammar_ir — the same path the golden test exercises.
  {
    let src = @fs.read_file_to_string("loomgen/fixtures/error_node_fixture.mbt") catch {
      _ => {
        println("ERROR: failed to read error_node_fixture.mbt")
        return
      }
    }
    match parse_annotations(src) {
      Err(msg) => println("ERROR: error_node_fixture.mbt — " + msg)
      Ok(ann) => {
        guard ann.token_enum is Some(token_enum) else {
          println("ERROR: error_node_fixture.mbt has no #loom.token enum")
          return
        }
        guard ann.term_enum is Some(term_enum) else {
          println("ERROR: error_node_fixture.mbt has no #loom.term enum")
          return
        }
        match
          emit_grammar_ir(
            term_enum, token_enum, "@token", "@syntax", "@grammar", "error_node_grammar_ir",
          ) {
          Err(msg) => println("ERROR: emitter — " + msg)
          Ok(content) => {
            let path = "loomgen/fixtures/error_node_fixture.g.mbt"
            @fs.write_string_to_file(path, content) catch {
              _ => println("ERROR: failed to write " + path)
            }
            println("  " + path)
          }
        }
      }
    }
  }
  // ------ rule_grammar_fixture.g.mbt (IR-level fixture) ------
  let src = @fs.read_file_to_string("loomgen/fixtures/rule_grammar_fixture.mbt") catch {
    _ => {
      println("ERROR: failed to read rule_grammar_fixture.mbt")
      return
    }
  }
  match parse_annotations(src) {
    Err(msg) => println("ERROR: rule_grammar_fixture.mbt — " + msg)
    Ok(ann) => {
      guard ann.token_enum is Some(token_enum) else {
        println("ERROR: rule_grammar_fixture.mbt has no #loom.token enum")
        return
      }
      guard ann.term_enum is Some(term_enum) else {
        println("ERROR: rule_grammar_fixture.mbt has no #loom.term enum")
        return
      }
      match
        emit_grammar_ir(
          term_enum, token_enum, "@token", "@syntax", "@grammar", "mini_grammar_ir",
        ) {
        Err(msg) => println("ERROR: emitter — " + msg)
        Ok(content) => {
          let path = "loomgen/fixtures/rule_grammar_fixture.g.mbt"
          @fs.write_string_to_file(path, content) catch {
            _ => println("ERROR: failed to write " + path)
          }
          println("  " + path)
        }
      }
    }
  }
  // ------ separated_list_fixture.g.mbt (IR-level fixture) ------
  let src = @fs.read_file_to_string(
    "loomgen/fixtures/separated_list_fixture.mbt",
  ) catch {
    _ => {
      println("ERROR: failed to read separated_list_fixture.mbt")
      return
    }
  }
  match parse_annotations(src) {
    Err(msg) => println("ERROR: separated_list_fixture.mbt — " + msg)
    Ok(ann) => {
      guard ann.token_enum is Some(token_enum) else {
        println("ERROR: separated_list_fixture.mbt has no #loom.token enum")
        return
      }
      guard ann.term_enum is Some(term_enum) else {
        println("ERROR: separated_list_fixture.mbt has no #loom.term enum")
        return
      }
      match
        emit_grammar_ir(
          term_enum, token_enum, "@token", "@syntax", "@grammar", "separated_list_grammar_ir",
        ) {
        Err(msg) => println("ERROR: emitter — " + msg)
        Ok(content) => {
          let path = "loomgen/fixtures/separated_list_fixture.g.mbt"
          @fs.write_string_to_file(path, content) catch {
            _ => println("ERROR: failed to write " + path)
          }
          println("  " + path)
        }
      }
    }
  }
  // ------ line_pattern_fixture.g.mbt (line-lexer fixture, #561) ------
  let src = @fs.read_file_to_string("loomgen/fixtures/line_pattern_fixture.mbt") catch {
    _ => {
      println("ERROR: failed to read line_pattern_fixture.mbt")
      return
    }
  }
  match parse_annotations(src) {
    Err(msg) => println("ERROR: line_pattern_fixture.mbt — " + msg)
    Ok(ann) => {
      guard ann.token_enum is Some(token_enum) else {
        println("ERROR: line_pattern_fixture.mbt has no #loom.token enum")
        return
      }
      guard ann.term_enum is Some(term_enum) else {
        println("ERROR: line_pattern_fixture.mbt has no #loom.term enum")
        return
      }
      match emit_line_lexer(token_enum, Some(term_enum), "@core") {
        None => println("ERROR: emit_line_lexer returned None")
        Some(content) => {
          let path = "loomgen/fixtures/line_pattern_fixture.g.mbt"
          @fs.write_string_to_file(path, content) catch {
            _ => println("ERROR: failed to write " + path)
          }
          println("  " + path)
        }
      }
    }
  }
}
