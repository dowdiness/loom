///|
test "Unicode P/S classifier: every generated interval boundary" {
  assert_eq(unicode_punctuation_symbol_ranges.length(), 349 * 2)
  let mut codepoint_count = 0
  let mut index = 0
  while index < unicode_punctuation_symbol_ranges.length() {
    let start = unicode_punctuation_symbol_ranges[index]
    let end = unicode_punctuation_symbol_ranges[index + 1]
    assert_true(start <= end)
    assert_eq(is_unicode_punctuation_or_symbol_codepoint(start), true)
    assert_eq(is_unicode_punctuation_or_symbol_codepoint(end), true)
    assert_eq(is_unicode_punctuation_or_symbol_codepoint(start - 1), false)
    assert_eq(is_unicode_punctuation_or_symbol_codepoint(end + 1), false)
    if index + 2 < unicode_punctuation_symbol_ranges.length() {
      assert_true(end + 1 < unicode_punctuation_symbol_ranges[index + 2])
    }
    codepoint_count = codepoint_count + end - start + 1
    index = index + 2
  }
  assert_eq(codepoint_count, 9369)
}

///|
test "Unicode P/S classifier: generated interval boundaries" {
  let cases = [
    // First interval and its immediate exterior code points.
    (0x20, false),
    (0x21, true),
    (0x2F, true),
    (0x30, false),
    // A merged non-ASCII interval containing punctuation and symbols.
    (0xA0, false),
    (0xA1, true),
    (0xA9, true),
    (0xAA, false),
    // Symbols added in Unicode 16.0.
    (0x1F8BF, false),
    (0x1F8C0, true),
    (0x1F8C1, true),
    (0x1F8C2, false),
    // Final generated interval and its immediate exterior code points.
    (0x1FB93, false),
    (0x1FB94, true),
    (0x1FBEF, true),
    (0x1FBF0, false),
    (-1, false),
    (0x110000, false),
  ]
  for case in cases {
    let (codepoint, expected) = case
    assert_eq(is_unicode_punctuation_or_symbol_codepoint(codepoint), expected)
  }
}

///|
test "Unicode P/S classifier: representative non-ASCII scalars" {
  assert_eq(is_unicode_punctuation_or_symbol('—'), true)
  assert_eq(is_unicode_punctuation_or_symbol('£'), true)
  assert_eq(is_unicode_punctuation_or_symbol('€'), true)
  assert_eq(is_unicode_punctuation_or_symbol('😀'), true)
  assert_eq(is_unicode_punctuation_or_symbol('\u{200B}'), false)
  assert_eq(is_unicode_punctuation_or_symbol('文'), false)
}

///|
test "delimiter neighbor classification uses Unicode P/S data" {
  assert_true(
    delimiter_neighbor_from_char(Some('—')) == DelimiterPunctuationOrSymbol,
  )
  assert_true(
    delimiter_neighbor_from_char(Some('£')) == DelimiterPunctuationOrSymbol,
  )
  assert_true(
    delimiter_neighbor_from_char(Some('€')) == DelimiterPunctuationOrSymbol,
  )
  assert_true(delimiter_neighbor_from_char(Some('文')) == DelimiterOther)
}

///|
test "delimiter neighbor classification uses CommonMark whitespace" {
  // CommonMark whitespace is Unicode Zs plus TAB, LF, FF, and CR. Other
  // characters accepted by Char::is_whitespace remain ordinary neighbors.
  for
    ch in [
      '\t', '\n', '\u{000C}', '\r', ' ', '\u{00A0}', '\u{1680}', '\u{2000}', '\u{2001}',
      '\u{2002}', '\u{2003}', '\u{2004}', '\u{2005}', '\u{2006}', '\u{2007}', '\u{2008}',
      '\u{2009}', '\u{200A}', '\u{202F}', '\u{205F}', '\u{3000}',
    ] {
    assert_true(delimiter_neighbor_from_char(Some(ch)) == DelimiterWhitespace)
  }
  for ch in ['\u{000B}', '\u{0085}', '\u{2028}', '\u{2029}'] {
    assert_true(delimiter_neighbor_from_char(Some(ch)) == DelimiterOther)
  }
}
