///|
const COMMONMARK_VERSION = "0.31.2"

///|
const DEFAULT_SPEC_PATH = "tools/commonmark-0.31.2-spec.json"

///|
struct AuditOptions {
  spec_path : String
}

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
fn usage() -> String {
  "Usage: moon run src/tools/commonmark_html_audit --target native -- [--spec path/to/spec.json]\n\n" +
  "Reads CommonMark " +
  COMMONMARK_VERSION +
  " spec.json and audits MarkdownIR -> CommonMark HTML output.\n" +
  "Default spec path: " +
  DEFAULT_SPEC_PATH
}

///|
fn program_args(args : Array[String]) -> ArrayView[String] {
  match args {
    [_, .. rest] => rest
    [] => []
  }
}

///|
fn parse_args(args : ArrayView[String]) -> AuditOptions {
  for i = 0, spec_path = DEFAULT_SPEC_PATH {
    if i >= args.length() {
      break { spec_path, }
    }
    match args[i] {
      "--help" | "-h" => {
        println(usage())
        @sys.exit(0)
        break { spec_path, }
      }
      "--spec" => {
        if i + 1 >= args.length() {
          println("error: --spec requires a path")
          @sys.exit(2)
          break { spec_path, }
        }
        continue i + 2, args[i + 1].to_string()
      }
      unknown => {
        println("error: unknown argument: " + unknown.to_string())
        @sys.exit(2)
        break { spec_path, }
      }
    }
  }
}

///|
fn load_spec_examples(path : String) -> Array[CommonMarkSpecExample] raise {
  let source = @fs.read_file_to_string(path)
  let json = @json.parse(source)
  @json.from_json(json)
}

///|
fn CommonMarkSpecExample::outcome(self : CommonMarkSpecExample) -> AuditOutcome {
  let (cst, diagnostics) = @markdown.parse_cst(self.markdown) catch {
    _ => return LexError
  }
  let ir = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
  let actual = @markdown.experimental_markdown_ir_to_commonmark_html(ir)
  if actual == self.html {
    Pass
  } else if actual.contains("unsupported MarkdownIR") ||
    actual.contains("recovered MarkdownIR") {
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
  let options = parse_args(program_args(@env.args()))
  let examples = load_spec_examples(options.spec_path) catch {
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
