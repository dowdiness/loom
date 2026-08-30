///|
/// Render a detached Markdown document as HTML.
///
/// Raw HTML is escaped by default.
pub fn html(document : MarkdownDocument) -> String {
  experimental_markdown_ir_to_commonmark_html(document.ir)
}
