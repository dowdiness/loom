///|
#loom.token
pub enum Token {
  // `<tag ... >` — full opening tag including name and attributes up to `>`
  #loom.literal("OpenTagToken")
  OpenTag(String)
  // `</tag>` — closing tag including `</` and name and `>`
  #loom.literal("CloseTagToken")
  CloseTag(String)
  // `=` in attribute context
  #loom.punct("=")
  Eq // =
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

///|
pub impl Show for Token with fn output(self, logger) {
  logger.write_string(
    match self {
      OpenTag(_) => "<tag>"
      CloseTag(_) => "</tag>"
      Eq => "="
      StringLit => "<string>"
      Text => "<text>"
      Comment => "<!-- -->"
      Doctype => "<!DOCTYPE>"
      RawText => "<rawtext>"
      CData => "<![CDATA["
      Whitespace => " "
      Error(msg) => "<error: " + msg + ">"
      EOF => "EOF"
    },
  )
}

///|
pub impl @seam.IsTrivia for Token with fn is_trivia(self) {
  self == Whitespace
}

///|
pub impl @seam.IsEof for Token with fn is_eof(self) {
  self == EOF
}

///|
pub impl @seam.ToRawKind for Token with fn to_raw(self) {
  let n : Int = match self {
    OpenTag(_) => 0
    CloseTag(_) => 1
    Eq => 2
    StringLit => 3
    Text => 4
    Comment => 5
    Doctype => 6
    RawText => 7
    CData => 8
    Whitespace => 9
    Error(_) => 10
    EOF => 11
  }
  @seam.RawKind(n)
}

///|
pub impl @seam.FromRawKind for Token with fn from_raw(raw) {
  let @seam.RawKind(n) = raw
  match n {
    0 => OpenTag("")
    1 => CloseTag("")
    2 => Eq
    3 => StringLit
    4 => Text
    5 => Comment
    6 => Doctype
    7 => RawText
    8 => CData
    9 => Whitespace
    10 => Error("")
    11 => EOF
    _ => Error("unknown kind")
  }
}
