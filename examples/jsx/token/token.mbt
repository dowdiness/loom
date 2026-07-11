///|
/// JSX token types used by the loom-generated parser pipeline.
///
/// Variants are annotated with #loom.token metadata for loomgen code generation.
/// Trait impls (Show, IsTrivia, IsEof, ToRawKind, FromRawKind) are generated
/// by loomgen into token_impls.g.mbt — do not hand-write them here.
///
/// Content-bearing tokens carry no payload (matching html's `Text`/`StringLit`
/// precedent, not its coarse `OpenTag(String)`): JSX needs fine-grained
/// tokens because attribute values and children can each independently
/// contain a `{...}` embedded expression requiring a lex-mode switch
/// mid-tag, so raw content is recovered from the token's source span at
/// AST-fold time, not stored redundantly on the token itself.
#loom.token
pub(all) enum Token {
  // `<` — starts a tag or, followed by `Slash`, a close-tag sequence
  // (`</name>` lexes as OpenTagStart, Slash, TagName, TagEnd — there is no
  // dedicated "close tag start" token).
  #loom.punct("<")
  #loom.recovery("sync")
  OpenTagStart
  // tag name or attribute name identifier
  #loom.literal("TagNameToken")
  TagName
  // `/` — self-close marker (before `>`) or close-tag marker (after `<`),
  // disambiguated by the parser from position, not by the lexer.
  #loom.punct("/")
  Slash
  // `>` closing a tag
  #loom.punct(">")
  #loom.recovery("sync")
  TagEnd
  // `/>` self-closing tag end
  #loom.punct("/>")
  #loom.recovery("sync")
  SelfCloseEnd
  // attribute name identifier
  #loom.literal("AttrNameToken")
  AttrName
  // `=` in attribute context
  #loom.punct("=")
  Eq
  // well-formed quoted attribute value (open and close quote both present)
  #loom.literal("AttrStringLitToken")
  AttrStringLit
  // quoted attribute value truncated by EOF before its closing quote —
  // distinct from AttrStringLit so the parser can push the
  // "unterminated attribute string literal" diagnostic (2026-07-10 Task
  // 1.1 design gate, Design B case 3) while still preserving the scanned
  // content as a normal token, not a synthetic error token that discards it.
  #loom.literal("AttrStringLitUnterminatedToken")
  AttrStringLitUnterminated
  // `{` opening an embedded expression
  #loom.punct("{")
  BraceOpen
  // `}` closing an embedded expression (at brace-depth 1, per Design A)
  #loom.punct("}")
  BraceClose
  // raw JS-expression content chunk between BraceOpen/BraceClose, opaque
  // and unparsed. One token per contiguous run between JsExprString mode
  // transitions (a run ends where a "/'/` sub-scan begins or ends), so
  // string-literal boundaries stay visible to the parser rather than
  // being silently merged into one blob (Design A / Design B case 4).
  #loom.literal("ExprRawTextToken")
  ExprRawText
  // expression content truncated by EOF while inside a string/template
  // literal specifically (as opposed to plain unterminated-`}` — see
  // ExprRawText) — distinct token kind so the parser can push an
  // additive "unterminated string literal in expression" diagnostic
  // alongside, not instead of, the missing-`}` one (Design B case 4,
  // Codex round-2 gap).
  #loom.literal("ExprStringUnterminatedToken")
  ExprStringUnterminated
  // JSX text content between tags
  #loom.literal("TextToken")
  Text
  // `<>` fragment open — has no tag name, so it cannot be decomposed into
  // OpenTagStart + TagName like a named element; needs its own token.
  #loom.punct("<>")
  #loom.recovery("sync")
  FragmentOpen
  // `</>` fragment close — same reasoning as FragmentOpen.
  #loom.punct("</>")
  #loom.recovery("sync")
  FragmentClose
  // whitespace
  #loom.trivia
  Whitespace
  // lex error
  #loom.error
  Error(String)
  // end of input
  #loom.eof
  #loom.recovery("sync")
  EOF
} derive(Eq, Debug)
