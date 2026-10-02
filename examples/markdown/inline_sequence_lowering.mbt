///|
priv enum InlineChildScope {
  GeneralInlineChildren(SyntaxKind?, String?)
  DirectListItemChildren
}

///|
// Return raw, source-ordered inline children. Container whitespace and source
// facts must be settled before adding deferred reference-finalization markers.
fn collect_inline_children(
  node : @seam.SyntaxNode,
  scope : InlineChildScope,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  let (skip_kind, newline_text) = match scope {
    GeneralInlineChildren(skip_kind, newline_text) => (skip_kind, newline_text)
    DirectListItemChildren => (None, Some("\n"))
  }
  let children : Array[MarkdownIR] = []
  let mut pending_newline : MarkdownIROrigin? = None
  let mut preceding_text_ends_escaped = false
  let mut previous_was_escaped_backtick = false
  let mut previous_was_literal_emphasis_marker = false
  fn push_child(child : MarkdownIR) -> Unit {
    let child = match pending_newline {
      Some(origin) => {
        flush_pending_inline_newline(
          children,
          origin,
          newline_text,
          context.source,
        )
        pending_newline = None
        trim_inline_text_start_after_newline(child)
      }
      None => child
    }
    children.push(child)
  }
  for element in node.direct_elements_iter() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if skip_kind is Some(kind) && token_kind == kind {
          match pending_newline {
            Some(origin) => {
              flush_pending_inline_newline(
                children,
                origin,
                newline_text,
                context.source,
              )
              pending_newline = None
            }
            None => ()
          }
          preceding_text_ends_escaped = false
          previous_was_escaped_backtick = false
          previous_was_literal_emphasis_marker = false
          continue
        }
        match token_kind {
          TextToken => {
            if token.text() == ">" && preceding_text_ends_escaped {
              append_escaped_inline_delimiter_ir(
                children,
                token.text(),
                origin_from_token(token),
                true,
              )
              preceding_text_ends_escaped = false
              previous_was_escaped_backtick = false
              previous_was_literal_emphasis_marker = false
              continue
            }
            let origin = origin_from_token(token)
            let text = strip_backslash_escapes(token.text())
            let literal_marker = is_literal_emphasis_marker_text(token.text())
            if pending_newline is None &&
              (
                previous_was_escaped_backtick ||
                previous_was_literal_emphasis_marker ||
                literal_marker
              ) {
              append_inline_text_ir(children, text, origin)
            } else {
              push_child(MarkdownIR::text(text, origin))
            }
            previous_was_literal_emphasis_marker = literal_marker
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              token.text(),
            )
            previous_was_escaped_backtick = false
          }
          BacktickToken => {
            let origin = origin_from_token(token)
            let escaped = preceding_text_ends_escaped
            if escaped {
              append_escaped_inline_delimiter_ir(
                children,
                token.text(),
                origin,
                true,
              )
            } else {
              push_child(MarkdownIR::text(token.text(), origin))
            }
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = escaped
            previous_was_literal_emphasis_marker = false
          }
          ErrorToken | ErrorNode => {
            let origin = origin_from_token(token)
            push_child(
              MarkdownIR::raw(
                context.source_id,
                token.text(),
                origin,
                (context.diagnostics_in_origin)(origin),
              ),
            )
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
            previous_was_literal_emphasis_marker = false
          }
          NewlineToken => {
            pending_newline = Some(origin_from_token(token))
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
            previous_was_literal_emphasis_marker = false
          }
          AtxHeadingMarkerToken
          | SetextHeadingUnderlineToken
          | ListMarkerToken
          | OrderedListMarkerToken
          | BlockQuoteMarkerToken
          | ThematicBreakToken
          | BlankLineToken
          | EofToken
          | CodeFenceOpenToken
          | CodeFenceCloseToken
          | CodeTextToken => {
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
            previous_was_literal_emphasis_marker = false
          }
          _ => {
            match delimiter_text(token_kind) {
              Some(text) =>
                push_child(MarkdownIR::text(text, origin_from_token(token)))
              None => ()
            }
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
            previous_was_literal_emphasis_marker = false
          }
        }
      }
      @seam.SyntaxElement::Node(child_node) => {
        preceding_text_ends_escaped = false
        previous_was_escaped_backtick = false
        previous_was_literal_emphasis_marker = false
        let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(
          child_node.kind(),
        )
        if child_kind == LinkNode {
          for
            atom in lower_link_node_atoms_with_diags(
              child_node, newline_text, context,
            ) {
            push_child(atom)
          }
        } else if scope is DirectListItemChildren {
          match
            lower_direct_inline_node_with_diags(
              child_node, newline_text, context,
            ) {
            Some(child) => push_child(child)
            None => ()
          }
        } else {
          push_child(
            lower_inline_node_with_diags(child_node, newline_text, context),
          )
        }
      }
    }
  }
  children
}
