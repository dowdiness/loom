///|
/// HTML token types used by the loom-generated parser pipeline.
///
/// Variants are annotated with #loom.token metadata for loomgen code generation.
/// Trait impls (Show, IsTrivia, IsEof, ToRawKind, FromRawKind) are generated
/// by loomgen into token_impls.g.mbt — do not hand-write them here.
#loom.token
pub(all) enum Token {
  // `<tag ... >` — full opening tag including name and attributes up to `>`
  #loom.literal("OpenTagToken")
  OpenTag(String)
  // `</tag>` — closing tag including `</` and name and `>`
  #loom.literal("CloseTagToken")
  CloseTag(String)
  // `=` in attribute context
  #loom.punct("=")
  Eq
  // attribute value in quotes
  #loom.literal("StringToken")
  StringLit
  // text content between tags
  #loom.literal("TextToken")
  Text
  // `<!-- ... -->`
  #loom.literal("CommentToken")
  Comment
  // `<!DOCTYPE html>` or similar
  #loom.literal("DoctypeToken")
  Doctype
  // raw text inside <script>, <style>
  #loom.literal("RawTextToken")
  RawText
  // `<![CDATA[ ... ]]>`
  #loom.literal("CDataToken")
  CData
  // whitespace
  #loom.trivia
  Whitespace
  // lex error
  #loom.error
  Error(String)
  // end of input
  #loom.eof
  EOF
} derive(Eq, Debug)
