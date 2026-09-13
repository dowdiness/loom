///|
// Deliberately has no Eq implementation: publication is not value backdating.
struct SemanticTestValue {
  history : String
}

///|
fn semantic_test_value(
  previous : SemanticAccepted[SemanticTestValue]?,
  snapshot : SemanticSnapshot,
) -> SemanticTestValue {
  let history = match previous {
    None => snapshot.source()
    Some(value) => value.value().history + "/" + snapshot.source()
  }
  { history, }
}

///|
test "semantic faults preserve one accepted frame and do not block siblings or edits" {
  let parser = Parser::new(
    @core.SourceId("siblings"),
    "a",
    test_imperative_language(),
  )
  let fault = Ref(false)
  let calls = Ref(0)
  let first : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic(fn(
      previous,
      snapshot,
      _change,
    ) raise {
      calls.val += 1
      let candidate = semantic_test_value(previous, snapshot)
      if fault.val {
        fail("candidate fault after construction")
      }
      Accept(candidate)
    },
  )
  let second : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic((
      previous,
      snapshot,
      _change,
    ) => Accept(semantic_test_value(previous, snapshot)),
  )
  defer first.dispose()
  defer second.dispose()
  let retained = first.read()
  ignore(second.read())
  fault.val = true
  parser.apply_edit(@core.Edit::new(0, 1, 1), "b")
  assert_eq(calls.val, 1)
  let failed = first.read()
  assert_true(failed.status() is CandidateFailed(_))
  assert_eq(failed.source(), "b")
  assert_eq(failed.accepted().unwrap().value().history, "a")
  assert_eq(second.read().accepted().unwrap().value().history, "a/b")
  fault.val = false
  parser.apply_edit(@core.Edit::new(0, 1, 1), "c")
  // Reverse sibling settlement order. Each starts from its own accepted frame.
  assert_eq(second.read().accepted().unwrap().value().history, "a/b/c")
  let newest = first.read()
  assert_eq(newest.accepted().unwrap().value().history, "a/c")
  assert_eq(newest.accepted().unwrap().snapshot().source(), "c")
  assert_eq(retained.accepted().unwrap().value().history, "a")
  assert_eq(failed.accepted().unwrap().snapshot().source(), "a")
  assert_eq(parser.source().read_or_abort(), "c")
}

///|
test "explicit semantic retry uses latest snapshot without another parser update" {
  let parser = Parser::new(
    @core.SourceId("retry"),
    "a",
    test_imperative_language(),
  )
  let fault = Ref(false)
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic(fn(
      previous,
      snapshot,
      _change,
    ) raise {
      let candidate = semantic_test_value(previous, snapshot)
      if fault.val {
        fail("candidate fault")
      }
      Accept(candidate)
    },
  )
  defer analysis.dispose()
  ignore(analysis.read())
  parser.set_source("b")
  fault.val = true
  let failed = analysis.read()
  assert_true(failed.status() is CandidateFailed(_))
  fault.val = false
  let recovered = analysis.read()
  assert_eq(recovered.revision(), failed.revision())
  assert_eq(recovered.accepted().unwrap().value().history, "a/b")
  assert_eq(analysis.read().accepted().unwrap().value().history, "a/b")
  assert_eq(failed.accepted().unwrap().value().history, "a")
}

///|
test "semantic rejection retains baseline and isolates snapshot diagnostics" {
  let source_id = @core.SourceId("rejected-source")
  let parser = Parser::new(source_id, "ok", test_imperative_language())
  let calls = Ref(0)
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic((
      previous,
      snapshot,
      _change,
    ) => {
      calls.val += 1
      if !snapshot.diagnostics().is_empty() {
        Reject(snapshot.source())
      } else {
        Accept(semantic_test_value(previous, snapshot))
      }
    },
  )
  defer analysis.dispose()
  let original = analysis.read().accepted().unwrap()
  original
  .snapshot()
  .diagnostics()
  .push(@core.lexer_diagnostic("external mutation"))
  assert_eq(original.snapshot().diagnostics().length(), 0)
  parser.set_source("@bad")
  let rejected = analysis.read()
  assert_true(rejected.status() is Rejected("@bad"))
  ignore(analysis.read())
  assert_eq(calls.val, 2)
  assert_eq(rejected.accepted().unwrap().value().history, "ok")
  parser.set_source("fixed")
  let recovered = analysis.read().accepted().unwrap()
  assert_eq(recovered.value().history, "ok/fixed")
  assert_eq(recovered.snapshot().source_id(), source_id)
  assert_eq(rejected.accepted().unwrap().value().history, "ok")
}

///|
test "semantic intent survives equal snapshots and explicit equal-text batches" {
  let parser = Parser::new(
    @core.SourceId("same-text"),
    "abc",
    test_imperative_language(),
  )
  let analysis : SemanticAnalysis[String, String] = parser.attach_semantic((
    previous,
    _snapshot,
    change,
  ) => {
    let value = previous.map(value => value.value()).unwrap_or("initial")
    Accept(if change.edit() is Some(_) { value + "!" } else { value })
  })
  defer analysis.dispose()
  let original = analysis.read()
  parser.apply_edit(@core.Edit::new(0, 1, 1), "abc")
  assert_eq(analysis.read().accepted().unwrap().value(), "initial!")
  let changes = @text_change.ChangeSet(source_length=3, changes=[
    @text_change.TextChange::ReplaceRange(start=0, delete_len=1, inserted="a"),
  ])
  parser.apply_changes(changes, "abc")
  let explicit = analysis.read()
  assert_eq(explicit.accepted().unwrap().value(), "initial!!")
  parser.set_source("abc")
  parser.apply_changes(@text_change.ChangeSet::empty(3), "abc")
  assert_eq(analysis.read().revision(), explicit.revision())
  assert_eq(original.accepted().unwrap().value(), "initial")
}

///|
test "semantic graph anchors survive gc and disposal preserves returned observations" {
  let parser = Parser::new(
    @core.SourceId("lifetime"),
    "a",
    test_imperative_language(),
  )
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic((
      previous,
      snapshot,
      _change,
    ) => Accept(semantic_test_value(previous, snapshot)),
  )
  let original = analysis.read()
  parser.runtime().gc()
  parser.set_source("b")
  let current = analysis.read()
  assert_eq(current.accepted().unwrap().value().history, "a/b")
  analysis.dispose()
  analysis.dispose()
  assert_eq(
    analysis.observation().unwrap().accepted().unwrap().value().history,
    "a/b",
  )
  try analysis.read() catch {
    Failure::Failure(_) => ()
  } noraise {
    _ => fail("closed analysis must reject live reads")
  }
  assert_eq(
    analysis.observation().unwrap().accepted().unwrap().value().history,
    "a/b",
  )
  assert_eq(original.accepted().unwrap().value().history, "a")
  assert_eq(current.accepted().unwrap().value().history, "a/b")
}

///|
test "candidate reentrant parser mutation is faulted before changing the parser" {
  let parser = Parser::new(
    @core.SourceId("reentrant"),
    "a",
    test_imperative_language(),
  )
  let reenter = Ref(false)
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic(fn(
      previous,
      snapshot,
      _change,
    ) raise {
      let candidate = semantic_test_value(previous, snapshot)
      if reenter.val {
        parser.set_source("forbidden")
      }
      Accept(candidate)
    },
  )
  defer analysis.dispose()
  ignore(analysis.read())
  parser.set_source("b")
  reenter.val = true
  let failed = analysis.read()
  assert_true(failed.status() is CandidateFailed(_))
  assert_eq(parser.source().read_or_abort(), "b")
  assert_eq(failed.accepted().unwrap().value().history, "a")
  reenter.val = false
  parser.set_source("c")
  assert_eq(analysis.read().accepted().unwrap().value().history, "a/c")
}

///|
test "disposing during candidate construction cancels acceptance" {
  let parser = Parser::new(
    @core.SourceId("cancel-candidate"),
    "a",
    test_imperative_language(),
  )
  let close = Ref(false)
  let handle : Ref[SemanticAnalysis[SemanticTestValue, String]?] = Ref(None)
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic((
      previous,
      snapshot,
      _change,
    ) => {
      let candidate = semantic_test_value(previous, snapshot)
      if close.val {
        handle.val.unwrap().dispose()
      }
      Accept(candidate)
    },
  )
  handle.val = Some(analysis)
  ignore(analysis.read())
  parser.set_source("b")
  close.val = true
  try analysis.read() catch {
    Failure::Failure(_) => ()
  } noraise {
    _ => fail("closing during construction must cancel publication")
  }
  parser.set_source("c")
  assert_eq(
    analysis.observation().unwrap().accepted().unwrap().value().history,
    "a",
  )
}

///|
test "failed parser updates do not advance semantic evidence or accepted state" {
  let parser = Parser::new(
    @core.SourceId("parser-failure"),
    "ok",
    test_imperative_language(fail_on="fault"),
  )
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic((
      previous,
      snapshot,
      _change,
    ) => Accept(semantic_test_value(previous, snapshot)),
  )
  defer analysis.dispose()
  let original = analysis.read()
  try parser.set_source("fault") catch {
    Failure::Failure(_) => ()
  } noraise {
    _ => fail("expected the parser callback to fail")
  }
  assert_eq(parser.source().read_or_abort(), "ok")
  assert_eq(analysis.read().revision(), original.revision())
  try parser.apply_edit(@core.Edit::new(0, 2, 5), "fault") catch {
    Failure::Failure(_) => ()
  } noraise {
    _ => fail("expected the incremental parser callback to fail")
  }
  assert_eq(parser.source().read_or_abort(), "ok")
  parser.set_source("ok")
  assert_eq(analysis.read().revision(), original.revision())
  try parser.apply_changes(@text_change.ChangeSet::empty(2), "wrong") catch {
    ParserUpdateError::ChangeSetMismatch => ()
    _ => fail("expected change-set mismatch")
  } noraise {
    _ => fail("expected invalid evidence to be rejected")
  }
  assert_eq(analysis.read().accepted().unwrap().value().history, "ok")
  parser.set_source("recovered")
  assert_eq(analysis.read().accepted().unwrap().value().history, "ok/recovered")
  assert_eq(original.accepted().unwrap().snapshot().source(), "ok")
}

///|
test "actual graph read failure remains distinct from candidate failure" {
  let parser = Parser::new(
    @core.SourceId("disposed-parser-cell"),
    "a",
    test_imperative_language(),
  )
  let analysis : SemanticAnalysis[SemanticTestValue, String] = parser.attach_semantic((
      previous,
      snapshot,
      _change,
    ) => Accept(semantic_test_value(previous, snapshot)),
  )
  defer analysis.dispose()
  ignore(analysis.read())
  parser.set_source("b")
  parser.runtime().dispose_cell(parser.snapshot().id())
  let failed = analysis.read()
  assert_true(failed.status() is GraphFailed(@incr.ReadError::Disposed(_)))
  assert_eq(failed.source(), "b")
  assert_eq(failed.accepted().unwrap().value().history, "a")
  parser.set_source("c")
  let latest = analysis.read()
  assert_true(latest.status() is GraphFailed(@incr.ReadError::Disposed(_)))
  assert_eq(latest.source(), "c")
  assert_eq(latest.accepted().unwrap().value().history, "a")
}

///|
test "failed edit before first parse preserves the original source" {
  let parser = @incremental.ImperativeParser::new(
    @core.SourceId("unparsed-failure"),
    "ok",
    test_imperative_language(fail_on="fault"),
  )
  try parser.edit(@core.Edit::new(0, 2, 5), "fault") catch {
    Failure::Failure(_) => ()
  } noraise {
    _ => fail("expected the initial full parse to fail")
  }
  assert_eq(parser.get_source(), "ok")
  assert_true(parser.current() is None)
  assert_eq(parser.parse().source, "ok")
}

///|
test "semantic edit evidence matches UTF-16 code units at every boundary" {
  let sources = ["", "a", "ab", "a\u{1F600}b", "a\u{1F601}b", "a\u{1FA00}b"]
  for old_source in sources {
    for new_source in sources {
      for start in 0..<=old_source.length() {
        for deleted in 0..<=(old_source.length() - start) {
          let inserted = new_source.length() - old_source.length() + deleted
          if inserted < 0 {
            continue
          }
          let mut expected = true
          for i in 0..<start {
            if old_source[i] != new_source[i] {
              expected = false
            }
          }
          for i in 0..<(old_source.length() - start - deleted) {
            if old_source[start + deleted + i] !=
              new_source[start + inserted + i] {
              expected = false
            }
          }
          let change = SemanticChange::SemanticChange(old_source).advance(
            new_source,
            edit=@core.Edit::new(start, deleted, inserted),
          )
          assert_eq(change.edit() is Some(_), expected)
        }
      }
    }
  }
}
