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
impl Parseable for TestLang with parse_source(_, s) {
  if s.length() > 0 && s[0] == '@' {
    CstStage::{
      cst: @seam.build_tree([], @seam.RawKind(0)),
      diagnostics: ["lex error: " + s],
      is_lex_error: true,
    }
  } else {
    CstStage::{
      cst: @seam.build_tree(
        [@seam.ParseEvent::Token(@seam.RawKind(1), s.length().to_string())],
        @seam.RawKind(0),
      ),
      diagnostics: [],
      is_lex_error: false,
    }
  }
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
