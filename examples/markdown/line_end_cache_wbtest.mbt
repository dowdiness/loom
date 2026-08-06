// Regression coverage for session-local physical-line-end reuse.

///|
fn line_end_cache_nested_quote_doc(depth : Int, line_count : Int) -> String {
  let out = StringBuilder::new()
  for line = 0; line < line_count; line = line + 1 {
    for prefix = 0; prefix < depth; prefix = prefix + 1 {
      out.write_string("> ")
    }
    out.write_string("payload \{line}\n")
  }
  out.to_string()
}

///|
test "line-end cache preserves deep-prefix tokenization" {
  for depth in [1, 8, 32, 128] {
    let source = line_end_cache_nested_quote_doc(depth, 100)
    let cached = tokenize(source) catch {
      _ => abort("cached deep-prefix tokenization failed")
    }
    let (uncached, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => abort("uncached deep-prefix tokenization failed")
    }
    assert_eq(cached, uncached)
  }
}

///|
test "line-end cache preserves quote forms and line terminators" {
  for
    source in [
      "> payload\n", ">payload\r\n", "  > payload\r", "\t> payload\n", "> > payload",
      ">\n", "> \r\n", "> first\n>second\r\n  > third\r> > fourth",
    ] {
    let cached = tokenize(source) catch {
      _ => abort("cached quote-form tokenization failed")
    }
    let (uncached, _) = @core.tokenize_with_modes(
      markdown_mode_lexer,
      source,
      EOF,
    ) catch {
      _ => abort("uncached quote-form tokenization failed")
    }
    assert_eq(cached, uncached)
  }
}

///|
test "line-end cache resets before earlier incremental relex" {
  let source_id = @core.SourceId("markdown-line-end-cache-relex")
  let source = line_end_cache_nested_quote_doc(128, 100)
  let initial = mode_factory.tokenize(source_id, source)
  let buffer = @core.TokenBuffer::new_from_mode_relex(
    source_id,
    source,
    factory=mode_factory,
    eof_token=EOF,
  )
  let edited = "!" + source[1:].to_owned()
  let edit = @core.Edit::replace(0, 1, 1)
  buffer.update(edit, edited) catch {
    _ => abort("line-end cache earlier relex failed")
  }
  let edited_full = mode_factory.tokenize(source_id, edited)
  assert_eq(buffer.get_tokens(), edited_full.tokens())
  assert_eq(buffer.get_starts(), edited_full.starts())

  buffer.update(edit, source) catch {
    _ => abort("line-end cache restore relex failed")
  }
  assert_eq(buffer.get_tokens(), initial.tokens())
  assert_eq(buffer.get_starts(), initial.starts())
}
