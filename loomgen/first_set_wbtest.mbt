///|
test "first analysis recognizes finite ASCII prefixes" {
  match first_units_for_pattern("a[0-9]+") {
    FirstCodeUnits::Finite(ranges) => {
      assert_true(ranges.length() == 1)
      assert_true(ranges[0].0 == 97 && ranges[0].1 == 97)
    }
    FirstCodeUnits::Any => fail("literal prefix should be finite")
  }
  match first_units_for_pattern("[a-z]") {
    FirstCodeUnits::Finite(ranges) => {
      assert_true(ranges.length() == 1)
      assert_true(ranges[0].0 == 97 && ranges[0].1 == 122)
    }
    FirstCodeUnits::Any => fail("ASCII class should be finite")
  }
}

///|
test "first analysis unions through nullable prefixes" {
  match first_units_for_pattern("a?b") {
    FirstCodeUnits::Finite(ranges) => {
      assert_true(ranges.length() == 2)
      assert_true(ranges[0].0 == 97 && ranges[0].1 == 97)
      assert_true(ranges[1].0 == 98 && ranges[1].1 == 98)
    }
    FirstCodeUnits::Any => fail("nullable prefix should remain finite")
  }
}

///|
test "first analysis fails closed for unknown prefixes" {
  match first_units_for_pattern("[^a]") {
    FirstCodeUnits::Any => ()
    FirstCodeUnits::Finite(_) => fail("negated class is not a finite ASCII set")
  }
  match first_units_for_pattern("\\x41") {
    FirstCodeUnits::Any => ()
    FirstCodeUnits::Finite(_) => fail("hex escape must remain conservative")
  }
  match first_units_for_pattern("(") {
    FirstCodeUnits::Any => ()
    FirstCodeUnits::Finite(_) =>
      fail("malformed pattern must remain conservative")
  }
  match first_units_for_pattern("é+") {
    FirstCodeUnits::Any => ()
    FirstCodeUnits::Finite(_) =>
      fail("non-ASCII literal prefix must remain conservative")
  }
  match first_units_for_pattern("[[:digit:]]") {
    FirstCodeUnits::Any => ()
    FirstCodeUnits::Finite(_) => fail("POSIX classes must remain conservative")
  }
  match first_units_for_pattern(".") {
    FirstCodeUnits::Any => ()
    FirstCodeUnits::Finite(_) => fail("wildcard must remain conservative")
  }
  match first_units_for_pattern("\\.") {
    FirstCodeUnits::Finite(ranges) => {
      assert_true(ranges.length() == 1)
      assert_true(ranges[0].0 == 46 && ranges[0].1 == 46)
    }
    FirstCodeUnits::Any =>
      fail("escaped literal dot should have a finite FIRST set")
  }
}
