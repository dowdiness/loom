///|
struct PrettyTestResolver {
  resolve : (@diagnostic.SourceId) -> @diagnostic.SourceSnapshot?
}

///|
impl @diagnostic.SourceResolver for PrettyTestResolver with fn resolve_source(
  self,
  source_id,
) {
  (self.resolve)(source_id)
}

///|
fn pretty_test_options(
  tab_width? : Int = 4,
  ambiguous_width? : @moji.AmbiguousWidth = @moji.AmbiguousWidth::Narrow,
) -> DiagnosticPrettyOptions {
  try DiagnosticPrettyOptions(tab_width~, ambiguous_width~) catch {
    _ => abort("expected valid diagnostic pretty test options")
  } noraise {
    options => options
  }
}

///|
fn pretty_test_range(start : Int, end : Int) -> @diagnostic.TextRange {
  try @diagnostic.TextRange::from_offsets(start, end) catch {
    _ => abort("expected valid diagnostic pretty test range")
  } noraise {
    range => range
  }
}

///|
fn pretty_test_label(
  style : @diagnostic.LabelStyle,
  source_id : @diagnostic.SourceId,
  start : Int,
  end : Int,
  message? : String? = None,
) -> @diagnostic.DiagnosticLabel {
  @diagnostic.DiagnosticLabel(
    style,
    @diagnostic.SourceSpan(source_id, pretty_test_range(start, end)),
    message,
  )
}

///|
test "options reject non-positive tab widths with the typed moji cause" {
  for width in [0, -2] {
    let result : Result[DiagnosticPrettyOptions, DiagnosticPrettyError] = Ok(
      DiagnosticPrettyOptions(tab_width=width),
    ) catch {
      error => Err(error)
    }
    match result {
      Err(DisplayWidth(@moji.InvalidTabWidth(actual))) =>
        inspect(actual, content=width.to_string())
      _ => abort("expected invalid tab width")
    }
  }
}

///|
test "locationless layout resolves no source and honors ambiguous-width fit" {
  let mut calls = 0
  let resolver = PrettyTestResolver::{
    resolve: _ => {
      calls = calls + 1
      None
    },
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Info,
    message="·",
  )
  let narrow = layout(diagnostic, resolver, pretty_test_options())
  let wide = layout(
    diagnostic,
    resolver,
    pretty_test_options(ambiguous_width=@moji.AmbiguousWidth::Wide),
  )
  inspect(@pretty.render_string(narrow, width=7), content="info: ·")
  inspect(
    @pretty.render_string(wide, width=7),
    content=(
      #|info:
      #|  ·
    ),
  )
  inspect(calls, content="0")
}

///|
test "report fields expand tabs and lower every line terminator to hardline" {
  let resolver = PrettyTestResolver::{ resolve: _ => None }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    code=Some(@diagnostic.DiagnosticCode("E\t1")),
    message="first\tvalue\nsecond",
    notes=["note\tone\r\nnext"],
  )
  let report = layout(diagnostic, resolver, pretty_test_options())
  inspect(
    @pretty.render_string(report, width=120),
    content=(
      #|error[E 1]:
      #|  first value
      #|  second
      #|= note:
      #|  note  one
      #|  next
    ),
  )
}

///|
test "source names and label messages never place raw newlines in text nodes" {
  let source_id = @diagnostic.SourceId("fields")
  let resolver = PrettyTestResolver::{
    resolve: _ => {
      Some(
        @diagnostic.SourceSnapshot(
          "src\tname\nnext",
          "x",
          @diagnostic.LineIndex::new("x"),
        ),
      )
    },
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Warning,
    message="source fields",
    labels=[
      pretty_test_label(
        Primary,
        source_id,
        0,
        1,
        message=Some("label\tone\rnext"),
      ),
    ],
  )
  inspect(
    @pretty.render_string(
      layout(diagnostic, resolver, pretty_test_options()),
      width=120,
    ),
    content=(
      #|warning: source fields
      #|--> src name
      #|next
      #|primary 1:1-1:2:
      #|  label one
      #|  next
      #|  1 | x
      #|    | ^
    ),
  )
}

///|
test "Unicode source markers use display cells tabs and zero-width fallback" {
  let source_id = @diagnostic.SourceId("unicode")
  let source = "\t界😈e\u{301}\u{200B}·"
  let resolver = PrettyTestResolver::{
    resolve: requested => {
      if requested == source_id {
        Some(
          @diagnostic.SourceSnapshot(
            "unicode.mbt",
            source,
            @diagnostic.LineIndex::new(source),
          ),
        )
      } else {
        None
      }
    },
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Warning,
    message="Unicode markers",
    labels=[
      pretty_test_label(Primary, source_id, 0, 1, message=Some("tab")),
      pretty_test_label(Primary, source_id, 2, 4, message=Some("emoji")),
      pretty_test_label(Primary, source_id, 5, 6, message=Some("combining")),
      pretty_test_label(Primary, source_id, 6, 7, message=Some("zero width")),
      pretty_test_label(Secondary, source_id, 7, 8, message=Some("ambiguous")),
    ],
  )
  let default_rendered = @pretty.render_string(
    layout(diagnostic, resolver, pretty_test_options()),
    width=120,
  )
  inspect(default_rendered.contains("    | ^^"), content="true")
  inspect(default_rendered.contains("    |     ^^"), content="true")
  inspect(default_rendered.contains("    |       ^"), content="true")
  inspect(default_rendered.contains("    |        ^"), content="true")
  inspect(default_rendered.contains("    |        -"), content="true")
  let tab_three = @pretty.render_string(
    layout(diagnostic, resolver, pretty_test_options(tab_width=3)),
    width=120,
  )
  inspect(tab_three.contains("    | ^^^"), content="true")
  let ambiguous_wide = @pretty.render_string(
    layout(
      diagnostic,
      resolver,
      pretty_test_options(ambiguous_width=@moji.AmbiguousWidth::Wide),
    ),
    width=120,
  )
  inspect(ambiguous_wide.contains("    |        --"), content="true")
}

///|
test "layout preserves source group and label order and resolves each source once" {
  let first = @diagnostic.SourceId("first")
  let second = @diagnostic.SourceId("second")
  let mut first_calls = 0
  let mut second_calls = 0
  let resolver = PrettyTestResolver::{
    resolve: source_id => {
      if source_id == first {
        first_calls = first_calls + 1
        Some(
          @diagnostic.SourceSnapshot(
            "first.mbt",
            "abc",
            @diagnostic.LineIndex::new("abc"),
          ),
        )
      } else if source_id == second {
        second_calls = second_calls + 1
        Some(
          @diagnostic.SourceSnapshot(
            "second.mbt",
            "xyz",
            @diagnostic.LineIndex::new("xyz"),
          ),
        )
      } else {
        None
      }
    },
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="ordered",
    labels=[
      pretty_test_label(Primary, first, 0, 1, message=Some("first primary")),
      pretty_test_label(Secondary, second, 1, 2, message=Some("second")),
      pretty_test_label(Secondary, first, 2, 3, message=Some("first secondary")),
    ],
    notes=["one", "two"],
  )
  inspect(
    @pretty.render_string(
      layout(diagnostic, resolver, pretty_test_options()),
      width=120,
    ),
    content=(
      #|error: ordered
      #|--> first.mbt
      #|primary 1:1-1:2: first primary
      #|  1 | abc
      #|    | ^
      #|secondary 1:3-1:4: first secondary
      #|  1 | abc
      #|    |   -
      #|--> second.mbt
      #|secondary 1:2-1:3: second
      #|  1 | xyz
      #|    |  -
      #|= note: one
      #|= note: two
    ),
  )
  inspect(first_calls, content="1")
  inspect(second_calls, content="1")
}

///|
test "layout preserves empty EOF multiline and line terminator ranges" {
  let empty = @diagnostic.SourceId("empty")
  let eof = @diagnostic.SourceId("eof")
  let multiline = @diagnostic.SourceId("multiline")
  let crlf = @diagnostic.SourceId("crlf")
  let cr = @diagnostic.SourceId("cr")
  let resolver = PrettyTestResolver::{
    resolve: source_id => {
      if source_id == empty {
        Some(
          @diagnostic.SourceSnapshot(
            "empty.mbt",
            "",
            @diagnostic.LineIndex::new(""),
          ),
        )
      } else if source_id == eof {
        Some(
          @diagnostic.SourceSnapshot(
            "eof.mbt",
            "ab",
            @diagnostic.LineIndex::new("ab"),
          ),
        )
      } else if source_id == multiline {
        Some(
          @diagnostic.SourceSnapshot(
            "lf.mbt",
            "ab\ncd",
            @diagnostic.LineIndex::new("ab\ncd"),
          ),
        )
      } else if source_id == crlf {
        Some(
          @diagnostic.SourceSnapshot(
            "crlf.mbt",
            "ab\r\ncd",
            @diagnostic.LineIndex::new("ab\r\ncd"),
          ),
        )
      } else if source_id == cr {
        Some(
          @diagnostic.SourceSnapshot(
            "cr.mbt",
            "ab\rcd",
            @diagnostic.LineIndex::new("ab\rcd"),
          ),
        )
      } else {
        None
      }
    },
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Hint,
    message="boundaries",
    labels=[
      pretty_test_label(Primary, empty, 0, 0),
      pretty_test_label(Secondary, eof, 2, 2),
      pretty_test_label(Primary, multiline, 1, 4),
      pretty_test_label(Primary, crlf, 3, 4),
      pretty_test_label(Primary, cr, 2, 3),
    ],
  )
  let rendered = @pretty.render_string(
    layout(diagnostic, resolver, pretty_test_options()),
    width=120,
  )
  inspect(
    rendered.contains("--> empty.mbt\nprimary 1:1-1:1\n  1 |\n    | ^"),
    content="true",
  )
  inspect(
    rendered.contains("--> eof.mbt\nsecondary 1:3-1:3\n  1 | ab\n    |   -"),
    content="true",
  )
  inspect(
    rendered.contains(
      "--> lf.mbt\nprimary 1:2-2:2\n  1 | ab\n    |  ^\n  2 | cd\n    | ^",
    ),
    content="true",
  )
  inspect(
    rendered.contains("--> crlf.mbt\nprimary 1:4-2:1\n  1 | ab\n    |    ^"),
    content="true",
  )
  inspect(
    rendered.contains("--> cr.mbt\nprimary 1:3-2:1\n  1 | ab\n    |   ^"),
    content="true",
  )
}

///|
test "layout wraps every source validation failure without clamping" {
  let source_id = @diagnostic.SourceId("bad")
  let diagnostic_for : (Int, Int) -> @diagnostic.Diagnostic = (start, end) => {
    @diagnostic.Diagnostic(
      origin=@diagnostic.DiagnosticOrigin("test"),
      severity=@diagnostic.DiagnosticSeverity::Error,
      message="bad source",
      labels=[pretty_test_label(Primary, source_id, start, end)],
    )
  }
  let missing : Result[@pretty.Layout[DiagnosticStyle], DiagnosticPrettyError] = Ok(
    layout(
      diagnostic_for(0, 1),
      PrettyTestResolver::{ resolve: _ => None },
      pretty_test_options(),
    ),
  ) catch {
    error => Err(error)
  }
  match missing {
    Err(Diagnostic(@diagnostic.MissingSource(actual))) =>
      inspect(actual == source_id, content="true")
    _ => abort("expected missing source")
  }
  let stale : Result[@pretty.Layout[DiagnosticStyle], DiagnosticPrettyError] = Ok(
    layout(
      diagnostic_for(0, 1),
      PrettyTestResolver::{
        resolve: _ => {
          Some(
            @diagnostic.SourceSnapshot(
              "stale.mbt",
              "x",
              @diagnostic.LineIndex::new("y\n"),
            ),
          )
        },
      },
      pretty_test_options(),
    ),
  ) catch {
    error => Err(error)
  }
  match stale {
    Err(Diagnostic(@diagnostic.MismatchedLineIndex(actual))) =>
      inspect(actual == source_id, content="true")
    _ => abort("expected stale line index")
  }
  let out_of_bounds : Result[
    @pretty.Layout[DiagnosticStyle],
    DiagnosticPrettyError,
  ] = Ok(
    layout(
      diagnostic_for(0, 2),
      PrettyTestResolver::{
        resolve: _ => {
          Some(
            @diagnostic.SourceSnapshot(
              "short.mbt",
              "x",
              @diagnostic.LineIndex::new("x"),
            ),
          )
        },
      },
      pretty_test_options(),
    ),
  ) catch {
    error => Err(error)
  }
  match out_of_bounds {
    Err(Diagnostic(@diagnostic.RangeOutOfBounds(span, source_len))) => {
      inspect(span.source_id() == source_id, content="true")
      inspect(source_len, content="1")
    }
    _ => abort("expected out-of-bounds range")
  }
  let invalid_utf16 : Result[
    @pretty.Layout[DiagnosticStyle],
    DiagnosticPrettyError,
  ] = Ok(
    layout(
      diagnostic_for(1, 2),
      PrettyTestResolver::{
        resolve: _ => {
          Some(
            @diagnostic.SourceSnapshot(
              "emoji.mbt",
              "😈",
              @diagnostic.LineIndex::new("😈"),
            ),
          )
        },
      },
      pretty_test_options(),
    ),
  ) catch {
    error => Err(error)
  }
  match invalid_utf16 {
    Err(Diagnostic(@diagnostic.InvalidUtf16Boundary(span))) =>
      inspect(span.source_id() == source_id, content="true")
    _ => abort("expected invalid UTF-16 boundary")
  }
}

///|
test "layout annotations preserve nesting and exact emitted UTF-16 spans" {
  let source_id = @diagnostic.SourceId("annotated")
  let resolver = PrettyTestResolver::{
    resolve: _ => {
      Some(
        @diagnostic.SourceSnapshot("s", "x", @diagnostic.LineIndex::new("x")),
      )
    },
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("test"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="m",
    labels=[pretty_test_label(Primary, source_id, 0, 1, message=Some("label"))],
  )
  let spans = @pretty.render_spans(
    layout(diagnostic, resolver, pretty_test_options()),
    width=80,
  )
  debug_inspect(
    spans,
    content=(
      #|[
      #|  ({ start: 0, end: 5 }, Severity(Error)),
      #|  ({ start: 9, end: 13 }, Gutter),
      #|  ({ start: 13, end: 14 }, SourceName),
      #|  ({ start: 15, end: 37 }, Primary),
      #|  ({ start: 38, end: 44 }, Gutter),
      #|  ({ start: 46, end: 52 }, Gutter),
      #|  ({ start: 46, end: 53 }, Primary),
      #|]
    ),
  )
}
