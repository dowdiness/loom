///|
const COMMONMARK_VERSION = "0.31.2"

///|
const DEFAULT_SPEC_PATH = "tools/commonmark-0.31.2-spec.json"

///|
struct CommonMarkSpecExample {
  markdown : String
  html : String
  section : String
  example : Int
} derive(FromJson, Debug)

///|
enum AuditOutcome {
  Pass
  LexError
  UnsupportedIr
  ParserDiagnostics
  Mismatch
} derive(Eq, Debug)

///|
struct AuditCounts {
  pass : Int
  lex_error : Int
  unsupported_ir : Int
  parser_diagnostics : Int
  mismatch : Int
} derive(Eq, Debug)

///|
struct SectionState {
  name : String
  counts : AuditCounts
}

///|
fn AuditCounts::empty() -> AuditCounts {
  {
    pass: 0,
    lex_error: 0,
    unsupported_ir: 0,
    parser_diagnostics: 0,
    mismatch: 0,
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
    UnsupportedIr => { ..self, unsupported_ir: self.unsupported_ir + 1 }
    ParserDiagnostics =>
      { ..self, parser_diagnostics: self.parser_diagnostics + 1 }
    Mismatch => { ..self, mismatch: self.mismatch + 1 }
  }
}

///|
fn AuditCounts::fail(self : AuditCounts) -> Int {
  self.lex_error + self.unsupported_ir + self.parser_diagnostics + self.mismatch
}

///|
fn AuditOutcome::label(self : AuditOutcome) -> String {
  match self {
    Pass => "pass"
    LexError => "lex-error"
    UnsupportedIr => "unsupported-ir"
    ParserDiagnostics => "parser-diagnostics"
    Mismatch => "mismatch"
  }
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
  let matches = audit_command().parse(argv=args, env={}) catch {
    err => {
      println(err.to_string())
      @sys.exit(2)
      return DEFAULT_SPEC_PATH
    }
  }
  first_value(matches.values, "spec", DEFAULT_SPEC_PATH)
}

///|
fn load_spec_examples(path : String) -> Array[CommonMarkSpecExample] raise {
  let source = @fs.read_file_to_string(path)
  let json = @json.parse(source)
  @json.from_json(json)
}

///|
fn markdown_ir_contains_unsupported_or_recovered(
  ir : @markdown.MarkdownIR,
) -> Bool {
  ir.is_raw() ||
  ir.is_recovered() ||
  ir.is_unsupported() ||
  ir.children().any(markdown_ir_contains_unsupported_or_recovered)
}

///|
fn CommonMarkSpecExample::outcome(self : CommonMarkSpecExample) -> AuditOutcome {
  let (cst, diagnostics) = @markdown.parse_cst(self.markdown) catch {
    @core.LexError(_) => return LexError
  }
  let ir = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = @markdown.experimental_markdown_ir_to_commonmark_html(ir)
  // Pass is based on rendered CommonMark HTML parity; recovery-assisted
  // examples can still count as pass when the output matches the spec.
  if actual == self.html {
    Pass
  } else if markdown_ir_contains_unsupported_or_recovered(ir) {
    UnsupportedIr
  } else if diagnostics.length() > 0 {
    ParserDiagnostics
  } else {
    Mismatch
  }
}

///|
fn print_example(
  example : CommonMarkSpecExample,
  outcome : AuditOutcome,
) -> Unit {
  println(
    "example\t" +
    example.section +
    "\t" +
    example.example.to_string() +
    "\t" +
    outcome.label(),
  )
}

///|
fn print_counts(kind : String, name : String, counts : AuditCounts) -> Unit {
  println(
    kind +
    "\t" +
    name +
    "\tpass=" +
    counts.pass.to_string() +
    "\tfail=" +
    counts.fail().to_string() +
    "\tskip=0\tlex-error=" +
    counts.lex_error.to_string() +
    "\tunsupported-ir=" +
    counts.unsupported_ir.to_string() +
    "\tparser-diagnostics=" +
    counts.parser_diagnostics.to_string() +
    "\tmismatch=" +
    counts.mismatch.to_string(),
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
    let outcome = example.outcome()
    print_example(example, outcome)
    continue Some({ name: section.name, counts: section.counts.record(outcome) }),
      total.record(outcome)
  } nobreak {
    flush_section(section)
    total
  }
}

///|
fn main {
  let spec_path = parse_spec_path(program_args(@env.args()))
  let examples = load_spec_examples(spec_path) catch {
    err => {
      println("error: " + err.to_string())
      @sys.exit(1)
      return
    }
  }
  println("CommonMark " + COMMONMARK_VERSION + " full-corpus HTML audit")
  println("kind\tsection\texample\tcategory")
  let counts = audit_examples(examples)
  print_counts("total", "all", counts)
}
