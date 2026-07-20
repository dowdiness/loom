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
  _ => abort("HTML grammar compilation failed")
}

///|
pub fn make_html_parse_root() -> HtmlParseRoot {
  fn(ctx) {
    let tag_stack : Array[String] = []
    let natives : Map[
      String,
      @grammar.NativeRule[@token.Token, @syntax.SyntaxKind],
    ] = {
      "parse_html_root": fn(inner, try_parse_rule) {
        parse_html_root(inner, tag_stack, try_parse_rule)
      },
    }
    let guards : Map[
      String,
      @grammar.HostGuard[@token.Token, @syntax.SyntaxKind],
    ] = {
      "html_tag_stack_valid": fn(inner) {
        match (inner.peek(), tag_stack.last()) {
          (@token.CloseTag(name), Some(expected)) =>
            ascii_lower_tag_name(name) == expected
          _ => false
        }
      },
    }
    @grammar.interpret_compiled(compiled_html_grammar, natives~, guards~)(ctx)
  }
}
