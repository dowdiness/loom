// Integration test fixtures: minimal two-token language (integers and '+').
// Kept in _wbtest.mbt so test types don't appear in pkg.generated.mbti.

///|
// Test language: integers and '+' only (with whitespace)
enum TestTok {
  Num(Int)
  Plus
  Ws
  Comment
  TokEof
} derive(Eq, Debug)

///|
impl Show for TestTok with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @seam.IsTrivia for TestTok with fn is_trivia(self) {
  self == Ws || self == Comment
}

///|
impl @seam.IsEof for TestTok with fn is_eof(self) {
  self == TokEof
}

///|
impl @seam.ToRawKind for TestTok with fn to_raw(self) {
  let n = match self {
    Num(_) => 0
    Plus => 1
    Comment => 8
    Ws => 4
    TokEof => 7
  }
  @seam.RawKind(n)
}

///|
enum TestKind {
  KNum
  KPlus
  KExpr
  KRoot
  KWs
  KComment
  KErr
  KIncomplete
} derive(Debug)

///|
fn test_kind_raw(k : TestKind) -> @seam.RawKind {
  let n = match k {
    KNum => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs => 4
    KComment => 8
    KErr => 5
    KIncomplete => 6
  }
  @seam.RawKind(n)
}

///|
impl @seam.ToRawKind for TestKind with fn to_raw(self) {
  test_kind_raw(self)
}

///|
fn test_tokenize(src : String) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  while i < src.length() {
    let code = src.code_unit_at(i).to_int()
    if code == 32 {
      // space
      let start = i
      while i < src.length() && src.code_unit_at(i).to_int() == 32 {
        i = i + 1
      }
      result.push({ token: TestTok::Ws, len: i - start })
    } else if code >= 48 && code <= 57 {
      // digit
      let start = i
      let mut n = code - 48
      i = i + 1
      while i < src.length() {
        let d = src.code_unit_at(i).to_int()
        if d >= 48 && d <= 57 {
          n = n * 10 + d - 48
          i = i + 1
        } else {
          break
        }
      }
      result.push({ token: TestTok::Num(n), len: i - start })
    } else if code == 43 {
      // '+'
      result.push({ token: TestTok::Plus, len: 1 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  result
}

///|
/// Tokenize and compute starts in one call.
fn test_tokenize_with_starts(
  src : String,
) -> (Array[TokenInfo[TestTok]], Array[Int]) {
  let toks = test_tokenize(src)
  let starts = build_starts(toks)
  (toks, starts)
}

///|
let test_spec : LanguageSpec[TestTok, TestKind] = {
  whitespace_kind: KWs,
  error_kind: KErr,
  incomplete_kind: KIncomplete,
  root_kind: KRoot,
  eof_token: TestTok::TokEof,
  parse_root: fn(_) { () },
  reuse_size_threshold: 64,
  trivia_kinds_spec: [KWs],
}

///|
fn test_grammar(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  let mark = ctx.mark()
  match ctx.peek() {
    TestTok::Num(_) => ctx.emit_token(KNum)
    _ => {
      ctx.error("expected number")
      return
    }
  }
  if ctx.at(TestTok::Plus) {
    ctx.start_at(mark, KExpr)
    while ctx.at(TestTok::Plus) {
      ctx.emit_token(KPlus)
      match ctx.peek() {
        TestTok::Num(_) => ctx.emit_token(KNum)
        _ => {
          ctx.error("expected number after +")
          // Consume the unexpected token to prevent the loop from spinning
          // on repeated non-Num tokens. Guard against EOF to avoid emitting
          // empty error tokens past end of input.
          if !ctx.at_eof() {
            ctx.bump_error()
          }
        }
      }
    }
    ctx.finish_node()
  }
}
