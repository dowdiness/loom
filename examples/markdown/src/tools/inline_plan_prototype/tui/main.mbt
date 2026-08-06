// PROTOTYPE — THROWAWAY. Keep this CLI shell off main.
//
// Run the interactive shell from examples/markdown:
//   ./src/tools/inline_plan_prototype/run.sh

///|
let help : String =
  #|#890 container-local inline-plan prototype
  #|
  #|Usage:
  #|  moon run src/tools/inline_plan_prototype/tui --target native -- --index N
  #|  moon run src/tools/inline_plan_prototype/tui --target native -- --all
  #|  moon run src/tools/inline_plan_prototype/tui --target native -- --stress
  #|
  #|Use ../run.sh for the interactive TUI.
  #|

///|
fn parse_index(raw : String) -> Int? {
  try @string.parse_int(raw) catch {
    _ => None
  } noraise {
    index => Some(index)
  }
}

///|
fn rendered_scenario(index : Int) -> String? {
  try @prototype.prototype_render_scenario(index) catch {
    _ => None
  } noraise {
    rendered => Some(rendered)
  }
}

///|
fn all_summary() -> String? {
  try @prototype.prototype_all_summary() catch {
    _ => None
  } noraise {
    summary => Some(summary)
  }
}

///|
fn main {
  match @env.args()[1:] {
    ["--index", raw] =>
      match parse_index(raw) {
        Some(index) =>
          match rendered_scenario(index) {
            Some(rendered) => println(rendered)
            None => @sys.exit(2)
          }
        None => @sys.exit(2)
      }
    ["--all"] =>
      match all_summary() {
        Some(summary) => println(summary)
        None => @sys.exit(2)
      }
    ["--stress"] => println(@prototype.prototype_stress_report())
    ["--count"] => println(@prototype.prototype_scenario_count())
    ["--help" | "-h"] | [] => println(help)
    _ => {
      println(help)
      @sys.exit(2)
    }
  }
}
