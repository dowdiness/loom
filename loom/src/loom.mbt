///|
// Public API facade for dowdiness/loom.
// A single import gives access to all framework types for both grammar
// authors (LanguageSpec, ParserContext, SyntaxNode) and parser consumers
// (Parser, ImperativeParser, Edit, Diagnostic).

///|
// CST types and traits — grammar callbacks receive SyntaxNode; the full green tree is CstNode.
pub using @seam {
  type CstElement,
  type CstNode,
  type CstToken,
  type Interner,
  type NodeInterner,
  type ParseEvent,
  type RawKind,
  type SyntaxElement,
  type SyntaxNode,
  type SyntaxToken,
  trait FromRawKind,
  trait IsEof,
  trait IsError,
  trait IsTrivia,
  trait ToRawKind,
  build_tree,
  build_tree_fully_interned,
  build_tree_interned,
}

///|
// Core parser primitives
pub using @core {
  type BlockReparseSpec,
  type DiagnosticBuildError,
  type DiagnosticCode,
  type DiagnosticLabel,
  type DiagnosticSet,
  type DiagnosticSeverity,
  type DiagnosticSource,
  type Diagnostic,
  type Edit,
  type LanguageSpec,
  type LexCursor,
  type LexError,
  type LexResult,
  type LexStep,
  type LocatedToken,
  type LineCol,
  type LineIndex,
  type LineRange,
  type ModeLexer,
  type ModeRelexResult,
  type ModeRelexState,
  type ParserContext,
  type PrefixLexer,
  type ProjectionIdentityBaseline,
  type ProjectionIdentityTracker,
  type ProjectionLeaf,
  type ProjectionStringIdAllocator,
  type Range,
  type ReuseCursor,
  type StableProjectionLeaf,
  type TextOffset,
  type TextRange,
  type TextDelta,
  type TokenEvidence,
  type TokenBuffer,
  type TokenInfo,
  trait Renderable,
  trait TreeNode,
  build_starts,
  erase_mode_lexer,
  parse_tokens_indexed,
  realign_projection_identities,
  realign_projection_identities_with_optional_edit,
  realign_projection_items,
  realign_projection_items_with_optional_edit,
  text_to_delta,
  to_edits,
  tokenize_via_steps_result,
  tokenize_via_steps,
  tokenize_with_modes,
}

///|
// Incremental engine — the primary parser type consumers interact with
pub using @incremental {type ImperativeParser, type ParseSnapshot}

///|
// Reactive parser — wraps ImperativeParser with signal/memo outputs
pub using @pipeline {type Parser}

// Grammar and factory functions (new_imperative_parser, new_parser) are
// defined in grammar.mbt and factories.mbt in this package.

///|
// AstView trait — implement for every typed view type in your language package.
pub using @core {trait AstView}

///|
// Memoized catamorphism — CstFold[Ast] for incremental CST → AST conversion
pub using @core {type CstFold, type FoldStats}
