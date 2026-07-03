///|
/// Regenerate all 3 grammar-parity fixture `.g.mbt` files from the current
/// emitter output.  Intended to be run after a PR that changes the emitter
/// output format (e.g. PR #573 AST-builder backend), so the checked-in
/// fixtures stay byte-identical to what `emit_grammar` produces.
///
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
}
