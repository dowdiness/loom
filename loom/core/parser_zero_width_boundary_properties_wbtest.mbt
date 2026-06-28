// Property coverage for repeated zero-width boundary-token reuse.
// Reuses TestTok/TestKind from parser_wbtest.mbt.

///|
enum ZeroWidthReuseShape {
  RegularNodes
  RepeatGroups
} derive(Debug, Eq)

///|
enum ZeroWidthOldTreeMode {
  PlainOldTree
  TokenInternedOldTree
  FullyInternedOldTree
} derive(Debug, Eq)

///|
enum ZeroWidthEditKind {
  EditItemDigit
  GrowBoundaryTrivia
  ShrinkBoundaryTrivia
} derive(Debug, Eq)

///|
struct ZeroWidthBoundaryCase {
  shape : ZeroWidthReuseShape
  old_tree_mode : ZeroWidthOldTreeMode
  edit_kind : ZeroWidthEditKind
  item_count : Int
  edit_index : Int
  synthetic_count : Int
  old_values : Array[Int]
  new_values : Array[Int]
  old_gaps : Array[Int]
  new_gaps : Array[Int]
  old_boundary_counts : Array[Int]
  new_boundary_counts : Array[Int]
}

///|
fn zero_width_shape_uses_repeat_groups(shape : ZeroWidthReuseShape) -> Bool {
  match shape {
    RegularNodes => false
    RepeatGroups => true
  }
}

///|
fn zero_width_record_repeat_hit(counter : Array[Int]?) -> Unit {
  match counter {
    None => ()
    Some(values) => {
      if values.length() != 1 {
        abort("repeat-group hit counter must be a single-cell array")
      }
      values[0] = values[0] + 1
    }
  }
}

///|
fn zero_width_parse_item_body(
  ctx : ParserContext[TestTok, TestKind],
  synthetic_count : Int,
) -> Unit {
  ctx.emit_token(KNum)
  while ctx.at(TestTok::Plus) {
    ctx.emit_token(KPlus)
  }
  for _ in 0..<synthetic_count {
    ctx.emit_zero_width(KPlus)
  }
}

///|
fn zero_width_parse_items(
  ctx : ParserContext[TestTok, TestKind],
  use_repeat_groups : Bool,
  synthetic_count : Int,
  repeat_group_hits : Array[Int]?,
) -> Unit {
  let mut parsed_repeat_prefix = false
  while !ctx.at_eof() {
    match ctx.peek() {
      Num(_) => {
        if use_repeat_groups && !parsed_repeat_prefix {
          parsed_repeat_prefix = true
          ctx.node(KPlus, fn() {
            zero_width_parse_item_body(ctx, synthetic_count)
          })
          continue
        }
        if use_repeat_groups && ctx.try_reuse_repeat_group() {
          zero_width_record_repeat_hit(repeat_group_hits)
          continue
        }
        ctx.node(KExpr, fn() {
          zero_width_parse_item_body(ctx, synthetic_count)
        })
      }
      _ => ctx.bump_error()
    }
  }
}

///|
fn zero_width_boundary_spec(
  use_repeat_groups : Bool,
  synthetic_count : Int,
  repeat_group_hits? : Array[Int]? = None,
) -> LanguageSpec[TestTok, TestKind] {
  LanguageSpec::new(
    KWs,
    KErr,
    KRoot,
    TestTok::TokEof,
    incomplete_kind=KIncomplete,
    parse_root=fn(ctx) {
      zero_width_parse_items(
        ctx, use_repeat_groups, synthetic_count, repeat_group_hits,
      )
    },
    reuse_size_threshold=0,
  )
}

///|
fn zero_width_source(values : Array[Int], gaps : Array[Int]) -> String {
  if values.length() == 0 {
    abort("zero-width property case must contain at least one item")
  }
  if gaps.length() != values.length() - 1 {
    abort("gap count must be item_count - 1")
  }
  let buf = StringBuilder::new()
  for i in 0..<values.length() {
    let value = values[i]
    if value < 0 || value > 9 {
      abort("item values must be single decimal digits")
    }
    buf.write_char((48 + value).unsafe_to_char())
    if i < gaps.length() {
      let gap = gaps[i]
      if gap <= 0 {
        abort("item gaps must stay positive so numbers do not merge")
      }
      for _ in 0..<gap {
        buf.write_string(" ")
      }
    }
  }
  buf.to_string()
}

///|
fn zero_width_tokenize_with_boundaries(
  src : String,
  boundary_counts : Array[Int],
) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  let mut item_index = 0
  while i < src.length() {
    let code = src.code_unit_at(i).to_int()
    if code == 32 {
      let start = i
      while i < src.length() && src.code_unit_at(i).to_int() == 32 {
        i = i + 1
      }
      result.push(TokenInfo::new(TestTok::Ws, i - start))
    } else if code >= 48 && code <= 57 {
      let start = i
      let mut n = code - 48
      i = i + 1
      while i < src.length() {
        let d = src.code_unit_at(i).to_int()
        if d >= 48 && d <= 57 {
          n = n * 10 + d - 48
          i = i + 1
        } else {
          break
        }
      }
      if item_index >= boundary_counts.length() {
        abort("boundary count array is shorter than the tokenized item list")
      }
      result.push(TokenInfo::new(TestTok::Num(n), i - start))
      let count = boundary_counts[item_index]
      if count < 0 {
        abort("zero-width boundary multiplicity must be non-negative")
      }
      for _ in 0..<count {
        result.push(TokenInfo::new(TestTok::Plus, 0))
      }
      item_index = item_index + 1
    } else {
      abort("zero-width property source contains an unsupported character")
    }
  }
  if item_index != boundary_counts.length() {
    abort("boundary count array is longer than the tokenized item list")
  }
  result
}

///|
fn zero_width_edit_from_sources(old_src : String, new_src : String) -> Edit {
  let change = @shared_text_change.compute_text_change(old_src, new_src)
  if change.is_noop() {
    abort("zero-width property case must include a real source edit")
  }
  Edit::new(change.start, change.delete_len, change.inserted.length())
}

///|
fn zero_width_build_tree_from_events(
  ctx : ParserContext[TestTok, TestKind],
  spec : LanguageSpec[TestTok, TestKind],
  mode : ZeroWidthOldTreeMode,
) -> @seam.CstNode {
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort("zero-width property grammar left nodes unclosed")
  }
  if !ctx.at_eof() {
    abort("zero-width property grammar did not consume the token stream")
  }
  if ctx.diagnostics.length() != 0 {
    abort("zero-width property grammar unexpectedly emitted diagnostics")
  }
  match mode {
    PlainOldTree =>
      build_tree_generic(ctx.events, spec) catch {
        _ => abort("expected plain old tree to build")
      }
    TokenInternedOldTree =>
      ctx.events.build_tree_interned(
        spec.root_kind.to_raw(),
        @seam.Interner::new(),
        trivia_kinds=Some([spec.whitespace_kind.to_raw()]),
        error_kind=Some(spec.error_kind.to_raw()),
        incomplete_kind=Some(spec.incomplete_kind.to_raw()),
      ) catch {
        _ => abort("expected token-interned old tree to build")
      }
    FullyInternedOldTree =>
      ctx.events.build_tree_fully_interned(
        spec.root_kind.to_raw(),
        @seam.Interner::new(),
        @seam.NodeInterner::new(),
        trivia_kinds=Some([spec.whitespace_kind.to_raw()]),
        error_kind=Some(spec.error_kind.to_raw()),
        incomplete_kind=Some(spec.incomplete_kind.to_raw()),
      ) catch {
        _ => abort("expected fully-interned old tree to build")
      }
  }
}

///|
fn zero_width_parse_old_tree(
  source : String,
  boundary_counts : Array[Int],
  spec : LanguageSpec[TestTok, TestKind],
  mode : ZeroWidthOldTreeMode,
) -> @seam.CstNode {
  let tokens = zero_width_tokenize_with_boundaries(source, boundary_counts)
  let ctx = ParserContext::new(tokens, source, spec)
  (spec.parse_root)(ctx)
  zero_width_build_tree_from_events(ctx, spec, mode)
}

///|
fn zero_width_parse_indexed(
  source : String,
  boundary_counts : Array[Int],
  spec : LanguageSpec[TestTok, TestKind],
  cursor? : ReuseCursor[TestTok, TestKind]? = None,
) -> (@seam.CstNode, DiagnosticSet, Int) {
  let tokens = zero_width_tokenize_with_boundaries(source, boundary_counts)
  let starts = build_starts(tokens)
  parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) { starts[i] + tokens[i].len },
    spec,
    cursor~,
  )
}

///|
fn zero_width_new_cursor(
  old_tree : @seam.CstNode,
  new_src : String,
  new_boundary_counts : Array[Int],
  edit : Edit,
  spec : LanguageSpec[TestTok, TestKind],
) -> ReuseCursor[TestTok, TestKind] {
  let tokens = zero_width_tokenize_with_boundaries(new_src, new_boundary_counts)
  let starts = build_starts(tokens)
  let cache = OldTokenCache::empty()
  cache.apply_source_edit(edit)
  ReuseCursor::new_with_edit(
    old_tree,
    edit,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { starts[i] },
    fn(i) {
      new_src.view(start_offset=starts[i], end_offset=starts[i] + tokens[i].len)
    },
    spec,
    old_token_cache=cache,
  )
}

///|
fn zero_width_contains_repeat_group(node : @seam.CstNode) -> Bool {
  if node.kind == @seam.repeat_group_kind {
    return true
  }
  for child in node.children {
    match child {
      @seam.CstElement::Node(child_node) =>
        if zero_width_contains_repeat_group(child_node) {
          return true
        }
      @seam.CstElement::Token(_) => ()
    }
  }
  false
}

///|
fn zero_width_case_summary(
  case : ZeroWidthBoundaryCase,
  old_src : String,
  new_src : String,
  edit : Edit,
) -> String {
  "shape=" +
  @debug.to_string(case.shape) +
  " mode=" +
  @debug.to_string(case.old_tree_mode) +
  " edit_kind=" +
  @debug.to_string(case.edit_kind) +
  " item_count=" +
  @debug.to_string(case.item_count) +
  " edit_index=" +
  @debug.to_string(case.edit_index) +
  " synthetic_count=" +
  @debug.to_string(case.synthetic_count) +
  " old_src=\"" +
  old_src +
  "\"" +
  " new_src=\"" +
  new_src +
  "\"" +
  " edit=" +
  edit.to_string() +
  " old_boundaries=" +
  @debug.to_string(case.old_boundary_counts) +
  " new_boundaries=" +
  @debug.to_string(case.new_boundary_counts)
}

///|
fn zero_width_validate_case(case : ZeroWidthBoundaryCase) -> Unit {
  if case.item_count <= 0 {
    abort("item_count must be positive")
  }
  if case.edit_index < 0 || case.edit_index >= case.item_count {
    abort("edit_index must point at an item")
  }
  if case.synthetic_count < 0 {
    abort("synthetic_count must be non-negative")
  }
  if case.old_values.length() != case.item_count ||
    case.new_values.length() != case.item_count ||
    case.old_boundary_counts.length() != case.item_count ||
    case.new_boundary_counts.length() != case.item_count {
    abort("value and boundary arrays must match item_count")
  }
  if case.old_gaps.length() != case.item_count - 1 ||
    case.new_gaps.length() != case.item_count - 1 {
    abort("gap arrays must have item_count - 1 entries")
  }
  match case.shape {
    RegularNodes =>
      if case.item_count >= 9 {
        abort("regular-node cases must stay below RepeatGroup threshold")
      }
    RepeatGroups =>
      if case.item_count <= 9 {
        abort("RepeatGroup cases need one prefix item plus >8 grouped items")
      }
  }
}

///|
fn zero_width_check_case(case : ZeroWidthBoundaryCase) -> (Int, Int) {
  zero_width_validate_case(case)
  let old_src = zero_width_source(case.old_values, case.old_gaps)
  let new_src = zero_width_source(case.new_values, case.new_gaps)
  let edit = zero_width_edit_from_sources(old_src, new_src)
  let use_repeat_groups = zero_width_shape_uses_repeat_groups(case.shape)
  let old_spec = zero_width_boundary_spec(
    use_repeat_groups,
    case.synthetic_count,
  )
  let old_tree = zero_width_parse_old_tree(
    old_src,
    case.old_boundary_counts,
    old_spec,
    case.old_tree_mode,
  )
  let has_repeat_group = zero_width_contains_repeat_group(old_tree)
  match case.shape {
    RegularNodes =>
      if has_repeat_group {
        abort("regular-node case unexpectedly built a RepeatGroup")
      }
    RepeatGroups =>
      if !has_repeat_group {
        abort("RepeatGroup case did not build a RepeatGroup")
      }
  }

  let full_spec = zero_width_boundary_spec(
    use_repeat_groups,
    case.synthetic_count,
  )
  let (full_tree, full_diagnostics, _) = zero_width_parse_indexed(
    new_src,
    case.new_boundary_counts,
    full_spec,
  )

  let repeat_group_hits = [0]
  let incremental_spec = zero_width_boundary_spec(
    use_repeat_groups,
    case.synthetic_count,
    repeat_group_hits=Some(repeat_group_hits),
  )
  let cursor = zero_width_new_cursor(
    old_tree,
    new_src,
    case.new_boundary_counts,
    edit,
    incremental_spec,
  )
  let (incremental_tree, incremental_diagnostics, reuse_count) = zero_width_parse_indexed(
    new_src,
    case.new_boundary_counts,
    incremental_spec,
    cursor=Some(cursor),
  )
  let summary = zero_width_case_summary(case, old_src, new_src, edit)
  if incremental_tree != full_tree {
    abort("incremental CST differs from full reparse: " + summary)
  }
  if incremental_diagnostics != full_diagnostics {
    abort("incremental diagnostics differ from full reparse: " + summary)
  }
  (reuse_count, repeat_group_hits[0])
}

///|
fn zero_width_next_seed(seed : Int) -> Int {
  let a = 1103515245
  let c = 12345
  let m = 2147483647
  (seed * a + c) % m
}

///|
fn zero_width_pick(seed : Int, salt : Int, modulo : Int) -> Int {
  if modulo <= 0 {
    abort("zero_width_pick requires a positive modulo")
  }
  let mixed = zero_width_next_seed(seed + salt * 7919)
  mixed.abs() % modulo
}

///|
fn zero_width_values_from_seed(
  seed : Int,
  item_count : Int,
  salt : Int,
) -> Array[Int] {
  let values : Array[Int] = []
  for i in 0..<item_count {
    values.push(zero_width_pick(seed, salt + i, 10))
  }
  values
}

///|
fn zero_width_gaps_from_seed(
  seed : Int,
  item_count : Int,
  salt : Int,
) -> Array[Int] {
  let gaps : Array[Int] = []
  for i in 0..<(item_count - 1) {
    gaps.push(1 + zero_width_pick(seed, salt + i, 3))
  }
  gaps
}

///|
fn zero_width_boundary_counts_from_seed(
  seed : Int,
  item_count : Int,
  salt : Int,
) -> Array[Int] {
  let counts : Array[Int] = []
  for i in 0..<item_count {
    counts.push(zero_width_pick(seed, salt + i, 5))
  }
  counts
}

///|
fn zero_width_gap_index_for_edit(edit_index : Int, item_count : Int) -> Int {
  if item_count <= 1 {
    abort("gap edit cases need at least two items")
  }
  if edit_index >= item_count - 1 {
    item_count - 2
  } else {
    edit_index
  }
}

///|
fn zero_width_changed_boundary_count(
  seed : Int,
  index : Int,
  current : Int,
) -> Int {
  let replacement = zero_width_pick(seed, 400 + index, 5)
  if replacement == current {
    (replacement + 1) % 5
  } else {
    replacement
  }
}

///|
fn zero_width_case_from_seed(seed : Int) -> ZeroWidthBoundaryCase {
  let shape = if zero_width_pick(seed, 1, 2) == 0 {
    ZeroWidthReuseShape::RegularNodes
  } else {
    ZeroWidthReuseShape::RepeatGroups
  }
  let item_count = match shape {
    RegularNodes => 4 + zero_width_pick(seed, 2, 4)
    RepeatGroups => 12 + zero_width_pick(seed, 2, 5)
  }
  let old_tree_mode = match zero_width_pick(seed, 3, 3) {
    0 => ZeroWidthOldTreeMode::PlainOldTree
    1 => ZeroWidthOldTreeMode::TokenInternedOldTree
    _ => ZeroWidthOldTreeMode::FullyInternedOldTree
  }
  let edit_kind = match zero_width_pick(seed, 4, 3) {
    0 => ZeroWidthEditKind::EditItemDigit
    1 => ZeroWidthEditKind::GrowBoundaryTrivia
    _ => ZeroWidthEditKind::ShrinkBoundaryTrivia
  }
  let edit_index = match shape {
    RepeatGroups =>
      match zero_width_pick(seed, 5, 4) {
        0 => 0
        1 => 1
        2 => item_count / 2
        _ => item_count - 1
      }
    RegularNodes => zero_width_pick(seed, 5, item_count)
  }
  let synthetic_count = zero_width_pick(seed, 6, 3)
  let old_values = zero_width_values_from_seed(seed, item_count, 100)
  let new_values = old_values.copy()
  let old_gaps = zero_width_gaps_from_seed(seed, item_count, 200)
  let new_gaps = old_gaps.copy()
  let old_boundary_counts = zero_width_boundary_counts_from_seed(
    seed, item_count, 300,
  )
  let new_boundary_counts = old_boundary_counts.copy()
  match edit_kind {
    EditItemDigit => {
      new_values[edit_index] = (old_values[edit_index] + 1) % 10
      new_boundary_counts[edit_index] = zero_width_changed_boundary_count(
        seed,
        edit_index,
        old_boundary_counts[edit_index],
      )
    }
    GrowBoundaryTrivia => {
      let gap_index = zero_width_gap_index_for_edit(edit_index, item_count)
      new_gaps[gap_index] = old_gaps[gap_index] + 1
    }
    ShrinkBoundaryTrivia => {
      let gap_index = zero_width_gap_index_for_edit(edit_index, item_count)
      if old_gaps[gap_index] <= 1 {
        old_gaps[gap_index] = 2
      }
      new_gaps[gap_index] = old_gaps[gap_index] - 1
    }
  }
  {
    shape,
    old_tree_mode,
    edit_kind,
    item_count,
    edit_index,
    synthetic_count,
    old_values,
    new_values,
    old_gaps,
    new_gaps,
    old_boundary_counts,
    new_boundary_counts,
  }
}

///|
fn zero_width_default_values(item_count : Int) -> Array[Int] {
  let values : Array[Int] = []
  for i in 0..<item_count {
    values.push((i + 1) % 10)
  }
  values
}

///|
fn zero_width_default_gaps(item_count : Int, gap_width : Int) -> Array[Int] {
  let gaps : Array[Int] = []
  for _ in 0..<(item_count - 1) {
    gaps.push(gap_width)
  }
  gaps
}

///|
fn zero_width_basis_case(
  shape : ZeroWidthReuseShape,
  old_tree_mode : ZeroWidthOldTreeMode,
  edit_kind : ZeroWidthEditKind,
  synthetic_count : Int,
  old_boundary_counts : Array[Int],
  new_boundary_counts : Array[Int],
  edit_index? : Int? = None,
) -> ZeroWidthBoundaryCase {
  let item_count = old_boundary_counts.length()
  if item_count == 0 || new_boundary_counts.length() != item_count {
    abort("basis boundary arrays must be non-empty and equally sized")
  }
  let selected_edit_index = match edit_index {
    None =>
      match shape {
        RepeatGroups => 0
        RegularNodes => item_count / 2
      }
    Some(index) => index
  }
  if selected_edit_index < 0 || selected_edit_index >= item_count {
    abort("basis edit_index must point at an item")
  }
  let old_values = zero_width_default_values(item_count)
  let new_values = old_values.copy()
  let old_gaps = zero_width_default_gaps(item_count, 2)
  let new_gaps = old_gaps.copy()
  match edit_kind {
    EditItemDigit =>
      new_values[selected_edit_index] = (old_values[selected_edit_index] + 3) %
        10
    GrowBoundaryTrivia => {
      let gap_index = zero_width_gap_index_for_edit(
        selected_edit_index, item_count,
      )
      new_gaps[gap_index] = old_gaps[gap_index] + 1
    }
    ShrinkBoundaryTrivia => {
      let gap_index = zero_width_gap_index_for_edit(
        selected_edit_index, item_count,
      )
      new_gaps[gap_index] = old_gaps[gap_index] - 1
    }
  }
  {
    shape,
    old_tree_mode,
    edit_kind,
    item_count,
    edit_index: selected_edit_index,
    synthetic_count,
    old_values,
    new_values,
    old_gaps,
    new_gaps,
    old_boundary_counts,
    new_boundary_counts,
  }
}

///|
fn zero_width_basis_cases() -> Array[ZeroWidthBoundaryCase] {
  [
    zero_width_basis_case(
      RegularNodes,
      PlainOldTree,
      EditItemDigit,
      0,
      [0, 1, 2, 3, 4, 1],
      [0, 1, 2, 0, 4, 1],
    ),
    zero_width_basis_case(
      RegularNodes,
      TokenInternedOldTree,
      GrowBoundaryTrivia,
      1,
      [3, 0, 1, 2, 4, 0],
      [3, 0, 1, 2, 4, 0],
    ),
    zero_width_basis_case(
      RegularNodes,
      PlainOldTree,
      ShrinkBoundaryTrivia,
      2,
      [4, 3, 2, 1, 0, 4],
      [4, 3, 2, 1, 0, 4],
    ),
    zero_width_basis_case(
      RepeatGroups,
      FullyInternedOldTree,
      EditItemDigit,
      2,
      [0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1],
      [4, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1],
    ),
    zero_width_basis_case(
      RepeatGroups,
      PlainOldTree,
      EditItemDigit,
      1,
      [4, 3, 2, 1, 0, 4, 3, 2, 1, 0, 4, 3],
      [0, 3, 2, 1, 0, 4, 3, 2, 1, 0, 4, 3],
    ),
    zero_width_basis_case(
      RepeatGroups,
      TokenInternedOldTree,
      GrowBoundaryTrivia,
      1,
      [0, 3, 1, 4, 2, 0, 3, 1, 4, 2, 0, 3],
      [0, 3, 1, 4, 2, 0, 3, 1, 4, 2, 0, 3],
      edit_index=Some(0),
    ),
    zero_width_basis_case(
      RepeatGroups,
      TokenInternedOldTree,
      EditItemDigit,
      2,
      [1, 0, 2, 4, 3, 1, 0, 2, 4, 3, 1, 0],
      [1, 0, 2, 4, 3, 1, 4, 2, 4, 3, 1, 0],
      edit_index=Some(6),
    ),
    zero_width_basis_case(
      RepeatGroups,
      FullyInternedOldTree,
      ShrinkBoundaryTrivia,
      2,
      [2, 4, 0, 3, 1, 2, 4, 0, 3, 1, 2, 4],
      [2, 4, 0, 3, 1, 2, 4, 0, 3, 1, 2, 4],
      edit_index=Some(10),
    ),
  ]
}

///|
fn zero_width_count_class(count : Int) -> Int {
  if count < 0 {
    abort("boundary count class requires a non-negative count")
  }
  if count >= 3 {
    3
  } else {
    count
  }
}

///|
test "property: repeated zero-width boundary-token reuse matches full reparse" {
  let cases = zero_width_basis_cases()
  let seeds : Array[Int] = @quickcheck.samples(96)
  for seed in seeds {
    cases.push(zero_width_case_from_seed(seed))
  }

  let count_classes = Array::make(4, false)
  let repeat_grouped_count_classes = Array::make(4, false)
  let mut saw_regular = false
  let mut saw_repeat = false
  let mut saw_synthetic = false
  let mut saw_plain = false
  let mut saw_token_interned = false
  let mut saw_fully_interned = false
  let mut saw_digit_edit = false
  let mut saw_grow_edit = false
  let mut saw_shrink_edit = false
  let mut saw_boundary_count_change = false
  let mut saw_repeat_prefix_edit = false
  let mut saw_repeat_pre_group_gap_edit = false
  let mut saw_repeat_grouped_digit_edit = false
  let mut saw_repeat_grouped_gap_edit = false
  let mut saw_repeat_grouped_boundary_count_change = false
  let mut saw_repeat_grouped_edit_repeat_group_reuse = false
  let mut saw_regular_reuse = false
  let mut saw_repeat_group_reuse = false

  for case in cases {
    match case.shape {
      RegularNodes => saw_regular = true
      RepeatGroups => {
        saw_repeat = true
        for i in 1..<case.item_count {
          repeat_grouped_count_classes[zero_width_count_class(
            case.old_boundary_counts[i],
          )] = true
          repeat_grouped_count_classes[zero_width_count_class(
            case.new_boundary_counts[i],
          )] = true
          if case.old_boundary_counts[i] != case.new_boundary_counts[i] {
            saw_repeat_grouped_boundary_count_change = true
          }
        }
        match case.edit_kind {
          EditItemDigit =>
            if case.edit_index == 0 {
              saw_repeat_prefix_edit = true
            } else {
              saw_repeat_grouped_digit_edit = true
            }
          GrowBoundaryTrivia | ShrinkBoundaryTrivia => {
            let gap_index = zero_width_gap_index_for_edit(
              case.edit_index,
              case.item_count,
            )
            if gap_index == 0 {
              saw_repeat_pre_group_gap_edit = true
            } else {
              saw_repeat_grouped_gap_edit = true
            }
          }
        }
      }
    }
    match case.old_tree_mode {
      PlainOldTree => saw_plain = true
      TokenInternedOldTree => saw_token_interned = true
      FullyInternedOldTree => saw_fully_interned = true
    }
    match case.edit_kind {
      EditItemDigit => saw_digit_edit = true
      GrowBoundaryTrivia => saw_grow_edit = true
      ShrinkBoundaryTrivia => saw_shrink_edit = true
    }
    if case.synthetic_count > 0 {
      saw_synthetic = true
    }
    for count in case.old_boundary_counts {
      count_classes[zero_width_count_class(count)] = true
    }
    for count in case.new_boundary_counts {
      count_classes[zero_width_count_class(count)] = true
    }
    for i in 0..<case.item_count {
      if case.old_boundary_counts[i] != case.new_boundary_counts[i] {
        saw_boundary_count_change = true
      }
    }

    let (reuse_count, repeat_group_hits) = zero_width_check_case(case)
    match case.shape {
      RegularNodes => if reuse_count > 0 { saw_regular_reuse = true }
      RepeatGroups => {
        if repeat_group_hits > 0 {
          saw_repeat_group_reuse = true
        }
        if case.edit_index > 0 && repeat_group_hits > 0 {
          saw_repeat_grouped_edit_repeat_group_reuse = true
        }
      }
    }
  }

  inspect(saw_regular, content="true")
  inspect(saw_repeat, content="true")
  inspect(saw_synthetic, content="true")
  inspect(saw_plain, content="true")
  inspect(saw_token_interned, content="true")
  inspect(saw_fully_interned, content="true")
  inspect(saw_digit_edit, content="true")
  inspect(saw_grow_edit, content="true")
  inspect(saw_shrink_edit, content="true")
  inspect(saw_boundary_count_change, content="true")
  inspect(saw_repeat_prefix_edit, content="true")
  inspect(saw_repeat_pre_group_gap_edit, content="true")
  inspect(saw_repeat_grouped_digit_edit, content="true")
  inspect(saw_repeat_grouped_gap_edit, content="true")
  inspect(saw_repeat_grouped_boundary_count_change, content="true")
  inspect(saw_repeat_grouped_edit_repeat_group_reuse, content="true")
  inspect(saw_regular_reuse, content="true")
  inspect(saw_repeat_group_reuse, content="true")
  inspect(count_classes[0], content="true")
  inspect(count_classes[1], content="true")
  inspect(count_classes[2], content="true")
  inspect(count_classes[3], content="true")
  inspect(repeat_grouped_count_classes[0], content="true")
  inspect(repeat_grouped_count_classes[1], content="true")
  inspect(repeat_grouped_count_classes[2], content="true")
  inspect(repeat_grouped_count_classes[3], content="true")
}
