///|
fn parse_rule_fn_name(name : String) -> String {
  "parse_" + name
}

///|
pub fn[T, K] emit_grammar(
  ir : @grammar.GrammarIr[T, K],
  token_type~ : String,
  syntax_type~ : String,
  core_qual~ : String,
  token_ref~ : (T) -> String,
  kind_ref~ : (K) -> String,
) -> Result[String, String] {
  let compiled = @grammar.compile(ir) catch {
    @grammar.MissingRoot(name) =>
      return Err("grammar emitter: missing root rule \"" + name + "\"")
    @grammar.MissingRef(name) =>
      return Err("grammar emitter: missing ref \"" + name + "\"")
  }
  let root_name = compiled.names[compiled.root_slot()]
  let root_fn = parse_rule_fn_name(root_name)
  let parser_context = core_qual +
    ".ParserContext[" +
    token_type +
    ", " +
    syntax_type +
    "]"
  let b = StringBuilder()
  b.write_string("///|\n")
  b.write_string("pub fn parse_root(ctx : ")
  b.write_string(parser_context)
  b.write_string(") -> Unit {\n")
  b.write_string("  ")
  b.write_string(root_fn)
  b.write_string("(ctx)\n")
  b.write_string("}\n\n")
  for i, name in compiled.names {
    let expr = compiled.rule(i)
    let body = match
      emit_compiled_expr(expr, compiled~, token_ref~, kind_ref~, indent="  ") {
      Ok(s) => s
      Err(msg) => return Err(msg)
    }
    b.write_string("///|\n")
    b.write_string("fn ")
    b.write_string(parse_rule_fn_name(name))
    b.write_string("(ctx : ")
    b.write_string(parser_context)
    b.write_string(") -> Unit {\n")
    b.write_string(body)
    b.write_string("}\n")
    if i != compiled.names.length() - 1 {
      b.write_string("\n")
    }
  }
  Ok(b.to_string())
}

///|
fn string_lit(s : String) -> String {
  let escaped = s
    .replace_all(old="\\", new="\\\\")
    .replace_all(old="\n", new="\\n")
    .replace_all(old="\r", new="\\r")
    .replace_all(old="\t", new="\\t")
    .replace_all(old="\"", new="\\\"")
  "\"" + escaped + "\""
}

///|
fn[T] emit_pred_closure(
  pred : @grammar.Pred[T],
  token_ref : (T) -> String,
) -> String {
  "fn(t) { " + emit_pred(pred, "t", token_ref) + " }"
}

///|
fn[T, K] emit_pair_array(
  pairs : Array[(T, K)],
  token_ref : (T) -> String,
  kind_ref : (K) -> String,
) -> String {
  let parts = pairs.map(fn(pair) {
    "(" + token_ref(pair.0) + ", " + kind_ref(pair.1) + ")"
  })
  "[" + parts.join(", ") + "]"
}

///|

///|
fn[T] emit_pred(
  pred : @grammar.Pred[T],
  token_var : String,
  token_ref : (T) -> String,
) -> String {
  match pred {
    @grammar.Pred::Any => "true"
    @grammar.Pred::IsToken(token) => token_var + " == " + token_ref(token)
    @grammar.Pred::OneOf(tokens) => {
      if tokens.length() == 0 {
        return "false"
      }
      let arms = tokens.map(fn(t) { token_ref(t) }).join(" | ")
      "match " + token_var + " { " + arms + " => true; _ => false }"
    }
    @grammar.Pred::Not(inner) =>
      "!(" + emit_pred(inner, token_var, token_ref) + ")"
  }
}

///|
fn[T, K] emit_compiled_expr(
  expr : @grammar.CompiledExpr[T, K],
  compiled~ : @grammar.CompiledGrammar[T, K],
  token_ref~ : (T) -> String,
  kind_ref~ : (K) -> String,
  indent~ : String,
) -> Result[String, String] {
  match expr {
    @grammar.CompiledExpr::Node(kind, body) => {
      let inner = match
        emit_compiled_expr(
          body,
          compiled~,
          token_ref~,
          kind_ref~,
          indent=indent + "  ",
        ) {
        Ok(s) => s
        Err(msg) => return Err(msg)
      }
      Ok(
        indent +
        "ctx.node(" +
        kind_ref(kind) +
        ", fn() {\n" +
        inner +
        indent +
        "})\n",
      )
    }
    @grammar.CompiledExpr::Emit(token, kind) =>
      Ok(
        indent +
        "if ctx.at(" +
        token_ref(token) +
        ") {\n" +
        indent +
        "  ctx.emit_token(" +
        kind_ref(kind) +
        ")\n" +
        indent +
        "}\n",
      )
    @grammar.CompiledExpr::RefSlot(slot) =>
      Ok(indent + parse_rule_fn_name(compiled.names[slot]) + "(ctx)\n")
    @grammar.CompiledExpr::Choice(alts) => {
      let b = StringBuilder()
      b.write_string(indent + "let token = ctx.peek()\n")
      for i, alt in alts {
        if i == 0 {
          b.write_string(indent + "if ")
        } else {
          b.write_string(indent + "} else if ")
        }
        b.write_string(emit_pred(alt.starts, "token", token_ref))
        b.write_string(" {\n")
        let body = match
          emit_compiled_expr(
            alt.body,
            compiled~,
            token_ref~,
            kind_ref~,
            indent=indent + "  ",
          ) {
          Ok(s) => s
          Err(msg) => return Err(msg)
        }
        b.write_string(body)
      }
      if alts.length() > 0 {
        b.write_string(indent + "}\n")
      }
      Ok(b.to_string())
    }
    @grammar.CompiledExpr::Seq(exprs) => {
      let b = StringBuilder()
      for e in exprs {
        let part = match
          emit_compiled_expr(e, compiled~, token_ref~, kind_ref~, indent~) {
          Ok(s) => s
          Err(msg) => return Err(msg)
        }
        b.write_string(part)
      }
      Ok(b.to_string())
    }
    @grammar.CompiledExpr::Expect(token, kind) =>
      Ok(
        indent +
        "ctx.expect(" +
        token_ref(token) +
        ", " +
        kind_ref(kind) +
        ") |> ignore\n",
      )
    @grammar.CompiledExpr::RepeatWhile(pred, body) => {
      let inner = match
        emit_compiled_expr(
          body,
          compiled~,
          token_ref~,
          kind_ref~,
          indent=indent + "  ",
        ) {
        Ok(s) => s
        Err(msg) => return Err(msg)
      }
      Ok(
        indent +
        "while !ctx.at_eof() && " +
        emit_pred(pred, "ctx.peek()", token_ref) +
        " {\n" +
        inner +
        indent +
        "}\n",
      )
    }
    @grammar.CompiledExpr::Empty => Ok("")
    @grammar.CompiledExpr::EmitError(msg) =>
      Ok(indent + "ctx.error(" + string_lit(msg) + ")\n")
    @grammar.CompiledExpr::ErrorUntil(stop, msg) =>
      Ok(
        indent +
        "ctx.error(" +
        string_lit(msg) +
        ")\n" +
        indent +
        "ctx.skip_until(" +
        emit_pred_closure(stop, token_ref) +
        ") |> ignore\n",
      )
    @grammar.CompiledExpr::Fail(msg) =>
      Ok(
        indent +
        "ctx.error(" +
        string_lit(msg) +
        ")\n" +
        indent +
        "ctx.emit_error_placeholder()\n",
      )
    @grammar.CompiledExpr::EmitOr(token, kind, msg) =>
      Ok(
        indent +
        "if ctx.at(" +
        token_ref(token) +
        ") {\n" +
        indent +
        "  ctx.emit_token(" +
        kind_ref(kind) +
        ")\n" +
        indent +
        "} else {\n" +
        indent +
        "  ctx.error(" +
        string_lit(msg) +
        ")\n" +
        indent +
        "  ctx.emit_error_placeholder()\n" +
        indent +
        "}\n",
      )
    @grammar.CompiledExpr::DiagnoseIf(pred, msg) =>
      Ok(
        indent +
        "if " +
        emit_pred(pred, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "  ctx.error(" +
        string_lit(msg) +
        ")\n" +
        indent +
        "}\n",
      )
    @grammar.CompiledExpr::ExpectSkip(skip, skip_kind, expected, kind) =>
      Ok(
        indent +
        "ctx.expect_after_skip(" +
        emit_pred_closure(skip, token_ref) +
        ", " +
        kind_ref(skip_kind) +
        ", " +
        token_ref(expected) +
        ", " +
        kind_ref(kind) +
        ") |> ignore\n",
      )
    @grammar.CompiledExpr::ConsumeGated(skip, skip_kind, look) =>
      Ok(
        indent +
        "ctx.consume_while_emit_if(" +
        emit_pred_closure(skip, token_ref) +
        ", " +
        kind_ref(skip_kind) +
        ", " +
        emit_pred_closure(look, token_ref) +
        ") |> ignore\n",
      )
    @grammar.CompiledExpr::RequireSep(delims, stop, alt, msg_alt~, msg_else~) =>
      Ok(
        indent +
        "let had = ctx.consume_while_emit_mapped(" +
        emit_pair_array(delims, token_ref, kind_ref) +
        ") > 0\n" +
        indent +
        "if !had && !(" +
        emit_pred(stop, "ctx.peek()", token_ref) +
        ") {\n" +
        indent +
        "  if " +
        emit_pred(alt, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "    ctx.error(" +
        string_lit(msg_alt) +
        ")\n" +
        indent +
        "  } else {\n" +
        indent +
        "    ctx.error(" +
        string_lit(msg_else) +
        ")\n" +
        indent +
        "  }\n" +
        indent +
        "}\n",
      )
    @grammar.CompiledExpr::ErrorNodeUntil(error_kind, stop, msg) =>
      Ok(
        indent +
        "ctx.error(" +
        string_lit(msg) +
        ")\n" +
        indent +
        "ctx.start_node(" +
        kind_ref(error_kind) +
        ")\n" +
        indent +
        "while !ctx.at_eof() && !(" +
        emit_pred(stop, "ctx.peek()", token_ref) +
        ") {\n" +
        indent +
        "  ctx.bump_error()\n" +
        indent +
        "}\n" +
        indent +
        "ctx.finish_node()\n",
      )
    @grammar.CompiledExpr::WrapIfNext(kind, pred, body) => {
      let inner = match
        emit_compiled_expr(
          body,
          compiled~,
          token_ref~,
          kind_ref~,
          indent=indent + "  ",
        ) {
        Ok(s) => s
        Err(msg) => return Err(msg)
      }
      Ok(
        indent +
        "let mark = ctx.mark()\n" +
        indent +
        "if " +
        emit_pred(pred, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "  ctx.wrap_at(mark, " +
        kind_ref(kind) +
        ", fn() {\n" +
        inner +
        indent +
        "  })\n" +
        indent +
        "} else {\n" +
        inner +
        indent +
        "}\n",
      )
    }
    @grammar.CompiledExpr::RepeatTopLevel(
      slot,
      starts~,
      delim~,
      delim_kind~,
      between_msg~,
      after_msg~
    ) => {
      let item_call = indent +
        "  " +
        parse_rule_fn_name(compiled.names[slot]) +
        "(ctx)\n"
      let consume_delim = fn(ind : String) -> String {
        "ctx.consume_while_emit(\n" +
        ind +
        "  " +
        emit_pred_closure(delim, token_ref) +
        ",\n" +
        ind +
        "  " +
        kind_ref(delim_kind) +
        ",\n" +
        ind +
        ")\n"
      }
      Ok(
        indent +
        consume_delim(indent) +
        indent +
        "while !ctx.at_eof() && " +
        emit_pred(starts, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "  if ctx.try_reuse_repeat_group() {\n" +
        indent +
        "    " +
        consume_delim(indent + "  ") +
        indent +
        "    continue\n" +
        indent +
        "  }\n" +
        item_call +
        indent +
        "  let had = " +
        emit_pred(delim, "ctx.peek()", token_ref) +
        "\n" +
        indent +
        "  " +
        consume_delim(indent + "  ") +
        indent +
        "  if !had && !ctx.at_eof() {\n" +
        indent +
        "    if " +
        emit_pred(starts, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "      ctx.error(" +
        string_lit(between_msg) +
        ")\n" +
        indent +
        "    } else {\n" +
        indent +
        "      ctx.error(" +
        string_lit(after_msg) +
        ")\n" +
        indent +
        "    }\n" +
        indent +
        "  }\n" +
        indent +
        "}\n",
      )
    }
    @grammar.CompiledExpr::PrattApp(slot, kind, starts) =>
      Ok(
        indent +
        "if ctx.try_reuse_current_node(" +
        kind_ref(kind) +
        ") {\n" +
        indent +
        "} else {\n" +
        indent +
        "  let mark = ctx.mark()\n" +
        indent +
        "  " +
        parse_rule_fn_name(compiled.names[slot]) +
        "(ctx)\n" +
        indent +
        "  if " +
        emit_pred(starts, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "    ctx.wrap_at(mark, " +
        kind_ref(kind) +
        ", fn() {\n" +
        indent +
        "      while " +
        emit_pred(starts, "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "        " +
        parse_rule_fn_name(compiled.names[slot]) +
        "(ctx)\n" +
        indent +
        "      }\n" +
        indent +
        "    })\n" +
        indent +
        "  }\n" +
        indent +
        "}\n",
      )
    @grammar.CompiledExpr::PrattBinary(slot, kind, ops, skip~) => {
      let op_tokens = ops.map(fn(pair) { pair.0 })
      let op_match = "match t { " +
        ops.map(fn(pair) { token_ref(pair.0) }).join(" | ") +
        " => true; _ => false }"
      let skip_to_op = match skip {
        Some((sep, sep_kind)) =>
          "ctx.consume_while_emit_if(" +
          emit_pred_closure(sep, token_ref) +
          ", " +
          kind_ref(sep_kind) +
          ", fn(t) { " +
          op_match +
          " }) |> ignore"
        None => "()"
      }
      let pairs = emit_pair_array(ops, token_ref, kind_ref)
      let prefix_call = parse_rule_fn_name(compiled.names[slot]) + "(ctx)"
      Ok(
        indent +
        "let ops = " +
        pairs +
        "\n" +
        indent +
        "if ctx.try_reuse_current_node(" +
        kind_ref(kind) +
        ") {\n" +
        indent +
        "} else {\n" +
        indent +
        "  let mark = ctx.mark()\n" +
        indent +
        "  " +
        prefix_call +
        "\n" +
        indent +
        "  " +
        skip_to_op +
        "\n" +
        indent +
        "  if " +
        emit_pred(@grammar.Pred::OneOf(op_tokens), "ctx.peek()", token_ref) +
        " {\n" +
        indent +
        "    ctx.wrap_at(mark, " +
        kind_ref(kind) +
        ", fn() {\n" +
        indent +
        "      while true {\n" +
        indent +
        "        " +
        skip_to_op +
        "\n" +
        indent +
        "        match ops.iter().find_first(fn(pair) { pair.0 == ctx.peek() }) {\n" +
        indent +
        "          None => break\n" +
        indent +
        "          Some(pair) => {\n" +
        indent +
        "            ctx.emit_token(pair.1)\n" +
        indent +
        "            " +
        prefix_call +
        "\n" +
        indent +
        "          }\n" +
        indent +
        "        }\n" +
        indent +
        "      }\n" +
        indent +
        "    })\n" +
        indent +
        "  }\n" +
        indent +
        "}\n",
      )
    }
    @grammar.CompiledExpr::ManualNewlineAppExpr =>
      Err(
        "grammar emitter: ManualNewlineAppExpr is a lambda-specific residue and cannot be emitted",
      )
  }
}
