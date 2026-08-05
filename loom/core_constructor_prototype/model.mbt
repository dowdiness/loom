// PROTOTYPE — do not ship.
//
// Question: can Loom's target interface make raw collection validation
// recoverable, give a mode-aware TokenBuffer one factory authority, discard a
// session that mutates before rejecting a partial result, atomically retain or
// replace committed state, and bypass partial re-lex while ResetRequired?
//
// Run the TUI with:
//   moon run loom/core_constructor_prototype --target native

// This file is the portable model. It performs no terminal I/O.

///|
struct TokenInfo[T] {
  token : T
  len : Int
}

///|
suberror LexResultError {
  TokenStartCountMismatch(Int, Int)
  NegativeTokenLength(Int, Int)
  NegativeStart(Int, Int)
  DecreasingStart(Int, Int, Int)
  OverlappingToken(Int, Int, Int)
  NegativeConvergence(Int)
} derive(Debug)

///|
suberror LexError {
  LexError(String)
} derive(Debug)

///|
struct LexResult[T] {
  tokens : Array[TokenInfo[T]]
  starts : Array[Int]
  diagnostics : Array[String]
}

///|
fn[T] LexResult::with_starts(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics~ : Array[String],
) -> LexResult[T] raise LexResultError {
  let tokens = tokens.copy()
  let starts = starts.copy()
  let diagnostics = diagnostics.copy()
  guard tokens.length() == starts.length() else {
    raise TokenStartCountMismatch(tokens.length(), starts.length())
  }
  for i = 0; i < tokens.length(); i = i + 1 {
    guard tokens[i].len >= 0 else {
      raise NegativeTokenLength(i, tokens[i].len)
    }
    guard starts[i] >= 0 else { raise NegativeStart(i, starts[i]) }
    if i > 0 {
      guard starts[i] >= starts[i - 1] else {
        raise DecreasingStart(i, starts[i - 1], starts[i])
      }
      let previous_end = starts[i - 1] + tokens[i - 1].len
      guard starts[i] >= previous_end else {
        raise OverlappingToken(i, previous_end, starts[i])
      }
    }
  }
  { tokens, starts, diagnostics }
}

///|
struct ModeRelexResult[T] {
  full_replacement : LexResult[T]
  converged_at_old_token : Int
}

///|
fn[T] ModeRelexResult::new(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics : Array[String],
  converged_at_old_token~ : Int,
) -> ModeRelexResult[T] raise LexResultError {
  guard converged_at_old_token >= 0 else {
    raise NegativeConvergence(converged_at_old_token)
  }
  {
    full_replacement: LexResult::with_starts(tokens, starts, diagnostics~),
    converged_at_old_token,
  }
}

///|
struct ModeRelexState[T] {
  id : Int
  source_id : String
  tokenize : (String) -> LexResult[T]
  relex_from : (String) -> ModeRelexResult[T] raise LexResultError
  poisoned : () -> Bool
}

///|
struct ModeRelexFactory[T] {
  new_session_impl : (String) -> ModeRelexState[T]
}

///|
fn[T] ModeRelexFactory::new(
  new_session~ : (String) -> ModeRelexState[T],
) -> ModeRelexFactory[T] {
  { new_session_impl: new_session }
}

///|
fn[T] ModeRelexFactory::new_session(
  self : ModeRelexFactory[T],
  source_id : String,
) -> ModeRelexState[T] {
  (self.new_session_impl)(source_id)
}

///|
fn[T] ModeRelexFactory::tokenize(
  self : ModeRelexFactory[T],
  source_id : String,
  source : String,
) -> LexResult[T] {
  let session = self.new_session(source_id)
  (session.tokenize)(source)
}

///|
enum SessionSlot[T] {
  Ready(ModeRelexState[T])
  ResetRequired
}

///|
enum SessionEvent[T] {
  PartialRejected
  FreshValidated(ModeRelexState[T])
  FreshRejected
}

///|
enum SessionDecision {
  RequestFresh
  CommitFresh
  KeepCommitted
}

///|
fn[T] transition(
  slot : SessionSlot[T],
  event : SessionEvent[T],
) -> (SessionSlot[T], SessionDecision) {
  match (slot, event) {
    (Ready(_), PartialRejected) => (ResetRequired, RequestFresh)
    (ResetRequired, FreshValidated(session)) => (Ready(session), CommitFresh)
    (ResetRequired, FreshRejected) => (ResetRequired, KeepCommitted)
    (current, _) => (current, KeepCommitted)
  }
}

///|
struct CommittedLexState[T] {
  source : String
  result : LexResult[T]
  version : Int
}

///|
enum BufferState[T] {
  Plain(CommittedLexState[T])
  Mode(CommittedLexState[T], SessionSlot[T])
}

///|
struct TokenBuffer[T] {
  source_id : String
  eof_token : T
  factory : ModeRelexFactory[T]?
  mut state : BufferState[T]
  mut invalid_partial_count : Int
}

///|
fn[T] TokenBuffer::committed(self : TokenBuffer[T]) -> CommittedLexState[T] {
  match self.state {
    Plain(committed) | Mode(committed, _) => committed
  }
}

///|
fn[T] TokenBuffer::slot(self : TokenBuffer[T]) -> SessionSlot[T]? {
  match self.state {
    Plain(_) => None
    Mode(_, slot) => Some(slot)
  }
}

///|
fn[T : Eq] validate_full_result(
  source : String,
  result : LexResult[T],
  eof_token : T,
) -> Bool {
  guard result.tokens.length() > 0 else { return false }
  for i = 0; i < result.tokens.length(); i = i + 1 {
    let end = result.starts[i] + result.tokens[i].len
    guard end <= source.length() else { return false }
  }
  let last = result.tokens.length() - 1
  result.tokens[last].token == eof_token &&
  result.tokens[last].len == 0 &&
  result.starts[last] == source.length()
}

///|
fn[T : Eq] TokenBuffer::new_from_lex(
  source_id : String,
  source : String,
  lex_fn~ : (String) -> LexResult[T],
  eof_token~ : T,
) -> TokenBuffer[T] {
  let result = lex_fn(source)
  guard validate_full_result(source, result, eof_token) else {
    abort("plain lexer violated initial token/start/source/EOF invariants")
  }
  {
    source_id,
    eof_token,
    factory: None,
    state: Plain({ source, result, version: 0 }),
    invalid_partial_count: 0,
  }
}

///|
fn[T : Eq] TokenBuffer::new_from_mode_relex(
  source_id : String,
  source : String,
  factory~ : ModeRelexFactory[T],
  eof_token~ : T,
) -> TokenBuffer[T] {
  let session = factory.new_session(source_id)
  let result = (session.tokenize)(source)
  guard validate_full_result(source, result, eof_token) else {
    abort("mode factory violated initial token/start/source/EOF invariants")
  }
  {
    source_id,
    eof_token,
    factory: Some(factory),
    state: Mode({ source, result, version: 0 }, Ready(session)),
    invalid_partial_count: 0,
  }
}

///|
fn[T : Eq] TokenBuffer::update_mode(
  self : TokenBuffer[T],
  new_source : String,
) -> Unit raise LexError {
  let factory = match self.factory {
    Some(factory) => factory
    None => raise LexError("plain buffer has no mode factory")
  }
  let (committed, initial_slot) = match self.state {
    Mode(committed, slot) => (committed, slot)
    Plain(_) => raise LexError("plain buffer cannot perform mode update")
  }
  let reset_slot = match initial_slot {
    Ready(session) => {
      let partial : Result[ModeRelexResult[T], LexResultError] = Ok(
        (session.relex_from)(new_source),
      ) catch {
        error => Err(error)
      }
      match partial {
        Ok(replacement) => {
          guard replacement.converged_at_old_token >= 0 &&
            validate_full_result(
              new_source,
              replacement.full_replacement,
              self.eof_token,
            ) else {
            raise LexError("prototype partial replacement was invalid")
          }
          let next_committed = {
            source: new_source,
            result: replacement.full_replacement,
            version: committed.version + 1,
          }
          self.state = Mode(next_committed, Ready(session))
          return
        }
        Err(_) => {
          self.invalid_partial_count = self.invalid_partial_count + 1
          let (next, decision) = transition(initial_slot, PartialRejected)
          guard decision is RequestFresh else {
            raise LexError("transition did not request a fresh session")
          }
          self.state = Mode(committed, next)
          next
        }
      }
    }
    ResetRequired => ResetRequired
  }
  let fresh = factory.new_session(self.source_id)
  let fresh_result = (fresh.tokenize)(new_source)
  if !validate_full_result(new_source, fresh_result, self.eof_token) {
    let (next, decision) = transition(reset_slot, FreshRejected)
    guard decision is KeepCommitted else {
      raise LexError("transition did not retain committed state")
    }
    self.state = Mode(committed, next)
    raise LexError("fresh factory session returned an invalid full result")
  }
  let next_committed = {
    source: new_source,
    result: fresh_result,
    version: committed.version + 1,
  }
  let (next, decision) = transition(reset_slot, FreshValidated(fresh))
  guard decision is CommitFresh else {
    raise LexError("transition did not commit the fresh session")
  }
  // One assignment publishes source, tokens, starts, diagnostics, version, and
  // replacement session together. No callback or fallible work follows it.
  self.state = Mode(next_committed, next)
}

///|
struct FactoryProbe {
  mut fresh_count : Int
  mut partial_count : Int
  mut last_poisoned_session : Int
  mut next_full_valid : Bool
}

///|
fn valid_full_result(source : String, session_id : Int) -> LexResult[String] {
  {
    tokens: [{ token: "TEXT", len: source.length() }, { token: "EOF", len: 0 }],
    starts: [0, source.length()],
    diagnostics: ["session=\{session_id}"],
  }
}

///|
fn invalid_eof_result(source : String, session_id : Int) -> LexResult[String] {
  {
    tokens: [{ token: "TEXT", len: source.length() }],
    starts: [0],
    diagnostics: ["invalid-session=\{session_id}"],
  }
}

///|
fn make_factory(probe : FactoryProbe) -> ModeRelexFactory[String] {
  ModeRelexFactory::new(new_session=source_id => {
    probe.fresh_count = probe.fresh_count + 1
    let session_id = probe.fresh_count
    let poisoned = Ref(false)
    {
      id: session_id,
      source_id,
      tokenize: source => {
        if probe.next_full_valid {
          valid_full_result(source, session_id)
        } else {
          invalid_eof_result(source, session_id)
        }
      },
      relex_from: _source => {
        probe.partial_count = probe.partial_count + 1
        poisoned.val = true
        probe.last_poisoned_session = session_id
        ModeRelexResult::new(
          [{ token: "TEXT", len: 1 }],
          [],
          [],
          converged_at_old_token=0,
        )
      },
      poisoned: () => poisoned.val,
    }
  })
}

///|
fn invalid_raw_result_is_rejected() -> Bool {
  let result : Result[LexResult[String], LexResultError] = Ok(
    LexResult::with_starts([{ token: "TEXT", len: 1 }], [], diagnostics=[]),
  ) catch {
    error => Err(error)
  }
  match result {
    Err(TokenStartCountMismatch(1, 0)) => true
    _ => false
  }
}
