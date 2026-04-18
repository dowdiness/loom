///|
// Public API facade for dowdiness/loom.
// A single import gives access to all framework types for both grammar
// authors (LanguageSpec, ParserContext, SyntaxNode) and parser consumers
// (ImperativeParser, ReactiveParser, Edit, Diagnostic).

///|
// CST types — grammar callbacks receive SyntaxNode; the full green tree is CstNode.
pub using @seam {
  type CstNode,
  type SyntaxNode,
  type SyntaxToken,
  type SyntaxElement,
}

///|
// Core parser primitives
pub using @core {
  type Edit,
  type TokenInfo,
  type Diagnostic,
  type LanguageSpec,
  type ParserContext,
  type TextDelta,
  type LexError,
  type BlockReparseSpec,
}

///|
// Incremental engine — the primary parser type consumers interact with
pub using @incremental {type ImperativeParser}

///|
// Reactive pipeline — Signal[String] → Memo[Ast]
pub using @pipeline {type ReactiveParser, type Parser}

// Grammar and factory functions (new_imperative_parser, new_reactive_parser,
// new_parser) are defined in grammar.mbt and factories.mbt in this package.

///|
// AstView trait — implement for every typed view type in your language package.
pub using @core {trait AstView}

///|
// Memoized catamorphism — CstFold[Ast] for incremental CST → AST conversion
pub using @core {type CstFold, type FoldStats}
