///|
test "ASCII display run maps UTF-16 offsets to cells" {
  let units = display_units("abc")
  inspect(display_width("abc"), content="3")
  inspect(units.length(), content="3")
  inspect(units[0].utf16_start(), content="0")
  inspect(units[0].utf16_end(), content="1")
  inspect(units[0].cell_start(), content="0")
  inspect(units[0].cell_end(), content="1")
  inspect(units[2].utf16_start(), content="2")
  inspect(units[2].utf16_end(), content="3")
  inspect(units[2].cell_start(), content="2")
  inspect(units[2].cell_end(), content="3")
}

///|
test "Ambiguous width is an explicit policy" {
  inspect(display_width("·"), content="1")
  inspect(
    display_width("·", ambiguous_width=AmbiguousWidth::Wide),
    content="2",
  )
}

///|
test "tabs advance from the absolute starting column" {
  let leading_tab = display_units("\t", tab_width=4)
  inspect(display_width("\t", tab_width=4), content="4")
  inspect(leading_tab[0].cell_start(), content="0")
  inspect(leading_tab[0].cell_end(), content="4")
  let units = display_units("a\tb", start_column=2, tab_width=4)
  inspect(display_width("a\tb", start_column=2, tab_width=4), content="3")
  inspect(units.length(), content="3")
  inspect(units[0].cell_start(), content="2")
  inspect(units[0].cell_end(), content="3")
  inspect(units[1].cell_start(), content="3")
  inspect(units[1].cell_end(), content="4")
  inspect(units[2].cell_start(), content="4")
  inspect(units[2].cell_end(), content="5")
}

///|
test "non-additive graphemes form one display unit" {
  let units = display_units("لا")
  inspect(display_width("لا"), content="1")
  inspect(units.length(), content="1")
  inspect(units[0].utf16_start(), content="0")
  inspect(units[0].utf16_end(), content="2")
  inspect(units[0].cell_start(), content="0")
  inspect(units[0].cell_end(), content="1")
}

///|
test "non-additivity discovered across three graphemes collapses the run" {
  let text = "\u{16D69}\u{16D68}\u{16D67}"
  let units = display_units(text)
  inspect(display_width(text), content="2")
  inspect(units.length(), content="1")
  inspect(units[0].utf16_start(), content="0")
  inspect(units[0].utf16_end(), content="6")
  inspect(units[0].cell_start(), content="0")
  inspect(units[0].cell_end(), content="2")
  inspect(display_width(text + "\tb", start_column=1, tab_width=4), content="4")
}

///|
test "tab-free total width matches unicodewidth's complete state machine" {
  for
    text in [
      "", "abc", "界e\u{301}👨‍👩‍👧‍👦", "لا", "\u{16D69}\u{16D68}\u{16D67}",
    ] {
    assert_eq(display_width(text), @unicodewidth.str_width(text))
  }
  assert_eq(
    display_width("·界", ambiguous_width=AmbiguousWidth::Wide),
    @unicodewidth.str_width("·界", cjk=true),
  )
}

///|
test "display width table version is explicit" {
  debug_inspect(display_width_unicode_version, content="(16, 0, 0)")
}

///|
test "CJK combining and ZWJ clusters keep UTF-16 and cell ranges" {
  let units = display_units("界e\u{301}👨‍👩‍👧‍👦")
  inspect(display_width("界e\u{301}👨‍👩‍👧‍👦"), content="5")
  inspect(units.length(), content="3")
  inspect(units[0].utf16_end(), content="1")
  inspect(units[0].cell_end(), content="2")
  inspect(units[1].utf16_start(), content="1")
  inspect(units[1].utf16_end(), content="3")
  inspect(units[1].cell_start(), content="2")
  inspect(units[1].cell_end(), content="3")
  inspect(units[2].utf16_start(), content="3")
  inspect(units[2].utf16_end(), content="14")
  inspect(units[2].cell_start(), content="3")
  inspect(units[2].cell_end(), content="5")
}

///|
test "zero-width and flag graphemes remain explicit display units" {
  let units = display_units("a\u{200B}🇯🇵")
  inspect(display_width("a\u{200B}🇯🇵"), content="3")
  inspect(units.length(), content="3")
  inspect(units[1].utf16_start(), content="1")
  inspect(units[1].utf16_end(), content="2")
  inspect(units[1].cell_start(), content="1")
  inspect(units[1].cell_end(), content="1")
  inspect(units[2].utf16_start(), content="2")
  inspect(units[2].utf16_end(), content="6")
  inspect(units[2].cell_start(), content="1")
  inspect(units[2].cell_end(), content="3")
}

///|
test "invalid display context is rejected before measurement" {
  let negative_start = Ok(display_width("x", start_column=-1)) catch {
    error => Err(error)
  }
  debug_inspect(negative_start, content="Err(InvalidStartColumn(-1))")
  let zero_tab = Ok(display_width("\t", tab_width=0)) catch {
    error => Err(error)
  }
  debug_inspect(zero_tab, content="Err(InvalidTabWidth(0))")
  let negative_tab = Ok(display_width("\t", tab_width=-2)) catch {
    error => Err(error)
  }
  debug_inspect(negative_tab, content="Err(InvalidTabWidth(-2))")
}

///|
test "empty and repeated-tab runs preserve absolute display context" {
  inspect(display_width("", start_column=5), content="0")
  inspect(display_units("", start_column=5).length(), content="0")
  let units = display_units("\t\t", start_column=1, tab_width=4)
  inspect(display_width("\t\t", start_column=1, tab_width=4), content="7")
  inspect(units[0].cell_start(), content="1")
  inspect(units[0].cell_end(), content="4")
  inspect(units[1].cell_start(), content="4")
  inspect(units[1].cell_end(), content="8")
}
