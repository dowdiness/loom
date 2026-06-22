// Tests for the soft-newline / recovery vocabulary added in Task 6. TestToken /
// TestKind / test_spec are defined in interpreter_test.mbt (shared blackbox
// compilation unit). Each test drives the node through @core.parse_with and
// asserts the diagnostic count it should (or should not) produce.

///|
/// One width-1 token (width-0 for EOF), so a source string of N non-EOF tokens
/// has length N and token offsets stay inside it.
fn tok(t : TestToken) -> @core.TokenInfo[TestToken] {
  @core.TokenInfo::new(t, if t == TestToken::EOF { 0 } else { 1 })
}

///|
/// Parse `tokens` against a one-rule grammar and return the diagnostics. `src`
/// must be as long as the number of non-EOF tokens.
fn vocab_diags(
  rules : Map[RuleName, Expr[TestToken, TestKind]],
  root : RuleName,
  tokens : Array[@core.TokenInfo[TestToken]],
  src : String,
) -> @core.DiagnosticSet raise GrammarCompileError {
  let parse_root = interpret(GrammarIr::GrammarIr(rules, root~))
  let spec = test_spec(parse_root)
  let (_, diags) = @core.parse_with(src, spec, _s => tokens, parse_root)
  diags
}

///|
test "Fail emits a diagnostic and an error placeholder" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Fail("boom"),
  }
  let diags = vocab_diags(rules, "source", [tok(TestToken::EOF)], "")
  inspect(diags.length(), content="1")
}

///|
test "EmitOr emits silently when the token is present" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::EmitOr(TestToken::Int, TestKind::IntToken, "missing int"),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(diags.length(), content="0")
}

///|
test "EmitOr reports the token when absent" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::EmitOr(TestToken::Int, TestKind::IntToken, "missing int"),
  }
  let diags = vocab_diags(rules, "source", [tok(TestToken::EOF)], "")
  inspect(diags.length(), content="1")
}

///|
test "DiagnoseIf fires only when the predicate matches the peek" {
  let matching : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Seq([
      Expr::DiagnoseIf(Pred::IsToken(TestToken::Int), "found int"),
      Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let diags = vocab_diags(
    matching,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(diags.length(), content="1")
  let nonmatching : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Seq([
      Expr::DiagnoseIf(Pred::IsToken(TestToken::Word), "found word"),
      Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let diags2 = vocab_diags(
    nonmatching,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(diags2.length(), content="0")
}

///|
test "ExpectSkip consumes the soft separator then expects" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::ExpectSkip(
      Pred::IsToken(TestToken::Skip),
      TestKind::SkipKind,
      TestToken::Expected,
      TestKind::ExpectedKind,
    ),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Skip), tok(TestToken::Expected), tok(TestToken::EOF)],
    "se",
  )
  inspect(diags.length(), content="0")
}

///|
test "ConsumeGated consumes the run when the lookahead holds" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Seq([
      Expr::ConsumeGated(
        Pred::IsToken(TestToken::Skip),
        TestKind::SkipKind,
        Pred::IsToken(TestToken::Int),
      ),
      Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Skip), tok(TestToken::Int), tok(TestToken::EOF)],
    "si",
  )
  inspect(diags.length(), content="0")
}

///|
test "RequireSep is silent with a separator, diagnoses without one" {
  let rule : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::RequireSep(
      Pred::IsToken(TestToken::Skip),
      TestKind::SkipKind,
      Pred::IsToken(TestToken::EOF),
      Pred::Any,
      msg_alt="alt",
      msg_else="else",
    ),
  }
  let with_sep = vocab_diags(
    rule,
    "source",
    [tok(TestToken::Skip), tok(TestToken::EOF)],
    "s",
  )
  inspect(with_sep.length(), content="0")
  let missing : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Seq([
      Expr::RequireSep(
        Pred::IsToken(TestToken::Skip),
        TestKind::SkipKind,
        Pred::IsToken(TestToken::EOF),
        Pred::Any,
        msg_alt="alt",
        msg_else="else",
      ),
      Expr::Emit(TestToken::Int, TestKind::IntToken),
    ]),
  }
  let without_sep = vocab_diags(
    missing,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(without_sep.length(), content="1")
}

///|
test "ErrorNodeUntil opens an error node over trailing garbage, EOF-guarded" {
  let guarded : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::Choice([
      Alt::{ starts: Pred::IsToken(TestToken::EOF), body: Expr::Empty },
      Alt::{
        starts: Pred::Any,
        body: Expr::ErrorNodeUntil(
          TestKind::Error,
          Pred::IsToken(TestToken::EOF),
          "unexpected trailing tokens",
        ),
      },
    ]),
  }
  let garbage = vocab_diags(
    guarded,
    "source",
    [tok(TestToken::Int), tok(TestToken::EOF)],
    "x",
  )
  inspect(garbage.length(), content="1")
  let clean = vocab_diags(guarded, "source", [tok(TestToken::EOF)], "")
  inspect(clean.length(), content="0")
}

///|
test "RepeatTopLevel parses every delimited item without diagnostics" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::RepeatTopLevel(
      "word",
      starts=Pred::IsToken(TestToken::Word),
      delim=Pred::IsToken(TestToken::Skip),
      delim_kind=TestKind::SkipKind,
      between_msg="expected separator between items",
      after_msg="expected separator after item",
    ),
    "word": Expr::Node(
      TestKind::WordNode,
      Expr::Emit(TestToken::Word, TestKind::WordToken),
    ),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [
      tok(TestToken::Word),
      tok(TestToken::Skip),
      tok(TestToken::Word),
      tok(TestToken::EOF),
    ],
    "wsw",
  )
  inspect(diags.length(), content="0")
}

///|
test "RepeatTopLevel diagnoses a missing delimiter between items" {
  let rules : Map[RuleName, Expr[TestToken, TestKind]] = {
    "source": Expr::RepeatTopLevel(
      "word",
      starts=Pred::IsToken(TestToken::Word),
      delim=Pred::IsToken(TestToken::Skip),
      delim_kind=TestKind::SkipKind,
      between_msg="expected separator between items",
      after_msg="expected separator after item",
    ),
    "word": Expr::Node(
      TestKind::WordNode,
      Expr::Emit(TestToken::Word, TestKind::WordToken),
    ),
  }
  let diags = vocab_diags(
    rules,
    "source",
    [tok(TestToken::Word), tok(TestToken::Word), tok(TestToken::EOF)],
    "ww",
  )
  inspect(diags.length(), content="1")
}
