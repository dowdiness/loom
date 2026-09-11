///|
/// Returns true for tokens that indicate a block boundary.
fn is_block_boundary(token : Token) -> Bool {
  match token {
    HeadingMarker(_)
    | ListMarker
    | OrderedListMarker(_)
    | BlockQuoteMarker
    | ThematicBreak
    | CodeFenceOpen(_, _)
    | HtmlBlockOpen(_)
    | BlankLine
    | EOF => true
    _ => false
  }
}

///|
/// Type 7 HTML block opens do not interrupt paragraphs; Types 1–6 do.
fn html_block_open_interrupts_paragraph(line : String) -> Bool {
  match classify_html_block_opening(line.view()) {
    Some(kind) => kind.interrupts_paragraph()
    None => true
  }
}

///|
/// Ordered lists can interrupt paragraphs only when the start number is 1.
/// Other ordered-list-looking lines remain paragraph text after a soft break.
/// Type 7 HTML block opens likewise stay in the paragraph.
fn token_breaks_paragraph_after_newline(token : Token) -> Bool {
  match token {
    OrderedListMarker(marker) => marker.start() == 1
    HtmlBlockOpen(line) => html_block_open_interrupts_paragraph(line)
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
    // Type 7 HTML may continue a lazy list-item paragraph.
    HtmlBlockOpen(line) => !html_block_open_interrupts_paragraph(line)
    _ => !is_block_boundary(token)
  }
}
