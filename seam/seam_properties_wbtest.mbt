///|
/// Generate a small number of token events deterministically from a seed.
fn token_events(seed : Int, count_raw : Int) -> Array[ParseEvent] {
  let texts = ["x", "y", "0", "1", "(", ")"]
  let count = count_raw.abs() % 8
  let events : Array[ParseEvent] = []
  let mut s = seed
  for _ in 0..<count {
    s = s * 1103515245 + 12345
    let kind = RawKind(s.abs() % 8 + 1)
    let text = texts[s.abs() % texts.length()]
    events.push(ParseEvent::Token(kind, text))
  }
  events
}

///|
test "property: build_tree hash is deterministic" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, count) = input
    let root1 = try! build_tree(token_events(seed, count), RawKind(0))
    let root2 = try! build_tree(token_events(seed, count), RawKind(0))
    root1.hash == root2.hash
  })
}

///|
test "property: build_tree preserves total text length" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (seed, count) = input
    let events = token_events(seed, count)
    let expected = events.fold(init=0, fn(acc, e) {
      match e {
        ParseEvent::Token(_, text) => acc + text.length()
        _ => acc
      }
    })
    let root = try! build_tree(events, RawKind(0))
    root.text_len == expected
  })
}

///|
/// Build a CST with two nested child nodes (each holding some tokens) and
/// verify that the resulting SyntaxNode children have contiguous, monotonic
/// offsets that partition the root span.
test "property: SyntaxNode child offsets are contiguous" {
  @qc.quick_check_fn(fn(input : (Int, Int)) -> Bool {
    let (count1_raw, count2_raw) = input
    let count1 = count1_raw.abs() % 4 + 1
    let count2 = count2_raw.abs() % 4 + 1
    let events : Array[ParseEvent] = []
    events.push(ParseEvent::StartNode(RawKind(1)))
    for _ in 0..<count1 {
      events.push(ParseEvent::Token(RawKind(2), "x"))
    }
    events.push(ParseEvent::FinishNode)
    events.push(ParseEvent::StartNode(RawKind(1)))
    for _ in 0..<count2 {
      events.push(ParseEvent::Token(RawKind(2), "y"))
    }
    events.push(ParseEvent::FinishNode)
    let cst = try! build_tree(events, RawKind(0))
    let root = SyntaxNode::from_cst(cst)
    let children = root.children()
    let (final_cursor, all_ok) = children.fold(init=(root.start(), true), (
      acc,
      child,
    ) => {
      let (cursor, ok) = acc
      (child.end(), ok && child.start() == cursor)
    })
    all_ok && root.end() == final_cursor
  })
}
