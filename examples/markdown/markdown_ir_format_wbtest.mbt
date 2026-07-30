///|
fn markdown_ir_canonical_test_origin(
  start : Int,
  end : Int,
) -> MarkdownIROrigin {
  MarkdownIROrigin::MarkdownIROrigin(start~, end~)
}

///|
fn markdown_ir_canonical_test_document_with_text(value : String) -> MarkdownIR {
  let origin = markdown_ir_canonical_test_origin(0, value.length())
  let text = MarkdownIR::text(value, origin)
  let paragraph = MarkdownIR::paragraph([text], origin, Some(origin))
  MarkdownIR::document([paragraph], origin)
}

///|
fn markdown_ir_canonical_test_candidates(
  ir : MarkdownIR,
) -> Array[MarkdownIRCanonicalCandidate] raise {
  let candidates : Array[MarkdownIRCanonicalCandidate] = []
  let mut search = markdown_ir_canonical_search_start(
    ir,
    markdown_ir_canonical_default_limits(),
  )
  while true {
    match markdown_ir_canonical_search_next_layer(search, ir) {
      CandidateLayer(next, layer) => {
        for candidate in layer {
          candidates.push(candidate)
        }
        search = next
      }
      Exhausted(_) => return candidates
      ExpansionLimited(_, failure) =>
        fail("unexpected candidate search limit: " + @debug.to_string(failure))
    }
  }
  abort("unreachable canonical test candidate search")
}

///|
fn assert_markdown_ir_canonical_semantic_distinct(
  left : MarkdownIR,
  right : MarkdownIR,
) -> Unit raise {
  assert_true(
    markdown_ir_canonical_semantic(left) !=
    markdown_ir_canonical_semantic(right),
  )
}

///|
test "checked canonical semantic comparison ignores origins and adjacent Text segmentation" {
  let wide = markdown_ir_canonical_test_origin(0, 2)
  let first = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [
          MarkdownIR::text("a", markdown_ir_canonical_test_origin(0, 1)),
          MarkdownIR::text("b", markdown_ir_canonical_test_origin(1, 2)),
        ],
        wide,
        Some(wide),
      ),
    ],
    wide,
  )
  let shifted = markdown_ir_canonical_test_origin(10, 12)
  let second = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [MarkdownIR::text("ab", shifted)],
        shifted,
        Some(shifted),
      ),
    ],
    shifted,
  )
  assert_eq(
    markdown_ir_canonical_semantic(first),
    markdown_ir_canonical_semantic(second),
  )
}

///|
test "checked canonical semantic comparison preserves meaning-bearing fields" {
  let origin = markdown_ir_canonical_test_origin(0, 1)
  let text = MarkdownIR::text("a", origin)
  let plain = MarkdownIR::document(
    [MarkdownIR::paragraph([text], origin, Some(origin))],
    origin,
  )
  let bold = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [MarkdownIR::bold([text], origin, Some(origin))],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  assert_true(
    markdown_ir_canonical_semantic(plain) !=
    markdown_ir_canonical_semantic(bold),
  )

  let dash = MarkdownIR::document(
    [MarkdownIR::unordered_list([], origin, spread=false, marker=Some(Dash))],
    origin,
  )
  let plus = MarkdownIR::document(
    [MarkdownIR::unordered_list([], origin, spread=false, marker=Some(Plus))],
    origin,
  )
  assert_eq(
    markdown_ir_canonical_semantic(dash),
    markdown_ir_canonical_semantic(plus),
  )

  let period = OrderedListMarker::OrderedListMarker(start=1, delimiter=Period)
  let paren = OrderedListMarker::OrderedListMarker(start=1, delimiter=Paren)
  let ordered_period = MarkdownIR::document(
    [MarkdownIR::ordered_list([], origin, spread=false, marker=Some(period))],
    origin,
  )
  let ordered_paren = MarkdownIR::document(
    [MarkdownIR::ordered_list([], origin, spread=false, marker=Some(paren))],
    origin,
  )
  let ordered_default = MarkdownIR::document(
    [MarkdownIR::ordered_list([], origin, spread=false, marker=None)],
    origin,
  )
  assert_eq(
    markdown_ir_canonical_semantic(ordered_period),
    markdown_ir_canonical_semantic(ordered_paren),
  )
  assert_eq(
    markdown_ir_canonical_semantic(ordered_period),
    markdown_ir_canonical_semantic(ordered_default),
  )
  let ordered_spread = MarkdownIR::document(
    [MarkdownIR::ordered_list([], origin, spread=true, marker=Some(period))],
    origin,
  )
  assert_true(
    markdown_ir_canonical_semantic(ordered_period) !=
    markdown_ir_canonical_semantic(ordered_spread),
  )
}

///|
test "checked canonical semantic comparison covers every supported payload class" {
  let origin = markdown_ir_canonical_test_origin(0, 1)
  let text_a = MarkdownIR::text("a", origin)
  let text_b = MarkdownIR::text("b", origin)
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::heading(1, [text_a], origin, Some(origin)),
    MarkdownIR::heading(2, [text_a], origin, Some(origin)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::paragraph([text_a], origin, Some(origin)),
    MarkdownIR::block_quote(
      [MarkdownIR::paragraph([text_a], origin, Some(origin))],
      origin,
    ),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::unordered_list([], origin, spread=false, marker=Some(Dash)),
    MarkdownIR::ordered_list([], origin, spread=false, marker=None),
  )
  let start_one = OrderedListMarker::OrderedListMarker(
    start=1,
    delimiter=Period,
  )
  let start_two = OrderedListMarker::OrderedListMarker(
    start=2,
    delimiter=Period,
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::ordered_list([], origin, spread=false, marker=Some(start_one)),
    MarkdownIR::ordered_list([], origin, spread=false, marker=Some(start_two)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::list_item([], origin, spread=false, None, marker=Some(Dash)),
    MarkdownIR::ordered_list_item(
      [],
      origin,
      spread=false,
      None,
      marker=Some(start_one),
    ),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::list_item([], origin, spread=false, None, marker=Some(Dash)),
    MarkdownIR::list_item([], origin, spread=true, None, marker=Some(Plus)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::code_block("mbt", "a", origin, Some(origin)),
    MarkdownIR::code_block("text", "a", origin, Some(origin)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::code_block("mbt", "a", origin, Some(origin)),
    MarkdownIR::code_block("mbt", "b", origin, Some(origin)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::html_block("<a>", origin, Some(origin)),
    MarkdownIR::html_block("<b>", origin, Some(origin)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::thematic_break(origin),
    text_a,
  )
  assert_markdown_ir_canonical_semantic_distinct(text_a, text_b)
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::bold([text_a], origin, Some(origin)),
    MarkdownIR::italic([text_a], origin, Some(origin)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::inline_code("a", origin, Some(origin)),
    MarkdownIR::inline_code("b", origin, Some(origin)),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::link([text_a], "/a", origin, Some(origin), Some(origin)),
    MarkdownIR::link([text_a], "/b", origin, None, None),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::link([text_a], "/a", origin, Some(origin), Some(origin)),
    MarkdownIR::link([text_b], "/a", origin, None, None),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::hard_break(origin),
    MarkdownIR::text("  \n", origin),
  )
  assert_markdown_ir_canonical_semantic_distinct(
    MarkdownIR::document(
      [MarkdownIR::paragraph([text_a], origin, Some(origin))],
      origin,
    ),
    MarkdownIR::document(
      [
        MarkdownIR::paragraph([text_a], origin, Some(origin)),
        MarkdownIR::paragraph([text_b], origin, Some(origin)),
      ],
      origin,
    ),
  )
}

///|
test "checked canonical formatting reports root and opaque failures before search" {
  let origin = markdown_ir_canonical_test_origin(0, 1)
  let raw = MarkdownIR::raw("*", origin, [])
  let root_attempt = markdown_ir_canonical_format_attempt(
    raw,
    markdown_ir_canonical_default_limits(),
  )
  assert_eq(root_attempt.result, Err(ExpectedDocument))
  assert_eq(root_attempt.stats.candidates, 0)
  assert_eq(root_attempt.stats.search_expansions, 0)
  assert_eq(root_attempt.stats.reparses, 0)

  let recovered = MarkdownIR::recovered("broken", origin, [])
  let unsupported = MarkdownIR::unsupported("extension", origin)
  let paragraph = MarkdownIR::paragraph(
    [raw, recovered, unsupported],
    origin,
    Some(origin),
  )
  let document = MarkdownIR::document([paragraph], origin)
  let opaque_attempt = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_default_limits(),
  )
  match opaque_attempt.result {
    Err(OpaqueNode(kind, Some(found_origin))) => {
      assert_eq(kind, MarkdownIRCanonicalOpaqueKind::Raw)
      assert_eq(found_origin, origin)
    }
    other =>
      fail(
        "expected first preorder Raw failure, got " + @debug.to_string(other),
      )
  }
  assert_eq(opaque_attempt.stats.candidates, 0)
  assert_eq(opaque_attempt.stats.search_expansions, 0)
  assert_eq(opaque_attempt.stats.reparses, 0)
}

///|
test "checked and compatibility formatters preserve every opaque mapping" {
  let origin = markdown_ir_canonical_test_origin(2, 7)
  let cases : Array[(MarkdownIR, MarkdownIRCanonicalOpaqueKind, String)] = [
    (
      MarkdownIR::raw("raw", origin, []),
      MarkdownIRCanonicalOpaqueKind::Raw,
      "raw",
    ),
    (
      MarkdownIR::recovered(RECOVERED_PARSE_ERROR, origin, []),
      MarkdownIRCanonicalOpaqueKind::Recovered,
      "<!-- recovered MarkdownIR: parse error -->",
    ),
    (
      MarkdownIR::recovered("literal fallback", origin, []),
      MarkdownIRCanonicalOpaqueKind::Recovered,
      "literal fallback",
    ),
    (
      MarkdownIR::unsupported("extension", origin),
      MarkdownIRCanonicalOpaqueKind::Unsupported,
      "<!-- unsupported MarkdownIR: extension -->",
    ),
  ]
  for case in cases {
    let (node, expected_kind, expected_legacy) = case
    let document = MarkdownIR::document([node], origin)
    let attempt = markdown_ir_canonical_format_attempt(
      document,
      markdown_ir_canonical_default_limits(),
    )
    match attempt.result {
      Err(OpaqueNode(kind, Some(found_origin))) => {
        assert_eq(kind, expected_kind)
        assert_eq(found_origin, origin)
      }
      other =>
        fail("expected checked opaque failure, got " + @debug.to_string(other))
    }
    assert_eq(attempt.stats.candidates, 0)
    assert_eq(attempt.stats.search_expansions, 0)
    assert_eq(attempt.stats.reparses, 0)
    assert_eq(
      experimental_markdown_ir_canonical_format(document),
      expected_legacy,
    )
  }
}

///|
test "checked canonical formatting validates every returned whole document" {
  let document = markdown_ir_canonical_test_document_with_text("*a*")
  let expected = match markdown_ir_canonical_semantic(document) {
    Some(expected) => expected
    None => fail("expected semantic document")
  }
  assert_false(markdown_ir_canonical_candidate_matches(expected, "*a*"))
  assert_true(markdown_ir_canonical_candidate_matches(expected, "\\*a\\*"))

  let attempt = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_default_limits(),
  )
  assert_eq(attempt.result, Ok("\\*a\\*"))
  assert_eq(attempt.stats.candidates, 2)
  assert_eq(attempt.stats.search_expansions, 3)
  assert_eq(attempt.stats.reparses, 2)
}

///|
test "checked canonical candidates follow the documented stable preference order" {
  let literal_markers = markdown_ir_canonical_test_document_with_text("*a*")
  let text_candidates = markdown_ir_canonical_test_candidates(literal_markers)
  assert_eq(text_candidates.map(candidate => candidate.markdown), [
    "*a*", "\\*a\\*", "&#x2a;a&#x2a;",
  ])

  let origin = markdown_ir_canonical_test_origin(0, 1)
  let emphasis = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [
          MarkdownIR::italic(
            [MarkdownIR::text("a", origin)],
            origin,
            Some(origin),
          ),
          MarkdownIR::text(" ", origin),
          MarkdownIR::bold(
            [MarkdownIR::text("b", origin)],
            origin,
            Some(origin),
          ),
        ],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  let emphasis_candidates = markdown_ir_canonical_test_candidates(emphasis)
  assert_eq(emphasis_candidates.map(candidate => candidate.markdown), [
    "*a* **b**", "*a* __b__", "_a_ **b**", "_a_ __b__",
  ])
}

///|
test "checked canonical numeric references stay limited to sensitive ASCII" {
  for code = 33; code <= 126; code = code + 1 {
    let ch = code.unsafe_to_char()
    if ch.is_ascii_punctuation() {
      let expected = match ch {
        '*'
        | '_'
        | '`'
        | '['
        | ']'
        | '('
        | ')'
        | '!'
        | '\\'
        | '&'
        | '<'
        | '>' => true
        _ => false
      }
      assert_eq(markdown_ir_canonical_reference_sensitive(ch), expected)
      let value = ch.to_string()
      let referenced = markdown_ir_canonical_reference_text(value)
      if expected {
        assert_true(referenced != value)
        assert_eq(markdown_ir_canonical_text_choices(value).length(), 3)
      } else {
        assert_eq(referenced, value)
        assert_eq(markdown_ir_canonical_text_choices(value).length(), 2)
      }
    }
  }
}

///|
test "checked canonical candidate stream deduplicates globally" {
  let origin = markdown_ir_canonical_test_origin(0, 1)
  let document = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [
          MarkdownIR::text("\\\\", origin),
          MarkdownIR::text("\\", origin),
          MarkdownIR::text("\\", origin),
          MarkdownIR::italic(
            [MarkdownIR::text("a", origin)],
            origin,
            Some(origin),
          ),
        ],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  let candidates = markdown_ir_canonical_test_candidates(document)
  let seen : Array[String] = []
  for candidate in candidates {
    assert_false(seen.any(markdown => markdown == candidate.markdown))
    seen.push(candidate.markdown)
  }
}

///|
test "checked canonical formatting distinguishes complete exhaustion" {
  let origin = markdown_ir_canonical_test_origin(0, 1)
  let invalid_document = MarkdownIR::document(
    [MarkdownIR::text("x", origin)],
    origin,
  )
  let attempt = markdown_ir_canonical_format_attempt(
    invalid_document,
    markdown_ir_canonical_default_limits(),
  )
  assert_eq(attempt.result, Err(Unrepresentable))
  assert_eq(attempt.stats.candidates, 1)
  assert_eq(attempt.stats.search_expansions, 1)
  assert_eq(attempt.stats.reparses, 1)
}

///|
test "checked canonical formatting reports deterministic injected search limits" {
  let document = markdown_ir_canonical_test_document_with_text("*a*")
  let candidate_limited = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_limits(
      max_container_candidates=100,
      max_container_expansions=100,
      max_document_candidates_per_container=1,
      max_document_expansions_per_container=100,
    ),
  )
  assert_eq(
    candidate_limited.result,
    Err(SearchLimitExceeded(observed=2, limit=1)),
  )

  let expansion_limited = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_limits(
      max_container_candidates=100,
      max_container_expansions=100,
      max_document_candidates_per_container=100,
      max_document_expansions_per_container=1,
    ),
  )
  assert_eq(
    expansion_limited.result,
    Err(SearchLimitExceeded(observed=2, limit=1)),
  )

  let origin = markdown_ir_canonical_test_origin(0, 3)
  let two_containers = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [MarkdownIR::text("*a*", origin)],
        origin,
        Some(origin),
      ),
      MarkdownIR::paragraph(
        [MarkdownIR::text("*a*", origin)],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  let document_limited = markdown_ir_canonical_format_attempt(
    two_containers,
    markdown_ir_canonical_limits(
      max_container_candidates=10,
      max_container_expansions=100,
      max_document_candidates_per_container=1,
      max_document_expansions_per_container=100,
    ),
  )
  assert_eq(
    document_limited.result,
    Err(SearchLimitExceeded(observed=3, limit=2)),
  )
}

///|
test "checked canonical search validates early candidates before finite caps" {
  let origin = markdown_ir_canonical_test_origin(0, 6)
  let stars : Array[MarkdownIR] = []
  for _ in 0..<6 {
    stars.push(MarkdownIR::text("*", origin))
  }
  let paragraph = MarkdownIR::paragraph(stars, origin, Some(origin))
  let document = MarkdownIR::document([paragraph], origin)
  let attempt = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_default_limits(),
  )
  match attempt.result {
    Ok(markdown) =>
      assert_true(
        markdown_ir_canonical_candidate_matches(
          markdown_ir_canonical_semantic(document).unwrap(),
          markdown,
        ),
      )
    Err(failure) =>
      fail(
        "expected an in-budget six-star candidate: " + @debug.to_string(failure),
      )
  }
  assert_true(attempt.stats.reparses > 0)
  assert_true(attempt.stats.reparses <= 256)
}

///|
test "checked canonical search keeps per-container caps independent" {
  let origin = markdown_ir_canonical_test_origin(0, 6)
  let stars : Array[MarkdownIR] = []
  for _ in 0..<6 {
    stars.push(MarkdownIR::text("*", origin))
  }
  let document = MarkdownIR::document(
    [
      MarkdownIR::paragraph(stars, origin, Some(origin)),
      MarkdownIR::paragraph(
        [MarkdownIR::text("plain", origin)],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  let attempt = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_limits(
      max_container_candidates=1,
      max_container_expansions=100,
      max_document_candidates_per_container=100,
      max_document_expansions_per_container=100,
    ),
  )
  assert_eq(attempt.result, Err(SearchLimitExceeded(observed=2, limit=1)))

  let unrepresentable_container = MarkdownIR::document(
    [MarkdownIR::text("*a*", origin)],
    origin,
  )
  let expansion_attempt = markdown_ir_canonical_format_attempt(
    unrepresentable_container,
    markdown_ir_canonical_limits(
      max_container_candidates=100,
      max_container_expansions=1,
      max_document_candidates_per_container=100,
      max_document_expansions_per_container=100,
    ),
  )
  assert_eq(
    expansion_attempt.result,
    Err(SearchLimitExceeded(observed=2, limit=1)),
  )
  assert_eq(expansion_attempt.stats.reparses, 2)
}

///|
test "checked canonical per-container candidate caps count deduplicated spellings" {
  let origin = markdown_ir_canonical_test_origin(0, 2)
  let document = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [MarkdownIR::text("\\", origin), MarkdownIR::text("\\", origin)],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  let unrestricted = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_default_limits(),
  )
  let capped = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_limits(
      max_container_candidates=2,
      max_container_expansions=100,
      max_document_candidates_per_container=100,
      max_document_expansions_per_container=100,
    ),
  )
  assert_eq(capped.result, unrestricted.result)
  match capped.result {
    Ok(_) => ()
    Err(failure) =>
      fail(
        "deduplicated container candidate should fit: " +
        @debug.to_string(failure),
      )
  }
}

///|
test "checked canonical expansion cutoff validates lexical prefix of a cost layer" {
  let origin = markdown_ir_canonical_test_origin(0, 4)
  let document = MarkdownIR::document(
    [
      MarkdownIR::paragraph(
        [MarkdownIR::text("_a", origin), MarkdownIR::text("_", origin)],
        origin,
        Some(origin),
      ),
    ],
    origin,
  )
  let attempt = markdown_ir_canonical_format_attempt(
    document,
    markdown_ir_canonical_limits(
      max_container_candidates=100,
      max_container_expansions=100,
      max_document_candidates_per_container=100,
      max_document_expansions_per_container=2,
    ),
  )
  assert_eq(attempt.result, Ok("\\_a_"))
  assert_eq(attempt.stats.search_expansions, 2)
  assert_eq(attempt.stats.reparses, 2)
}

///|
priv struct MarkdownIRCanonicalCorpusRng {
  mut state : Int
}

///|
fn MarkdownIRCanonicalCorpusRng::next(
  self : MarkdownIRCanonicalCorpusRng,
  bound : Int,
) -> Int {
  guard bound > 0 else { abort("canonical corpus bound must be positive") }
  self.state = (self.state * 25173 + 13849) % 65521
  self.state % bound
}

///|
fn markdown_ir_canonical_corpus_alphabet() -> Array[Char] {
  let alphabet = ['a', 'Z', '0', ' ', '。', '→', '😈']
  for code = 33; code <= 126; code = code + 1 {
    let ch = code.unsafe_to_char()
    if ch.is_ascii_punctuation() {
      alphabet.push(ch)
    }
  }
  alphabet
}

///|
fn markdown_ir_canonical_corpus_payload(
  rng : MarkdownIRCanonicalCorpusRng,
  alphabet : Array[Char],
) -> String {
  let buf = StringBuilder::StringBuilder()
  let length = 1 + rng.next(6)
  buf.write_char(if rng.next(2) == 0 { 'a' } else { '0' })
  for position = 1; position < length; position = position + 1 {
    if position == length - 1 {
      buf.write_char(if rng.next(2) == 0 { 'a' } else { '0' })
    } else {
      buf.write_char(alphabet[rng.next(alphabet.length())])
    }
  }
  buf.to_string()
}

///|
fn markdown_ir_canonical_corpus_inline(
  kind : Int,
  payload : String,
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  let text = MarkdownIR::text(payload, origin)
  match kind % 5 {
    0 => text
    1 => MarkdownIR::bold([text], origin, Some(origin))
    2 => MarkdownIR::italic([text], origin, Some(origin))
    3 => MarkdownIR::link([text], "/u", origin, None, None)
    _ => MarkdownIR::inline_code(payload, origin, Some(origin))
  }
}

///|
fn markdown_ir_canonical_corpus_nested(
  depth : Int,
  selector : Int,
  payload : String,
  origin : MarkdownIROrigin,
) -> MarkdownIR {
  if depth == 0 {
    return MarkdownIR::text(payload, origin)
  }
  let child = markdown_ir_canonical_corpus_nested(
    depth - 1,
    selector,
    payload,
    origin,
  )
  let children = [
    MarkdownIR::text("x ", origin),
    child,
    MarkdownIR::text(" y", origin),
  ]
  if (selector + depth) % 2 == 0 {
    MarkdownIR::bold(children, origin, Some(origin))
  } else {
    MarkdownIR::italic(children, origin, Some(origin))
  }
}

///|
fn markdown_ir_canonical_corpus_case(
  recursive : Bool,
  index : Int,
  rng : MarkdownIRCanonicalCorpusRng,
  alphabet : Array[Char],
) -> (MarkdownIR, Int, Int) {
  let depth = if recursive { 1 + index % 3 } else { 0 }
  let width = 1 + index / 3 % 4
  let origin = markdown_ir_canonical_test_origin(0, 1)
  let children : Array[MarkdownIR] = []
  if recursive {
    let payload = markdown_ir_canonical_corpus_payload(rng, alphabet)
    let nested = markdown_ir_canonical_corpus_nested(
      depth, index, payload, origin,
    )
    children.push(
      if index % 4 == 0 {
        MarkdownIR::link([nested], "/u", origin, None, None)
      } else {
        nested
      },
    )
    for position = 1; position < width; position = position + 1 {
      if position % 2 == 0 {
        children.push(MarkdownIR::inline_code("f", origin, Some(origin)))
      } else {
        children.push(MarkdownIR::text("f", origin))
      }
    }
  } else {
    for position = 0; position < width; position = position + 1 {
      children.push(
        markdown_ir_canonical_corpus_inline(
          index + position,
          markdown_ir_canonical_corpus_payload(rng, alphabet),
          origin,
        ),
      )
    }
  }
  let paragraph = MarkdownIR::paragraph(children, origin, Some(origin))
  (MarkdownIR::document([paragraph], origin), depth, width)
}

///|
fn markdown_ir_canonical_pad4(value : Int) -> String {
  let text = value.to_string()
  let buf = StringBuilder::StringBuilder()
  for index = text.length(); index < 4; index = index + 1 {
    buf.write_char('0')
  }
  buf.write_string(text)
  buf.to_string()
}

///|
priv struct MarkdownIRCanonicalCorpusRun {
  transcript : String
  replay_keys : Array[String]
  digest : Int
  max_container_candidates : Int
  max_container_expansions : Int
  max_document_candidates : Int
  max_document_expansions : Int
  max_reparses : Int
  saw_depth3 : Bool
  saw_width4 : Bool
}

///|
fn markdown_ir_run_canonical_corpus() -> MarkdownIRCanonicalCorpusRun raise {
  let rng = { state: 39777 }
  let alphabet = markdown_ir_canonical_corpus_alphabet()
  let transcript = StringBuilder::StringBuilder()
  transcript.write_string(
    "canonical-v2 seed=39777 shallow=128 recursive=128 depth=3 width=4 " +
    "alphabet=ascii-punctuation+aZ0-space-unicode\n",
  )
  let replay_keys : Array[String] = []
  let mut max_container_candidates = 0
  let mut max_container_expansions = 0
  let mut max_document_candidates = 0
  let mut max_document_expansions = 0
  let mut max_reparses = 0
  let mut saw_depth3 = false
  let mut saw_width4 = false
  for recursive in [false, true] {
    for index = 0; index < 128; index = index + 1 {
      let (document, depth, width) = markdown_ir_canonical_corpus_case(
        recursive, index, rng, alphabet,
      )
      if depth == 3 {
        saw_depth3 = true
      }
      if width == 4 {
        saw_width4 = true
      }
      let class = if recursive { "recursive" } else { "shallow" }
      let key = "canonical-v2/s39777/" +
        class +
        "/i" +
        markdown_ir_canonical_pad4(index) +
        "/d" +
        depth.to_string() +
        "/w" +
        width.to_string()
      replay_keys.push(key)
      let attempt = markdown_ir_canonical_format_attempt(
        document,
        markdown_ir_canonical_default_limits(),
      )
      let formatted = match attempt.result {
        Ok(formatted) => formatted
        Err(failure) =>
          fail(
            "canonical corpus failure " +
            key +
            ": " +
            @debug.to_string(failure) +
            " document=" +
            @debug.to_string(document),
          )
      }
      max_container_candidates = max_container_candidates.max(
        attempt.stats.container_candidates,
      )
      max_container_expansions = max_container_expansions.max(
        attempt.stats.container_expansions,
      )
      max_document_candidates = max_document_candidates.max(
        attempt.stats.candidates,
      )
      max_document_expansions = max_document_expansions.max(
        attempt.stats.search_expansions,
      )
      max_reparses = max_reparses.max(attempt.stats.reparses)
      transcript.write_string(key)
      transcript.write_char('\t')
      transcript.write_string(formatted)
      transcript.write_char('\t')
      transcript.write_string(attempt.stats.container_candidates.to_string())
      transcript.write_char('/')
      transcript.write_string(attempt.stats.container_expansions.to_string())
      transcript.write_char('/')
      transcript.write_string(attempt.stats.candidates.to_string())
      transcript.write_char('/')
      transcript.write_string(attempt.stats.search_expansions.to_string())
      transcript.write_char('/')
      transcript.write_string(attempt.stats.reparses.to_string())
      transcript.write_char('\n')
    }
  }
  let transcript = transcript.to_string()
  {
    transcript,
    replay_keys,
    digest: @seam.string_hash(transcript),
    max_container_candidates,
    max_container_expansions,
    max_document_candidates,
    max_document_expansions,
    max_reparses,
    saw_depth3,
    saw_width4,
  }
}

///|
test "checked canonical source-free corpus is deterministic and bounded" {
  let first = markdown_ir_run_canonical_corpus()
  let second = markdown_ir_run_canonical_corpus()
  assert_eq(first.transcript, second.transcript)
  assert_eq(first.replay_keys, second.replay_keys)
  assert_eq(first.digest, second.digest)
  assert_eq(first.replay_keys.length(), 256)
  assert_true(first.saw_depth3)
  assert_true(first.saw_width4)
  assert_true(
    MARKDOWN_CANONICAL_CONTAINER_CANDIDATE_LIMIT >=
    first.max_container_candidates * 2,
  )
  assert_true(
    MARKDOWN_CANONICAL_CONTAINER_EXPANSION_LIMIT >=
    first.max_container_expansions * 2,
  )
  assert_true(
    MARKDOWN_CANONICAL_DOCUMENT_CANDIDATES_PER_CONTAINER >=
    first.max_document_candidates * 2,
  )
  assert_true(
    MARKDOWN_CANONICAL_DOCUMENT_EXPANSIONS_PER_CONTAINER >=
    first.max_document_expansions * 2,
  )
  assert_eq(first.digest, 2101345741)
  assert_eq(first.transcript.length(), 18466)
  assert_eq(first.max_container_candidates, 49)
  assert_eq(first.max_container_expansions, 20)
  assert_eq(first.max_document_candidates, 20)
  assert_eq(first.max_document_expansions, 49)
  assert_eq(first.max_reparses, 19)
}
