///|
/// Renders span-carrying groups compactly for slot-span assertions:
/// `g<index>@<start>-<end>:<body>` where body is `_` for an empty group or
/// `#<element count>` otherwise, groups joined by " || ".
fn render_group_spans(groups : Array[DirectElementGroup]) -> String {
  groups
  .map(group => {
    let body = if group.is_empty() {
      "_"
    } else {
      "#\{group.elements().length()}"
    }
    "g\{group.index()}@\{group.start()}-\{group.end()}:\{body}"
  })
  .join(" || ")
}

///|
test "SyntaxNode::direct_element_groups_by non-empty groups span their element extent" {
  // Same stack-call shape as the raw-API test, at base offset 10:
  // `stack`@10-15 `(`@15-16 n2@16-17 `,`@17-18 n2@18-19 n3@19-21 `,`@21-22 `42`@22-24 `)`@24-25
  let arg = (kind : Int, text : String) => {
    CstElement::Node(
      CstNode::new(RawKind(kind), [
        CstElement::Token(CstToken::CstToken(RawKind(9), text)),
      ]),
    )
  }
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(5), "stack")),
    CstElement::Token(CstToken::CstToken(RawKind(6), "(")),
    arg(2, "a"),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    arg(2, "b"),
    arg(3, ".f"),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    CstElement::Token(CstToken::CstToken(RawKind(4), "42")),
    CstElement::Token(CstToken::CstToken(RawKind(7), ")")),
  ])
  let node = SyntaxNode::from_cst(root, offset=10)
  let groups = node.direct_element_groups_by(RawKind(1))
  inspect(
    render_group_spans(groups),
    content="g0@10-17:#3 || g1@18-21:#2 || g2@22-25:#2",
  )
  // Element parity with the raw grouping API.
  inspect(
    render_groups(groups.map(group => group.elements().to_owned())),
    content=render_groups(node.direct_elements_grouped_by(RawKind(1))),
  )
}

///|
test "SyntaxNode::direct_element_groups_by leading empty group spans parent start to first separator" {
  // ` `@0-1 (trivia) `,`@1-2 `a`@2-3 — the leading slot covers the trivia.
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(8), " ")),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    CstElement::Token(CstToken::CstToken(RawKind(9), "a")),
  ])
  let groups = SyntaxNode::from_cst(root).direct_element_groups_by(
    RawKind(1),
    trivia_kind=Some(RawKind(8)),
  )
  inspect(render_group_spans(groups), content="g0@0-1:_ || g1@2-3:#1")
}

///|
test "SyntaxNode::direct_element_groups_by trailing empty group spans after last separator" {
  // `a`@0-1 `,`@1-2 ` `@2-3 (trivia) — the trailing slot covers the trivia.
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(9), "a")),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    CstElement::Token(CstToken::CstToken(RawKind(8), " ")),
  ])
  let groups = SyntaxNode::from_cst(root).direct_element_groups_by(
    RawKind(1),
    trivia_kind=Some(RawKind(8)),
  )
  inspect(render_group_spans(groups), content="g0@0-1:#1 || g1@2-3:_")
}

///|
test "SyntaxNode::direct_element_groups_by doubled separator empty group spans the gap" {
  // `a`@0-1 `,`@1-2 ` `@2-3 (trivia) `,`@3-4 `b`@4-5 — middle slot is 2..3.
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(9), "a")),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    CstElement::Token(CstToken::CstToken(RawKind(8), " ")),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    CstElement::Token(CstToken::CstToken(RawKind(9), "b")),
  ])
  let groups = SyntaxNode::from_cst(root).direct_element_groups_by(
    RawKind(1),
    trivia_kind=Some(RawKind(8)),
  )
  inspect(
    render_group_spans(groups),
    content="g0@0-1:#1 || g1@2-3:_ || g2@4-5:#1",
  )
}

///|
test "SyntaxNode::direct_element_groups_by edge separators without trivia yield zero-width slot spans" {
  // `,`@0-1 `a`@1-2 — leading slot collapses to 0..0 (parent start, separator start).
  let leading = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
    CstElement::Token(CstToken::CstToken(RawKind(9), "a")),
  ])
  inspect(
    render_group_spans(
      SyntaxNode::from_cst(leading).direct_element_groups_by(RawKind(1)),
    ),
    content="g0@0-0:_ || g1@1-2:#1",
  )
  // `a`@0-1 `,`@1-2 — trailing slot collapses to 2..2 (separator end, parent end).
  let trailing = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(9), "a")),
    CstElement::Token(CstToken::CstToken(RawKind(1), ",")),
  ])
  inspect(
    render_group_spans(
      SyntaxNode::from_cst(trailing).direct_element_groups_by(RawKind(1)),
    ),
    content="g0@0-1:#1 || g1@2-2:_",
  )
}

///|
test "SyntaxNode::direct_element_groups_by handles zero-width separator tokens" {
  // `a`@0-1, zero-width seps @1-1, `b`@1-2 — the doubled slot collapses to 1..1.
  let root = CstNode::new(RawKind(0), [
    CstElement::Token(CstToken::CstToken(RawKind(9), "a")),
    CstElement::Token(CstToken::CstToken(RawKind(1), "")),
    CstElement::Token(CstToken::CstToken(RawKind(1), "")),
    CstElement::Token(CstToken::CstToken(RawKind(9), "b")),
  ])
  let groups = SyntaxNode::from_cst(root).direct_element_groups_by(RawKind(1))
  inspect(
    render_group_spans(groups),
    content="g0@0-1:#1 || g1@1-1:_ || g2@1-2:#1",
  )
}

///|
test "SyntaxNode::direct_element_groups_by on empty node yields one empty group over the node span" {
  let groups = SyntaxNode::from_cst(CstNode::new(RawKind(0), [])).direct_element_groups_by(
    RawKind(1),
  )
  inspect(render_group_spans(groups), content="g0@0-0:_")
}

///|
test "DirectElementGroup cardinality helpers accept well-shaped groups" {
  // `2`@0-1 `,`@1-2 n73@2-5 — group 0 holds the count token, group 1 the callback node.
  let number_kind = RawKind(71)
  let comma_kind = RawKind(72)
  let callback_kind = RawKind(73)
  let callback = CstNode::new(callback_kind, [
    CstElement::Token(CstToken::CstToken(RawKind(75), "rev")),
  ])
  let call = SyntaxNode::from_cst(
    CstNode::new(RawKind(70), [
      CstElement::Token(CstToken::CstToken(number_kind, "2")),
      CstElement::Token(CstToken::CstToken(comma_kind, ",")),
      CstElement::Node(callback),
    ]),
  )
  let groups = call.direct_element_groups_by(comma_kind)
  inspect(groups.length(), content="2")
  match groups[0].required_token_of_kind(number_kind, message="one count") {
    Ok(tok) => inspect(tok.text(), content="2")
    Err(_) => fail("expected exactly one count token in group 0")
  }
  match
    groups[1].required_child_of_kind(callback_kind, message="one callback") {
    Ok(node) => inspect(node.kind().0, content="73")
    Err(_) => fail("expected exactly one callback child in group 1")
  }
  match
    groups[0].optional_token_of_kind(RawKind(99), message="optional missing") {
    Ok(None) => inspect("none", content="none")
    Ok(Some(_)) => fail("missing optional token should be None")
    Err(_) => fail("missing optional token should not error")
  }
  match groups[1].expect_no_tokens_of_kind(number_kind, message="no count") {
    Ok(_) => inspect("ok", content="ok")
    Err(_) => fail("group 1 holds no count token")
  }
}

///|
test "DirectElementGroup required_token_of_kind reports the slot span for an empty group" {
  // `2`@0-1 `,`@1-2 ` `@2-3 (trivia) — trailing empty slot is 2..3.
  let number_kind = RawKind(71)
  let comma_kind = RawKind(72)
  let call = SyntaxNode::from_cst(
    CstNode::new(RawKind(70), [
      CstElement::Token(CstToken::CstToken(number_kind, "2")),
      CstElement::Token(CstToken::CstToken(comma_kind, ",")),
      CstElement::Token(CstToken::CstToken(RawKind(74), " ")),
    ]),
  )
  let groups = call.direct_element_groups_by(
    comma_kind,
    trivia_kind=Some(RawKind(74)),
  )
  inspect(groups.length(), content="2")
  match groups[1].required_token_of_kind(number_kind, message="argument 2") {
    Ok(_) => fail("empty group must reject required cardinality")
    Err(err) => {
      inspect(err.message, content="argument 2")
      inspect(err.node_kind.0, content="70")
      inspect(err.target_kind.0, content="71")
      inspect(err.element == TokenElement, content="true")
      inspect(err.expectation == ExpectedOne, content="true")
      inspect(err.actual, content="0")
      inspect(err.start, content="2")
      inspect(err.end, content="3")
    }
  }
}

///|
/// Checked `.every(count, callback)` projection example: grouping by comma plus
/// group-level cardinality helpers replace hand-rolled separator-offset math
/// and hand-built errors. The group index lives in the projection-supplied
/// message; delimiter tokens may share a group with an argument without
/// disturbing the kind-filtered checks.
fn project_every(
  args : SyntaxNode,
  number_kind~ : RawKind,
  callback_kind~ : RawKind,
  separator~ : RawKind,
  trivia~ : RawKind,
) -> Result[(String, SyntaxNode), ProjectionShapeError] {
  let groups = args.direct_element_groups_by(
    separator,
    trivia_kind=Some(trivia),
  )
  guard groups.length() == 2 else {
    abort("arity validation is projection-owned and out of scope here")
  }
  match
    groups[0].required_token_of_kind(
      number_kind,
      message="argument 1: expected interval count",
    ) {
    Ok(count) =>
      match
        groups[1].required_child_of_kind(
          callback_kind,
          message="argument 2: expected callback",
        ) {
        Ok(callback) => Ok((count.text(), callback))
        Err(err) => Err(err)
      }
    Err(err) => Err(err)
  }
}

///|
test "checked .every(count, callback) example projects well-formed argument lists" {
  // `(`@0-1 `2`@1-2 `,`@2-3 ` `@3-4 n85@4-7 `)`@7-8 — `(2, rev)`.
  let callback = CstNode::new(RawKind(85), [
    CstElement::Token(CstToken::CstToken(RawKind(86), "rev")),
  ])
  let args = SyntaxNode::from_cst(
    CstNode::new(RawKind(80), [
      CstElement::Token(CstToken::CstToken(RawKind(81), "(")),
      CstElement::Token(CstToken::CstToken(RawKind(82), "2")),
      CstElement::Token(CstToken::CstToken(RawKind(83), ",")),
      CstElement::Token(CstToken::CstToken(RawKind(84), " ")),
      CstElement::Node(callback),
      CstElement::Token(CstToken::CstToken(RawKind(87), ")")),
    ]),
  )
  match
    project_every(
      args,
      number_kind=RawKind(82),
      callback_kind=RawKind(85),
      separator=RawKind(83),
      trivia=RawKind(84),
    ) {
    Ok((count, callback)) => {
      inspect(count, content="2")
      inspect(callback.kind().0, content="85")
    }
    Err(_) => fail("well-formed .every arguments must project")
  }
}

///|
test "checked .every(count, callback) example rejects a missing callback argument" {
  // `(`@0-1 `2`@1-2 `,`@2-3 `)`@3-4 — `(2,)`: group 1 holds only the rparen.
  let args = SyntaxNode::from_cst(
    CstNode::new(RawKind(80), [
      CstElement::Token(CstToken::CstToken(RawKind(81), "(")),
      CstElement::Token(CstToken::CstToken(RawKind(82), "2")),
      CstElement::Token(CstToken::CstToken(RawKind(83), ",")),
      CstElement::Token(CstToken::CstToken(RawKind(87), ")")),
    ]),
  )
  match
    project_every(
      args,
      number_kind=RawKind(82),
      callback_kind=RawKind(85),
      separator=RawKind(83),
      trivia=RawKind(84),
    ) {
    Ok(_) => fail("missing callback must be rejected")
    Err(err) => {
      inspect(err.message, content="argument 2: expected callback")
      inspect(err.element == ChildElement, content="true")
      inspect(err.expectation == ExpectedOne, content="true")
      inspect(err.actual, content="0")
      // No callback child: the error falls back to the group span (the rparen).
      inspect(err.start, content="3")
      inspect(err.end, content="4")
    }
  }
}
