///|
fn markdown_document_benchmark_parse_runner(source : String) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-source")
  () => {
    let document = parse_document(source_id, source) catch {
      _ => abort("source-bound parse benchmark failed")
    }
    document.source()
  }
}

///|
fn markdown_document_benchmark_semantic_read_runner(
  source : String,
) -> () -> MarkdownIR {
  let source_id = @core.SourceId("markdown-document-benchmark-read")
  let document = parse_document(source_id, source) catch {
    _ => abort("source-bound semantic-read setup failed")
  }
  () => document.semantic_read().ir()
}

///|
fn markdown_document_benchmark_block_runner(source : String) -> () -> Block {
  let source_id = @core.SourceId("markdown-document-benchmark-block")
  let document = parse_document(source_id, source) catch {
    _ => abort("source-bound Block setup failed")
  }
  let read = document.semantic_read()
  () => markdown_semantic_read_to_block(read)
}

///|
fn markdown_document_benchmark_mdast_runner(source : String) -> () -> Json {
  let source_id = @core.SourceId("markdown-document-benchmark-mdast")
  let document = parse_document(source_id, source) catch {
    _ => abort("source-bound mdast setup failed")
  }
  let read = document.semantic_read()
  () => markdown_semantic_read_to_mdast_json_with_positions(read)
}

///|
fn markdown_document_benchmark_preserve_runner(source : String) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-preserve")
  let document = parse_document(source_id, source) catch {
    _ => abort("source-bound preserve setup failed")
  }
  let read = document.semantic_read()
  () => markdown_semantic_read_preserve_rewrite(read)
}

///|
fn markdown_document_benchmark_local_rewrite_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-local")
  let document = parse_document(source_id, source) catch {
    _ => abort("source-bound local-rewrite setup failed")
  }
  let read = document.semantic_read()
  let selection = match read.root().children() {
    [_heading, paragraph, ..] =>
      match paragraph.children() {
        [link] =>
          match
            link.selection(kind=MarkdownSemanticSelectionKind::Destination) {
            Some(selection) => selection
            None => abort("source-bound local-rewrite target missing")
          }
        _ => abort("source-bound local-rewrite link missing")
      }
    _ => abort("source-bound local-rewrite paragraph missing")
  }
  () => {
    markdown_semantic_read_local_transform_rewrite(
      selection,
      replacement_text="https://changed.test",
    )
  }
}

///|
fn markdown_document_benchmark_ir_only_runner(source : String) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-ir-only")
  let document = parse_document(source_id, source) catch {
    _ => abort("source-bound IR-only setup failed")
  }
  let read = document.semantic_read()
  () => experimental_markdown_ir_to_commonmark_html(read.ir())
}

///|
fn markdown_document_benchmark_attachment_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-attachment")
  let parser = @loom.new_parser(source_id, source, markdown_grammar) catch {
    _ => abort("source-bound attachment setup failed")
  }
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  () => attachment.source_document().source()
}
