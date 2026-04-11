// ReactiveParser tests: generic pipeline invariants.
//
// Uses a self-contained TestLang fixture rather than @lambda, so the tests
// document ReactiveParser[Ast] contracts without depending on the lambda grammar.
//
// TestLang design
// ───────────────
// • Lex error: source starts with "@"
// • CstNode token text = source.length().to_string()
//   → two sources of the same length produce structurally equal CstNodes
//     → equal CstStages → term_memo backdates (skips recompute)
//   → two sources of different lengths produce different CstNodes
//     → term_memo recomputes
// • Ast = String: on success returns the CstNode token text (the length string)
//                 on lex error returns "error: <first diagnostic>"

// ── TestLang fixture ──────────────────────────────────────────────────────────

///|
struct TestLang {}

///|
fn stage_for_source(s : String) -> CstStage {
  if s.length() > 0 && s[0] == '@' {
    CstStage::{
      cst: try! @seam.build_tree([], @seam.RawKind(0)),
      diagnostics: ["lex error: " + s],
      is_lex_error: true,
    }
  } else {
    CstStage::{
      cst: try! @seam.build_tree(
        [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
        @seam.RawKind(0),
      ),
      diagnostics: [],
      is_lex_error: false,
    }
  }
}

///|
impl Parseable for TestLang with parse_source(_, s) {
  stage_for_source(s)
}

///|
fn test_lang() -> Language[String] {
  Language::from(
    TestLang::{  },
    to_ast=fn(n) {
      let toks = n.tokens()
      if toks.length() > 0 {
        toks[0].text()
      } else {
        ""
      }
    },
    on_lex_error=fn(msg) { "error: " + msg },
  )
}

///|
fn new_db(source : String) -> ReactiveParser[String] {
  ReactiveParser::new(source, test_lang())
}

// ── Warm-path caching ─────────────────────────────────────────────────────────

///|
/// Calling term() twice with no source change returns the same value.
/// The second call is a staleness check only — no recompute.
test "ReactiveParser: repeated term() calls are idempotent (warm path)" {
  let db = new_db("hello")
  let t1 = ReactiveParser::term(db)
  let t2 = ReactiveParser::term(db)
  assert_eq(t1, t2)
}

// ── cst / term consistency ────────────────────────────────────────────────────

///|
/// cst().is_lex_error and the Ast routing must agree:
///   is_lex_error = true  → on_lex_error path → Ast starts with "error: "
///   is_lex_error = false → to_ast path        → Ast is the length string
test "ReactiveParser: is_lex_error on cst() agrees with Ast routing in term()" {
  // Lex-error path
  let db_err = new_db("@oops")
  assert_eq(ReactiveParser::cst(db_err).is_lex_error, true)
  inspect(ReactiveParser::term(db_err), content="error: lex error: @oops")
  // Valid path
  let db_ok = new_db("hi")
  assert_eq(ReactiveParser::cst(db_ok).is_lex_error, false)
  inspect(ReactiveParser::term(db_ok), content="2") // length of "hi"
}

// ── diagnostics() defensive copy ─────────────────────────────────────────────

///|
/// diagnostics() must return a copy of the internal array.
/// Mutating the returned slice must not affect subsequent calls.
test "ReactiveParser: diagnostics() returns a defensive copy" {
  let db = new_db("@bad")
  let d1 = ReactiveParser::diagnostics(db)
  assert_eq(d1.length(), 1)
  d1.push("injected") // mutate the returned copy
  let d2 = ReactiveParser::diagnostics(db) // re-read
  assert_eq(d2.length(), 1) // original must be unaffected
}

// ── set_source invalidation ───────────────────────────────────────────────────

///|
/// set_source with a different value must invalidate cst_memo and term_memo.
test "ReactiveParser: set_source with a different value updates term()" {
  let db = new_db("hi") // length 2 → term = "2"
  inspect(ReactiveParser::term(db), content="2")
  ReactiveParser::set_source(db, "hello") // length 5 → term = "5"
  inspect(ReactiveParser::term(db), content="5")
}

// ── Backdating invariant ──────────────────────────────────────────────────────

///|
/// When parse_source produces an equal CstStage for a new source,
/// term_memo skips recomputation (backdating) and the term remains equal.
///
/// TestLang maps source length → CstNode token text, so:
///   "hello" (len 5) and "world" (len 5) produce identical CstStages
///     → term_memo backdates → term() returns the same "5"
///   "hi"    (len 2) produces a different CstStage
///     → term_memo recomputes → term() returns "2"
test "ReactiveParser: equal CstStage backdates term_memo — term() Eq holds" {
  let db = new_db("hello")
  let t1 = ReactiveParser::term(db)
  ReactiveParser::set_source(db, "world")
  let t2 = ReactiveParser::term(db)
  assert_eq(t1, t2)
  ReactiveParser::set_source(db, "hi")
  let t3 = ReactiveParser::term(db)
  assert_not_eq(t1, t3)
}

///|
test "ReactiveParser::get_source returns current source" {
  let db = new_db("hello")
  inspect(ReactiveParser::get_source(db), content="hello")
  ReactiveParser::set_source(db, "world")
  inspect(ReactiveParser::get_source(db), content="world")
}

///|
test "ReactiveParser::runtime exposes the internal Runtime" {
  let db = new_db("hello")
  let derived = @incr.Memo::new(ReactiveParser::runtime(db), fn() -> String {
    ReactiveParser::term(db) + "!"
  })
  inspect(derived.get(), content="5!")
}

///|
test "panic ReactiveParser::from_parts rejects cross-runtime cells" {
  let rt_a = @incr.Runtime::new()
  let rt_b = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt_a, "hello", label="source_text")
  let cst_memo = @incr.Memo::new(
    rt_b,
    fn() -> CstStage { stage_for_source("hello") },
    label="cst",
  )
  let term_memo = @incr.Memo::new(rt_b, fn() -> String { "5" }, label="term")
  let _ = ReactiveParser::from_parts(
    rt_a, source_text, cst_memo, cst_memo, term_memo,
  )
}

///|
test "panic ReactiveParser::from_parts rejects cst memo disconnected from source_text on access" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "hello", label="source_text")
  let other_source = @incr.Signal::new(rt, "world", label="other_source")
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { stage_for_source(other_source.get()) },
    label="cst",
  )
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      let stage = cst_memo.get()
      if stage.is_lex_error {
        "error"
      } else {
        "ok"
      }
    },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, cst_memo, cst_memo, term_memo,
  )
  let _ = ReactiveParser::cst(parser)
}

///|
test "panic ReactiveParser::from_parts revalidates dynamic source memo dependencies" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "hello", label="source_text")
  let use_source = @incr.Signal::new(rt, true, label="use_source")
  let source_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      if use_source.get() {
        source_text.get()
      } else {
        "detached"
      }
    },
    label="source",
  )
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { stage_for_source(source_memo.get()) },
    label="cst",
  )
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      let stage = cst_memo.get()
      if stage.is_lex_error {
        "error"
      } else {
        "ok"
      }
    },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, source_memo, cst_memo, term_memo,
  )
  inspect(ReactiveParser::cst(parser).is_lex_error, content="false")
  use_source.set(false)
  let _ = ReactiveParser::cst(parser)
}

///|
test "panic ReactiveParser::from_parts revalidates dynamic cst memo dependencies" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "hello", label="source_text")
  let use_source_memo = @incr.Signal::new(rt, true, label="use_source_memo")
  let source_memo = @incr.Memo::new(
    rt,
    fn() -> String { source_text.get() },
    label="source",
  )
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage {
      if use_source_memo.get() {
        stage_for_source(source_memo.get())
      } else {
        stage_for_source("detached")
      }
    },
    label="cst",
  )
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      let stage = cst_memo.get()
      if stage.is_lex_error {
        "error"
      } else {
        "ok"
      }
    },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, source_memo, cst_memo, term_memo,
  )
  inspect(ReactiveParser::cst(parser).is_lex_error, content="false")
  use_source_memo.set(false)
  let _ = ReactiveParser::diagnostics(parser)
}

///|
test "panic ReactiveParser::from_parts rejects term memo disconnected from cst_memo" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "hello", label="source_text")
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { stage_for_source(source_text.get()) },
    label="cst",
  )
  let other_memo = @incr.Memo::new(
    rt,
    fn() -> String { source_text.get().length().to_string() },
    label="other",
  )
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String { other_memo.get() },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, cst_memo, cst_memo, term_memo,
  )
  let _ = ReactiveParser::term(parser)
}

///|
test "panic ReactiveParser::from_parts revalidates dynamic term memo dependencies" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "hello", label="source_text")
  let use_cst = @incr.Signal::new(rt, true, label="use_cst")
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { stage_for_source(source_text.get()) },
    label="cst",
  )
  let detached_memo = @incr.Memo::new(
    rt,
    fn() -> String { if use_cst.get() { "attached" } else { "detached" } },
    label="detached",
  )
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      if use_cst.get() {
        let stage = cst_memo.get()
        if stage.is_lex_error {
          "error"
        } else {
          "ok"
        }
      } else {
        detached_memo.get()
      }
    },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, cst_memo, cst_memo, term_memo,
  )
  inspect(ReactiveParser::term(parser), content="ok")
  use_cst.set(false)
  let _ = ReactiveParser::term(parser)
}

///|
test "ReactiveParser::from_parts does not eagerly evaluate term_memo" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "@oops", label="source_text")
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { stage_for_source(source_text.get()) },
    label="cst",
  )
  let term_calls : Ref[Int] = { val: 0 }
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      term_calls.val = term_calls.val + 1
      let stage = cst_memo.get()
      if stage.is_lex_error {
        "error"
      } else {
        "ok"
      }
    },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, cst_memo, cst_memo, term_memo,
  )
  inspect(term_calls.val, content="0")
  inspect(ReactiveParser::cst(parser).is_lex_error, content="true")
  inspect(term_calls.val, content="0")
  inspect(ReactiveParser::term(parser), content="error")
  inspect(term_calls.val, content="1")
}

///|
test "ReactiveParser::from_parts does not eagerly evaluate source/cst memos" {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, "hello", label="source_text")
  let source_calls : Ref[Int] = { val: 0 }
  let cst_calls : Ref[Int] = { val: 0 }
  let source_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      source_calls.val = source_calls.val + 1
      source_text.get()
    },
    label="source",
  )
  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage {
      cst_calls.val = cst_calls.val + 1
      stage_for_source(source_memo.get())
    },
    label="cst",
  )
  let term_memo = @incr.Memo::new(
    rt,
    fn() -> String {
      let stage = cst_memo.get()
      if stage.is_lex_error {
        "error"
      } else {
        "ok"
      }
    },
    label="term",
  )
  let parser = ReactiveParser::from_parts(
    rt, source_text, source_memo, cst_memo, term_memo,
  )
  inspect(source_calls.val, content="0")
  inspect(cst_calls.val, content="0")
  inspect(ReactiveParser::cst(parser).is_lex_error, content="false")
  inspect(source_calls.val, content="1")
  inspect(cst_calls.val, content="1")
}
