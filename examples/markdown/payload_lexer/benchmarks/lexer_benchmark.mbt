///|
fn repeated_payload_input(unit : String, count : Int) -> String {
  let builder = StringBuilder()
  for _ in 0..<count {
    builder.write_string(unit)
  }
  builder.to_string()
}

///|
const PAYLOAD_UNIT = "### heading ```lang\n"

///|
fn payload_lexer_input() -> String {
  repeated_payload_input(PAYLOAD_UNIT, 1024)
}

///|
fn payload_prefix_lexer() -> @core.PrefixLexer[@payload.Token] {
  @core.PrefixLexer::new(lex_step=@payload.step_lex)
}

///|
fn new_payload_buffer(source : String) -> @core.TokenBuffer[@payload.Token] {
  @core.TokenBuffer::new_from_steps(
    @core.SourceId::SourceId("payload-lexer-baseline"),
    source,
    payload_prefix_lexer(),
    eof_token=@payload.EOF,
    error_token=@payload.EOF,
  )
}

///|
test "payload benchmark input preserves repeated fence boundaries" {
  let steps = payload_prefix_lexer().lex_all(payload_lexer_input(), 0)
  let code_fence_count = steps.fold(init=0, (count, step) => {
    match step {
      @core.LexStep::Produced(info, next_offset=_) =>
        match info.token {
          @payload.Token::CodeFenceOpen(_, _) => count + 1
          _ => count
        }
      _ => count
    }
  })
  assert_eq(code_fence_count, 1024)
}

///|
test "payload generated lexer: full prefix lex" (b : @bench.T) {
  let source = payload_lexer_input()
  let lexer = payload_prefix_lexer()
  b.bench(() => {
    let steps = lexer.lex_all(source, 0)
    b.keep(steps)
  })
}

///|
test "payload generated lexer: TokenBuffer construction" (b : @bench.T) {
  let source = payload_lexer_input()
  b.bench(() => {
    let buffer = new_payload_buffer(source)
    b.keep(buffer.token_count())
  })
}

///|
test "payload generated lexer: TokenBuffer edit and restore" (b : @bench.T) {
  let source = payload_lexer_input()
  let midpoint = source.length() / 2
  let edited = source[:midpoint].to_owned() +
    "x" +
    source[midpoint + 1:].to_owned()
  let edit = @core.Edit::replace(midpoint, midpoint + 1, midpoint + 1)
  let buffer = new_payload_buffer(source)
  b.bench(() => {
    buffer.update(edit, edited) catch {
      _ => abort("payload edit failed")
    }
    b.keep(buffer.token_count())
    buffer.update(edit, source) catch {
      _ => abort("payload restore failed")
    }
  })
}
