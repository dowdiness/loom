///|
/// Editor-facing roles for the Markdown CST.
///
/// These roles remain local to the Markdown example while the parser-backed
/// shape is being evaluated against nested inline syntax and links.
pub(all) enum MarkdownRole {
  HeadingMarker
  HeadingText
  ListMarker
  ListContent
  CodeFenceDelimiter
  CodeFenceContent
  InlineCodeDelimiter
  InlineCodeContent
  EmphasisDelimiter
  EmphasisContent
  LinkText
  LinkDestination
  Punctuation
  Error
} derive(Eq, Debug)

///|
/// Stable lower-kebab role name used by editor-neutral exports.
pub fn MarkdownRole::export_name(self : MarkdownRole) -> String {
  match self {
    HeadingMarker => "heading-marker"
    HeadingText => "heading-text"
    ListMarker => "list-marker"
    ListContent => "list-content"
    CodeFenceDelimiter => "code-fence-delimiter"
    CodeFenceContent => "code-fence-content"
    InlineCodeDelimiter => "inline-code-delimiter"
    InlineCodeContent => "inline-code-content"
    EmphasisDelimiter => "emphasis-delimiter"
    EmphasisContent => "emphasis-content"
    LinkText => "link-text"
    LinkDestination => "link-destination"
    Punctuation => "punctuation"
    Error => "error"
  }
}

///|
/// A Markdown role assigned to a UTF-16 source span.
pub struct MarkdownRoleSpan {
  priv role : MarkdownRole
  priv start : Int
  priv end : Int
} derive(Eq, Debug)

///|
pub fn MarkdownRoleSpan::MarkdownRoleSpan(
  role~ : MarkdownRole,
  start~ : Int,
  end~ : Int,
) -> MarkdownRoleSpan {
  { role, start, end }
}

///|
pub fn MarkdownRoleSpan::role(self : MarkdownRoleSpan) -> MarkdownRole {
  self.role
}

///|
pub fn MarkdownRoleSpan::start(self : MarkdownRoleSpan) -> Int {
  self.start
}

///|
pub fn MarkdownRoleSpan::end(self : MarkdownRoleSpan) -> Int {
  self.end
}

///|
/// Editor-neutral Markdown role span with stable lower-kebab role names.
pub struct MarkdownRoleSpanExport {
  priv start : Int
  priv end : Int
  priv role : String
} derive(Eq, Debug)

///|
fn MarkdownRoleSpanExport::MarkdownRoleSpanExport(
  start~ : Int,
  end~ : Int,
  role~ : String,
) -> MarkdownRoleSpanExport {
  { start, end, role }
}

///|
pub fn MarkdownRoleSpanExport::start(self : MarkdownRoleSpanExport) -> Int {
  self.start
}

///|
pub fn MarkdownRoleSpanExport::end(self : MarkdownRoleSpanExport) -> Int {
  self.end
}

///|
pub fn MarkdownRoleSpanExport::role(self : MarkdownRoleSpanExport) -> String {
  self.role
}

///|
pub impl ToJson for MarkdownRoleSpanExport with fn to_json(self) -> Json {
  { "start": (self.start : Int), "end": (self.end : Int), "role": self.role }
}

///|
fn MarkdownRoleSpan::to_export(
  self : MarkdownRoleSpan,
) -> MarkdownRoleSpanExport {
  MarkdownRoleSpanExport(
    start=self.start,
    end=self.end,
    role=self.role.export_name(),
  )
}

///|
/// Convert typed Markdown role spans to the editor-neutral export shape.
pub fn export_markdown_role_spans(
  spans : Array[MarkdownRoleSpan],
) -> Array[MarkdownRoleSpanExport] {
  spans.map(fn(span) { span.to_export() })
}

///|
fn markdown_role_for_token(
  parent_kind : SyntaxKind,
  token_kind : SyntaxKind,
) -> MarkdownRole? {
  match (parent_kind, token_kind) {
    (HeadingNode, HeadingMarkerToken) => Some(HeadingMarker)
    (HeadingNode, TextToken) => Some(HeadingText)
    (ListItemNode, ListMarkerToken | OrderedListMarkerToken) => Some(ListMarker)
    (ListItemNode, TextToken) => Some(ListContent)
    (CodeBlockNode, CodeFenceOpenToken | CodeFenceCloseToken) =>
      Some(CodeFenceDelimiter)
    (CodeBlockNode, CodeTextToken) => Some(CodeFenceContent)
    (InlineCodeNode, BacktickToken) => Some(InlineCodeDelimiter)
    (InlineCodeNode, _) => Some(InlineCodeContent)
    (BoldNode | ItalicNode, StarToken | StarStarToken) =>
      Some(EmphasisDelimiter)
    (BoldNode | ItalicNode, _) => Some(EmphasisContent)
    (
      LinkNode,
      LeftBracketToken
      | RightBracketToken
      | LeftParenToken
      | RightParenToken,
    ) => Some(Punctuation)
    _ => None
  }
}

///|
fn markdown_role_span_for_token(
  parent_kind : SyntaxKind,
  token : @seam.SyntaxToken,
  error_context : Bool,
) -> MarkdownRoleSpan? {
  let start = token.start()
  let end = token.end()
  guard end > start else { None }
  let token_kind = SyntaxKind::from_raw(token.kind())
  let role = if error_context || token_kind == ErrorToken {
    Some(MarkdownRole::Error)
  } else {
    match token_kind {
      BlankLineToken | NewlineToken | IndentationToken | EofToken => None
      _ => markdown_role_for_token(parent_kind, token_kind)
    }
  }
  role.map(fn(role) { MarkdownRoleSpan(role~, start~, end~) })
}

///|
fn markdown_link_span(
  role : MarkdownRole,
  token : @seam.SyntaxToken,
) -> MarkdownRoleSpan? {
  let start = token.start()
  let end = token.end()
  guard end > start else { None }
  Some(MarkdownRoleSpan(role~, start~, end~))
}

///|
/// Link phases are driven by ordered direct elements, not reconstructed text.
priv enum MarkdownLinkPhase {
  Label
  AfterLabel
  Destination
  Complete
} derive(Eq)

///|
/// Walk a LinkNode with the state needed to distinguish its outer delimiters
/// from balanced parentheses inside the destination.
fn markdown_link_role_spans_iter(
  node : @seam.SyntaxNode,
  error_context : Bool,
) -> Iter[MarkdownRoleSpan] {
  // Direct elements are ordered because the first right bracket, first left
  // parenthesis, and balanced destination parentheses have distinct roles.
  let mut phase = MarkdownLinkPhase::Label
  let mut depth = 0
  let spans : Array[MarkdownRoleSpan] = []
  for element in node.direct_elements_iter() {
    match element {
      Node(child) =>
        for span in markdown_role_spans_iter_with_error(child, error_context) {
          spans.push(span)
        }
      Token(token) => {
        let kind = SyntaxKind::from_raw(token.kind())
        let role = if error_context || kind == ErrorToken {
          markdown_role_span_for_token(LinkNode, token, true)
        } else {
          match phase {
            Label =>
              match kind {
                LeftBracketToken | RightBracketToken =>
                  markdown_role_span_for_token(LinkNode, token, false)
                BlankLineToken | NewlineToken | IndentationToken | EofToken =>
                  None
                _ => markdown_link_span(LinkText, token)
              }
            AfterLabel =>
              match kind {
                LeftParenToken => {
                  phase = MarkdownLinkPhase::Destination
                  depth = 1
                  markdown_role_span_for_token(LinkNode, token, false)
                }
                _ => markdown_link_span(LinkDestination, token)
              }
            Destination =>
              match kind {
                LeftParenToken => {
                  depth = depth + 1
                  markdown_link_span(LinkDestination, token)
                }
                RightParenToken if depth > 1 => {
                  depth = depth - 1
                  markdown_link_span(LinkDestination, token)
                }
                RightParenToken => {
                  phase = MarkdownLinkPhase::Complete
                  markdown_role_span_for_token(LinkNode, token, false)
                }
                BlankLineToken | NewlineToken | IndentationToken | EofToken =>
                  None
                _ => markdown_link_span(LinkDestination, token)
              }
            Complete => markdown_link_span(Punctuation, token)
          }
        }
        match role {
          Some(span) => spans.push(span)
          None => ()
        }
        if phase == MarkdownLinkPhase::Label && kind == RightBracketToken {
          phase = MarkdownLinkPhase::AfterLabel
        }
      }
    }
  }
  spans.iter()
}

///|
fn markdown_role_spans_iter_with_error(
  node : @seam.SyntaxNode,
  error_context : Bool,
) -> Iter[MarkdownRoleSpan] {
  let parent_kind = SyntaxKind::from_raw(node.kind())
  let current_error = error_context || parent_kind == ErrorNode
  if parent_kind == LinkNode {
    markdown_link_role_spans_iter(node, current_error)
  } else {
    node
    .direct_elements_iter()
    .flat_map(element => {
      match element {
        Node(child) => markdown_role_spans_iter_with_error(child, current_error)
        Token(token) =>
          markdown_role_span_for_token(parent_kind, token, current_error)
          .map(Iter::singleton)
          .unwrap_or(Iter::empty())
      }
    })
  }
}

///|
fn markdown_role_spans_iter(node : @seam.SyntaxNode) -> Iter[MarkdownRoleSpan] {
  markdown_role_spans_iter_with_error(node, false)
}

///|
/// Project a Markdown syntax tree to ordered editor role spans.
///
/// Spans use the source-backed UTF-16 token ranges. Trivia and synthetic
/// zero-width recovery tokens are omitted; source-backed recovery tokens keep
/// the parser's existing error provenance without consulting diagnostics.
pub fn project_markdown_roles(
  syntax : @seam.SyntaxNode,
) -> Array[MarkdownRoleSpan] {
  markdown_role_spans_iter(syntax).to_array()
}
