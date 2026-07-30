///|
/// CommonMark 0.31.2 defines Unicode whitespace as every Zs character plus
/// TAB, LF, FF, and CR. This is intentionally narrower than
/// `Char::is_whitespace`, which also accepts VT, NEL, LS, and PS.
fn is_commonmark_unicode_whitespace(ch : Char) -> Bool {
  let codepoint = ch.to_int()
  codepoint == 0x09 ||
  codepoint == 0x0A ||
  codepoint == 0x0C ||
  codepoint == 0x0D ||
  codepoint == 0x20 ||
  codepoint == 0xA0 ||
  codepoint == 0x1680 ||
  (codepoint >= 0x2000 && codepoint <= 0x200A) ||
  codepoint == 0x202F ||
  codepoint == 0x205F ||
  codepoint == 0x3000
}
