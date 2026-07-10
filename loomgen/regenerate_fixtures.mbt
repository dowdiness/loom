///|

///| Regenerate grammar-parity fixture `.g.mbt` files from the current

///| emitter and IR-level fixture `.g.mbt` files from the current

///|
/// EBNF-to-IR lowering.
/// Usage: `moon run loomgen --target native -- --regenerate-fixtures`
pub fn regenerate_fixtures() -> Unit {
  // ---------- simple_parser.g.mbt (ParityToken / ParityKind) ----------
  {
    let rules : Map[String, @grammar.Expr[String, String]] = {
      "source": @grammar.Expr::Node(
        "Root",
        @grammar.Expr::Emit("Int", "IntToken"),
      ),
    }
    let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
    match
      emit_grammar(
        ir,
        token_type="ParityToken",
        syntax_type="ParityKind",
        core_qual="@core",
        token_ref=fn(t) { "ParityToken::" + t },
        kind_ref=fn(k) { "ParityKind::" + k },
      ) {
      Err(msg) => println("ERROR: simple_parser: " + msg)
      Ok(content) => {
        let path = "loomgen/fixtures/grammar_parity/simple_parser.g.mbt"
        @fs.write_string_to_file(path, content) catch {
          _ => println("ERROR: failed to write " + path)
        }
        println("  " + path)
      }
    }
  }

  // ------ repeat_parser.g.mbt (ReuseToken / ReuseKind) ------
  {
    let rules : Map[String, @grammar.Expr[String, String]] = {
      "source": @grammar.Expr::Node(
        "Root",
        @grammar.Expr::RepeatTopLevel(
          "item",
          starts=@grammar.Pred::IsToken("Int"),
          delim=@grammar.Pred::IsToken("Skip"),
          delim_kind="SkipKind",
          between_msg="between",
          after_msg="after",
        ),
      ),
      "item": @grammar.Expr::Node(
        "IntItem",
        @grammar.Expr::Emit("Int", "IntToken"),
      ),
    }
    let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
    match
      emit_grammar(
        ir,
        token_type="ReuseToken",
        syntax_type="ReuseKind",
        core_qual="@core",
        token_ref=fn(t) { "ReuseToken::" + t },
        kind_ref=fn(k) { "ReuseKind::" + k },
      ) {
      Err(msg) => println("ERROR: repeat_parser: " + msg)
      Ok(content) => {
        let path = "loomgen/fixtures/grammar_parity_reuse/repeat_parser.g.mbt"
        @fs.write_string_to_file(path, content) catch {
          _ => println("ERROR: failed to write " + path)
        }
        println("  " + path)
      }
    }
  }

  // ------ native_parser.g.mbt (NativeParityToken / NativeParityKind) ------
  // This fixture has a hand-written `delegate_to_inner` function after the
  // generated portion.  `emit_grammar` emits only the header comment + rule
  // functions; we append the hand-written tail back.
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Node(
      "Root",
      @grammar.Expr::Native("delegate_to_inner"),
    ),
    "inner": @grammar.Expr::Emit("Int", "IntToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let tail = "\n" +
    "///|\n" +
    "/// Hand-written per the header comment above (`emit_grammar` never emits a\n" +
    "/// native's body). Re-entry is free in the emitted path: this calls the\n" +
    "/// sibling `parse_inner(ctx)` directly, no `call_rule` plumbing — contrast\n" +
    "/// with `native_registry()` in parity_defs.mbt, which re-enters the same\n" +
    "/// `inner` rule through the interpreter's `call_rule` handle instead.\n" +
    "fn delegate_to_inner(\n" +
    "  ctx : @core.ParserContext[NativeParityToken, NativeParityKind],\n" +
    ") -> Unit {\n" +
    "  parse_inner(ctx)\n" +
    "}\n"
  match
    emit_grammar(
      ir,
      token_type="NativeParityToken",
      syntax_type="NativeParityKind",
      core_qual="@core",
      token_ref=fn(t) { "NativeParityToken::" + t },
      kind_ref=fn(k) { "NativeParityKind::" + k },
      native_names=Set::Set(["delegate_to_inner"]),
    ) {
    Err(msg) => println("ERROR: native_parser: " + msg)
    Ok(content) => {
      let path = "loomgen/fixtures/grammar_parity_native/native_parser.g.mbt"
      @fs.write_string_to_file(path, content + tail) catch {
        _ => println("ERROR: failed to write " + path)
      }
      println("  " + path)
    }
  }

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
}
