///|
/// Semantic extensions enabled for one Markdown lowering pass.
///
/// Parsing remains lossless for extension-shaped syntax. These options decide
/// whether that syntax is promoted beyond CommonMark literal semantics.
pub struct MarkdownExtensions {
  priv task_list : Bool
} derive(Eq, @debug.Debug)

///|
/// CommonMark semantics without extensions.
pub fn MarkdownExtensions::none() -> MarkdownExtensions {
  { task_list: false }
}

///|
/// CommonMark semantics with the GFM task-list-item extension.
pub fn MarkdownExtensions::task_list() -> MarkdownExtensions {
  { task_list: true }
}

///|
fn MarkdownExtensions::has_task_list(self : MarkdownExtensions) -> Bool {
  self.task_list
}
