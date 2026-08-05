// PROTOTYPE — do not ship.
//
// Question: can Loom expose separate plain-lexer and mode-aware constructors
// so a ModeFactory is the sole source of the initial result and every fresh
// reset, while the state machine makes a mutated session unusable after an
// invalid partial result?

///|
struct LexResult[T] {
  tokens : Array[T]
  diagnostics : Array[String]
}

///|
struct ModeSession[T] {
  id : Int
  tokenize : (String) -> LexResult[T]
}

///|
struct ModeFactory[T] {
  initialize_fresh : (String) -> (ModeSession[T], LexResult[T])
}

///|
enum SessionSlot[T] {
  Ready(ModeSession[T])
  ResetRequired
}

///|
enum BufferMode[T] {
  Plain
  Mode(ModeFactory[T], SessionSlot[T])
}

///|
struct TokenBuffer[T] {
  source : String
  result : LexResult[T]
  mode : BufferMode[T]
}

///|
fn[T] new_from_lex(
  source : String,
  lex : (String) -> LexResult[T],
) -> TokenBuffer[T] {
  { source, result: lex(source), mode: Plain }
}

///|
fn[T] new_from_mode_relex(
  source : String,
  factory : ModeFactory[T],
) -> TokenBuffer[T] {
  let (session, result) = (factory.initialize_fresh)(source)
  { source, result, mode: Mode(factory, Ready(session)) }
}

///|
enum SessionEvent {
  InvalidPartial
  FreshResetSucceeded(Int)
  FreshResetFailed
}

///|
enum SessionDecision {
  DiscardAndRequestFresh
  CommitFresh
  KeepCommitted
}

///|
fn transition(
  slot : SessionSlot[String],
  event : SessionEvent,
) -> (SessionSlot[String], SessionDecision) {
  match (slot, event) {
    (Ready(_), InvalidPartial) => (ResetRequired, DiscardAndRequestFresh)
    (ResetRequired, FreshResetSucceeded(id)) => {
      let session : ModeSession[String] = {
        id,
        tokenize: source => LexResult::{ tokens: [source], diagnostics: [] },
      }
      (Ready(session), CommitFresh)
    }
    (ResetRequired, FreshResetFailed) => (ResetRequired, KeepCommitted)
    (current, _) => (current, KeepCommitted)
  }
}

///|
fn render_slot(slot : SessionSlot[String]) -> String {
  match slot {
    Ready(session) => "Ready(session=\{session.id})"
    ResetRequired => "ResetRequired"
  }
}

///|
fn render_decision(decision : SessionDecision) -> String {
  match decision {
    DiscardAndRequestFresh => "discard partial; request fresh factory session"
    CommitFresh => "atomically commit fresh result and session"
    KeepCommitted => "keep previously committed buffer"
  }
}

///|
fn render(slot : SessionSlot[String], decision : String) -> Unit {
  println("\u001b[2J\u001b[H\u001b[1mConstructor split prototype\u001b[0m")
  println("\u001b[1msession\u001b[0m: \{render_slot(slot)}")
  println("\u001b[1mlast decision\u001b[0m: \{decision}")
  println("")
  println(
    "\u001b[1mi\u001b[0m invalid partial  \u001b[1mf\u001b[0m fresh reset succeeds",
  )
  println("\u001b[1mx\u001b[0m fresh reset fails  \u001b[1mq\u001b[0m quit")
}

///|
async fn main {
  let plain = new_from_lex("plain", source => LexResult::{
    tokens: [source],
    diagnostics: [],
  })
  ignore(plain)
  let factory : ModeFactory[String] = {
    initialize_fresh: source => {
      let session : ModeSession[String] = {
        id: 1,
        tokenize: text => LexResult::{ tokens: [text], diagnostics: [] },
      }
      (session, (session.tokenize)(source))
    },
  }
  let buffer = new_from_mode_relex("mode", factory)
  let slot : Ref[SessionSlot[String]] = Ref(
    match buffer.mode {
      Mode(_, initial) => initial
      Plain => ResetRequired
    },
  )
  let last = Ref("constructed by factory only")
  let mut running = true
  while running {
    render(slot.val, last.val)
    let input = @stdio.stdin.read_until("\n")
    match input {
      None => running = false
      Some(line) => {
        let event = match line.trim() {
          "i" => Some(InvalidPartial)
          "f" => Some(FreshResetSucceeded(2))
          "x" => Some(FreshResetFailed)
          "q" => {
            running = false
            None
          }
          _ => None
        }
        match event {
          Some(event) => {
            let (next, decision) = transition(slot.val, event)
            slot.val = next
            last.val = render_decision(decision)
          }
          None => ()
        }
      }
    }
  }
}
