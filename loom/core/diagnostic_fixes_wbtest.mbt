///|
fn fix_test_offset(value : Int) -> TextOffset {
  try TextOffset(value) catch {
    _ => abort("expected valid test offset")
  } noraise {
    offset => offset
  }
}

///|
fn fix_test_range(start : Int, end : Int) -> TextRange {
  try TextRange(fix_test_offset(start), fix_test_offset(end)) catch {
    _ => abort("expected valid test range")
  } noraise {
    range => range
  }
}

///|
fn fix_test_source(value : String) -> SourceId {
  SourceId(value)
}

///|
fn fix_test_replacement(
  source_id : SourceId,
  start : Int,
  end : Int,
  replacement : String,
) -> TextReplacement {
  TextReplacement(
    SourceSpan(source_id, fix_test_range(start, end)),
    replacement,
  )
}

///|
fn fix_test_make(
  title : String,
  applicability : FixApplicability,
  edits : Array[TextReplacement],
) -> DiagnosticFix {
  try DiagnosticFix(title, applicability, edits) catch {
    _ => abort("expected valid diagnostic fix")
  } noraise {
    fix => fix
  }
}

///|
fn fix_test_apply(
  fix : DiagnosticFix,
  source_id : SourceId,
  source : String,
) -> String {
  try fix.apply(source_id, source) catch {
    _ => abort("expected diagnostic fix to apply")
  } noraise {
    result => result
  }
}

///|
fn fix_test_reference_apply(
  source : String,
  edits : Array[TextReplacement],
) -> String {
  let builder = StringBuilder()
  let cursor = edits.fold(init=0, (cursor, edit) => {
    let range = edit.span().range()
    builder.write_stringview(
      source.view(start_offset=cursor, end_offset=range.start().value()),
    )
    builder.write_string(edit.replacement())
    range.end().value()
  })
  builder.write_stringview(
    source.view(start_offset=cursor, end_offset=source.length()),
  )
  builder.to_string()
}

///|
test "diagnostic fix applies insertion replacement and deletion" {
  let source_id = fix_test_source("main")
  let insertion = fix_test_make("insert", Always, [
    fix_test_replacement(source_id, 1, 1, "X"),
  ])
  let replacement = fix_test_make("replace", Always, [
    fix_test_replacement(source_id, 1, 3, "X"),
  ])
  let deletion = fix_test_make("delete", MaybeIncorrect, [
    fix_test_replacement(source_id, 1, 3, ""),
  ])
  inspect(fix_test_apply(insertion, source_id, "abcd"), content="aXbcd")
  inspect(fix_test_apply(replacement, source_id, "abcd"), content="aXd")
  inspect(fix_test_apply(deletion, source_id, "abcd"), content="ad")
  inspect(insertion.title(), content="insert")
  debug_inspect(deletion.applicability(), content="MaybeIncorrect")
}

///|
test "diagnostic fix normalizes out-of-order edits and applies from the end" {
  let source_id = fix_test_source("main")
  let fix = fix_test_make("normalize", Always, [
    fix_test_replacement(source_id, 4, 6, "Z"),
    fix_test_replacement(source_id, 0, 0, "<"),
    fix_test_replacement(source_id, 1, 3, ""),
  ])
  let edits = fix.edits()
  inspect(edits[0].span().range().start().value(), content="0")
  inspect(edits[1].span().range().start().value(), content="1")
  inspect(edits[2].span().range().start().value(), content="4")
  inspect(fix_test_apply(fix, source_id, "abcdef"), content="<adZ")
}

///|
test "diagnostic fix rejects an empty edit list" {
  try DiagnosticFix("empty", Always, []) catch {
    EmptyDiagnosticFix => ()
    _ => abort("expected empty-fix error")
  } noraise {
    _ => abort("expected empty fix to reject")
  }
}

///|
test "diagnostic fix rejects multiple sources" {
  let source_a = fix_test_source("a")
  let source_b = fix_test_source("b")
  try
    DiagnosticFix("multi-source", Always, [
      fix_test_replacement(source_a, 0, 1, "A"),
      fix_test_replacement(source_b, 2, 3, "B"),
    ])
  catch {
    MultiSourceDiagnosticFix(expected, actual) => {
      inspect(expected == source_a, content="true")
      inspect(actual == source_b, content="true")
    }
    _ => abort("expected multi-source error")
  } noraise {
    _ => abort("expected multi-source fix to reject")
  }
}

///|
test "diagnostic fix rejects overlapping nonempty ranges" {
  let source_id = fix_test_source("main")
  try
    DiagnosticFix("overlap", Always, [
      fix_test_replacement(source_id, 1, 4, "A"),
      fix_test_replacement(source_id, 3, 5, "B"),
    ])
  catch {
    OverlappingDiagnosticFixEdits(_, _) => ()
    _ => abort("expected overlapping-edits error")
  } noraise {
    _ => abort("expected overlapping edits to reject")
  }
}

///|
test "diagnostic fix rejects duplicate-position insertions" {
  let source_id = fix_test_source("main")
  try
    DiagnosticFix("duplicate insertions", Always, [
      fix_test_replacement(source_id, 2, 2, "A"),
      fix_test_replacement(source_id, 2, 2, "B"),
    ])
  catch {
    DuplicateDiagnosticFixInsertion(_, _) => ()
    _ => abort("expected duplicate-insertion error")
  } noraise {
    _ => abort("expected duplicate insertions to reject")
  }
}

///|
test "diagnostic fix rejects insertions at range start or interior" {
  let source_id = fix_test_source("main")
  for insertion_at in [1, 2] {
    try
      DiagnosticFix("ambiguous insertion", Always, [
        fix_test_replacement(source_id, 1, 3, "R"),
        fix_test_replacement(source_id, insertion_at, insertion_at, "I"),
      ])
    catch {
      OverlappingDiagnosticFixEdits(_, _) => ()
      _ => abort("expected ambiguous insertion to overlap")
    } noraise {
      _ => abort("expected ambiguous insertion to reject")
    }
  }
}

///|
test "diagnostic fix accepts touching ranges and insertion at exclusive end" {
  let source_id = fix_test_source("main")
  let touching = fix_test_make("touching", Always, [
    fix_test_replacement(source_id, 1, 2, "X"),
    fix_test_replacement(source_id, 2, 3, "Y"),
  ])
  let end_insertion = fix_test_make("end insertion", Always, [
    fix_test_replacement(source_id, 1, 2, "X"),
    fix_test_replacement(source_id, 2, 2, "!"),
  ])
  inspect(fix_test_apply(touching, source_id, "abcd"), content="aXYd")
  inspect(fix_test_apply(end_insertion, source_id, "abcd"), content="aX!cd")
}

///|
test "diagnostic fix rejects a mismatched application source" {
  let source_a = fix_test_source("a")
  let source_b = fix_test_source("b")
  let fix = fix_test_make("source-bound", Always, [
    fix_test_replacement(source_a, 0, 1, "A"),
  ])
  try fix.apply(source_b, "abc") catch {
    DiagnosticFixSourceMismatch(expected, actual) => {
      inspect(expected == source_a, content="true")
      inspect(actual == source_b, content="true")
    }
    _ => abort("expected source-mismatch error")
  } noraise {
    _ => abort("expected mismatched source to reject")
  }
}

///|
test "diagnostic fix rejects out-of-bounds ranges before application" {
  let source_id = fix_test_source("main")
  let fix = fix_test_make("out of bounds", Always, [
    fix_test_replacement(source_id, 1, 4, "X"),
  ])
  try fix.apply(source_id, "abc") catch {
    DiagnosticFixRangeOutOfBounds(span, source_length) => {
      inspect(span.range().end().value(), content="4")
      inspect(source_length, content="3")
    }
    _ => abort("expected out-of-bounds error")
  } noraise {
    _ => abort("expected out-of-bounds range to reject")
  }
}

///|
test "diagnostic fix validates UTF-16 surrogate boundaries" {
  let source_id = fix_test_source("main")
  let interior = fix_test_make("invalid boundary", Always, [
    fix_test_replacement(source_id, 2, 2, "X"),
  ])
  try interior.apply(source_id, "a😀b") catch {
    DiagnosticFixInvalidUtf16Boundary(span) =>
      inspect(span.range().start().value(), content="2")
    _ => abort("expected invalid UTF-16 boundary error")
  } noraise {
    _ => abort("expected surrogate-interior range to reject")
  }
  let valid = fix_test_make("valid emoji", Always, [
    fix_test_replacement(source_id, 1, 3, "X"),
  ])
  inspect(fix_test_apply(valid, source_id, "a😀b"), content="aXb")
}

///|
test "diagnostic fix arrays are defensively copied" {
  let source_id = fix_test_source("main")
  let edits = [fix_test_replacement(source_id, 1, 2, "X")]
  let fix = fix_test_make("owned edits", Always, edits)
  edits.push(fix_test_replacement(source_id, 2, 3, "Y"))
  let exposed = fix.edits()
  exposed.push(fix_test_replacement(source_id, 3, 4, "Z"))
  inspect(fix.edits().length(), content="1")
  inspect(fix_test_apply(fix, source_id, "abcd"), content="aXcd")
}

///|
test "diagnostic stores defensive fix copies and candidates stay distinct" {
  let source_id = fix_test_source("main")
  let first = fix_test_make("first", Always, [
    fix_test_replacement(source_id, 0, 1, "A"),
  ])
  let second = fix_test_make("second", MaybeIncorrect, [
    fix_test_replacement(source_id, 0, 1, "B"),
  ])
  let fixes = [first, second]
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="two choices",
    fixes~,
  )
  fixes.push(first)
  let exposed = diagnostic.fixes()
  exposed.push(second)
  let stored = diagnostic.fixes()
  inspect(stored.length(), content="2")
  inspect(fix_test_apply(stored[0], source_id, "x"), content="A")
  inspect(fix_test_apply(stored[1], source_id, "x"), content="B")
}

///|
test "diagnostic transforms preserve snapshot-bound fixes without remapping" {
  let source_id = fix_test_source("main")
  let fix = fix_test_make("snapshot-bound", Always, [
    fix_test_replacement(source_id, 4, 5, "X"),
  ])
  let diagnostic = Diagnostic(
    source=DiagnosticSource::parser(),
    severity=Error,
    message="shift label only",
    labels=[
      DiagnosticLabel(
        Primary,
        SourceSpan(source_id, fix_test_range(4, 5)),
        None,
      ),
    ],
    fixes=[fix],
  )
  let shifted = try
    diagnostic.offset_by(source_id, 3, fix_test_offset(4))
  catch {
    _ => abort("expected label shift")
  } noraise {
    diagnostic => diagnostic
  }
  inspect(shifted.labels()[0].span().range().start().value(), content="7")
  inspect(
    shifted.fixes()[0].edits()[0].span().range().start().value(),
    content="4",
  )
}

///|
test "parser diagnostic identity includes fix candidates" {
  let source_id = fix_test_source("main")
  let make_diagnostic = replacement => {
    Diagnostic(
      source=DiagnosticSource::parser(),
      severity=Error,
      message="same parser error",
      fixes=[
        fix_test_make("candidate", Always, [
          fix_test_replacement(source_id, 0, 1, replacement),
        ]),
      ],
    )
  }
  inspect(
    parser_diagnostic_same_key(make_diagnostic("A"), make_diagnostic("B")),
    content="false",
  )
}

///|
test "property: normalized reverse application matches forward reference" {
  let source_id = fix_test_source("main")
  let seeds : Array[Int] = @quickcheck.samples(64)
  for seed in seeds {
    let magnitude = if seed < 0 { -(seed + 1) } else { seed }
    let first_start = magnitude % 2
    let second_start = 4 + magnitude / 2 % 2
    let edits = [
      fix_test_replacement(
        source_id,
        second_start,
        second_start + 1,
        "R" + (magnitude % 7).to_string(),
      ),
      fix_test_replacement(source_id, first_start, first_start, "I"),
      fix_test_replacement(source_id, 2, 3, ""),
    ]
    let fix = fix_test_make("property", Always, edits)
    let normalized = fix.edits()
    let expected = fix_test_reference_apply("abcdefgh", normalized)
    let actual = fix_test_apply(fix, source_id, "abcdefgh")
    guard actual == expected else {
      abort("fix application property failed for seed " + seed.to_string())
    }
  }
}
