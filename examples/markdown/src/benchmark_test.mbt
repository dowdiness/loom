// Markdown incremental parser benchmarks.
//
// Exercises realistic Markdown documents: headings, paragraphs with inline
// markup (bold, italic, inline code, links), unordered lists, fenced code
// blocks. Compares full reparse vs tokenize-only vs incremental edit.
//
// Run with: cd loom/examples/markdown && moon bench --release

///|
/// A realistic ~20-block Markdown document exercising all supported features.
fn realistic_markdown_doc() -> String {
  [
    "# Project Overview", "", "This is a **comprehensive** guide to the *incremental* parser framework.",
    "It supports `inline code`, [links](https://example.com), and **bold *nested* text**.",
    "", "## Architecture", "", "The system is built on three pillars:", "", "- Lexer with **mode-aware** tokenization",
    "- Incremental reparsing via `damage` tracking", "- CST-to-AST folding with *error recovery*",
    "", "## Getting Started", "", "Clone the repository and run the following command:",
    "", "```bash", "moon test --release", "cd examples/markdown && moon bench --release",
    "```", "", "The output will show timing for each benchmark.", "", "## Inline Markup Examples",
    "", "Here is a paragraph with **bold text**, *italic text*, `code spans`,", "and [a link](https://docs.example.com/guide) embedded in the flow.",
    "Multiple lines of text continue the same paragraph until a blank line.", "",
    "- First item with **emphasis** and `code`", "- Second item with a [reference](https://example.org)",
    "- Third item is plain text", "- Fourth item has *italic* markup", "", "## Code Examples",
    "", "```python", "def fibonacci(n):", "    if n <= 1:", "        return n", "    return fibonacci(n - 1) + fibonacci(n - 2)",
    "```", "", "The function above computes Fibonacci numbers recursively.", "For large inputs, consider **memoization** or an *iterative* approach.",
    "", "## Summary", "", "This document exercises headings, paragraphs, lists, and code blocks.",
    "Each block type has inline markup to stress the **full** grammar.",
  ].join("\n")
}

///|
/// Helper: replace one byte at pos in source.
fn md_replace_at(source : String, pos : Int, replacement : String) -> String {
  source[:pos].to_string() + replacement + source[pos + 1:].to_string()
}

///|
/// Find the byte position of a target substring in source.
/// Returns the position of the first character of the match, or -1.
fn find_substring(source : String, target : String) -> Int {
  for i = 0; i < source.length() - target.length() + 1; i = i + 1 {
    let sub : String = source[i:i + target.length()].to_string()
    if sub == target {
      return i
    }
  }
  -1
}

///|
/// Generate a scaled Markdown document by repeating varied sections.
/// Each repetition adds ~20 lines: heading, paragraph with inline markup,
/// list, and code block. Total lines ≈ repeats * 20.
fn scaled_markdown_doc(repeats : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("# Main Title\n\n")
  for i = 0; i < repeats; i = i + 1 {
    let n = i.to_string()
    buf.write_string("## Section " + n + "\n\n")
    buf.write_string(
      "This is paragraph " +
      n +
      " with **bold** and *italic* and `code` and [link](url).\n",
    )
    buf.write_string("Continuation line for paragraph " + n + ".\n\n")
    buf.write_string("- Item " + n + "a with **emphasis**\n")
    buf.write_string("- Item " + n + "b with `code`\n")
    buf.write_string("- Item " + n + "c plain\n\n")
    buf.write_string("```lang" + n + "\n")
    buf.write_string("code_line_1_" + n + "\n")
    buf.write_string("code_line_2_" + n + "\n")
    buf.write_string("```\n\n")
  }
  buf.to_string()
}

// --- Scaled benchmarks (10x, 50x, 100x) ------------------------------------

///|
test "markdown: 10x (~200 lines) - tokenize" (b : @bench.T) {
  let source = scaled_markdown_doc(10)
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown: 10x (~200 lines) - full parse" (b : @bench.T) {
  let source = scaled_markdown_doc(10)
  b.bench(fn() {
    let ast = parse(source)
    b.keep(ast)
  })
}

///|
test "markdown: 10x (~200 lines) - incremental" (b : @bench.T) {
  let source = scaled_markdown_doc(10)
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  // Edit in the middle: change a character in a paragraph
  let mid = source.length() / 2
  let edited = md_replace_at(source, mid, "X")
  let edit = @core.Edit::replace(mid, mid + 1, mid + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "markdown: 50x (~1000 lines) - tokenize" (b : @bench.T) {
  let source = scaled_markdown_doc(50)
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown: 50x (~1000 lines) - full parse" (b : @bench.T) {
  let source = scaled_markdown_doc(50)
  b.bench(fn() {
    let ast = parse(source)
    b.keep(ast)
  })
}

///|
test "markdown: 50x (~1000 lines) - incremental" (b : @bench.T) {
  let source = scaled_markdown_doc(50)
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  let mid = source.length() / 2
  let edited = md_replace_at(source, mid, "X")
  let edit = @core.Edit::replace(mid, mid + 1, mid + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "markdown: 100x (~2000 lines) - tokenize" (b : @bench.T) {
  let source = scaled_markdown_doc(100)
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

///|
test "markdown: 100x (~2000 lines) - full parse" (b : @bench.T) {
  let source = scaled_markdown_doc(100)
  b.bench(fn() {
    let ast = parse(source)
    b.keep(ast)
  })
}

///|
test "markdown: 100x (~2000 lines) - incremental" (b : @bench.T) {
  let source = scaled_markdown_doc(100)
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  let mid = source.length() / 2
  let edited = md_replace_at(source, mid, "X")
  let edit = @core.Edit::replace(mid, mid + 1, mid + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

// --- Baseline benchmarks (original ~55 line doc) ----------------------------

// --- Full parse benchmarks ---------------------------------------------------

///|
test "markdown: realistic doc - full parse (CST)" (b : @bench.T) {
  let source = realistic_markdown_doc()
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("parse failed") }
    b.keep(cst)
  })
}

///|
test "markdown: realistic doc - full parse (CST+AST)" (b : @bench.T) {
  let source = realistic_markdown_doc()
  b.bench(fn() {
    let ast = parse(source)
    b.keep(ast)
  })
}

// --- Tokenize-only benchmark -------------------------------------------------

///|
test "markdown: realistic doc - tokenize only" (b : @bench.T) {
  let source = realistic_markdown_doc()
  b.bench(fn() {
    let tokens = tokenize(source) catch { _ => abort("lex failed") }
    b.keep(tokens)
  })
}

// --- Incremental edit benchmarks ---------------------------------------------

///|
test "markdown: realistic doc - incremental (edit paragraph)" (b : @bench.T) {
  let source = realistic_markdown_doc()
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  // Edit inside "comprehensive" -> change 'c' to 'C' in a paragraph
  let target = "comprehensive"
  let edit_pos = find_substring(source, target)
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = md_replace_at(source, edit_pos, "C")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "markdown: realistic doc - incremental (edit heading)" (b : @bench.T) {
  let source = realistic_markdown_doc()
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  // Edit inside "Architecture" heading -> change 'A' to 'a'
  let target = "Architecture"
  let edit_pos = find_substring(source, target)
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = md_replace_at(source, edit_pos, "a")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "markdown: realistic doc - incremental (edit list item)" (b : @bench.T) {
  let source = realistic_markdown_doc()
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  // Edit inside "Second item" -> change 'S' to 's'
  let target = "Second item"
  let edit_pos = find_substring(source, target)
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = md_replace_at(source, edit_pos, "s")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "markdown: realistic doc - incremental (edit code block)" (b : @bench.T) {
  let source = realistic_markdown_doc()
  let parser = @loom.new_imperative_parser(source, markdown_grammar)
  let _ = parser.parse()
  // Edit inside code block: "fibonacci" -> change 'f' to 'F'
  let target = "fibonacci"
  let edit_pos = find_substring(source, target)
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = md_replace_at(source, edit_pos, "F")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}
