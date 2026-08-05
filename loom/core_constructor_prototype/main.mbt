// PROTOTYPE — do not ship. Interactive shell for model.mbt.

///|
fn render_tokens(result : LexResult[String]) -> String {
  let parts : Array[String] = []
  for i = 0; i < result.tokens.length(); i = i + 1 {
    parts.push(
      "\{result.tokens[i].token}@\{result.starts[i]}+\{result.tokens[i].len}",
    )
  }
  parts.join(", ")
}

///|
fn render(
  buffer : TokenBuffer[String],
  probe : FactoryProbe,
  last : String,
) -> Unit {
  let committed = buffer.committed()
  let slot = match buffer.slot() {
    None => "Plain"
    Some(ResetRequired) => "ResetRequired"
    Some(Ready(session)) =>
      "Ready(id=\{session.id}, source_id=\{session.source_id}, poisoned=\{(session.poisoned)()})"
  }
  println("\u001b[2J\u001b[H\u001b[1mMode authority prototype\u001b[0m")
  println("\u001b[1msource\u001b[0m: \{committed.source}")
  println("\u001b[1mtokens\u001b[0m: \{render_tokens(committed.result)}")
  println(
    "\u001b[1mdiagnostics\u001b[0m: \{committed.result.diagnostics.join(", ")}",
  )
  println("\u001b[1mversion\u001b[0m: \{committed.version}")
  println("\u001b[1mslot\u001b[0m: \{slot}")
  println("\u001b[1mfresh sessions\u001b[0m: \{probe.fresh_count}")
  println("\u001b[1mpartial calls\u001b[0m: \{probe.partial_count}")
  println(
    "\u001b[1mlast poisoned session\u001b[0m: \{probe.last_poisoned_session}",
  )
  println("\u001b[1minvalid partials\u001b[0m: \{buffer.invalid_partial_count}")
  println("\u001b[1mlast check\u001b[0m: \{last}")
  println("")
  println(
    "\u001b[1ms\u001b[0m invalid partial + valid fresh  \u001b[1mx\u001b[0m invalid partial + invalid fresh",
  )
  println(
    "\u001b[1mr\u001b[0m retry ResetRequired  \u001b[1md\u001b[0m detached factory tokenize  \u001b[1mv\u001b[0m reject raw shape  \u001b[1mq\u001b[0m quit",
  )
  println(
    "\u001b[1ma\u001b[0m prove invalid plain initial abort  \u001b[1mm\u001b[0m prove invalid mode initial abort",
  )
}

///|
async fn main {
  let probe = FactoryProbe::{
    fresh_count: 0,
    partial_count: 0,
    last_poisoned_session: 0,
    next_full_valid: true,
  }
  let factory = make_factory(probe)
  let plain = TokenBuffer::new_from_lex(
    "plain-source-id",
    "plain",
    lex_fn=source => valid_full_result(source, 0),
    eof_token="EOF",
  )
  let buffer = TokenBuffer::new_from_mode_relex(
    "mode-source-id",
    "initial",
    factory~,
    eof_token="EOF",
  )
  let last = Ref(
    "PASS constructors split; plain=\{plain.committed().source}; mode factory owns initial result",
  )
  let mut running = true
  while running {
    render(buffer, probe, last.val)
    match @stdio.stdin.read_until("\n") {
      None => running = false
      Some(line) =>
        match line.trim() {
          "s" => {
            probe.next_full_valid = true
            let before_fresh = probe.fresh_count
            let before_partial = probe.partial_count
            let before_version = buffer.committed().version
            let replaced_session = match buffer.slot() {
              Some(Ready(session)) => session.id
              _ => -1
            }
            try buffer.update_mode("success-\{before_version + 1}") catch {
              LexError(message) =>
                last.val = "FAIL unexpected error: \{message}"
            } noraise {
              _ => {
                let committed = buffer.committed()
                let passed = probe.partial_count == before_partial + 1 &&
                  probe.fresh_count == before_fresh + 1 &&
                  probe.last_poisoned_session == replaced_session &&
                  committed.version == before_version + 1 &&
                  buffer.slot() is Some(Ready(_))
                last.val = if passed {
                  "PASS poisoned session discarded; fresh result/session committed together"
                } else {
                  "FAIL successful reset invariants"
                }
              }
            }
          }
          "x" => {
            probe.next_full_valid = false
            let before = buffer.committed()
            try buffer.update_mode("must-not-commit") catch {
              LexError(_) => {
                let after = buffer.committed()
                let passed = after.source == before.source &&
                  after.version == before.version &&
                  render_tokens(after.result) == render_tokens(before.result) &&
                  after.result.diagnostics == before.result.diagnostics &&
                  buffer.slot() is Some(ResetRequired)
                last.val = if passed {
                  "PASS invalid fresh kept all committed fields and set ResetRequired"
                } else {
                  "FAIL rollback/ResetRequired invariants"
                }
              }
            } noraise {
              _ => last.val = "FAIL invalid fresh unexpectedly committed"
            }
          }
          "r" => {
            probe.next_full_valid = true
            let before_partial = probe.partial_count
            let before_version = buffer.committed().version
            try buffer.update_mode("retry-\{before_version + 1}") catch {
              LexError(message) => last.val = "FAIL retry error: \{message}"
            } noraise {
              _ => {
                let passed = probe.partial_count == before_partial &&
                  buffer.committed().version == before_version + 1 &&
                  buffer.slot() is Some(Ready(_))
                last.val = if passed {
                  "PASS ResetRequired bypassed partial and installed a fresh session"
                } else {
                  "FAIL ResetRequired retry invariants"
                }
              }
            }
          }
          "d" => {
            probe.next_full_valid = true
            let before_fresh = probe.fresh_count
            let detached = factory.tokenize("detached-source-id", "detached")
            let passed = probe.fresh_count == before_fresh + 1 &&
              validate_full_result("detached", detached, "EOF")
            last.val = if passed {
              "PASS detached tokenize created a fresh factory session"
            } else {
              "FAIL detached tokenize authority"
            }
          }
          "v" =>
            last.val = if invalid_raw_result_is_rejected() {
              "PASS invalid raw collection raised LexResultError; no opaque result escaped"
            } else {
              "FAIL raw collection validation"
            }
          "a" =>
            ignore(
              TokenBuffer::new_from_lex(
                "invalid-plain-source-id",
                "invalid",
                lex_fn=source => invalid_eof_result(source, -1),
                eof_token="EOF",
              ),
            )
          "m" => {
            probe.next_full_valid = false
            ignore(
              TokenBuffer::new_from_mode_relex(
                "invalid-mode-source-id",
                "invalid",
                factory~,
                eof_token="EOF",
              ),
            )
          }
          "q" => running = false
          _ => last.val = "unknown command"
        }
    }
  }
}
