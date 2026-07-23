///|
/// Returns true for tokens that indicate a block boundary.
fn is_block_boundary(token : Token) -> Bool {
  match token {
    HeadingMarker(_)
    | ListMarker(_)
    | OrderedListMarker(_)
    | BlockQuoteMarker
    | ThematicBreak(_)
    | CodeFenceOpen(_, _)
    | HtmlBlockOpen(_)
    | BlankLine
    | EOF => true
    _ => false
  }
}

///|
/// Ordered lists can interrupt paragraphs only when the start number is 1.
/// Other ordered-list-looking lines remain paragraph text after a soft break.
fn token_breaks_paragraph_after_newline(token : Token) -> Bool {
  match token {
    OrderedListMarker(marker) => marker.start() == 1
    _ => is_block_boundary(token)
  }
}

///|
fn token_continues_paragraph_after_softbreak(token : Token) -> Bool {
  match token {
    Newline | EOF => false
    _ => !token_breaks_paragraph_after_newline(token)
  }
}

///|
fn token_can_start_lazy_list_item_continuation(
  token : Token,
  allow_ordered_marker~ : Bool,
) -> Bool {
  match token {
    Text([' ' | '\t', ..]) => false
    Newline | EOF => false
    OrderedListMarker(_) if allow_ordered_marker =>
      !token_breaks_paragraph_after_newline(token)
    _ => !is_block_boundary(token)
  }
}
