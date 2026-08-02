///|
fn trim_inline_text_end_before_newline(children : Array[MarkdownIR]) -> Int {
  match children.last() {
    Some({ node: Text(value), origin }) => {
      let hard_break_spaces = value.length() -
        value.trim_end(chars=" ".view()).length()
      let trimmed = value.trim_end(chars=" \t".view())
      let removed = value.length() - trimmed.length()
      if removed > 0 {
        children[children.length() - 1] = MarkdownIR::text(
          trimmed.to_owned(),
          MarkdownIROrigin(start=origin.start(), end=origin.end() - removed),
        )
      }
      hard_break_spaces
    }
    _ => 0
  }
}

///|
fn trim_inline_backslash_end_before_newline(
  children : Array[MarkdownIR],
) -> Unit {
  match children.pop() {
    Some({ node: Text(value), origin }) => {
      guard value.has_suffix("\\") else {
        abort("hard-break backslash must end inline text")
      }
      let retained = value[:value.length() - 1].to_owned()
      if retained.length() > 0 {
        children.push(
          MarkdownIR::text(
            retained,
            MarkdownIROrigin(start=origin.start(), end=origin.end() - 1),
          ),
        )
      }
    }
    _ => abort("hard-break backslash must follow inline text")
  }
}

///|
fn flush_pending_inline_newline(
  children : Array[MarkdownIR],
  origin : MarkdownIROrigin,
  newline_text : String?,
  source : String,
) -> Unit {
  let hard_break_spaces = trim_inline_text_end_before_newline(children)
  if hard_break_spaces >= 2 {
    children.push(
      MarkdownIR::hard_break(
        TrailingSpaces(hard_break_spaces),
        MarkdownIROrigin(
          start=origin.start() - hard_break_spaces,
          end=origin.end(),
        ),
      ),
    )
  } else if preceded_by_odd_backslashes(source, origin.start()) {
    trim_inline_backslash_end_before_newline(children)
    children.push(
      MarkdownIR::hard_break(
        Backslash,
        MarkdownIROrigin(start=origin.start() - 1, end=origin.end()),
      ),
    )
  } else {
    match newline_text {
      Some(_) => children.push(MarkdownIR::soft_break(origin))
      None => ()
    }
  }
}

///|
fn trim_inline_text_start_after_newline(child : MarkdownIR) -> MarkdownIR {
  match child.node {
    Text(value) => {
      let trimmed = value.trim_start(chars=" \t".view())
      let removed = value.length() - trimmed.length()
      if removed > 0 {
        let origin = child.origin()
        MarkdownIR::text(
          trimmed.to_owned(),
          MarkdownIROrigin(start=origin.start() + removed, end=origin.end()),
        )
      } else {
        child
      }
    }
    _ => child
  }
}

///|

///|
fn append_literal_backtick_ir(
  children : Array[MarkdownIR],
  text : String,
  origin : MarkdownIROrigin,
  preceded_by_escaped_text : Bool,
) -> Unit {
  if preceded_by_escaped_text {
    match children.last() {
      Some(previous) =>
        match previous.node {
          Text(value) if value.length() > 0 => {
            let prefix = value[:value.length() - 1].to_owned()
            let merged_origin = MarkdownIROrigin(
              start=previous.origin().start(),
              end=origin.end(),
            )
            children[children.length() - 1] = MarkdownIR::text(
              prefix + text,
              merged_origin,
            )
          }
          _ => children.push(MarkdownIR::text(text, origin))
        }
      None => children.push(MarkdownIR::text(text, origin))
    }
  } else {
    children.push(MarkdownIR::text(text, origin))
  }
}

///|
fn append_inline_text_ir(
  children : Array[MarkdownIR],
  text : String,
  origin : MarkdownIROrigin,
) -> Unit {
  match children.last() {
    Some(previous) =>
      match previous.node {
        Text(value) if previous.origin().end() == origin.start() =>
          children[children.length() - 1] = MarkdownIR::text(
            value + text,
            MarkdownIROrigin(start=previous.origin().start(), end=origin.end()),
          )
        _ => children.push(MarkdownIR::text(text, origin))
      }
    None => children.push(MarkdownIR::text(text, origin))
  }
}

///|
fn lower_inline_text_token(token : @seam.SyntaxToken) -> MarkdownIR {
  let origin = origin_from_token(token)
  match classify_inline_angle_text(token.text()) {
    Some({ kind: UriAutolink, .. }) => {
      let value = token.text()[1:token.text().length() - 1].to_owned()
      let value_origin = MarkdownIROrigin(
        start=origin.start() + 1,
        end=origin.end() - 1,
      )
      MarkdownIR::autolink(
        UriAutolinkKind,
        value,
        normalize_autolink_uri_destination(value),
        origin,
        Some(value_origin),
        Some(value_origin),
      )
    }
    Some({ kind: EmailAutolink, .. }) => {
      let value = token.text()[1:token.text().length() - 1].to_owned()
      MarkdownIR::autolink(
        EmailAutolinkKind,
        value,
        "mailto:" + value,
        origin,
        Some(MarkdownIROrigin(start=origin.start() + 1, end=origin.end() - 1)),
        None,
      )
    }
    Some({ kind: InlineHtmlAngle, .. }) =>
      MarkdownIR::inline_html(token.text(), origin, Some(origin))
    None => MarkdownIR::text(strip_backslash_escapes(token.text()), origin)
  }
}

///|
/// Context for parser-recovery delimiters that remain literal because their
/// opener was backslash-escaped. CST recovery stays lossless; this state only
/// controls the semantic MarkdownIR projection.
priv enum EscapedInlineRecoveryState {
  NoEscapedInlineRecovery
  EscapedBracketRecovery(Int)
  AfterEscapedBracketRecovery(Int)
  EscapedParenthesisRecovery(Int)
}

///|
/// Immutable inputs shared by one MarkdownIR lowering pass.
///
/// `source` is reconstructed once at the public boundary so nested inline
/// recovery normalization never walks and joins the entire syntax root again.
priv struct MarkdownIRLoweringContext {
  source_id : @core.SourceId
  source : String
  reference_definitions : LinkReferenceDefinitionTable
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic]
}

///|
fn escaped_inline_recovery_after_text(
  state : EscapedInlineRecoveryState,
  source : String,
  origin : MarkdownIROrigin,
) -> EscapedInlineRecoveryState {
  let mut next = match state {
    AfterEscapedBracketRecovery(_) => NoEscapedInlineRecovery
    _ => state
  }
  let mut offset = origin.start()
  while offset < origin.end() {
    match char_at(source, offset) {
      Some('\n') | Some('\r') => next = NoEscapedInlineRecovery
      Some('[') if preceded_by_odd_backslashes(source, offset) =>
        match next {
          EscapedBracketRecovery(depth) =>
            next = EscapedBracketRecovery(depth + 1)
          EscapedParenthesisRecovery(_) => ()
          _ => next = EscapedBracketRecovery(1)
        }
      _ => ()
    }
    offset = offset + 1
  }
  next
}

///|
fn escaped_inline_recovery_after_inline(
  state : EscapedInlineRecoveryState,
) -> EscapedInlineRecoveryState {
  match state {
    AfterEscapedBracketRecovery(_) => NoEscapedInlineRecovery
    _ => state
  }
}

///|
fn escaped_inline_recovery_transition(
  state : EscapedInlineRecoveryState,
  text : String,
  origin : MarkdownIROrigin,
) -> (EscapedInlineRecoveryState, Bool) {
  match state {
    EscapedBracketRecovery(depth) if text == "]" =>
      if depth == 1 {
        (AfterEscapedBracketRecovery(origin.end()), true)
      } else {
        (EscapedBracketRecovery(depth - 1), true)
      }
    AfterEscapedBracketRecovery(previous_end) if text == "(" &&
      origin.start() == previous_end => (EscapedParenthesisRecovery(1), true)
    EscapedParenthesisRecovery(depth) if text == "(" =>
      (EscapedParenthesisRecovery(depth + 1), true)
    EscapedParenthesisRecovery(depth) if text == ")" =>
      if depth == 1 {
        (NoEscapedInlineRecovery, true)
      } else {
        (EscapedParenthesisRecovery(depth - 1), true)
      }
    _ => (NoEscapedInlineRecovery, false)
  }
}

///|
/// Reclassify only recovery artifacts proven to continue an escaped opener.
/// Incoming diagnostics win over the contextual literal classification so
/// callers never lose externally supplied recovery information.
fn normalize_escaped_inline_recoveries(
  children : Array[MarkdownIR],
  source : String,
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  let normalized : Array[MarkdownIR] = []
  let mut state = NoEscapedInlineRecovery
  for child in children {
    let origin = child.origin()
    match child.node {
      Text(value) => {
        let continues_escaped_parentheses = state
          is EscapedParenthesisRecovery(_)
        if continues_escaped_parentheses {
          append_inline_text_ir(normalized, value, origin)
        } else {
          normalized.push(child)
        }
        state = escaped_inline_recovery_after_text(state, source, origin)
      }
      Raw(value, _) | Recovered(value, _) => {
        let (next, literal) = escaped_inline_recovery_transition(
          state, value, origin,
        )
        if literal && diagnostics_in_origin(origin).length() == 0 {
          state = next
          append_inline_text_ir(normalized, value, origin)
        } else {
          state = if literal { NoEscapedInlineRecovery } else { next }
          normalized.push(child)
        }
      }
      SoftBreak(_) | HardBreak(_, _) => {
        state = NoEscapedInlineRecovery
        normalized.push(child)
      }
      _ => {
        state = escaped_inline_recovery_after_inline(state)
        normalized.push(child)
      }
    }
  }
  normalized
}

///|
/// A recovered bracket is literal only when a typed inline sibling occurs to
/// its right. Keep actual/injected diagnostic recovery and trailing unmatched
/// brackets intact.
fn normalize_typed_inline_recovered_prefix(
  children : Array[MarkdownIR],
  diagnostics_in_origin : (MarkdownIROrigin) -> Array[@core.Diagnostic],
) -> Array[MarkdownIR] {
  let typed_to_right = Array::make(children.length(), false)
  let mut has_later_typed_inline = false
  for index = children.length() - 1; index >= 0; index = index - 1 {
    typed_to_right[index] = has_later_typed_inline
    let child = children[index]
    match child.node {
      Link(_, _, _, _)
      | InlineCode(_, _)
      | InlineHtml(_, _)
      | Autolink(_, _, _, _, _) => has_later_typed_inline = true
      _ => ()
    }
  }
  let normalized : Array[MarkdownIR] = []
  for index, child in children {
    match child.node {
      Recovered("[", _) if typed_to_right[index] &&
        diagnostics_in_origin(child.origin()).length() == 0 =>
        normalized.push(MarkdownIR::text("[", child.origin()))
      _ => normalized.push(child)
    }
  }
  normalized
}

///|
fn lower_inline_children_skip_with_diags(
  node : @seam.SyntaxNode,
  skip_kind : SyntaxKind?,
  newline_text : String?,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
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
  for element in node.all_children() {
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
            match classify_inline_angle_text(token.text()) {
              Some(_) => push_child(lower_inline_text_token(token))
              None => {
                let origin = origin_from_token(token)
                let text = strip_backslash_escapes(token.text())
                let literal_marker = is_literal_emphasis_marker_text(
                  token.text(),
                )
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
              }
            }
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              token.text(),
            )
            previous_was_escaped_backtick = false
          }
          BacktickToken => {
            let origin = origin_from_token(token)
            let escaped = preceding_text_ends_escaped
            if escaped {
              append_literal_backtick_ir(children, token.text(), origin, true)
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
        } else {
          push_child(
            lower_inline_node_with_diags(child_node, newline_text, context),
          )
        }
      }
    }
  }
  resolve_inline_images(
    literalize_balanced_raw_parentheses(
      resolve_emphasis_boundary_shortcuts(
        normalize_typed_inline_recovered_prefix(
          resolve_shortcut_references(
            normalize_escaped_inline_recoveries(
              children,
              context.source,
              context.diagnostics_in_origin,
            ),
            context,
          ),
          context.diagnostics_in_origin,
        ),
        context,
      ),
    ),
    context.source,
  )
}

///|
fn lower_inline_children_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  lower_inline_children_skip_with_diags(node, None, Some(newline_text), context)
}

///|
fn lower_direct_inline_token_with_diags(
  token : @seam.SyntaxToken,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR? {
  let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
  match token_kind {
    TextToken => Some(lower_inline_text_token(token))
    BacktickToken =>
      Some(MarkdownIR::text(token.text(), origin_from_token(token)))
    ErrorToken | ErrorNode => {
      let origin = origin_from_token(token)
      Some(
        MarkdownIR::raw(
          context.source_id,
          token.text(),
          origin,
          (context.diagnostics_in_origin)(origin),
        ),
      )
    }
    AtxHeadingMarkerToken
    | SetextHeadingUnderlineToken
    | ListMarkerToken
    | OrderedListMarkerToken
    | BlockQuoteMarkerToken
    | ThematicBreakToken
    | BlankLineToken
    | NewlineToken
    | EofToken
    | CodeFenceOpenToken
    | CodeFenceCloseToken
    | CodeTextToken => None
    _ =>
      delimiter_text(token_kind).map(text => {
        MarkdownIR::text(text, origin_from_token(token))
      })
  }
}

///|
fn lower_direct_inline_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR? {
  let node_kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match node_kind {
    HeadingNode
    | ParagraphNode
    | UnorderedListNode
    | OrderedListNode
    | HtmlBlockNode
    | ThematicBreakNode
    | CodeBlockNode
    | BlockQuoteNode
    | LinkReferenceDefinitionNode => None
    _ => Some(lower_inline_node_with_diags(node, newline_text, context))
  }
}

///|
fn lower_direct_inline_children_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
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
          Some(newline_text),
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
        if token_kind == NewlineToken {
          pending_newline = Some(origin_from_token(token))
          preceding_text_ends_escaped = false
          previous_was_escaped_backtick = false
          previous_was_literal_emphasis_marker = false
        } else {
          match token_kind {
            TextToken => {
              match classify_inline_angle_text(token.text()) {
                Some(_) => push_child(lower_inline_text_token(token))
                None => {
                  let origin = origin_from_token(token)
                  let text = strip_backslash_escapes(token.text())
                  let literal_marker = is_literal_emphasis_marker_text(
                    token.text(),
                  )
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
                }
              }
              preceding_text_ends_escaped = text_ends_with_odd_backslashes(
                token.text(),
              )
              previous_was_escaped_backtick = false
            }
            BacktickToken => {
              let origin = origin_from_token(token)
              let escaped = preceding_text_ends_escaped
              if escaped {
                append_literal_backtick_ir(children, token.text(), origin, true)
              } else {
                push_child(MarkdownIR::text(token.text(), origin))
              }
              preceding_text_ends_escaped = false
              previous_was_escaped_backtick = escaped
              previous_was_literal_emphasis_marker = false
            }
            _ => {
              match lower_direct_inline_token_with_diags(token, context) {
                Some(child) => push_child(child)
                None => ()
              }
              preceding_text_ends_escaped = false
              previous_was_escaped_backtick = false
              previous_was_literal_emphasis_marker = false
            }
          }
        }
      }
      @seam.SyntaxElement::Node(node) => {
        preceding_text_ends_escaped = false
        previous_was_escaped_backtick = false
        previous_was_literal_emphasis_marker = false
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
        if kind == LinkNode {
          for
            atom in lower_link_node_atoms_with_diags(
              node,
              Some(newline_text),
              context,
            ) {
            push_child(atom)
          }
        } else {
          match
            lower_direct_inline_node_with_diags(
              node,
              Some(newline_text),
              context,
            ) {
            Some(child) => push_child(child)
            None => ()
          }
        }
      }
    }
  }
  normalize_escaped_inline_recoveries(
    children,
    context.source,
    context.diagnostics_in_origin,
  )
}

///|

///|
fn normalize_inline_code_value(value : String) -> String {
  let line_normalized = StringBuilder::StringBuilder()
  let mut pending_carriage_return = false
  for ch in value {
    if pending_carriage_return {
      line_normalized.write_char(' ')
      pending_carriage_return = false
      if ch == '\n' {
        continue
      }
    }
    if ch == '\r' {
      pending_carriage_return = true
    } else if ch == '\n' {
      line_normalized.write_char(' ')
    } else {
      line_normalized.write_char(ch)
    }
  }
  if pending_carriage_return {
    line_normalized.write_char(' ')
  }
  let normalized = line_normalized.to_string()
  if normalized.length() >= 2 &&
    normalized.has_prefix(" ") &&
    normalized.has_suffix(" ") {
    let interior = normalized[1:normalized.length() - 1].to_owned()
    let has_non_space = for ch in interior {
      if ch != ' ' {
        break true
      }
    } nobreak {
      false
    }
    if has_non_space {
      interior
    } else {
      normalized
    }
  } else {
    normalized
  }
}

///|
fn lower_code_span_with_source(
  node : @seam.SyntaxNode,
  source : String?,
) -> (String, MarkdownIROrigin?) {
  let mut crosses_structural_prefix = false
  let buf = StringBuilder::StringBuilder()
  let content_tokens : Array[MarkdownIROrigin] = []
  let mut continuation_source : String? = None
  let mut continuation_content_column = 0
  for element in node.direct_elements_iter() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          BlockQuoteMarkerToken | ListMarkerToken | OrderedListMarkerToken =>
            crosses_structural_prefix = true
          IndentationToken => {
            let source = match continuation_source {
              Some(source) => source
              None => {
                let source = source.unwrap_or_else(fn() {
                  syntax_root(node).text()
                })
                continuation_content_column = nearest_container_content_column(
                  node, source,
                )
                continuation_source = Some(source)
                source
              }
            }
            let token_column = visual_column_at_offset(source, token.start())
            let stripped = strip_visual_columns(
              token.text(),
              token_column,
              (continuation_content_column - token_column).max(0),
            )
            if stripped != token.text() {
              crosses_structural_prefix = true
            }
            buf.write_string(stripped)
          }
          BacktickToken =>
            if token.start() != node.start() && token.end() != node.end() {
              buf.write_string(token.text())
              content_tokens.push(origin_from_token(token))
            }
          _ => {
            buf.write_string(token.text())
            content_tokens.push(origin_from_token(token))
          }
        }
      }
      _ => ()
    }
  }
  let content_origin = if crosses_structural_prefix {
    None
  } else {
    span_token_origins(content_tokens)
  }
  (normalize_inline_code_value(buf.to_string()), content_origin)
}

///|
fn lower_code_span(node : @seam.SyntaxNode) -> (String, MarkdownIROrigin?) {
  lower_code_span_with_source(node, None)
}

///|
fn span_token_origins(origins : Array[MarkdownIROrigin]) -> MarkdownIROrigin? {
  match origins {
    [] => None
    [first, ..] => {
      let last = origins.last().unwrap()
      Some(MarkdownIROrigin(start=first.start(), end=last.end()))
    }
  }
}

///|
fn contiguous_label_origin(
  children : Array[MarkdownIR],
  start : Int,
  end : Int,
) -> MarkdownIROrigin? {
  let mut cursor = start
  for child in children {
    let origin = child.origin()
    guard origin.start() == cursor else { return None }
    cursor = origin.end()
  }
  if cursor == end {
    Some(MarkdownIROrigin(start~, end~))
  } else {
    None
  }
}

///|
fn lower_literal_link_token(
  token : @seam.SyntaxToken,
  _context : MarkdownIRLoweringContext,
) -> MarkdownIR? {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
  let origin = origin_from_token(token)
  match kind {
    TextToken => Some(lower_inline_text_token(token))
    BacktickToken => Some(MarkdownIR::text(token.text(), origin))
    NewlineToken => Some(MarkdownIR::soft_break(origin))
    // This helper is used exclusively for the parser-confirmed
    // LiteralLinkDisposition envelope.  Its recovery tokens spell literal
    // Markdown, unlike recovery elsewhere in the document.
    ErrorToken | ErrorNode => Some(MarkdownIR::text(token.text(), origin))
    _ => delimiter_text(kind).map(text => MarkdownIR::text(text, origin))
  }
}

///|
/// Inspect only an already-lowered inline subtree. The explicit stack keeps
/// this bounded by the subtree's MarkdownIR nodes without recursive CST or
/// source traversal.
fn markdown_ir_contains_link(node : MarkdownIR) -> Bool {
  let pending : Array[MarkdownIR] = [node]
  while pending.length() > 0 {
    let current = pending.pop().unwrap()
    if current.node is Link(_, _, _, _) {
      return true
    }
    for child in current.children() {
      pending.push(child)
    }
  }
  false
}

///|
fn lower_literal_link_node_atoms(
  node : @seam.SyntaxNode,
  context : MarkdownIRLoweringContext,
  target_start : Int?,
  target_end : Int?,
) -> Array[MarkdownIR] {
  let atoms : Array[MarkdownIR] = []
  let mut contains_nested_link = false
  let opaque_target = match (target_start, target_end) {
    (Some(start), Some(end)) if start <= end =>
      match classify_inline_angle_text(context.source[start:end].to_owned()) {
        Some({ kind: InlineHtmlAngle, .. }) =>
          Some(
            MarkdownIR::inline_html(
              context.source[start:end].to_owned(),
              MarkdownIROrigin(start~, end~),
              Some(MarkdownIROrigin(start~, end~)),
            ),
          )
        _ => None
      }
    _ => None
  }
  let mut emitted_opaque_target = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let origin = origin_from_token(token)
        let in_opaque_target = match (target_start, target_end, opaque_target) {
          (Some(start), Some(end), Some(_)) =>
            start <= origin.start() && origin.end() <= end
          _ => false
        }
        if in_opaque_target {
          if !emitted_opaque_target {
            atoms.push(opaque_target.unwrap())
            emitted_opaque_target = true
          }
        } else {
          match lower_literal_link_token(token, context) {
            Some(atom) => atoms.push(atom)
            None => ()
          }
        }
      }
      @seam.SyntaxElement::Node(child_node) => {
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(child_node.kind())
        if kind == LinkNode {
          for
            atom in lower_link_node_atoms_with_diags(child_node, None, context) {
            if markdown_ir_contains_link(atom) {
              contains_nested_link = true
            }
            // A nested candidate in a LiteralLinkDisposition envelope is
            // literal source, but preserve every already-typed non-recovery
            // atom (notably inline HTML and any nested image/link result).
            match atom.node {
              Raw(value, _) | Recovered(value, _) =>
                atoms.push(MarkdownIR::text(value, atom.origin()))
              _ => atoms.push(atom)
            }
          }
        } else if kind == ErrorNode {
          // See lower_literal_link_token: only this literal LinkNode fallback
          // has authority to turn parser recovery into visible text.
          atoms.push(
            MarkdownIR::text(child_node.text(), origin_from_node(child_node)),
          )
        } else {
          let atom = lower_inline_node_with_diags(child_node, None, context)
          if markdown_ir_contains_link(atom) {
            contains_nested_link = true
          }
          atoms.push(atom)
        }
      }
    }
  }
  // The parser marks an outer candidate containing an active nested link as a
  // literal envelope.  Hide only its primary opener from the later shortcut
  // pass by joining it to the contiguous label prefix; any suffix `[ref]`
  // remains a separate exact bracket atom and can resolve normally.
  if contains_nested_link {
    match atoms {
      [first, second, ..] =>
        match (first.node, second.node) {
          (Text("["), Text(prefix)) if first.origin().end() ==
            second.origin().start() => {
            atoms[0] = MarkdownIR::text(
              "[" + prefix,
              MarkdownIROrigin(
                start=first.origin().start(),
                end=second.origin().end(),
              ),
            )
            ignore(atoms.remove(1))
          }
          _ => ()
        }
      _ => ()
    }
  }
  atoms
}

///|
/// A parser-confirmed LiteralLinkDisposition keeps the label brackets
/// structural but lowers every suffix token as TextToken.  Valid inline and
/// full/collapsed-reference candidates always retain a structural suffix
/// opener, so this shape is unambiguous without rereading source text.
fn is_literal_link_node_envelope(node : @seam.SyntaxNode) -> Bool {
  let mut saw_label_closer = false
  let mut saw_post_label_text = false
  let mut saw_structural_suffix = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if !saw_label_closer {
          if kind == RightBracketToken {
            saw_label_closer = true
          }
        } else {
          match kind {
            LeftParenToken | LeftBracketToken => saw_structural_suffix = true
            TextToken => saw_post_label_text = true
            _ => ()
          }
        }
      }
      @seam.SyntaxElement::Node(_) => ()
    }
  }
  saw_label_closer && saw_post_label_text && !saw_structural_suffix
}

///|
fn lower_link_node_atoms_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  if is_literal_link_node_envelope(node) {
    return lower_literal_link_node_atoms(node, context, None, None)
  }
  let display : Array[MarkdownIR] = []
  let destination_buf = StringBuilder::StringBuilder()
  let destination_origins : Array[MarkdownIROrigin] = []
  let mut label_start : Int? = None
  let mut label_end : Int? = None
  let mut url_depth = 0
  let mut past_bracket = false
  let mut target_start : Int? = None
  let mut target_end : Int? = None
  let mut in_angle_destination = false
  let mut reference_label_start : Int? = None
  let mut reference_label_end : Int? = None
  let mut preceding_text_ends_escaped = false
  let mut previous_was_escaped_backtick = false
  let mut previous_was_literal_emphasis_marker = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          LeftBracketToken if !past_bracket && url_depth == 0 => {
            label_start = Some(origin_from_token(token).end())
            previous_was_literal_emphasis_marker = false
          }
          RightBracketToken if !past_bracket && url_depth == 0 => {
            label_end = Some(origin_from_token(token).start())
            past_bracket = true
            previous_was_literal_emphasis_marker = false
          }
          LeftBracketToken if past_bracket && url_depth == 0 =>
            reference_label_start = Some(origin_from_token(token).end())
          RightBracketToken if past_bracket &&
            url_depth == 0 &&
            reference_label_start is Some(_) =>
            reference_label_end = Some(origin_from_token(token).start())
          LeftParenToken if past_bracket && url_depth == 0 => {
            url_depth = 1
            target_start = Some(origin_from_token(token).end())
            in_angle_destination = false
          }
          LeftParenToken if past_bracket && in_angle_destination => {
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          LeftParenToken if past_bracket => {
            url_depth = url_depth + 1
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          RightParenToken if url_depth > 1 || in_angle_destination => {
            url_depth = url_depth - 1
            if in_angle_destination {
              url_depth = url_depth + 1
            }
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          RightParenToken if url_depth == 1 => {
            url_depth = 0
            target_end = Some(origin_from_token(token).start())
          }
          TextToken if url_depth > 0 => {
            let origin = origin_from_token(token)
            if target_start == Some(origin.start()) &&
              token.text().has_prefix("<") {
              in_angle_destination = true
            }
            destination_buf.write_string(token.text())
            destination_origins.push(origin)
            if in_angle_destination && token.text().has_suffix(">") {
              in_angle_destination = false
            }
          }
          _ if url_depth > 0 => {
            destination_buf.write_string(token.text())
            destination_origins.push(origin_from_token(token))
          }
          TextToken if !past_bracket => {
            let origin = origin_from_token(token)
            let text = strip_backslash_escapes(token.text())
            let literal_marker = is_literal_emphasis_marker_text(token.text())
            if previous_was_escaped_backtick ||
              previous_was_literal_emphasis_marker ||
              literal_marker {
              append_inline_text_ir(display, text, origin)
            } else {
              display.push(MarkdownIR::text(text, origin))
            }
            preceding_text_ends_escaped = text_ends_with_odd_backslashes(
              token.text(),
            )
            previous_was_escaped_backtick = false
            previous_was_literal_emphasis_marker = literal_marker
          }
          BacktickToken if !past_bracket => {
            let origin = origin_from_token(token)
            let escaped = preceding_text_ends_escaped
            if escaped {
              append_literal_backtick_ir(display, token.text(), origin, true)
            } else {
              display.push(MarkdownIR::text(token.text(), origin))
            }
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = escaped
            previous_was_literal_emphasis_marker = false
          }
          ErrorToken | ErrorNode if !past_bracket => {
            let origin = origin_from_token(token)
            display.push(
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
          _ => {
            preceding_text_ends_escaped = false
            previous_was_escaped_backtick = false
            previous_was_literal_emphasis_marker = false
          }
        }
      }
      @seam.SyntaxElement::Node(child_node) => {
        if !past_bracket && url_depth == 0 {
          let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(
            child_node.kind(),
          )
          if child_kind == LinkNode {
            for
              atom in lower_link_node_atoms_with_diags(
                child_node, newline_text, context,
              ) {
              display.push(atom)
            }
          } else {
            display.push(
              lower_inline_node_with_diags(child_node, newline_text, context),
            )
          }
        }
        preceding_text_ends_escaped = false
        previous_was_escaped_backtick = false
        previous_was_literal_emphasis_marker = false
      }
    }
  }
  let normalized_display = resolve_inline_images(
    literalize_balanced_raw_parentheses(
      normalize_typed_inline_recovered_prefix(
        resolve_shortcut_references(
          normalize_escaped_inline_recoveries(
            display,
            context.source,
            context.diagnostics_in_origin,
          ),
          context,
        ),
        context.diagnostics_in_origin,
      ),
    ),
    context.source,
  )
  let label_origin = match (label_start, label_end) {
    (Some(start), Some(end)) if start <= end =>
      contiguous_label_origin(normalized_display, start, end)
    _ => None
  }
  match (target_start, target_end) {
    (Some(start), Some(end)) if start <= end =>
      match parse_inline_link_target(context.source[start:end].to_owned()) {
        Some(target) =>
          [
            MarkdownIR::link_with_metadata(
              normalized_display,
              target.destination,
              target.title,
              InlineLinkForm,
              origin_from_node(node),
              label_origin,
              None,
              Some(
                MarkdownIROrigin(
                  start=start + target.destination_start,
                  end=start + target.destination_end,
                ),
              ),
              match (target.title_start, target.title_end) {
                (Some(title_start), Some(title_end)) =>
                  Some(
                    MarkdownIROrigin(
                      start=start + title_start,
                      end=start + title_end,
                    ),
                  )
                _ => None
              },
            ),
          ]
        None =>
          lower_literal_link_node_atoms(node, context, target_start, target_end)
      }
    _ => {
      let resolved_reference = match
        (label_start, label_end, reference_label_start, reference_label_end) {
        (
          Some(label_start),
          Some(label_end),
          Some(reference_start),
          Some(reference_end),
        ) if label_start <= label_end && reference_start <= reference_end => {
          let collapsed = reference_start == reference_end
          let lookup_start = if collapsed {
            label_start
          } else {
            reference_start
          }
          let lookup_end = if collapsed { label_end } else { reference_end }
          lookup_bounded_link_reference_definition(
            context,
            MarkdownIROrigin(start=lookup_start, end=lookup_end),
          ).map(definition => {
            (
              definition,
              if collapsed {
                CollapsedReferenceLinkForm
              } else {
                FullReferenceLinkForm
              },
              Some(MarkdownIROrigin(start=reference_start, end=reference_end)),
            )
          })
        }
        (Some(label_start), Some(label_end), None, None) if label_start <=
          label_end =>
          lookup_bounded_link_reference_definition(
            context,
            MarkdownIROrigin(start=label_start, end=label_end),
          ).map(definition => (definition, ShortcutReferenceLinkForm, None))
        _ => None
      }
      match resolved_reference {
        Some((definition, form, reference_label_origin)) =>
          [
            MarkdownIR::link_with_metadata(
              normalized_display,
              definition.destination_value,
              definition.title_value,
              form,
              origin_from_node(node),
              label_origin,
              reference_label_origin,
              Some(definition.destination_value_origin),
              definition.title_value_origin,
            ),
          ]
        None => lower_literal_link_node_atoms(node, context, None, None)
      }
    }
  }
}

///|
fn emphasis_content_origin_from_boundaries(
  node : @seam.SyntaxNode,
  boundary_width : Int,
) -> MarkdownIROrigin? {
  let boundaries : Array[MarkdownIROrigin] = []
  for element in node.direct_elements_iter() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        if kind == EmphasisDelimiterToken {
          boundaries.push(origin_from_token(token))
        }
      }
      @seam.SyntaxElement::Node(_) => ()
    }
  }
  guard boundary_width > 0 && boundaries.length() == boundary_width * 2 else {
    return None
  }
  Some(
    MarkdownIROrigin(
      start=boundaries[boundary_width - 1].end(),
      end=boundaries[boundary_width].start(),
    ),
  )
}

///|
fn lower_inline_node_with_diags(
  node : @seam.SyntaxNode,
  newline_text : String?,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    BoldNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(EmphasisDelimiterToken),
        newline_text,
        context,
      )
      MarkdownIR::bold(
        children,
        origin_from_node(node),
        emphasis_content_origin_from_boundaries(node, 2),
      )
    }
    ItalicNode => {
      let children = lower_inline_children_skip_with_diags(
        node,
        Some(EmphasisDelimiterToken),
        newline_text,
        context,
      )
      MarkdownIR::italic(
        children,
        origin_from_node(node),
        emphasis_content_origin_from_boundaries(node, 1),
      )
    }
    InlineCodeNode => {
      let (value, content_origin) = lower_code_span_with_source(
        node,
        Some(context.source),
      )
      MarkdownIR::inline_code(value, origin_from_node(node), content_origin)
    }
    LinkNode => lower_link_node_atoms_with_diags(node, newline_text, context)[0]
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(
        context.source_id,
        node.text(),
        origin,
        (context.diagnostics_in_origin)(origin),
      )
    }
    _ =>
      MarkdownIR::unsupported(
        "unsupported inline node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
fn is_setext_heading(node : @seam.SyntaxNode) -> Bool {
  node.direct_token_of_kind(SetextHeadingUnderlineToken.to_raw()) is Some(_)
}

///|
/// Trim leading and trailing whitespace from setext heading inline children.
/// CommonMark spec: leading indentation (up to 3 spaces) and trailing
/// whitespace on content lines are not part of the heading's text content.
/// Also adjusts each child's origin so that position-aware consumers (mdast,
/// content-origin) receive ranges that match the trimmed text value.
fn trim_setext_heading_children(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let len = children.length()
  if len == 0 {
    return children
  }
  children.mapi((i, child) => {
    match child.node {
      Text(value) => {
        let mut trimmed = value
        let mut origin = child.origin()
        // Trim leading whitespace on first child
        if i == 0 {
          let trimmed_view = value.trim_start(chars=" \t".view())
          let removed = value.length() - trimmed_view.length()
          if removed > 0 {
            trimmed = trimmed_view.to_owned()
            origin = MarkdownIROrigin(
              start=origin.start() + removed,
              end=origin.end(),
            )
          }
        }
        // Trim trailing whitespace on last child
        if i == len - 1 {
          let trimmed_view = trimmed.trim_end(chars=" \t".view())
          let removed = trimmed.length() - trimmed_view.length()
          if removed > 0 {
            trimmed = trimmed_view.to_owned()
            origin = MarkdownIROrigin(
              start=origin.start(),
              end=origin.end() - removed,
            )
          }
        }
        if trimmed.length() != value.length() {
          MarkdownIR::text(trimmed, origin)
        } else {
          child
        }
      }
      _ => child
    }
  })
}

///|
fn heading_depth_from_marker(node : @seam.SyntaxNode) -> Int? {
  match node.direct_token_of_kind(AtxHeadingMarkerToken.to_raw()) {
    Some(marker) => {
      let marker_start = skip_leading_spaces(marker.text(), 0)
      let n = count_hashes(marker.text(), marker_start)
      // count_hashes caps at 6, so n <= 6 is guaranteed.
      if n >= 1 {
        Some(n)
      } else {
        None
      }
    }
    None =>
      match node.direct_token_of_kind(SetextHeadingUnderlineToken.to_raw()) {
        Some(underline) => parse_setext_underline_depth(underline.text().view())
        None => None
      }
  }
}

///|
fn lower_paragraph_with_newline_and_diags(
  node : @seam.SyntaxNode,
  newline_text : String,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR {
  let children = normalize_paragraph_boundary_spaces(
    lower_inline_children_with_newline_and_diags(node, newline_text, context),
  )
  MarkdownIR::paragraph(
    children,
    origin_from_node(node),
    span_origin_of_children(children),
  )
}

///|
fn lower_container_child_with_diags(
  child : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  paragraph_newline_text : String,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR? {
  let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
  match child_kind {
    ParagraphNode =>
      Some(
        lower_paragraph_with_newline_and_diags(
          child, paragraph_newline_text, context,
        ),
      )
    HeadingNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode => Some(recurse(child))
    ErrorNode => {
      let origin = origin_from_node(child)
      Some(
        MarkdownIR::recovered(
          context.source_id,
          RECOVERED_PARSE_ERROR,
          origin,
          (context.diagnostics_in_origin)(origin),
        ),
      )
    }
    _ => None
  }
}

///|
fn list_marker_from_node(node : @seam.SyntaxNode) -> UnorderedListMarker? {
  match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
    Some(marker) => unordered_list_marker_from_text(marker.text())
    None => None
  }
}

///|
fn ordered_list_marker_from_node(node : @seam.SyntaxNode) -> OrderedListMarker? {
  match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
    Some(marker) => ordered_list_marker_from_text(marker.text())
    None => None
  }
}

///|
fn ordered_list_marker_from_ir(ir : MarkdownIR) -> OrderedListMarker? {
  match ir.node {
    OrderedListItem(_, _, _, marker) => marker
    _ => None
  }
}

///|
fn list_item_paragraph_origin(
  node : @seam.SyntaxNode,
  content_origin : MarkdownIROrigin?,
) -> MarkdownIROrigin {
  match content_origin {
    Some(origin) => origin
    None =>
      match node.direct_token_of_kind(ListMarkerToken.to_raw()) {
        Some(marker) => zero_width_origin_at(marker.end())
        None =>
          match node.direct_token_of_kind(OrderedListMarkerToken.to_raw()) {
            Some(marker) => zero_width_origin_at(marker.end())
            None => zero_width_origin_at(node.end())
          }
      }
  }
}

///|
fn trim_container_child_paragraph(ir : MarkdownIR) -> MarkdownIR {
  match ir.node {
    Paragraph(children, _) => {
      let trimmed = match children {
        [{ node: Text(value), origin }, ..] => {
          let trimmed_value = value.trim_start(chars=" \t".view())
          let removed = value.length() - trimmed_value.length()
          if removed == 0 {
            children
          } else {
            children.mapi((index, child) => {
              if index == 0 {
                MarkdownIR::text(
                  trimmed_value.to_owned(),
                  MarkdownIROrigin(
                    start=origin.start() + removed,
                    end=origin.end(),
                  ),
                )
              } else {
                child
              }
            })
          }
        }
        _ => children
      }
      MarkdownIR::paragraph(
        trimmed,
        ir.origin(),
        span_origin_of_children(trimmed),
      )
    }
    _ => ir
  }
}

///|
fn append_list_item_flow_block_children(
  node : @seam.SyntaxNode,
  children : Array[MarkdownIR],
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> Unit {
  for child in node.children() {
    let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    match child_kind {
      ParagraphNode =>
        children.push(trim_container_child_paragraph(recurse(child)))
      HeadingNode
      | UnorderedListNode
      | OrderedListNode
      | HtmlBlockNode
      | ThematicBreakNode
      | CodeBlockNode
      | BlockQuoteNode => children.push(recurse(child))
      _ => ()
    }
  }
}

///|
fn markdown_ir_has_non_blank_inline_content(ir : MarkdownIR) -> Bool {
  match ir.node {
    Text(text) => direct_list_item_text_has_non_blank_content(text)
    SoftBreak(_) => false
    _ => true
  }
}

///|
fn lower_list_item_flow_children_with_diags(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  context : MarkdownIRLoweringContext,
) -> (Array[MarkdownIR], MarkdownIROrigin?) {
  let lowered_inline_children = normalize_paragraph_boundary_spaces(
    lower_direct_inline_children_with_newline_and_diags(node, "\n", context),
  )
  let inline_children = retain_direct_list_item_inline_children(
    lowered_inline_children, markdown_ir_has_non_blank_inline_content,
  )
  let content_origin = span_origin_of_children(inline_children)
  let paragraph_origin = list_item_paragraph_origin(node, content_origin)
  let paragraph = trim_container_child_paragraph(
    MarkdownIR::paragraph(inline_children, paragraph_origin, content_origin),
  )
  let children = [paragraph]
  append_list_item_flow_block_children(node, children, recurse)
  (children, paragraph.content_origin())
}

///|
fn code_block_info(node : @seam.SyntaxNode) -> String {
  match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
    Some(fence_token) => {
      let text = fence_token.text()
      let i = count_leading_fence_characters(text)
      if i < text.length() {
        decode_markdown_info_string_entities(text[i:].to_owned())
        .trim(chars=" \t".view())
        .to_owned()
      } else {
        ""
      }
    }
    None => ""
  }
}

///|
fn count_leading_fence_characters(text : String) -> Int {
  match text.get_char(0) {
    None => 0
    Some(fence_character) => {
      let mut count = 0
      while count < text.length() {
        match text.get_char(count) {
          Some(ch) if ch == fence_character => count = count + 1
          _ => break
        }
      }
      count
    }
  }
}

///|
fn trim_commonmark_leading_indent_spaces(value : String) -> (String, Int) {
  // CommonMark permits up to three literal spaces of block indentation before
  // paragraph/setext heading content. Tabs and four-space indented-code
  // semantics are parser concerns and intentionally stay outside this Slice A
  // MarkdownIR normalization.
  let count = for ch in value; count = 0 {
    match ch {
      ' ' if count < 3 => continue count + 1
      _ => break count
    }
  } nobreak {
    count
  }
  if count == 0 {
    (value, 0)
  } else {
    (value[count:].to_owned(), count)
  }
}

///|
fn trim_commonmark_trailing_spaces(value : String) -> (String, Int) {
  // Setext heading content excludes trailing literal spaces before the newline.
  // Keep this ASCII-space-only so tab handling remains with the later full
  // indentation semantics slice.
  let count = for pos = value.length() - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some(' ') => continue pos - 1, count + 1
      _ => break count
    }
  }
  if count == 0 {
    (value, 0)
  } else {
    (value[:value.length() - count].to_owned(), count)
  }
}

///|
fn normalize_paragraph_boundary_spaces(
  children : Array[MarkdownIR],
) -> Array[MarkdownIR] {
  let len = children.length()
  if len == 0 {
    return children
  }
  children.mapi((index, child) => {
    match child.node {
      Text(value) => {
        let (trimmed, origin) = if index == 0 {
          let (leading_trimmed, cut) = trim_commonmark_leading_indent_spaces(
            value,
          )
          if cut > 0 {
            (
              leading_trimmed,
              MarkdownIROrigin(
                start=child.origin().start() + cut,
                end=child.origin().end(),
              ),
            )
          } else {
            (value, child.origin())
          }
        } else {
          (value, child.origin())
        }
        let (trimmed, origin) = if index == len - 1 {
          let (trailing_trimmed, cut) = trim_commonmark_trailing_spaces(trimmed)
          if cut > 0 {
            (
              trailing_trimmed,
              MarkdownIROrigin(start=origin.start(), end=origin.end() - cut),
            )
          } else {
            (trimmed, origin)
          }
        } else {
          (trimmed, origin)
        }
        if trimmed.length() == value.length() {
          child
        } else {
          MarkdownIR::text(trimmed, origin)
        }
      }
      _ => child
    }
  })
}

///|
fn trim_trailing_atx_closing_hashes(
  value : String,
  source_text : String,
  source_offset : Int,
  origin_end : Int,
) -> (String, Int) {
  let hash_count = for pos = value.length() - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some('#') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard hash_count > 0 else { return (value, 0) }
  let before_hash_pos = value.length() - hash_count
  let space_count = for pos = before_hash_pos - 1, count = 0 {
    guard pos >= 0 else { break count }
    match value.get_char(pos) {
      Some(' ') | Some('\t') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard origin_end >= source_offset else { return (value, 0) }
  let raw_end = origin_end - source_offset
  let raw_hash_count = for pos = raw_end - 1, count = 0 {
    guard pos >= 0 else { break count }
    match source_text.get_char(pos) {
      Some('#') => continue pos - 1, count + 1
      _ => break count
    }
  }
  guard raw_hash_count > 0 else { return (value, 0) }
  let raw_hash_start = raw_end - raw_hash_count
  // Escaped trailing hashes are content, not an ATX closing sequence. The raw
  // source still contains the backslash while `value` has already been unescaped.
  guard raw_hash_start > 0 else { return (value, 0) }
  match source_text.get_char(raw_hash_start - 1) {
    Some('\\') => (value, 0)
    Some(' ' | '\t') if before_hash_pos == 0 || space_count > 0 => {
      let cut = hash_count + space_count
      (value[:value.length() - cut].to_owned(), cut)
    }
    _ => (value, 0)
  }
}

///|
fn normalize_heading_leading_whitespace(
  children : Array[MarkdownIR],
  trim_all~ : Bool,
) -> Array[MarkdownIR] {
  if !trim_all {
    return normalize_paragraph_boundary_spaces(children)
  }
  match children {
    [{ node: Text(value), origin }, ..] => {
      let trimmed_view = value.trim_start(chars=" \t".view())
      let cut = value.length() - trimmed_view.length()
      if cut == 0 {
        children
      } else {
        children.mapi((index, child) => {
          if index == 0 {
            MarkdownIR::text(
              trimmed_view.to_owned(),
              MarkdownIROrigin(start=origin.start() + cut, end=origin.end()),
            )
          } else {
            child
          }
        })
      }
    }
    _ => children
  }
}

///|
fn normalize_heading_whitespace(
  children : Array[MarkdownIR],
  source_text : String,
  source_offset : Int,
  trim_all_leading~ : Bool,
  skip_closing_hashes? : Bool = false,
) -> Array[MarkdownIR] {
  let leading_normalized = normalize_heading_leading_whitespace(
    children,
    trim_all=trim_all_leading,
  )
  match leading_normalized {
    [.., { node: Text(value), origin }] => {
      let (space_trimmed, space_cut) = trim_commonmark_trailing_spaces(value)
      let trimmed_end = origin.end() - space_cut
      let (trimmed, hash_cut) = if skip_closing_hashes {
        (space_trimmed, 0)
      } else {
        trim_trailing_atx_closing_hashes(
          space_trimmed, source_text, source_offset, trimmed_end,
        )
      }
      let cut = space_cut + hash_cut
      if cut == 0 {
        leading_normalized
      } else {
        let last_index = leading_normalized.length() - 1
        leading_normalized.mapi((index, child) => {
          if index == last_index {
            MarkdownIR::text(
              trimmed,
              MarkdownIROrigin(start=origin.start(), end=origin.end() - cut),
            )
          } else {
            child
          }
        })
      }
    }
    _ => leading_normalized
  }
}

///|
/// Extract concatenated HTML content from an `HtmlBlockNode`, including the
/// opening line, text lines, and interleaved newlines. HTML blocks preserve
/// exact source formatting, so this does not trim leading or trailing newlines.
fn html_block_value(node : @seam.SyntaxNode) -> String {
  let buf = StringBuilder::StringBuilder()
  let mut in_html = false
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          IndentationToken => buf.write_string(token.text())
          HtmlBlockOpenToken => {
            in_html = true
            // NB: HtmlBlockOpen text does not include the trailing newline;
            // the lexer emits that separately as a NewlineToken.
            buf.write_string(token.text())
          }
          // Defensive: the parser guarantees HtmlBlockOpenToken is first, so
          // in_html is always true here for well-formed CSTs.
          HtmlTextToken if in_html => buf.write_string(token.text())
          // HTML block parsing emits newline runs as NewlineToken; BlankLineToken
          // remains structural outside code blocks.
          NewlineToken if in_html => buf.write_string("\n")
          _ => ()
        }
      }
      _ => ()
    }
  }
  buf.to_string()
}

///|
fn html_block_content_origin(node : @seam.SyntaxNode) -> MarkdownIROrigin? {
  // Unlike code_block_content_origin, include HtmlBlockOpenToken: HTML blocks
  // have no close fence, and the opening line is content.
  let content_tokens : Array[@seam.SyntaxToken] = Array::new()
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          IndentationToken
          | HtmlBlockOpenToken
          | HtmlTextToken
          | NewlineToken => content_tokens.push(token)
          _ => ()
        }
      }
      _ => ()
    }
  }
  span_token_origins(content_tokens.map(origin_from_token))
}

///|
fn code_block_content_origin(node : @seam.SyntaxNode) -> MarkdownIROrigin? {
  // Indented code content is visually deindented using CommonMark tab stops;
  // that mapping is not necessarily a single source slice. Keep local rewrite
  // targets fenced-only until indented-code rewrites can reindent per line.
  guard node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) is Some(_) else {
    return None
  }
  let mut in_code = false
  let content_tokens : Array[@seam.SyntaxToken] = Array::new()
  for element in node.all_children() {
    match element {
      @seam.SyntaxElement::Token(token) => {
        let token_kind : SyntaxKind = @seam.FromRawKind::from_raw(token.kind())
        match token_kind {
          CodeFenceOpenToken => in_code = true
          CodeFenceCloseToken => in_code = false
          CodeTextToken if in_code => content_tokens.push(token)
          IndentationToken => {
            in_code = true
            content_tokens.push(token)
          }
          NewlineToken | BlankLineToken if in_code => content_tokens.push(token)
          _ => ()
        }
      }
      _ => ()
    }
  }
  let start_offset = if content_tokens.length() > 0 {
    let first_kind : SyntaxKind = @seam.FromRawKind::from_raw(
      content_tokens[0].kind(),
    )
    if first_kind is NewlineToken {
      1
    } else {
      0
    }
  } else {
    0
  }
  let end_offset = if content_tokens.length() > start_offset {
    let last_kind : SyntaxKind = @seam.FromRawKind::from_raw(
      content_tokens[content_tokens.length() - 1].kind(),
    )
    if last_kind is NewlineToken {
      content_tokens.length() - 1
    } else {
      content_tokens.length()
    }
  } else {
    0
  }
  if start_offset < end_offset {
    Some(
      MarkdownIROrigin(
        start=content_tokens[start_offset].start(),
        end=content_tokens[end_offset - 1].end(),
      ),
    )
  } else if content_tokens.length() > start_offset {
    Some(
      MarkdownIROrigin(
        start=content_tokens[start_offset].start(),
        end=content_tokens[start_offset].start(),
      ),
    )
  } else if content_tokens.length() > 0 {
    let last_token = content_tokens[content_tokens.length() - 1]
    Some(MarkdownIROrigin(start=last_token.end(), end=last_token.end()))
  } else {
    match node.direct_token_of_kind(CodeFenceOpenToken.to_raw()) {
      Some(fence_token) =>
        Some(MarkdownIROrigin(start=fence_token.end(), end=fence_token.end()))
      None => None
    }
  }
}

///|
fn lower_list_children(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
) -> Array[MarkdownIR] {
  node
  .children()
  .iter()
  .filter_map(child => {
    let child_kind : SyntaxKind = @seam.FromRawKind::from_raw(child.kind())
    match child_kind {
      ListItemNode => Some(recurse(child))
      _ => None
    }
  })
  .collect()
}

///|
fn lower_block_quote_children(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  context : MarkdownIRLoweringContext,
) -> Array[MarkdownIR] {
  node
  .children()
  .iter()
  .filter_map(child => {
    match lower_container_child_with_diags(child, recurse, "\n", context) {
      Some(ir) => Some(trim_container_child_paragraph(ir))
      None => None
    }
  })
  .collect()
}

///|
fn list_spread_from_node(
  node : @seam.SyntaxNode,
  children : Array[MarkdownIR],
) -> Bool {
  node.direct_token_of_kind(BlankLineToken.to_raw()) is Some(_) ||
  children.iter().any(child => child.spread() == Some(true))
}

///|
/// Experimental CstFold algebra for the M1 MarkdownIR slice.
///
/// Covers documents, headings, paragraphs, and text. Other Markdown constructs
/// lower to explicit `Unsupported` IR nodes instead of cloned CST token piles.
fn experimental_markdown_ir_fold_node_with_diags(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    DocumentNode => {
      // #811 collects the immutable document table before recursive lowering.
      // #812 will consume it while resolving reference-form inline nodes.
      ignore(context.reference_definitions)
      let children : Array[MarkdownIR] = node
        .children()
        .iter()
        .filter_map(child => {
          lower_container_child_with_diags(child, recurse, "\n", context)
        })
        .collect()
      MarkdownIR::document(children, origin_from_node(node))
    }
    HeadingNode => {
      let setext = is_setext_heading(node)
      let children = normalize_heading_whitespace(
        lower_inline_children_with_newline_and_diags(node, "\n", context),
        node.text(),
        node.start(),
        trim_all_leading=!setext,
        skip_closing_hashes=setext,
      )
      let content_children = if setext {
        trim_setext_heading_children(children)
      } else {
        children
      }
      match heading_depth_from_marker(node) {
        Some(depth) =>
          MarkdownIR::heading(
            depth,
            content_children,
            origin_from_node(node),
            span_origin_of_children(content_children),
          )
        None =>
          MarkdownIR::unsupported(
            "invalid heading marker",
            origin_from_node(node),
          )
      }
    }
    ParagraphNode => lower_paragraph_with_newline_and_diags(node, "\n", context)
    BlockQuoteNode =>
      MarkdownIR::block_quote(
        lower_block_quote_children(node, recurse, context),
        origin_from_node(node),
      )
    UnorderedListNode => {
      let children = lower_list_children(node, recurse)
      let marker = match children {
        [first, ..] => first.list_marker()
        [] => None
      }
      MarkdownIR::unordered_list(
        children,
        origin_from_node(node),
        spread=list_spread_from_node(node, children),
        marker~,
      )
    }
    OrderedListNode => {
      let children = lower_list_children(node, recurse)
      let marker = match children {
        [first, ..] => ordered_list_marker_from_ir(first)
        [] => None
      }
      MarkdownIR::ordered_list(
        children,
        origin_from_node(node),
        spread=list_spread_from_node(node, children),
        marker~,
      )
    }
    ListItemNode => {
      let (children, content_origin) = lower_list_item_flow_children_with_diags(
        node, recurse, context,
      )
      let spread = node.direct_token_of_kind(BlankLineToken.to_raw()) is Some(_)
      match ordered_list_marker_from_node(node) {
        Some(marker) =>
          MarkdownIR::ordered_list_item(
            children,
            origin_from_node(node),
            spread~,
            content_origin,
            marker=Some(marker),
          )
        None =>
          MarkdownIR::list_item(
            children,
            origin_from_node(node),
            spread~,
            content_origin,
            marker=list_marker_from_node(node),
          )
      }
    }
    CodeBlockNode =>
      MarkdownIR::code_block(
        code_block_info(node),
        code_block_value_with_source(node, context.source),
        origin_from_node(node),
        code_block_content_origin(node),
      )
    HtmlBlockNode =>
      MarkdownIR::html_block(
        html_block_value(node),
        origin_from_node(node),
        html_block_content_origin(node),
      )
    ThematicBreakNode => MarkdownIR::thematic_break(origin_from_node(node))
    ErrorNode => {
      let origin = origin_from_node(node)
      MarkdownIR::recovered(
        context.source_id,
        RECOVERED_PARSE_ERROR,
        origin,
        (context.diagnostics_in_origin)(origin),
      )
    }
    _ =>
      MarkdownIR::unsupported(
        "unsupported node: " + kind.to_string(),
        origin_from_node(node),
      )
  }
}

///|
fn experimental_markdown_ir_fold_node(
  node : @seam.SyntaxNode,
  recurse : (@seam.SyntaxNode) -> MarkdownIR,
  context : MarkdownIRLoweringContext,
) -> MarkdownIR {
  experimental_markdown_ir_fold_node_with_diags(node, recurse, context)
}

///|
fn diagnostic_primary_overlaps_origin(
  diagnostic : @core.Diagnostic,
  source_id : @core.SourceId,
  origin : MarkdownIROrigin,
) -> Bool {
  diagnostic
  .labels()
  .any(label => {
    let span = label.span()
    label.style() == @core.LabelStyle::Primary &&
    span.source_id() == source_id &&
    @core.Range::new(span.range().start().value(), span.range().end().value()).overlaps(
      @core.Range::new(origin.start(), origin.end()),
    )
  })
}

///|
fn diagnostics_in_origin(
  source_id : @core.SourceId,
  diagnostics : @core.DiagnosticSet,
  origin : MarkdownIROrigin,
) -> Array[@core.Diagnostic] {
  diagnostics
  .items()
  .iter()
  .filter(diagnostic => {
    diagnostic_primary_overlaps_origin(diagnostic, source_id, origin)
  })
  .collect()
}

///|
/// Experimental `SyntaxNode -> MarkdownIR` lowering for the M1 slice.
///
/// Built by a direct recursive walk rather than `CstFold` because MarkdownIR
/// stores absolute source origins, and `CstFold` reuses cached results
/// verbatim based on position-independent structural hashes. Using `CstFold`
/// would return stale origins after position-shifting edits. See
/// `docs/decisions/2026-06-16-markdown-ir-performance-policy.md`.
pub fn experimental_markdown_ir_from_syntax(
  source_id : @core.SourceId,
  root : @seam.SyntaxNode,
) -> MarkdownIR {
  let document_root = syntax_root(root)
  let context : MarkdownIRLoweringContext = {
    source_id,
    source: document_root.text(),
    reference_definitions: collect_link_reference_definitions(document_root),
    diagnostics_in_origin: _ => [],
  }
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node(node, lower, context)
  }
  decode_markdown_ir_text_entities(lower(root), context.source)
}

///|
pub fn experimental_markdown_ir_from_syntax_with_diagnostics(
  source_id : @core.SourceId,
  root : @seam.SyntaxNode,
  diagnostics : @core.DiagnosticSet,
) -> MarkdownIR {
  let document_root = syntax_root(root)
  let context : MarkdownIRLoweringContext = {
    source_id,
    source: document_root.text(),
    reference_definitions: collect_link_reference_definitions(document_root),
    diagnostics_in_origin: origin => {
      diagnostics_in_origin(source_id, diagnostics, origin)
    },
  }
  fn lower(node : @seam.SyntaxNode) -> MarkdownIR {
    experimental_markdown_ir_fold_node_with_diags(node, lower, context)
  }
  decode_markdown_ir_text_entities(lower(root), context.source)
}
