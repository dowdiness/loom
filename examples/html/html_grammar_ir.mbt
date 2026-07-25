///|
type HtmlParseRoot = (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit

///|
pub let html_grammar_ir : @grammar.GrammarIr[@token.Token, @syntax.SyntaxKind] = @grammar.GrammarIr::GrammarIr(
  {
    "source": @grammar.Expr::Native("parse_html_root"),
    "close_boundary": @grammar.Expr::Choice([
      @grammar.Alt::{
        starts: @grammar.Pred::HostGuard("html_tag_stack_valid"),
        body: @grammar.Expr::Empty,
      },
    ]),
  },
  root="source",
)

///|
let compiled_html_grammar : @grammar.CompiledGrammar[
  @token.Token,
  @syntax.SyntaxKind,
] = @grammar.compile(
  html_grammar_ir,
  native_names=Set::Set(["parse_html_root"]),
  guard_names=Set::Set(["html_tag_stack_valid"]),
  native_rule_refs={ "parse_html_root": Set::Set(["close_boundary"]) },
) catch {
  e => abort("HTML grammar compilation failed: \{@debug.to_string(e)}")
}

///|
/// Open-element nesting for the in-flight parse.
///
/// Shared by every parse rather than allocated per call. Two things make that
/// sound, and both are load-bearing:
///
/// - the parser unwinds its own pushes, so the stack is already empty when
///   `parse_html_root` returns — pinned by `tag_stack_wbtest.mbt`;
/// - the grammar's root *is* the single Native, so `parse_html_root` runs once
///   per parse and is never re-entered. Adding a second native, or reaching
///   `Native("parse_html_root")` from anywhere but the root, breaks this and
///   requires going back to per-parse state.
///
/// The `clear()` on entry is a backstop for the first point, not the mechanism
/// behind it: it costs nothing and keeps a future recovery path that returns
/// without unwinding from corrupting the *next* parse instead of its own.
let html_tag_stack : Array[String] = []

///|
/// Bound once: `compile` and `bind` do not depend on the input, so repeating
/// them per parse only rebuilt the same capability and guard tables.
let executable_html_grammar : @grammar.ExecutableGrammar[
  @token.Token,
  @syntax.SyntaxKind,
] = @grammar.bind(
  compiled_html_grammar,
  natives={
    "parse_html_root": capabilities => {
      let close_boundary = capabilities.require("close_boundary")
      (inner, dispatcher) => {
        html_tag_stack.clear()
        let close_boundary_query = () => {
          dispatcher.try_rule(inner, close_boundary)
        }
        parse_html_root(inner, html_tag_stack, close_boundary_query)
      }
    },
  },
  guards={
    "html_tag_stack_valid": inner => {
      match (inner.peek(), html_tag_stack.last()) {
        (@token.CloseTag(name), Some(expected)) =>
          ascii_lower_tag_name(name) == ascii_lower_tag_name(expected)
        _ => false
      }
    },
  },
) catch {
  e => abort("HTML grammar binding failed: \{@debug.to_string(e)}")
}

///|
pub fn make_html_parse_root() -> HtmlParseRoot {
  executable_html_grammar.parse_root()
}
