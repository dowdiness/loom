///|
test "emit_grammar emits parse_root and one node rule" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Node(
      "Root",
      @grammar.Expr::Emit("Int", "IntToken"),
    ),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("pub fn parse_root"), content="true")
  inspect(source.contains("fn parse_source"), content="true")
  inspect(source.contains("ctx.node(@syntax.Root"), content="true")
  inspect(source.contains("ctx.emit_token(@syntax.IntToken)"), content="true")
}

///|
test "emit_grammar orders root first and lowers Ref to direct call" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Ref("expr"),
    "z_tail": @grammar.Expr::Emit("Tail", "TailToken"),
    "expr": @grammar.Expr::Emit("Int", "IntToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("parse_expr(ctx)"), content="true")
  let source_pos = match source.find("fn parse_source") {
    Some(i) => i
    None => fail("missing parse_source")
  }
  let expr_pos = match source.find("fn parse_expr") {
    Some(i) => i
    None => fail("missing parse_expr")
  }
  let z_pos = match source.find("fn parse_z_tail") {
    Some(i) => i
    None => fail("missing parse_z_tail")
  }
  inspect(source_pos < expr_pos, content="true")
  inspect(expr_pos < z_pos, content="true")
}

///|
test "emit_grammar rejects unresolved Ref before emitting source" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Ref("missing"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  match rendered {
    Err("grammar emitter: missing ref \"missing\"") => ()
    _ => fail("expected missing-ref error")
  }
}

///|
test "emit_grammar lowers Choice predicates in order" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::IsToken("Int"),
        body: @grammar.Expr::Emit("Int", "IntToken"),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::Any,
        body: @grammar.Expr::Emit("Word", "WordToken"),
      },
    ]),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("let token = ctx.peek()"), content="true")
  inspect(source.contains("if token == @token.Int"), content="true")
  inspect(source.contains("} else if true {"), content="true")
  inspect(source.contains("ctx.emit_token(@syntax.WordToken)"), content="true")
}

///|
test "emit_grammar lowers OneOf and Not predicates" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::OneOf(["Int", "Word"]),
        body: @grammar.Expr::Emit("Int", "IntToken"),
      },
      @grammar.Alt::{
        starts: @grammar.Pred::Not(@grammar.Pred::IsToken("EOF")),
        body: @grammar.Expr::Emit("Word", "WordToken"),
      },
    ]),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("@token.Int | @token.Word => true"), content="true")
  inspect(source.contains("!(token == @token.EOF)"), content="true")
}

///|
test "emit_grammar lowers Seq Expect RepeatWhile and Empty" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::Empty,
      @grammar.Expr::Expect("Expected", "ExpectedToken"),
      @grammar.Expr::RepeatWhile(
        @grammar.Pred::IsToken("Int"),
        @grammar.Expr::Emit("Int", "IntToken"),
      ),
    ]),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(
    source.contains(
      "ctx.expect(@token.Expected, @syntax.ExpectedToken) |> ignore",
    ),
    content="true",
  )
  inspect(
    source.contains("while !ctx.at_eof() && ctx.peek() == @token.Int {"),
    content="true",
  )
  inspect(source.contains("ctx.emit_token(@syntax.IntToken)"), content="true")
}

///|
test "emit_grammar lowers diagnostics and gated consume arms" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::EmitError("warn"),
      @grammar.Expr::Fail("missing"),
      @grammar.Expr::EmitOr("Int", "IntToken", "expected int"),
      @grammar.Expr::DiagnoseIf(@grammar.Pred::IsToken("EOF"), "at eof"),
      @grammar.Expr::ExpectSkip(
        @grammar.Pred::IsToken("Newline"),
        "NewlineToken",
        "Expected",
        "ExpectedToken",
      ),
      @grammar.Expr::ConsumeGated(
        @grammar.Pred::IsToken("Newline"),
        "NewlineToken",
        @grammar.Pred::IsToken("Int"),
      ),
    ]),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("ctx.error(\"warn\")"), content="true")
  inspect(source.contains("ctx.error(\"missing\")"), content="true")
  inspect(source.contains("ctx.emit_error_placeholder()"), content="true")
  inspect(source.contains("if ctx.at(@token.Int) {"), content="true")
  inspect(source.contains("ctx.error(\"expected int\")"), content="true")
  inspect(source.contains("if ctx.peek() == @token.EOF {"), content="true")
  inspect(source.contains("ctx.expect_after_skip("), content="true")
  inspect(source.contains("ctx.consume_while_emit_if("), content="true")
}

///|
test "emit_grammar lowers error node wrap and separator arms" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::ErrorUntil(@grammar.Pred::IsToken("EOF"), "skip"),
      @grammar.Expr::RequireSep(
        [("Newline", "NewlineToken"), ("Semi", "SemiToken")],
        @grammar.Pred::IsToken("RBrace"),
        @grammar.Pred::IsToken("Let"),
        msg_alt="between",
        msg_else="after",
      ),
      @grammar.Expr::ErrorNodeUntil(
        "ErrorNode",
        @grammar.Pred::IsToken("EOF"),
        "garbage",
      ),
      @grammar.Expr::WrapIfNext(
        "ParamList",
        @grammar.Pred::IsToken("LParen"),
        @grammar.Expr::Emit("LParen", "LParenToken"),
      ),
    ]),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(
    source.contains("ctx.skip_until(fn(t) { t == @token.EOF })"),
    content="true",
  )
  inspect(source.contains("ctx.consume_while_emit_mapped(["), content="true")
  inspect(
    source.contains("(@token.Newline, @syntax.NewlineToken)"),
    content="true",
  )
  inspect(source.contains("ctx.start_node(@syntax.ErrorNode)"), content="true")
  inspect(source.contains("ctx.bump_error()"), content="true")
  inspect(source.contains("let mark = ctx.mark()"), content="true")
  inspect(
    source.contains("ctx.wrap_at(mark, @syntax.ParamList"),
    content="true",
  )
}

///|
test "emit_grammar escapes diagnostic string literals" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::EmitError("line\nquote\"tab\tcr\rslash\\"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(
    source.contains("ctx.error(\"line\\nquote\\\"tab\\tcr\\rslash\\\\\")"),
    content="true",
  )
}

///|
test "emit_grammar rejects ManualNewlineAppExpr with explicit residue error" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::ManualNewlineAppExpr,
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  match rendered {
    Err(
      "grammar emitter: ManualNewlineAppExpr is a lambda-specific residue and cannot be emitted"
    ) => ()
    _ => fail("expected explicit ManualNewlineAppExpr error")
  }
}

///|
test "emit_grammar lowers Native to a literal call, no parse_ prefix, no stub" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Node(
      "Root",
      @grammar.Expr::Native("parse_element_with_stack"),
    ),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
    native_names=Set::Set(["parse_element_with_stack"]),
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("  parse_element_with_stack(ctx)\n"), content="true")
  inspect(source.contains("fn parse_parse_element_with_stack"), content="false")
  inspect(
    source.contains(
      "consumers must hand-write `fn parse_element_with_stack(ctx : ",
    ),
    content="true",
  )
}

///|
test "emit_grammar rejects Native with an unregistered name as MissingNative" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Native("missing_native"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  match rendered {
    Err("grammar emitter: missing native \"missing_native\"") => ()
    _ => fail("expected missing-native error")
  }
}

///|
test "emit_grammar rejects a name that is both a rule and a native as AmbiguousRule" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Emit("Int", "IntToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
    native_names=Set::Set(["source"]),
  )
  match rendered {
    Err("grammar emitter: \"source\" is both a grammar rule and a native") => ()
    _ => fail("expected ambiguous-rule error")
  }
}

///|
/// `AmbiguousRule` only catches a name that is literally both a rule and a
/// native. It can't see the `parse_` prefix the rule-stub generator adds, so
/// a native named exactly `parse_<other rule>` would otherwise silently
/// collide with that rule's generated stub in the emitted file.
test "emit_grammar rejects a native name that collides with a generated rule stub" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Node("Root", @grammar.Expr::Ref("inner")),
    "inner": @grammar.Expr::Emit("Int", "IntToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
    native_names=Set::Set(["parse_inner"]),
  )
  match rendered {
    Err(
      "grammar emitter: native \"parse_inner\" collides with the generated stub for rule \"inner\""
    ) => ()
    _ => fail("expected stub-collision error")
  }
}

///|
test "emit_grammar output contains simple parity fixture markers" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Node(
      "Root",
      @grammar.Expr::Emit("Int", "IntToken"),
    ),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="ParityToken",
    syntax_type="ParityKind",
    core_qual="@core",
    token_ref=fn(t) { "ParityToken::" + t },
    kind_ref=fn(k) { "ParityKind::" + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  let fixture = @fs.read_file_to_string(
    "fixtures/grammar_parity/simple_parser.g.mbt",
  ) catch {
    _ =>
      @fs.read_file_to_string(
        "loomgen/fixtures/grammar_parity/simple_parser.g.mbt",
      ) catch {
        _ => fail("could not read generated parser fixture")
      }
  }
  inspect(source.contains("pub fn parse_root"), content="true")
  inspect(source.contains("fn parse_source"), content="true")
  inspect(fixture.contains("pub fn parse_root"), content="true")
  inspect(source.contains("ParityToken"), content="true")
  inspect(fixture.contains("ParityToken"), content="true")
}

///|
test "emit_grammar output contains repeat parity fixture markers" {
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
  let rendered = emit_grammar(
    ir,
    token_type="ReuseToken",
    syntax_type="ReuseKind",
    core_qual="@core",
    token_ref=fn(t) { "ReuseToken::" + t },
    kind_ref=fn(k) { "ReuseKind::" + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  let fixture = @fs.read_file_to_string(
    "fixtures/grammar_parity_reuse/repeat_parser.g.mbt",
  ) catch {
    _ =>
      @fs.read_file_to_string(
        "loomgen/fixtures/grammar_parity_reuse/repeat_parser.g.mbt",
      ) catch {
        _ => fail("could not read generated repeat parser fixture")
      }
  }
  inspect(source.contains("pub fn parse_root"), content="true")
  inspect(fixture.contains("pub fn parse_root"), content="true")
  inspect(source.contains("fn parse_source"), content="true")
  inspect(fixture.contains("fn parse_source"), content="true")
  inspect(source.contains("fn parse_item"), content="true")
  inspect(fixture.contains("fn parse_item"), content="true")
}

///|
/// `emit_grammar`'s real output for a `Native`-containing grammar must
/// actually contain the shape `grammar_parity_native/native_parser.g.mbt`
/// hand-writes against, so the checked-in fixture can't silently drift from
/// what the emitter produces (issue #541 correction 5).
test "emit_grammar output contains native parity fixture markers" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Node(
      "Root",
      @grammar.Expr::Native("delegate_to_inner"),
    ),
    "inner": @grammar.Expr::Emit("Int", "IntToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="NativeParityToken",
    syntax_type="NativeParityKind",
    core_qual="@core",
    token_ref=fn(t) { "NativeParityToken::" + t },
    kind_ref=fn(k) { "NativeParityKind::" + k },
    native_names=Set::Set(["delegate_to_inner"]),
  )
  guard rendered is Ok(source) else {
    fail("expected native grammar emission to succeed")
  }
  let fixture = @fs.read_file_to_string(
    "loomgen/fixtures/grammar_parity_native/native_parser.g.mbt",
  ) catch {
    _ => fail("could not read generated native parser fixture")
  }
  inspect(source.contains("  delegate_to_inner(ctx)\n"), content="true")
  inspect(fixture.contains("delegate_to_inner(ctx)"), content="true")
  inspect(source.contains("fn parse_delegate_to_inner"), content="false")
  inspect(fixture.contains("fn parse_delegate_to_inner"), content="false")
  inspect(
    source.contains(
      "consumers must hand-write `fn delegate_to_inner(ctx : @core.ParserContext[NativeParityToken, NativeParityKind]) -> Unit`",
    ),
    content="true",
  )
  inspect(
    fixture.contains(
      "consumers must hand-write `fn delegate_to_inner(ctx : @core.ParserContext[NativeParityToken, NativeParityKind]) -> Unit`",
    ),
    content="true",
  )
}

///|
test "emit_grammar lowers RepeatTopLevel reuse loop" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::RepeatTopLevel(
      "item",
      starts=@grammar.Pred::IsToken("Let"),
      delim=@grammar.Pred::IsToken("Newline"),
      delim_kind="NewlineToken",
      between_msg="between",
      after_msg="after",
    ),
    "item": @grammar.Expr::Emit("Let", "LetToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(source.contains("ctx.consume_while_emit(\n"), content="true")
  inspect(
    source.contains("while !ctx.at_eof() && ctx.peek() == @token.Let {"),
    content="true",
  )
  inspect(source.contains("if ctx.try_reuse_repeat_group() {"), content="true")
  inspect(source.contains("parse_item(ctx)"), content="true")
  inspect(source.contains("ctx.error(\"between\")"), content="true")
  inspect(source.contains("ctx.error(\"after\")"), content="true")
}

///|
test "emit_grammar lowers PrattApp and PrattBinary reuse paths" {
  let rules : Map[String, @grammar.Expr[String, String]] = {
    "source": @grammar.Expr::Seq([
      @grammar.Expr::PrattApp("atom", "AppExpr", @grammar.Pred::IsToken("Int")),
      @grammar.Expr::PrattBinary(
        "atom",
        "BinaryExpr",
        [("Plus", "PlusToken"), ("Minus", "MinusToken")],
        skip=Some((@grammar.Pred::IsToken("Newline"), "NewlineToken")),
      ),
    ]),
    "atom": @grammar.Expr::Emit("Int", "IntToken"),
  }
  let ir = @grammar.GrammarIr::GrammarIr(rules, root="source")
  let rendered = emit_grammar(
    ir,
    token_type="Token",
    syntax_type="SyntaxKind",
    core_qual="@core",
    token_ref=fn(t) { "@token." + t },
    kind_ref=fn(k) { "@syntax." + k },
  )
  guard rendered is Ok(source) else {
    fail("expected grammar emission to succeed")
  }
  inspect(
    source.contains("ctx.try_reuse_current_node(@syntax.AppExpr)"),
    content="true",
  )
  inspect(
    source.contains("ctx.try_reuse_current_node(@syntax.BinaryExpr)"),
    content="true",
  )
  inspect(source.contains("ctx.wrap_at(mark, @syntax.AppExpr"), content="true")
  inspect(
    source.contains("ctx.wrap_at(mark, @syntax.BinaryExpr"),
    content="true",
  )
  inspect(
    source.contains("ctx.consume_while_emit_if(fn(t) { t == @token.Newline }"),
    content="true",
  )
  inspect(source.contains("@token.Plus | @token.Minus => true"), content="true")
  inspect(source.contains("ctx.emit_token(pair.1)"), content="true")
}
