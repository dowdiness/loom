///| Test incremental re-lex with mode convergence.
///  Uses the mock 2-mode language from mode_lexer_wbtest.mbt.

///|
/// Helper: create a TokenBuffer with mode-aware re-lex for the mock language.
fn create_mock_buffer(source : String) -> TokenBuffer[MockToken] {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let factory = erase_mode_lexer(
    lexer,
    MockToken::EOF,
    error_token=Error("error"),
    error_token_from_message=Some(msg => Error(msg)),
  )
  let source_id = SourceId("mode-relex-mock-source")
  TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory~,
    eof_token=MockToken::EOF,
  )
}

///|
fn create_mixed_buffer(source : String) -> TokenBuffer[MixedToken] {
  let lexer : ModeLexer[MixedToken, MixedMode] = {
    lex_step: mixed_lex_step,
    initial_mode: Normal,
  }
  let factory = erase_mode_lexer(
    lexer,
    MixedToken::EOF,
    error_token=OpaqueRaw("error"),
  )
  let source_id = SourceId("mode-relex-mixed-source")
  TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory~,
    eof_token=MixedToken::EOF,
  )
}

///|
test "mode relex: head edit propagates opaque to notation context" {
  let buffer = create_mixed_buffer(mixed_source())
  let edit = Edit::new(11, 7, 1)
  let new_source = "s(\"bd sd\") s(\"verse: 1\")"
  buffer.update(edit, new_source)
  inspect(buffer.get_token(9), content="HeadS")
  inspect(buffer.get_token(12), content="NotationWord(\"verse\")")
  inspect(buffer.get_token(13), content="NotationColon")
  inspect(buffer.get_token(14), content="NotationSpace")
  inspect(buffer.get_token(15), content="NotationWord(\"1\")")
  inspect(buffer.get_token(16), content="Quote")
  inspect(buffer.get_token(17), content="CloseParen")
  inspect(buffer.get_token(18), content="EOF")
  inspect(buffer.get_start(12), content="14")
  inspect(buffer.get_start(13), content="19")
  inspect(buffer.get_start(14), content="20")
  inspect(buffer.get_start(15), content="21")
  inspect(buffer.get_start(16), content="22")
  inspect(buffer.get_start(17), content="23")
  inspect(buffer.get_start(18), content="24")
}

///|
test "mode relex: same-cardinality edit converges before close paren" {
  let old_source = "section(\"verse\") s(\"tail\")"
  let new_source = "s(\"verse\") s(\"tail\")"
  let buffer = create_mixed_buffer(old_source)
  buffer.update(Edit::replace(0, 7, 1), new_source)
  inspect(buffer.get_token(3), content="NotationWord(\"verse\")")
  inspect(buffer.get_start(3), content="3")
  inspect(buffer.get_token(5), content="CloseParen")
}

///|
test "mode relex: edit inside normal region converges immediately" {
  let buffer = create_mock_buffer("hello\"world\"end")
  // Edit: change "hello" to "hi" (replace 5 chars with 2)
  let edit = Edit::new(0, 5, 2)
  buffer.update(edit, "hi\"world\"end")
  inspect(buffer.token_count(), content="6")
  inspect(buffer.get_token(0), content="Text(\"hi\")")
  inspect(buffer.get_token(2), content="StringContent(\"world\")")
}

///|
test "mode relex: construction owns initial result arrays" {
  let source_id = SourceId("mode-relex-owned-arrays-source")
  let source = "hello\"world\"end"
  let retained_tokens = [
    TokenInfo::new(Text(source), source.length()),
    TokenInfo::new(MockToken::EOF, 0),
  ]
  let retained_starts = [0, source.length()]
  let factory = ModeRelexFactory::new(new_session=_source_id => {
    ModeRelexState::new(
      tokenize=fn(_source) {
        LexResult::with_starts(
          retained_tokens,
          retained_starts,
          diagnostics=DiagnosticSet::empty(),
        ) catch {
          error =>
            abort(
              "mode lexer fixture adapter defect: " + @debug.to_string(error),
            )
        }
      },
      relex_from=(
        _source,
        _start_offset,
        _start_tok_idx,
        old_token_count,
        _old_starts,
        _edit_delta,
        _new_damage_end,
      ) => {
        ModeRelexResult::new(
          [],
          [],
          DiagnosticSet::empty(),
          converged_at_old_token=old_token_count,
        )
      },
    )
  })
  let buffer = TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory~,
    eof_token=MockToken::EOF,
  )
  retained_tokens[0] = TokenInfo::new(Text("mutated"), 7)
  retained_starts[0] = 7
  inspect(buffer.get_token(0), content="Text(\"hello\\\"world\\\"end\")")
  inspect(buffer.get_start(0), content="0")
}

///|
test "mode relex: retained old starts cannot mutate committed buffer" {
  let retained_old_starts : Ref[OldTokenStarts?] = Ref(None)
  let retained_result_tokens : Array[TokenInfo[MockToken]] = []
  let retained_result_starts : Array[Int] = []
  let factory = ModeRelexFactory::new(new_session=_source_id => {
    ModeRelexState::new(
      tokenize=fn(source) {
        lex_result_from_owned_or_abort(
          [
            TokenInfo::new(Text(source), source.length()),
            TokenInfo::new(EOF, 0),
          ],
          [0, source.length()],
          diagnostics=DiagnosticSet::empty(),
        )
      },
      relex_from=(
        source,
        _start_offset,
        _start_tok_idx,
        old_token_count,
        old_starts,
        _edit_delta,
        _new_damage_end,
      ) => {
        retained_old_starts.val = Some(old_starts)
        retained_result_tokens.push(
          TokenInfo::new(Text(source), source.length()),
        )
        retained_result_starts.push(0)
        ModeRelexResult::new(
          retained_result_tokens,
          retained_result_starts,
          DiagnosticSet::empty(),
          converged_at_old_token=old_token_count,
        )
      },
    )
  })
  let buffer = TokenBuffer::new_from_mode_relex(
    SourceId("mode-relex-retained-old-starts"),
    "a",
    factory~,
    eof_token=MockToken::EOF,
  )
  buffer.update(Edit::replace(0, 1, 1), "b")
  inspect(retained_old_starts.val.unwrap().start_at(0), content="0")
  retained_result_tokens[0] = TokenInfo::new(Text("mutated"), 7)
  retained_result_starts[0] = 99
  inspect(buffer.get_token(0), content="Text(\"b\")")
  inspect(buffer.get_start(0), content="0")
}

///|
test "OldTokenStarts owns public constructor input" {
  let starts = [0, 3]
  let old_starts = OldTokenStarts::new(starts)
  starts[0] = 99
  inspect(old_starts.length(), content="2")
  inspect(old_starts.start_at(0), content="0")
  inspect(old_starts.start_at(1), content="3")
}

///|
test "panic OldTokenStarts rejects an out-of-range index" {
  ignore(OldTokenStarts::new([0]).start_at(1))
}

///|
test "panic plain lex rejects invalid initial token stream" {
  ignore(
    TokenBuffer::new_from_lex(
      SourceId("plain-invalid-source"),
      "a",
      lex_fn=_ => {
        lex_result_from_owned_or_abort(
          [TokenInfo::new(Text("a"), 1), TokenInfo::new(EOF, 0)],
          [0, 2],
          diagnostics=DiagnosticSet::empty(),
        )
      },
      eof_token=MockToken::EOF,
    ),
  )
}

///|
test "mode relex: invalid partial and failed reset preserve committed state" {
  let session_creations : Ref[Int] = Ref(0)
  let partial_calls : Ref[Int] = Ref(0)
  let factory = ModeRelexFactory::new(new_session=_source_id => {
    session_creations.val = session_creations.val + 1
    let session_number = session_creations.val
    let session_mutated : Ref[Bool] = Ref(false)
    ModeRelexState::new(
      tokenize=fn(source) {
        if session_mutated.val {
          abort("mutated mode session was reused for full tokenization")
        }
        if session_number == 2 {
          lex_result_from_owned_or_abort(
            [
              TokenInfo::new(Text(source), source.length()),
              TokenInfo::new(EOF, 0),
            ],
            [0, source.length() + 1],
            diagnostics=DiagnosticSet::empty(),
          )
        } else {
          lex_result_from_owned_or_abort(
            [
              TokenInfo::new(Text(source), source.length()),
              TokenInfo::new(EOF, 0),
            ],
            [0, source.length()],
            diagnostics=DiagnosticSet::empty(),
          )
        }
      },
      relex_from=(
        _source,
        _start_offset,
        _start_tok_idx,
        _old_token_count,
        _old_starts,
        _edit_delta,
        _new_damage_end,
      ) => {
        partial_calls.val = partial_calls.val + 1
        session_mutated.val = true
        raise TokenStartCountMismatch(1, 0)
      },
    )
  })
  let source_id = SourceId("mode-relex-failed-reset")
  let buffer = TokenBuffer::new_from_mode_relex(
    source_id,
    "a",
    factory~,
    eof_token=MockToken::EOF,
  )
  let before_tokens = buffer.get_tokens()
  let before_starts = buffer.get_starts()
  let before_diagnostics = buffer.get_diagnostics().format()
  let before_source = buffer.get_source()
  let before_version = buffer.get_version()
  let failed = try {
    buffer.update(Edit::replace(0, 1, 1), "b")
    false
  } catch {
    LexError(_) => true
  }
  inspect(failed, content="true")
  inspect(buffer.get_tokens() == before_tokens, content="true")
  inspect(buffer.get_starts() == before_starts, content="true")
  inspect(
    buffer.get_diagnostics().format() == before_diagnostics,
    content="true",
  )
  inspect(buffer.get_source() == before_source, content="true")
  inspect(buffer.get_version() == before_version, content="true")
  inspect(session_creations.val, content="2")
  inspect(partial_calls.val, content="1")

  buffer.update(Edit::replace(0, 1, 1), "c")
  inspect(session_creations.val, content="3")
  inspect(partial_calls.val, content="1")
  let detached = factory.tokenize(source_id, "c")
  inspect(buffer.get_tokens() == detached.tokens(), content="true")
  inspect(buffer.get_starts() == detached.starts(), content="true")
  inspect(
    buffer.get_diagnostics().equal(detached.diagnostics()),
    content="true",
  )
}

///|
test "mode relex: context-invalid partial falls back through a fresh session" {
  let session_creations : Ref[Int] = Ref(0)
  let partial_calls : Ref[Int] = Ref(0)
  let factory = ModeRelexFactory::new(new_session=_source_id => {
    session_creations.val = session_creations.val + 1
    ModeRelexState::new(
      tokenize=fn(source) {
        lex_result_from_owned_or_abort(
          [
            TokenInfo::new(Text(source), source.length()),
            TokenInfo::new(EOF, 0),
          ],
          [0, source.length()],
          diagnostics=DiagnosticSet::empty(),
        )
      },
      relex_from=(
        source,
        _start_offset,
        _start_tok_idx,
        old_token_count,
        _old_starts,
        _edit_delta,
        _new_damage_end,
      ) => {
        partial_calls.val = partial_calls.val + 1
        ModeRelexResult::new(
          [TokenInfo::new(Text(source), source.length())],
          [0],
          DiagnosticSet::empty(),
          converged_at_old_token=old_token_count + 1,
        )
      },
    )
  })
  let source_id = SourceId("mode-relex-context-invalid")
  let buffer = TokenBuffer::new_from_mode_relex(
    source_id,
    "a",
    factory~,
    eof_token=MockToken::EOF,
  )
  buffer.update(Edit::replace(0, 1, 1), "b")
  inspect(session_creations.val, content="2")
  inspect(partial_calls.val, content="1")
  let detached = factory.tokenize(source_id, "b")
  inspect(buffer.get_tokens() == detached.tokens(), content="true")
  inspect(buffer.get_starts() == detached.starts(), content="true")
}

///|
test "mode relex: same-length cardinality change rebuilds storage" {
  let buffer = create_mock_buffer("hello world")
  buffer.update(Edit::replace(5, 1, 1), "hello\"world")
  inspect(buffer.token_count(), content="4")
  inspect(buffer.get_token(0), content="Text(\"hello\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\"world\")")
  inspect(buffer.get_token(3), content="EOF")
  debug_inspect(buffer.get_starts(), content="[0, 5, 6, 11]")
}

///|
test "mode relex: insert quote changes mode — propagates" {
  let buffer = create_mock_buffer("hello world")
  // tokens: Text("hello world"), EOF
  // Insert a quote at position 5: "hello\" world"
  let edit = Edit::new(5, 0, 1)
  buffer.update(edit, "hello\" world")
  // Now: Text("hello"), Quote, StringContent(" world"), EOF
  inspect(buffer.get_token(0), content="Text(\"hello\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\" world\")")
}

///|
test "mode relex: delete quote reverts mode" {
  let buffer = create_mock_buffer("hello\"world\"end")
  // Delete first quote (at position 5, length 1)
  let edit = Edit::new(5, 1, 0)
  buffer.update(edit, "helloworld\"end")
  // Now: Text("helloworld"), Quote, StringContent("end"), EOF
  inspect(buffer.get_token(0), content="Text(\"helloworld\")")
  inspect(buffer.get_token(1), content="Quote")
  inspect(buffer.get_token(2), content="StringContent(\"end\")")
}

///|
test "mode relex: sessions retain independent mode snapshots" {
  let lexer : ModeLexer[MockToken, MockMode] = {
    lex_step: mock_lex_step,
    initial_mode: Normal,
  }
  let factory = erase_mode_lexer(
    lexer,
    MockToken::EOF,
    error_token=Error("error"),
  )
  let source = "hello\"world\"end"
  let source_id = SourceId("mode-relex-session-source")
  let first = TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory~,
    eof_token=MockToken::EOF,
  )
  let second = TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory~,
    eof_token=MockToken::EOF,
  )
  let first_source = "helloworld\"end"
  let second_source = "hello\"earth\"end"
  first.update(Edit::delete(5, 6), first_source)
  second.update(Edit::replace(6, 11, 11), second_source)
  let first_full = factory.tokenize(source_id, first_source)
  let second_full = factory.tokenize(source_id, second_source)
  inspect(first.get_tokens() == first_full.tokens(), content="true")
  inspect(first.get_starts() == first_full.starts(), content="true")
  inspect(second.get_tokens() == second_full.tokens(), content="true")
  inspect(second.get_starts() == second_full.starts(), content="true")
}

///|
test "panic mode relex rejects invalid initial token stream" {
  let factory = ModeRelexFactory::new(new_session=_source_id => {
    ModeRelexState::new(
      tokenize=fn(_source) {
        lex_result_from_owned_or_abort(
          [TokenInfo::new(Text("a"), 2), TokenInfo::new(EOF, 0)],
          [0, 1],
          diagnostics=DiagnosticSet::empty(),
        )
      },
      relex_from=(
        _source,
        _start_offset,
        _start_tok_idx,
        old_token_count,
        _old_starts,
        _edit_delta,
        _new_damage_end,
      ) => {
        ModeRelexResult::new(
          [],
          [],
          DiagnosticSet::empty(),
          converged_at_old_token=old_token_count,
        )
      },
    )
  })
  ignore(
    TokenBuffer::new_from_mode_relex(
      SourceId("mode-relex-invalid-source"),
      "a",
      factory~,
      eof_token=MockToken::EOF,
    ),
  )
}

///|
/// Verify that TokenBuffer without mode_relex behaves identically.
test "backward compat: TokenBuffer::new still works without mode_relex" {
  let tokenize_fn : (String) -> Array[TokenInfo[MockToken]] raise LexError = s => {
    let lexer : ModeLexer[MockToken, MockMode] = {
      lex_step: mock_lex_step,
      initial_mode: Normal,
    }
    let (tokens, _modes) = tokenize_with_modes(lexer, s, MockToken::EOF)
    tokens
  }
  let buffer = TokenBuffer::new(
    SourceId("mode-relex-backward-source"),
    "hello",
    tokenize_fn~,
    eof_token=MockToken::EOF,
  )
  inspect(buffer.token_count(), content="2")
  inspect(buffer.get_token(0), content="Text(\"hello\")")
}
