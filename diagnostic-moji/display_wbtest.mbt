///|
struct DisplayTestResolver {
  id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
}

///|
impl @diagnostic.SourceResolver for DisplayTestResolver with fn resolve_source(
  self,
  id,
) {
  if id == self.id {
    Some(self.snapshot)
  } else {
    None
  }
}

///|
fn display_test_range(start : Int, end : Int) -> @diagnostic.TextRange {
  try @diagnostic.TextRange::from_offsets(start, end) catch {
    _ => abort("expected valid display test range")
  } noraise {
    range => range
  }
}

///|
fn display_test_label(
  style : @diagnostic.LabelStyle,
  source_id : @diagnostic.SourceId,
  start : Int,
  end : Int,
  message : String,
) -> @diagnostic.DiagnosticLabel {
  @diagnostic.DiagnosticLabel(
    style,
    @diagnostic.SourceSpan(source_id, display_test_range(start, end)),
    Some(message),
  )
}

///|
test "moji diagnostic renderer aligns CJK and tab markers" {
  let source_id = @diagnostic.SourceId("width")
  let source = "界\tx"
  let resolver = DisplayTestResolver::{
    id: source_id,
    snapshot: @diagnostic.SourceSnapshot(
      "width.mbt",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Hint,
    message="display cells",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        source_id,
        0,
        1,
        "wide",
      ),
      display_test_label(
        @diagnostic.LabelStyle::Secondary,
        source_id,
        2,
        3,
        "after tab",
      ),
    ],
  )
  inspect(
    render_plain(diagnostic, resolver),
    content=(
      #|hint: display cells
      #|--> width.mbt
      #|primary 1:1-1:2: wide
      #|  1 | 界    x
      #|    | ^^
      #|secondary 1:3-1:4: after tab
      #|  1 | 界    x
      #|    |       -
    ),
  )
}

///|
test "moji diagnostic renderer aligns a later marker after an astral prefix" {
  let source_id = @diagnostic.SourceId("astral-prefix")
  let source = "𝒜; let ="
  let resolver = DisplayTestResolver::{
    id: source_id,
    snapshot: @diagnostic.SourceSnapshot(
      "astral.js",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("js_engine"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="expected identifier",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        source_id,
        8,
        9,
        "parser stopped here",
      ),
    ],
  )
  inspect(
    render_plain(diagnostic, resolver),
    content=(
      #|error: expected identifier
      #|--> astral.js
      #|primary 1:9-1:10: parser stopped here
      #|  1 | 𝒜; let =
      #|    |        ^
    ),
  )
}

///|
test "moji diagnostic renderer keeps a marker for a zero-width span" {
  let source_id = @diagnostic.SourceId("zero-width")
  let source = "a\u{200B}b"
  let resolver = DisplayTestResolver::{
    id: source_id,
    snapshot: @diagnostic.SourceSnapshot(
      "zero.mbt",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
  let diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Warning,
    message="zero width",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        source_id,
        1,
        2,
        "invisible",
      ),
    ],
  )
  inspect(
    render_plain(diagnostic, resolver),
    content="warning: zero width\n--> zero.mbt\nprimary 1:2-1:3: invisible\n  1 | a\u{200B}b\n    |  ^",
  )
}

///|
test "moji diagnostic renderer expands interior spans to display units" {
  let sequence_id = @diagnostic.SourceId("sequence")
  let sequence = "\u{16D69}\u{16D68}\u{16D67}"
  let sequence_resolver = DisplayTestResolver::{
    id: sequence_id,
    snapshot: @diagnostic.SourceSnapshot(
      "sequence.mbt",
      sequence,
      @diagnostic.LineIndex::new(sequence),
    ),
  }
  let sequence_diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="non-additive sequence",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        sequence_id,
        4,
        6,
        "last grapheme",
      ),
    ],
  )
  inspect(
    render_plain(sequence_diagnostic, sequence_resolver),
    content="error: non-additive sequence\n--> sequence.mbt\nprimary 1:5-1:7: last grapheme\n  1 | \u{16D69}\u{16D68}\u{16D67}\n    | ^^",
  )
  let combining_id = @diagnostic.SourceId("combining-interior")
  let combining = "e\u{301}"
  let combining_resolver = DisplayTestResolver::{
    id: combining_id,
    snapshot: @diagnostic.SourceSnapshot(
      "combining.mbt",
      combining,
      @diagnostic.LineIndex::new(combining),
    ),
  }
  let combining_diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Warning,
    message="combining interior",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Secondary,
        combining_id,
        1,
        2,
        "mark",
      ),
    ],
  )
  inspect(
    render_plain(combining_diagnostic, combining_resolver),
    content="warning: combining interior\n--> combining.mbt\nsecondary 1:2-1:3: mark\n  1 | e\u{301}\n    | -",
  )
}

///|
test "moji diagnostic renderer preserves line terminator positions" {
  let lf_id = @diagnostic.SourceId("lf")
  let lf_source = "ab\ncd"
  let lf_diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="LF",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        lf_id,
        2,
        3,
        "line feed",
      ),
    ],
  )
  inspect(
    render_plain(lf_diagnostic, DisplayTestResolver::{
      id: lf_id,
      snapshot: @diagnostic.SourceSnapshot(
        "lf.mbt",
        lf_source,
        @diagnostic.LineIndex::new(lf_source),
      ),
    }),
    content="error: LF\n--> lf.mbt\nprimary 1:3-2:1: line feed\n  1 | ab\n    |   ^",
  )
  let crlf_id = @diagnostic.SourceId("crlf")
  let crlf_source = "ab\r\ncd"
  let crlf_diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="CRLF",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        crlf_id,
        3,
        4,
        "inside CRLF",
      ),
    ],
  )
  inspect(
    render_plain(crlf_diagnostic, DisplayTestResolver::{
      id: crlf_id,
      snapshot: @diagnostic.SourceSnapshot(
        "crlf.mbt",
        crlf_source,
        @diagnostic.LineIndex::new(crlf_source),
      ),
    }),
    content="error: CRLF\n--> crlf.mbt\nprimary 1:4-2:1: inside CRLF\n  1 | ab\n    |    ^",
  )
  let cr_id = @diagnostic.SourceId("cr")
  let cr_source = "ab\rcd"
  let cr_diagnostic = @diagnostic.Diagnostic(
    origin=@diagnostic.DiagnosticOrigin("renderer"),
    severity=@diagnostic.DiagnosticSeverity::Error,
    message="CR",
    labels=[
      display_test_label(
        @diagnostic.LabelStyle::Primary,
        cr_id,
        2,
        3,
        "carriage return",
      ),
    ],
  )
  inspect(
    render_plain(cr_diagnostic, DisplayTestResolver::{
      id: cr_id,
      snapshot: @diagnostic.SourceSnapshot(
        "cr.mbt",
        cr_source,
        @diagnostic.LineIndex::new(cr_source),
      ),
    }),
    content="error: CR\n--> cr.mbt\nprimary 1:3-2:1: carriage return\n  1 | ab\n    |   ^",
  )
}
