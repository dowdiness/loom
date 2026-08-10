///|
fn repeated_lexer_input(unit : String, count : Int) -> String {
  let builder = StringBuilder()
  for _ in 0..<count {
    builder.write_string(unit)
  }
  builder.to_string()
}

///|
const REALISTIC_UNIT = "- -> let foo 123 bar _name 456\n"

///|
fn realistic_lexer_input() -> String {
  repeated_lexer_input(REALISTIC_UNIT, 1024)
}

///|
const SCALING32_UNIT = "a1b1c1d1e1f1g1h1i1j1k1l1m1n1o1p1q1r1s1t1u1v1w1x1y1z1A1B1C1D1E1F1"

///|
fn scaling32_lexer_input() -> String {
  repeated_lexer_input(SCALING32_UNIT, 256)
}

///|
test "generated lexer: 32 candidate scaling" (b : @bench.T) {
  let source = scaling32_lexer_input()
  let lexer = @core.PrefixLexer::new(lex_step=@scaling32.step_lex)
  b.bench(() => {
    let steps = lexer.lex_all(source, 0)
    b.keep(steps)
  })
}

///|
fn fixture_prefix_lexer() -> @core.PrefixLexer[Token] {
  @core.PrefixLexer::new(lex_step=step_lex)
}

///|
fn new_fixture_buffer(source : String) -> @core.TokenBuffer[Token] {
  @core.TokenBuffer::new_from_steps(
    @core.SourceId::SourceId("pattern-lexer-baseline"),
    source,
    fixture_prefix_lexer(),
    eof_token=EOF,
    error_token=Error(""),
  )
}

///|
test "generated lexer: full prefix lex" (b : @bench.T) {
  let source = realistic_lexer_input()
  let lexer = fixture_prefix_lexer()
  b.bench(() => {
    let steps = lexer.lex_all(source, 0)
    b.keep(steps)
  })
}

///|
test "generated lexer: TokenBuffer construction" (b : @bench.T) {
  let source = realistic_lexer_input()
  b.bench(() => {
    let buffer = new_fixture_buffer(source)
    b.keep(buffer.token_count())
  })
}

///|
test "generated lexer: TokenBuffer edit and restore" (b : @bench.T) {
  let source = realistic_lexer_input()
  let midpoint = source.length() / 2
  let edited = source[:midpoint].to_owned() +
    "X" +
    source[midpoint + 1:].to_owned()
  let edit = @core.Edit::replace(midpoint, midpoint + 1, midpoint + 1)
  let buffer = new_fixture_buffer(source)
  b.bench(() => {
    buffer.update(edit, edited) catch {
      _ => abort("edit failed")
    }
    b.keep(buffer.token_count())
    buffer.update(edit, source) catch {
      _ => abort("restore failed")
    }
  })
}
