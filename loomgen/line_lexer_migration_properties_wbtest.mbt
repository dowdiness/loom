///|
enum MigrationOwnership {
  MigrationCanonical
  MigrationAlreadyDelegated
  MigrationHandwritten
  MigrationMutatedAbortMessage
  MigrationMutatedWhitespace
  MigrationMutatedSignature
  MigrationCommentInserted
  MigrationAbsent
} derive(Debug, Eq)

///|
struct MigrationWord {
  camel : String
  snake : String
} derive(Debug, Eq)

///|
struct MigrationMode {
  mode_name : String
  fn_name : String
  helper_name : String
  component_count : Int
  ownership : MigrationOwnership
} derive(Debug, Eq)

///|
struct MigrationCase {
  modes : Array[MigrationMode]
  selected_modes : Array[String]
} derive(Debug, Eq)

///|
fn migration_property_words() -> Array[MigrationWord] {
  [
    { camel: "Bold", snake: "bold" },
    { camel: "Calm", snake: "calm" },
    { camel: "Deep", snake: "deep" },
    { camel: "Fast", snake: "fast" },
    { camel: "Kind", snake: "kind" },
    { camel: "Line", snake: "line" },
    { camel: "HTTP", snake: "h_t_t_p" },
    { camel: "V2Id", snake: "v2_id" },
  ]
}

///|
fn migration_property_mode(
  word_indices : Array[Int],
  ownership : MigrationOwnership,
) -> MigrationMode {
  if word_indices.length() < 1 || word_indices.length() > 3 {
    abort("migration mode identifiers need one to three components")
  }
  let words = migration_property_words()
  let mode_name = StringBuilder()
  let fn_name = StringBuilder()..write_string("lex_")
  let helper_name = StringBuilder()..write_string("generated_lex_")
  for i, index in word_indices {
    if index < 0 || index >= words.length() {
      abort("migration mode word index is out of bounds")
    }
    let word = words[index]
    mode_name.write_string(word.camel)
    if i > 0 {
      fn_name.write_string("_")
      helper_name.write_string("_")
    }
    fn_name.write_string(word.snake)
    helper_name.write_string(word.snake)
  }
  {
    mode_name: mode_name.to_string(),
    fn_name: fn_name.to_string(),
    helper_name: helper_name.to_string(),
    component_count: word_indices.length(),
    ownership,
  }
}

///|
fn migration_property_contains(values : Array[String], needle : String) -> Bool {
  for value in values {
    if value == needle {
      return true
    }
  }
  false
}

///|
fn migration_property_stable_deduplicate(
  values : Array[String],
) -> Array[String] {
  let deduplicated : Array[String] = []
  for value in values {
    if !migration_property_contains(deduplicated, value) {
      deduplicated.push(value)
    }
  }
  deduplicated
}

///|
fn migration_property_reverse(values : Array[String]) -> Array[String] {
  let reversed : Array[String] = []
  for i = values.length(); i > 0; i = i - 1 {
    reversed.push(values[i - 1])
  }
  reversed
}

///|
fn migration_property_rotate(values : Array[String]) -> Array[String] {
  if values.length() < 2 {
    return values.copy()
  }
  let rotated : Array[String] = []
  for i in 1..<values.length() {
    rotated.push(values[i])
  }
  rotated.push(values[0])
  rotated
}

///|
fn migration_property_effective_ownership(
  mode : MigrationMode,
  selected_modes : Array[String],
  migrate_selected : Bool,
) -> MigrationOwnership {
  if migrate_selected &&
    mode.ownership == MigrationCanonical &&
    migration_property_contains(selected_modes, mode.mode_name) {
    MigrationAlreadyDelegated
  } else {
    mode.ownership
  }
}

///|
fn migration_property_render_block(
  mode : MigrationMode,
  ownership : MigrationOwnership,
) -> String? {
  let canonical_header = "fn " +
    mode.fn_name +
    "(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n"
  match ownership {
    MigrationCanonical =>
      Some(
        canonical_header +
        "  abort(\"" +
        mode.fn_name +
        " not implemented\")\n}",
      )
    MigrationAlreadyDelegated =>
      Some(canonical_header + "  " + mode.helper_name + "(source, pos)\n}")
    MigrationHandwritten =>
      Some(canonical_header + "  custom_" + mode.fn_name + "(source, pos)\n}")
    MigrationMutatedAbortMessage =>
      Some(
        canonical_header +
        "  abort(\"" +
        mode.fn_name +
        " needs implementation\")\n}",
      )
    MigrationMutatedWhitespace =>
      Some(
        "fn " +
        mode.fn_name +
        "(source: String, pos : Int) -> (@core.LexStep[Token], LexMode) {\n" +
        "  abort(\"" +
        mode.fn_name +
        " not implemented\")\n}",
      )
    MigrationMutatedSignature =>
      Some(
        "fn " +
        mode.fn_name +
        "(source : String, pos : Int) -> (@core.LexStep[OtherToken], LexMode) {\n" +
        "  abort(\"" +
        mode.fn_name +
        " not implemented\")\n}",
      )
    MigrationCommentInserted =>
      Some(
        canonical_header +
        "  // user-owned marker\n" +
        "  abort(\"" +
        mode.fn_name +
        " not implemented\")\n}",
      )
    MigrationAbsent => None
  }
}

///|
fn migration_property_render_skeleton(
  case : MigrationCase,
  migrate_selected : Bool,
) -> String {
  let output = StringBuilder()
    ..write_string("///|\n")
    ..write_string("/// Generated lex dispatch skeleton.\n")
    ..write_string("/// Fill in the mode-specific `lex_*` functions below.\n")
    ..write_string("pub fn lex(\n")
    ..write_string("  source : String,\n")
    ..write_string("  pos : Int,\n")
    ..write_string("  mode : LexMode,\n")
    ..write_string(") -> (@core.LexStep[Token], LexMode) {\n")
    ..write_string("  match mode {\n")
  for mode in case.modes {
    output
    ..write_string("    ")
    ..write_string(mode.mode_name)
    ..write_string(" => ")
    ..write_string(mode.fn_name)
    .write_string("(source, pos)\n")
  }
  output.write_string("  }\n}")
  let blocks : Array[String] = []
  for mode in case.modes {
    let ownership = migration_property_effective_ownership(
      mode,
      case.selected_modes,
      migrate_selected,
    )
    match migration_property_render_block(mode, ownership) {
      Some(block) => blocks.push(block)
      None => ()
    }
  }
  if blocks.length() == 0 {
    output.write_string("\n")
  } else {
    for block in blocks {
      output.write_string("\n\n")
      output.write_string(block)
    }
    output.write_string("\n")
  }
  output.to_string()
}

///|
fn migration_property_assert_exact(
  label : String,
  case : MigrationCase,
  actual : String,
  expected : String,
) -> Unit {
  if actual != expected {
    abort(
      label +
      "\ncase: " +
      to_repr(case).to_string() +
      "\nexpected:\n" +
      expected +
      "\nactual:\n" +
      actual,
    )
  }
}

///|
fn migration_property_check_case(case : MigrationCase) -> Unit {
  migration_property_assert_unique_names(case)
  let existing = migration_property_render_skeleton(case, false)
  let expected = migration_property_render_skeleton(case, true)
  let selections = [
    case.selected_modes,
    migration_property_stable_deduplicate(case.selected_modes),
    migration_property_reverse(case.selected_modes),
    migration_property_rotate(case.selected_modes),
  ]
  for selection in selections {
    let actual = integrate_line_lexer_skeleton(
      existing, selection, "Token", "@core",
    )
    migration_property_assert_exact(
      "migration mismatch", case, actual, expected,
    )
  }
  let migrated_again = integrate_line_lexer_skeleton(
    expected,
    case.selected_modes,
    "Token",
    "@core",
  )
  migration_property_assert_exact(
    "migration is not idempotent", case, migrated_again, expected,
  )
}

///|
fn migration_property_golden_case() -> MigrationCase {
  let bold = migration_property_mode([0], MigrationCanonical)
  let calm_line = migration_property_mode([1, 5], MigrationHandwritten)
  { modes: [bold, calm_line], selected_modes: [bold.mode_name] }
}

///|
fn migration_property_basis_cases() -> Array[MigrationCase] {
  let selected_states = [
    migration_property_mode([1], MigrationAlreadyDelegated),
    migration_property_mode([2, 0], MigrationHandwritten),
    migration_property_mode([3, 1, 5], MigrationMutatedAbortMessage),
    migration_property_mode([4], MigrationMutatedWhitespace),
    migration_property_mode([5, 3], MigrationMutatedSignature),
    migration_property_mode([6, 4, 0], MigrationCommentInserted),
    migration_property_mode([7], MigrationAbsent),
  ]
  let selected_modes = [
    selected_states[6].mode_name,
    selected_states[0].mode_name,
    selected_states[3].mode_name,
    selected_states[1].mode_name,
    selected_states[4].mode_name,
    selected_states[2].mode_name,
    selected_states[5].mode_name,
    selected_states[3].mode_name,
  ]
  let unselected = migration_property_mode([0, 1, 2], MigrationCanonical)
  [
    migration_property_golden_case(),
    { modes: selected_states, selected_modes },
    { modes: [unselected], selected_modes: [] },
  ]
}

///|
fn migration_property_ownership_index(ownership : MigrationOwnership) -> Int {
  match ownership {
    MigrationCanonical => 0
    MigrationAlreadyDelegated => 1
    MigrationHandwritten => 2
    MigrationMutatedAbortMessage => 3
    MigrationMutatedWhitespace => 4
    MigrationMutatedSignature => 5
    MigrationCommentInserted => 6
    MigrationAbsent => 7
  }
}

///|
fn migration_property_mode_index(
  modes : Array[MigrationMode],
  mode_name : String,
) -> Int {
  for i, mode in modes {
    if mode.mode_name == mode_name {
      return i
    }
  }
  abort("selected migration mode is absent from case data")
}

///|
test "line skeleton migration oracle matches literal skeleton bytes" {
  let case = migration_property_golden_case()
  let existing =
    #|///|
    #|/// Generated lex dispatch skeleton.
    #|/// Fill in the mode-specific `lex_*` functions below.
    #|pub fn lex(
    #|  source : String,
    #|  pos : Int,
    #|  mode : LexMode,
    #|) -> (@core.LexStep[Token], LexMode) {
    #|  match mode {
    #|    Bold => lex_bold(source, pos)
    #|    CalmLine => lex_calm_line(source, pos)
    #|  }
    #|}
    #|
    #|fn lex_bold(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
    #|  abort("lex_bold not implemented")
    #|}
    #|
    #|fn lex_calm_line(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
    #|  custom_lex_calm_line(source, pos)
    #|}
    #|
  let expected =
    #|///|
    #|/// Generated lex dispatch skeleton.
    #|/// Fill in the mode-specific `lex_*` functions below.
    #|pub fn lex(
    #|  source : String,
    #|  pos : Int,
    #|  mode : LexMode,
    #|) -> (@core.LexStep[Token], LexMode) {
    #|  match mode {
    #|    Bold => lex_bold(source, pos)
    #|    CalmLine => lex_calm_line(source, pos)
    #|  }
    #|}
    #|
    #|fn lex_bold(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
    #|  generated_lex_bold(source, pos)
    #|}
    #|
    #|fn lex_calm_line(source : String, pos : Int) -> (@core.LexStep[Token], LexMode) {
    #|  custom_lex_calm_line(source, pos)
    #|}
    #|
  assert_eq(migration_property_render_skeleton(case, false), existing)
  assert_eq(migration_property_render_skeleton(case, true), expected)
  migration_property_check_case(case)
}

///|
test "line skeleton migration basis covers ownership and selection classes" {
  let cases = migration_property_basis_cases()
  let selected_ownerships = Array::make(8, false)
  let identifier_depths = Array::make(4, false)
  let mut saw_unselected_canonical = false
  let mut saw_empty = false
  let mut saw_singleton = false
  let mut saw_multiple = false
  let mut saw_duplicate = false
  let mut saw_reordered = false
  let mut saw_minimum_mode_count = false
  let mut saw_maximum_mode_count = false
  for case in cases {
    migration_property_check_case(case)
    if case.modes.length() == 1 {
      saw_minimum_mode_count = true
    }
    if case.modes.length() == 7 {
      saw_maximum_mode_count = true
    }
    for mode in case.modes {
      identifier_depths[mode.component_count] = true
      if migration_property_contains(case.selected_modes, mode.mode_name) {
        selected_ownerships[migration_property_ownership_index(mode.ownership)] = true
      } else if mode.ownership == MigrationCanonical {
        saw_unselected_canonical = true
      }
    }
    let deduplicated = migration_property_stable_deduplicate(
      case.selected_modes,
    )
    if case.selected_modes.length() == 0 {
      saw_empty = true
    }
    if case.selected_modes.length() == 1 {
      saw_singleton = true
    }
    if deduplicated.length() > 1 {
      saw_multiple = true
    }
    if deduplicated.length() < case.selected_modes.length() {
      saw_duplicate = true
    }
    let mut previous_index = -1
    for selected in deduplicated {
      let current_index = migration_property_mode_index(case.modes, selected)
      if current_index < previous_index {
        saw_reordered = true
      }
      previous_index = current_index
    }
  }
  for covered in selected_ownerships {
    inspect(covered, content="true")
  }
  inspect(saw_unselected_canonical, content="true")
  inspect(saw_empty, content="true")
  inspect(saw_singleton, content="true")
  inspect(saw_multiple, content="true")
  inspect(saw_duplicate, content="true")
  inspect(saw_reordered, content="true")
  inspect(saw_minimum_mode_count, content="true")
  inspect(saw_maximum_mode_count, content="true")
  inspect(identifier_depths[1], content="true")
  inspect(identifier_depths[2], content="true")
  inspect(identifier_depths[3], content="true")
}

///|
fn migration_property_assert_unique_names(case : MigrationCase) -> Unit {
  if case.modes.length() < 1 || case.modes.length() > 7 {
    abort("migration cases need one to seven modes")
  }
  for i, left in case.modes {
    for j in (i + 1)..<case.modes.length() {
      let right = case.modes[j]
      if left.mode_name == right.mode_name ||
        left.fn_name == right.fn_name ||
        left.helper_name == right.helper_name {
        abort("migration case contains colliding generated identifiers")
      }
    }
  }
  for selected in case.selected_modes {
    ignore(migration_property_mode_index(case.modes, selected))
  }
}

///|
fn migration_property_pick(random : @splitmix.RandomState, modulo : Int) -> Int {
  if modulo <= 0 {
    abort("migration_property_pick requires a positive modulo")
  }
  (random.next_uint() % modulo.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn migration_property_shuffle_ints(
  values : Array[Int],
  random : @splitmix.RandomState,
) -> Unit {
  for i = values.length() - 1; i > 0; i = i - 1 {
    let j = migration_property_pick(random, i + 1)
    let value = values[i]
    values[i] = values[j]
    values[j] = value
  }
}

///|
fn migration_property_shuffle_strings(
  values : Array[String],
  random : @splitmix.RandomState,
) -> Unit {
  for i = values.length() - 1; i > 0; i = i - 1 {
    let j = migration_property_pick(random, i + 1)
    let value = values[i]
    values[i] = values[j]
    values[j] = value
  }
}

///|
fn migration_property_ownership_from_pick(index : Int) -> MigrationOwnership {
  match index {
    0 => MigrationCanonical
    1 => MigrationAlreadyDelegated
    2 => MigrationHandwritten
    3 => MigrationMutatedAbortMessage
    4 => MigrationMutatedWhitespace
    5 => MigrationMutatedSignature
    6 => MigrationCommentInserted
    7 => MigrationAbsent
    _ => abort("migration ownership pick is out of bounds")
  }
}

///|
impl @quickcheck.Arbitrary for MigrationCase with fn arbitrary(_size, random) {
  let first_word_indices : Array[Int] = []
  for i in 0..<migration_property_words().length() {
    first_word_indices.push(i)
  }
  migration_property_shuffle_ints(first_word_indices, random)
  let mode_count = 1 + migration_property_pick(random, 7)
  let modes : Array[MigrationMode] = []
  for i in 0..<mode_count {
    let component_count = 1 + migration_property_pick(random, 3)
    let word_indices = [first_word_indices[i]]
    for _ in 1..<component_count {
      word_indices.push(
        migration_property_pick(random, migration_property_words().length()),
      )
    }
    modes.push(
      migration_property_mode(
        word_indices,
        migration_property_ownership_from_pick(
          migration_property_pick(random, 8),
        ),
      ),
    )
  }
  let selected_modes : Array[String] = []
  match migration_property_pick(random, 5) {
    0 => ()
    1 =>
      selected_modes.push(
        modes[migration_property_pick(random, modes.length())].mode_name,
      )
    2 => {
      for mode in modes {
        if migration_property_pick(random, 2) == 0 {
          selected_modes.push(mode.mode_name)
        }
      }
      if selected_modes.length() == 0 {
        selected_modes.push(
          modes[migration_property_pick(random, modes.length())].mode_name,
        )
      }
    }
    3 =>
      for mode in modes {
        selected_modes.push(mode.mode_name)
      }
    _ => {
      for mode in modes {
        selected_modes.push(mode.mode_name)
      }
      selected_modes.push(
        selected_modes[migration_property_pick(random, selected_modes.length())],
      )
    }
  }
  migration_property_shuffle_strings(selected_modes, random)
  let case = { modes, selected_modes }
  migration_property_assert_unique_names(case)
  case
}

///|
fn migration_property_fixed_seed_cases() -> Array[MigrationCase] {
  let seeds : Array[UInt64] = [
    0UL, 1UL, 2UL, 3UL, 4UL, 5UL, 6UL, 7UL, 8UL, 9UL, 10UL, 11UL, 12UL, 13UL, 14UL,
    15UL, 16UL, 17UL, 18UL, 19UL, 20UL, 21UL, 22UL, 23UL, 24UL, 25UL, 26UL, 27UL,
    28UL, 29UL, 30UL, 31UL,
  ]
  let cases : Array[MigrationCase] = []
  for seed in seeds {
    let random = @splitmix.new(seed~)
    let case : MigrationCase = @quickcheck.Arbitrary::arbitrary(12, random)
    cases.push(case)
  }
  cases
}

///|
test "property: structural line skeleton migration matches exact oracle" {
  let basis_cases = migration_property_basis_cases()
  let fixed_seed_cases = migration_property_fixed_seed_cases()
  let generated_cases : Array[MigrationCase] = @quickcheck.samples(96)
  for case in basis_cases {
    migration_property_check_case(case)
  }
  for case in fixed_seed_cases {
    migration_property_check_case(case)
  }
  for case in generated_cases {
    migration_property_check_case(case)
  }

  let generated_ownerships = Array::make(8, false)
  let generated_identifier_depths = Array::make(4, false)
  let mut saw_empty = false
  let mut saw_singleton = false
  let mut saw_multiple = false
  let mut saw_duplicate = false
  let mut saw_reordered = false
  let mut saw_acronym = false
  let mut saw_digit = false
  for case in fixed_seed_cases {
    for mode in case.modes {
      generated_ownerships[migration_property_ownership_index(mode.ownership)] = true
      generated_identifier_depths[mode.component_count] = true
      if mode.mode_name.contains("HTTP") {
        saw_acronym = true
      }
      if mode.mode_name.contains("V2Id") {
        saw_digit = true
      }
    }
    let deduplicated = migration_property_stable_deduplicate(
      case.selected_modes,
    )
    if case.selected_modes.length() == 0 {
      saw_empty = true
    }
    if case.selected_modes.length() == 1 {
      saw_singleton = true
    }
    if deduplicated.length() > 1 {
      saw_multiple = true
    }
    if deduplicated.length() < case.selected_modes.length() {
      saw_duplicate = true
    }
    let mut previous_index = -1
    for selected in deduplicated {
      let current_index = migration_property_mode_index(case.modes, selected)
      if current_index < previous_index {
        saw_reordered = true
      }
      previous_index = current_index
    }
  }
  for covered in generated_ownerships {
    inspect(covered, content="true")
  }
  inspect(generated_identifier_depths[1], content="true")
  inspect(generated_identifier_depths[2], content="true")
  inspect(generated_identifier_depths[3], content="true")
  inspect(saw_empty, content="true")
  inspect(saw_singleton, content="true")
  inspect(saw_multiple, content="true")
  inspect(saw_duplicate, content="true")
  inspect(saw_reordered, content="true")
  inspect(saw_acronym, content="true")
  inspect(saw_digit, content="true")
}
