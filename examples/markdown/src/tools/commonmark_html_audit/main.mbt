///|
const COMMONMARK_VERSION = "0.31.2"

///|
const DEFAULT_SPEC_PATH = "tools/commonmark-0.31.2-spec.json"

///|
const PINNED_SPEC_SHA256 = "d431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20"

///|
const PINNED_SPEC_EXAMPLE_COUNT = 652

///|
struct CommonMarkSpecExample {
  markdown : String
  html : String
  section : String
  example : Int
} derive(FromJson, Debug)

///|
struct LoadedCorpus {
  examples : Array[CommonMarkSpecExample]
  sha256 : String
}

///|
enum AuditOutcome {
  Pass
  LexError
  ParserDiagnostics
  Unsupported
  MalformedRaw
  Recovered
  AdapterPolicyRejection
  HtmlMismatch
} derive(Eq, Debug)

///|
struct AuditCounts {
  pass : Int
  render_match : Int
  lex_error : Int
  parser_diagnostics : Int
  unsupported : Int
  malformed_raw : Int
  recovered : Int
  adapter_policy_rejection : Int
  html_mismatch : Int
  skip : Int
  xfail : Int
} derive(Eq, Debug)

///|
struct AuditAssessment {
  outcome : AuditOutcome
  html_matches : Bool
} derive(Eq, Debug)

///|
struct AuditSignals {
  parser_diagnostics : Bool
  unsupported : Bool
  malformed_raw : Bool
  recovered : Bool
  adapter_policy_rejected : Bool
  html_matches : Bool
} derive(Eq, Debug)

///|
struct MarkdownIRAssistance {
  unsupported : Bool
  malformed_raw : Bool
  recovered : Bool
}

///|
struct SectionState {
  name : String
  counts : AuditCounts
}

///|
fn AuditCounts::empty() -> AuditCounts {
  {
    pass: 0,
    render_match: 0,
    lex_error: 0,
    parser_diagnostics: 0,
    unsupported: 0,
    malformed_raw: 0,
    recovered: 0,
    adapter_policy_rejection: 0,
    html_mismatch: 0,
    skip: 0,
    xfail: 0,
  }
}

///|
fn AuditCounts::record_assessment(
  self : AuditCounts,
  assessment : AuditAssessment,
) -> AuditCounts {
  let counts = self.record(assessment.outcome)
  if assessment.html_matches {
    { ..counts, render_match: counts.render_match + 1 }
  } else {
    counts
  }
}

///|
fn AuditCounts::record(
  self : AuditCounts,
  outcome : AuditOutcome,
) -> AuditCounts {
  match outcome {
    Pass => { ..self, pass: self.pass + 1 }
    LexError => { ..self, lex_error: self.lex_error + 1 }
    ParserDiagnostics =>
      { ..self, parser_diagnostics: self.parser_diagnostics + 1 }
    Unsupported => { ..self, unsupported: self.unsupported + 1 }
    MalformedRaw => { ..self, malformed_raw: self.malformed_raw + 1 }
    Recovered => { ..self, recovered: self.recovered + 1 }
    AdapterPolicyRejection =>
      { ..self, adapter_policy_rejection: self.adapter_policy_rejection + 1 }
    HtmlMismatch => { ..self, html_mismatch: self.html_mismatch + 1 }
  }
}

///|
fn AuditCounts::fail(self : AuditCounts) -> Int {
  self.lex_error +
  self.parser_diagnostics +
  self.unsupported +
  self.malformed_raw +
  self.recovered +
  self.adapter_policy_rejection +
  self.html_mismatch +
  self.skip +
  self.xfail
}

///|
fn AuditCounts::total(self : AuditCounts) -> Int {
  self.pass + self.fail()
}

///|
fn AuditCounts::is_complete(self : AuditCounts, expected_total~ : Int) -> Bool {
  self.total() == expected_total &&
  self.pass == expected_total &&
  self.render_match == expected_total &&
  self.fail() == 0
}

///|
fn AuditOutcome::label(self : AuditOutcome) -> String {
  match self {
    Pass => "pass"
    LexError => "lex-error"
    ParserDiagnostics => "parser-diagnostics"
    Unsupported => "unsupported"
    MalformedRaw => "malformed-raw"
    Recovered => "recovered"
    AdapterPolicyRejection => "adapter-policy-rejection"
    HtmlMismatch => "html-mismatch"
  }
}

///|
fn classify_audit(signals : AuditSignals) -> AuditOutcome {
  // Lexing failure is returned before signals exist. Once parsing succeeds,
  // this order assigns exactly one owner to every example:
  // diagnostics > Unsupported > malformed Raw > Recovered > adapter policy
  // > HTML mismatch > clean pass.
  if signals.parser_diagnostics {
    ParserDiagnostics
  } else if signals.unsupported {
    Unsupported
  } else if signals.malformed_raw {
    MalformedRaw
  } else if signals.recovered {
    Recovered
  } else if signals.adapter_policy_rejected {
    AdapterPolicyRejection
  } else if !signals.html_matches {
    HtmlMismatch
  } else {
    Pass
  }
}

///|
fn corpus_is_pinned(
  version~ : String,
  sha256~ : String,
  example_count~ : Int,
) -> Bool {
  version == COMMONMARK_VERSION &&
  sha256 == PINNED_SPEC_SHA256 &&
  example_count == PINNED_SPEC_EXAMPLE_COUNT
}

///|
fn sha256_hex(source : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding.encode(@encoding.UTF8, source)),
  )
}

///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  match args {
    [_, .. rest] => rest
    [] => []
  }
}

///|
fn first_value(
  values : Map[String, Array[String]],
  key : String,
  default : String,
) -> String {
  match values.get(key) {
    Some([value, ..]) => value
    _ => default
  }
}

///|
fn audit_command() -> @argparse.Command {
  @argparse.Command(
    "commonmark-html-audit",
    options=[
      @argparse.OptionArg(
        "spec",
        default_values=[DEFAULT_SPEC_PATH],
        about="Path to CommonMark spec.json (default: " +
          DEFAULT_SPEC_PATH +
          ")",
      ),
    ],
    about="Audit MarkdownIR -> CommonMark HTML output against CommonMark " +
      COMMONMARK_VERSION +
      ".",
  )
}

///|
fn parse_spec_path(args : ArrayView[String]) -> String {
  let matches = audit_command().parse(argv=args, env=Map([])) catch {
    err => {
      println(err.to_string())
      @sys.exit(2)
      return DEFAULT_SPEC_PATH
    }
  }
  first_value(matches.values, "spec", DEFAULT_SPEC_PATH)
}

///|
fn load_spec_examples(path : String) -> LoadedCorpus raise {
  let source = @fs.read_file_to_string(path)
  let json = @json.parse(source)
  let examples : Array[CommonMarkSpecExample] = @json.from_json(json)
  { examples, sha256: sha256_hex(source) }
}

///|
fn markdown_ir_assistance(ir : @markdown.MarkdownIR) -> MarkdownIRAssistance {
  let mut assistance = MarkdownIRAssistance::{
    unsupported: ir.is_unsupported(),
    malformed_raw: ir.is_raw(),
    recovered: ir.is_recovered(),
  }
  for child in ir.children() {
    let child_assistance = markdown_ir_assistance(child)
    assistance = {
      unsupported: assistance.unsupported || child_assistance.unsupported,
      malformed_raw: assistance.malformed_raw || child_assistance.malformed_raw,
      recovered: assistance.recovered || child_assistance.recovered,
    }
  }
  assistance
}

///|
fn CommonMarkSpecExample::assessment(
  self : CommonMarkSpecExample,
) -> AuditAssessment {
  let source_id = @core.SourceId(
    "markdown-commonmark-html-audit:" + self.example.to_string(),
  )
  let (cst, diagnostics) = @markdown.parse_cst(source_id, self.markdown) catch {
    @core.LexError(_) =>
      return AuditAssessment::{ outcome: LexError, html_matches: false }
  }
  let ir = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = @markdown.experimental_markdown_ir_to_commonmark_html(ir)
  let assistance = markdown_ir_assistance(ir)
  let signals = AuditSignals::{
    parser_diagnostics: diagnostics.length() > 0,
    unsupported: assistance.unsupported,
    malformed_raw: assistance.malformed_raw,
    recovered: assistance.recovered,
    // The current CommonMark adapter cannot reject a raw-HTML policy. This
    // remains an explicit signal so #809 can wire its structured failure into
    // the taxonomy without changing classification precedence.
    adapter_policy_rejected: false,
    html_matches: actual == self.html,
  }
  { outcome: classify_audit(signals), html_matches: signals.html_matches }
}

///|
fn example_line(
  example : CommonMarkSpecExample,
  assessment : AuditAssessment,
) -> String {
  "example\t" +
  example.section +
  "\t" +
  example.example.to_string() +
  "\t" +
  assessment.outcome.label() +
  "\t" +
  assessment.html_matches.to_string()
}

///|
fn print_example(
  example : CommonMarkSpecExample,
  assessment : AuditAssessment,
) -> Unit {
  println(example_line(example, assessment))
}

///|
fn print_counts(kind : String, name : String, counts : AuditCounts) -> Unit {
  println(
    kind +
    "\t" +
    name +
    "\ttotal=" +
    counts.total().to_string() +
    "\tpass=" +
    counts.pass.to_string() +
    "\trender-match=" +
    counts.render_match.to_string() +
    "\tfail=" +
    counts.fail().to_string() +
    "\tskip=" +
    counts.skip.to_string() +
    "\txfail=" +
    counts.xfail.to_string() +
    "\tlex-error=" +
    counts.lex_error.to_string() +
    "\tparser-diagnostics=" +
    counts.parser_diagnostics.to_string() +
    "\tunsupported=" +
    counts.unsupported.to_string() +
    "\tmalformed-raw=" +
    counts.malformed_raw.to_string() +
    "\trecovered=" +
    counts.recovered.to_string() +
    "\tadapter-policy-rejection=" +
    counts.adapter_policy_rejection.to_string() +
    "\thtml-mismatch=" +
    counts.html_mismatch.to_string(),
  )
}

///|
fn flush_section(state : SectionState?) -> Unit {
  match state {
    Some(section) => print_counts("section", section.name, section.counts)
    None => ()
  }
}

///|
fn audit_examples(examples : Array[CommonMarkSpecExample]) -> AuditCounts {
  for
    example in examples
    section = (None : SectionState?), total = AuditCounts::empty() {
    let section = match section {
      Some(current) if current.name == example.section => current
      Some(current) => {
        print_counts("section", current.name, current.counts)
        { name: example.section, counts: AuditCounts::empty() }
      }
      None => { name: example.section, counts: AuditCounts::empty() }
    }
    let assessment = example.assessment()
    print_example(example, assessment)
    continue Some({
        name: section.name,
        counts: section.counts.record_assessment(assessment),
      }),
      total.record_assessment(assessment)
  } nobreak {
    flush_section(section)
    total
  }
}

///|
fn main {
  let spec_path = parse_spec_path(program_args(@env.args()))
  let corpus = load_spec_examples(spec_path) catch {
    err => {
      println("error: " + err.to_string())
      @sys.exit(1)
      return
    }
  }
  if !corpus_is_pinned(
      version=COMMONMARK_VERSION,
      sha256=corpus.sha256,
      example_count=corpus.examples.length(),
    ) {
    println(
      "error: unpinned CommonMark corpus" +
      "\tversion=" +
      COMMONMARK_VERSION +
      "\tsha256=" +
      corpus.sha256 +
      "\texamples=" +
      corpus.examples.length().to_string(),
    )
    @sys.exit(1)
    return
  }
  println("CommonMark " + COMMONMARK_VERSION + " full-corpus HTML audit")
  println(
    "corpus\tall\tversion=" +
    COMMONMARK_VERSION +
    "\tsha256=" +
    corpus.sha256 +
    "\texamples=" +
    corpus.examples.length().to_string() +
    "\tpinned=true",
  )
  println("kind\tsection\texample\tcategory\thtml-match")
  let counts = audit_examples(corpus.examples)
  print_counts("total", "all", counts)
  println(
    "completion\tall\tcomplete=" +
    counts.is_complete(expected_total=PINNED_SPEC_EXAMPLE_COUNT).to_string(),
  )
}
