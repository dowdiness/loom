///|
/// Code-unit predicates for rule identifier characters.  `String[i]` is a UTF-16
/// `UInt16`; ASCII identifier characters are single code units, so byte-range
/// checks are exact here.
fn is_rule_ident_start(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
/// Whether `c` is a valid identifier continuation character — either an
/// identifier-start character or a decimal digit.
fn is_rule_ident_char(c : UInt16) -> Bool {
  is_rule_ident_start(c) || (c >= '0' && c <= '9')
}
