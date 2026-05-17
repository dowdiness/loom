// Tests for `Canonical for JsonValue` and the canonical/placeholder drift
// detector. See lambda's proj_traits_canonical_wbtest.mbt for the
// non-circularity rule (don't call Renderable::placeholder from the drift
// reference, since after rewire it would call the free function we're
// validating).

///|
/// Frozen, pre-change placeholder mapping. Returns `Some` for the 6
/// fitting variants and `None` for the `Error` carve-out (UX masking).
fn hand_written_placeholder_reference(v : JsonValue) -> String? {
  match v {
    Null => Some("null")
    Bool(_) => Some("false")
    Number(_) => Some("0")
    String(_) => Some("\"\"")
    Array(_) => Some("[]")
    Object(_) => Some("{}")
    Error(_) => None // carve-out: UX masking
  }
}

// --- Bounded generator -------------------------------------------------
//
// JsonValue has no existing @qc.Arbitrary impl. Scope a small bounded
// generator (depth ≤ 3) here per the plan. Strings are drawn from a fixed
// small alphabet; numbers from a small set.

///|
fn gen_string(rs : @splitmix.RandomState) -> String {
  let names = ["", "a", "hello", "foo", "bar"]
  names[rs.split().next_uint64().to_int().abs() % names.length()]
}

///|
fn gen_number(rs : @splitmix.RandomState) -> Double {
  let nums = [0.0, 1.0, -1.0, 3.14, 100.0]
  nums[rs.split().next_uint64().to_int().abs() % nums.length()]
}

///|
fn gen_json(rs : @splitmix.RandomState, depth : Int) -> JsonValue {
  if depth <= 0 {
    match rs.split().next_uint64().to_int().abs() % 5 {
      0 => Null
      1 => Bool(rs.split().next_uint64().to_int().abs() % 2 == 0)
      2 => Number(gen_number(rs))
      3 => String(gen_string(rs))
      _ => Error(gen_string(rs))
    }
  } else {
    match rs.split().next_uint64().to_int().abs() % 8 {
      0 => Null
      1 => Bool(rs.split().next_uint64().to_int().abs() % 2 == 0)
      2 => Number(gen_number(rs))
      3 => String(gen_string(rs))
      4 => {
        let n = rs.split().next_uint64().to_int().abs() % 3
        let items : Array[JsonValue] = []
        for i = 0; i < n; i = i + 1 {
          items.push(gen_json(rs, depth - 1))
        }
        Array(items)
      }
      5 => {
        let n = rs.split().next_uint64().to_int().abs() % 3
        let members : Array[(String, JsonValue)] = []
        for i = 0; i < n; i = i + 1 {
          members.push((gen_string(rs), gen_json(rs, depth - 1)))
        }
        Object(members)
      }
      6 => Error(gen_string(rs))
      _ => Null
    }
  }
}

// --- Manual property loop ---------------------------------------------
//
// JSON tests don't use @qc.Arbitrary; run a manual deterministic loop
// over `gen_json(seed, depth=3)` to exercise the laws across the variant
// space. Use a fixed seed so failures reproduce.

///|
const PROPERTY_TRIALS : Int = 200

///|
test "property: Canonical preserves kind" {
  let rs = @splitmix.new(seed=0x1234_5678_9ABC_DEF0UL)
  for _i = 0; _i < PROPERTY_TRIALS; _i = _i + 1 {
    let v = gen_json(rs.split(), 3)
    if !@core.TreeNode::same_kind(v, @core.Canonical::canonical(v)) {
      fail("same_kind violated for: \{v}")
    }
  }
}

///|
test "property: Canonical is idempotent" {
  let rs = @splitmix.new(seed=0x1234_5678_9ABC_DEF0UL)
  for _i = 0; _i < PROPERTY_TRIALS; _i = _i + 1 {
    let v = gen_json(rs.split(), 3)
    let c = @core.Canonical::canonical(v)
    if @core.Canonical::canonical(c) != c {
      fail("idempotence violated for: \{v}")
    }
  }
}

///|
test "property: default_placeholder_via_canonical matches frozen reference" {
  let rs = @splitmix.new(seed=0x1234_5678_9ABC_DEF0UL)
  for _i = 0; _i < PROPERTY_TRIALS; _i = _i + 1 {
    let v = gen_json(rs.split(), 3)
    match hand_written_placeholder_reference(v) {
      None => () // carve-out
      Some(ref_str) => {
        let actual = @core.default_placeholder_via_canonical(v)
        if actual != ref_str {
          fail("drift for \{v}: got \{actual}, expected \{ref_str}")
        }
      }
    }
  }
}

// --- Per-variant inspect coverage -------------------------------------

///|
test "canonical: Null" {
  inspect(
    @core.Canonical::canonical(JsonValue::Null),
    content=(
      #|Null
    ),
  )
}

///|
test "canonical: Bool normalized to false" {
  inspect(
    @core.Canonical::canonical(JsonValue::Bool(true)),
    content=(
      #|Bool(false)
    ),
  )
}

///|
test "canonical: Number normalized to 0.0" {
  inspect(
    @core.Canonical::canonical(JsonValue::Number(42.5)),
    content=(
      #|Number(0)
    ),
  )
}

///|
test "canonical: String normalized to empty" {
  inspect(
    @core.Canonical::canonical(JsonValue::String("hello")),
    content=(
      #|String("")
    ),
  )
}

///|
test "canonical: Array normalized to empty" {
  inspect(
    @core.Canonical::canonical(JsonValue::Array([JsonValue::Null])),
    content=(
      #|Array([])
    ),
  )
}

///|
test "canonical: Object normalized to empty" {
  inspect(
    @core.Canonical::canonical(JsonValue::Object([("k", JsonValue::Null)])),
    content=(
      #|Object([])
    ),
  )
}

///|
test "canonical: Error normalized to \"?\"" {
  inspect(
    @core.Canonical::canonical(JsonValue::Error("parse failure")),
    content=(
      #|Error("?")
    ),
  )
}

// --- Per-variant placeholder snapshots --------------------------------

///|
test "placeholder: all variants match expected strings" {
  let cases : Array[(JsonValue, String)] = [
    (JsonValue::Null, "null"),
    (JsonValue::Bool(true), "false"),
    (JsonValue::Number(42.5), "0"),
    (JsonValue::String("hello"), "\"\""),
    (JsonValue::Array([JsonValue::Null]), "[]"),
    (JsonValue::Object([("k", JsonValue::Null)]), "{}"),
    (JsonValue::Error("oops"), "null"),
  ]
  for case in cases {
    let (v, expected) = case
    let actual = @core.Renderable::placeholder(v)
    if actual != expected {
      fail("placeholder(\{v}) = \{actual}, expected \{expected}")
    }
  }
}
