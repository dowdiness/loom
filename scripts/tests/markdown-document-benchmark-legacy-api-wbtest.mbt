///|
fn markdown_document_benchmark_legacy_ir(
  source_id : @core.SourceId,
  source : String,
) -> MarkdownIR {
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("legacy source-bound benchmark parse failed")
  }
  experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    @seam.SyntaxNode::from_cst(cst),
    diagnostics,
  )
}

///|
fn markdown_document_benchmark_parse_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-source")
  () => {
    let _ = parse_cst(source_id, source) catch {
      _ => abort("legacy source-bound parse benchmark failed")
    }
    source
  }
}

///|
fn markdown_document_benchmark_semantic_read_runner(
  source : String,
) -> () -> MarkdownIR {
  let source_id = @core.SourceId("markdown-document-benchmark-read")
  let (cst, diagnostics) = parse_cst(source_id, source) catch {
    _ => abort("legacy source-bound semantic-read setup failed")
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  () => experimental_markdown_ir_from_syntax_with_diagnostics(
    source_id,
    syntax,
    diagnostics,
  )
}

///|
fn markdown_document_benchmark_block_runner(
  source : String,
) -> () -> Block {
  let source_id = @core.SourceId("markdown-document-benchmark-block")
  let ir = markdown_document_benchmark_legacy_ir(source_id, source)
  () => experimental_markdown_ir_to_block(ir)
}

///|
fn markdown_document_benchmark_mdast_runner(
  source : String,
) -> () -> Json {
  let source_id = @core.SourceId("markdown-document-benchmark-mdast")
  let ir = markdown_document_benchmark_legacy_ir(source_id, source)
  () => experimental_markdown_ir_to_mdast_json_with_positions(ir, source)
}

///|
fn markdown_document_benchmark_preserve_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-preserve")
  let ir = markdown_document_benchmark_legacy_ir(source_id, source)
  () => experimental_markdown_ir_preserve_rewrite(ir, source)
}

///|
fn markdown_document_benchmark_local_rewrite_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-local")
  let ir = markdown_document_benchmark_legacy_ir(source_id, source)
  let origin = match ir.children() {
    [_heading, paragraph, ..] =>
      match paragraph.children() {
        [link] => match link.destination_origin() {
          Some(origin) => origin
          None => abort("legacy source-bound local-rewrite target missing")
        }
        _ => abort("legacy source-bound local-rewrite link missing")
      }
    _ => abort("legacy source-bound local-rewrite paragraph missing")
  }
  () => experimental_markdown_ir_local_transform_rewrite(
    ir,
    source,
    target_origin=origin,
    replacement_text="https://changed.test",
  )
}

///|
fn markdown_document_benchmark_ir_only_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-ir-only")
  let ir = markdown_document_benchmark_legacy_ir(source_id, source)
  () => experimental_markdown_ir_to_commonmark_html(ir)
}

///|
fn markdown_document_benchmark_attachment_runner(
  source : String,
) -> () -> String {
  let source_id = @core.SourceId("markdown-document-benchmark-attachment")
  let parser = @loom.new_parser(source_id, source, markdown_grammar) catch {
    _ => abort("legacy source-bound attachment setup failed")
  }
  let attachment = MarkdownSemanticAttachment::MarkdownSemanticAttachment(
    parser,
  )
  () => {
    let _ = attachment.document()
    source
  }
}
