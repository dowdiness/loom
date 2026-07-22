// Standalone delimiter-frontier probe over real Markdown lexer facts.
// This remains a standalone validation artifact; production integration also requires
// continuation-boundary, invalidation, and performance gates.

///|
enum ProbeTokenKind {
  Text
  Backtick
  Newline
  Prefix
  BlockBoundary
  Other
} derive(Eq)

///|
struct ProbeToken {
  kind : ProbeTokenKind
  start : Int
  end : Int
}

///|
struct ProbeContainer {
  tokens : Array[ProbeToken]
  end : Int
}

///|
struct ProbeRun {
  token_index : Int
  start : Int
  length : Int
}

///|
struct DelimiterScanFrontier {
  mut frontier_token : Int
  runs_by_length : Map[Int, Array[ProbeRun]]
  cursor_by_length : Map[Int, Int]
  mut exhausted : Bool
  mut visits : Int
}

///|
fn probe_kind(token : Token) -> ProbeTokenKind {
  match token {
    Text(_) => Text
    Backtick => Backtick
    Newline => Newline
    Indentation(_) | BlockQuoteMarker => Prefix
    HeadingMarker(_)
    | ListMarker
    | OrderedListMarker(_)
    | ThematicBreak
    | CodeFenceOpen(_, _)
    | CodeFenceClose
    | HtmlBlockOpen(_)
    | HtmlText(_)
    | BlankLine
    | CodeText(_)
    | EOF => BlockBoundary
    _ => Other
  }
}

///|
fn probe_container_from_source(
  source : String,
  container_end : Int,
) -> ProbeContainer raise @core.LexError {
  guard 0 <= container_end && container_end <= source.length() else {
    raise @core.LexError("container end is outside source")
  }
  let infos = tokenize(source)
  let tokens : Array[ProbeToken] = []
  let mut start = 0
  for info in infos {
    let end = start + info.len
    tokens.push({ kind: probe_kind(info.token), start, end })
    start = end
  }
  let mut boundary_aligned = container_end == 0
  for token in tokens {
    if token.end == container_end {
      boundary_aligned = true
    }
  }
  guard boundary_aligned else {
    raise @core.LexError("container end must align to a token boundary")
  }
  { tokens, end: container_end }
}

///|
fn in_container_token_count(container : ProbeContainer) -> Int {
  let mut count = 0
  for token in container.tokens {
    if token.end <= container.end {
      count = count + 1
    }
  }
  count
}

///|
fn frontier_new() -> DelimiterScanFrontier {
  {
    frontier_token: 0,
    runs_by_length: Map([]),
    cursor_by_length: Map([]),
    exhausted: false,
    visits: 0,
  }
}

///|
fn record_run(frontier : DelimiterScanFrontier, run : ProbeRun) -> Unit {
  match frontier.runs_by_length.get(run.length) {
    Some(runs) => runs.push(run)
    None => frontier.runs_by_length[run.length] = [run]
  }
}

///|
fn frontier_observe_until(
  frontier : DelimiterScanFrontier,
  container : ProbeContainer,
  stop_after_token : Int,
) -> Unit {
  let limit = if stop_after_token < container.tokens.length() {
    stop_after_token
  } else {
    container.tokens.length()
  }
  if frontier.exhausted {
    return
  }
  while frontier.frontier_token < limit {
    let index = frontier.frontier_token
    let token = container.tokens[index]
    guard token.end <= container.end else {
      frontier.exhausted = true
      break
    }
    frontier.frontier_token = frontier.frontier_token + 1
    frontier.visits = frontier.visits + 1
    if token.kind is Backtick {
      record_run(frontier, {
        token_index: index,
        start: token.start,
        length: token.end - token.start,
      })
    }
  }
  if frontier.frontier_token >= limit {
    frontier.exhausted = frontier.frontier_token >= container.tokens.length()
  }
}

///|
fn frontier_next_closer(
  frontier : DelimiterScanFrontier,
  opener : ProbeRun,
  container : ProbeContainer,
) -> ProbeRun? {
  frontier_observe_until(frontier, container, container.tokens.length())
  let runs = frontier.runs_by_length.get(opener.length).unwrap_or([])
  let mut cursor = frontier.cursor_by_length.get(opener.length).unwrap_or(0)
  while cursor < runs.length() &&
        (
          runs[cursor].token_index <= opener.token_index ||
          runs[cursor].start <= opener.start
        ) {
    cursor = cursor + 1
  }
  frontier.cursor_by_length[opener.length] = cursor
  if cursor < runs.length() {
    Some(runs[cursor])
  } else {
    None
  }
}

///|
test "delimiter frontier: extract real token facts and honor explicit boundary" {
  let source = "`a`\n> `b` trailing"
  let container_end = 4
  let container = probe_container_from_source(source, container_end) catch {
    _ => abort("lexer failed")
  }
  inspect(container.end, content="4")
  inspect(container.tokens[0].kind == ProbeTokenKind::Backtick, content="true")
  inspect(container.tokens[0].start, content="0")
  inspect(container.tokens[0].end, content="1")
  let post_boundary = container.tokens[4]
  inspect(post_boundary.start >= container_end, content="true")
  inspect(post_boundary.kind == ProbeTokenKind::Prefix, content="true")
  inspect(post_boundary.start, content="4")
  inspect(post_boundary.end, content="6")
}

///|
test "delimiter frontier: rejects non-boundary and out-of-range ends" {
  let interior_raised = try {
    let _ = probe_container_from_source("abc", 1)
    false
  } catch {
    @core.LexError(_) => true
  }
  let outside_raised = try {
    let _ = probe_container_from_source("abc", 4)
    false
  } catch {
    @core.LexError(_) => true
  }
  inspect(interior_raised, content="true")
  inspect(outside_raised, content="true")
}

///|
test "delimiter frontier: ignores a same-length run after the boundary" {
  let source = "`a\n`b`"
  let container = probe_container_from_source(source, 3) catch {
    _ => abort("lexer failed")
  }
  let frontier = frontier_new()
  let closer = frontier_next_closer(
    frontier,
    { token_index: 0, start: 0, length: 1 },
    container,
  )
  inspect(closer is None, content="true")
  inspect(
    frontier.visits == in_container_token_count(container),
    content="true",
  )
}

///|
test "delimiter frontier: ignores an extended post-boundary tail" {
  let prefix = "`a`\n"
  let tail = "  tail `x` ".repeat(128)
  let extended_tail = tail + " tail `y`".repeat(128)
  let source = prefix + tail
  let extended_source = prefix + extended_tail
  let container_end = prefix.length()
  let container = probe_container_from_source(source, container_end) catch {
    _ => abort("lexer failed")
  }
  let extended_container = probe_container_from_source(
    extended_source, container_end,
  ) catch {
    _ => abort("lexer failed")
  }
  let frontier = frontier_new()
  let extended_frontier = frontier_new()
  let _ = frontier_next_closer(
    frontier,
    { token_index: 0, start: 0, length: 1 },
    container,
  )
  let visits_before = frontier.visits
  frontier_observe_until(frontier, container, container.tokens.length() + 100)
  let _ = frontier_next_closer(
    extended_frontier,
    { token_index: 0, start: 0, length: 1 },
    extended_container,
  )
  inspect(frontier.visits == visits_before, content="true")
  inspect(
    frontier.visits == in_container_token_count(container),
    content="true",
  )
  inspect(
    extended_frontier.visits == in_container_token_count(extended_container),
    content="true",
  )
  inspect(frontier.visits == extended_frontier.visits, content="true")
}

///|
test "delimiter frontier: visits full in-container stream once" {
  let source = "text `a` filler `` unmatched\n  prefix `b` after"
  let container_end = source.length()
  let container = probe_container_from_source(source, container_end) catch {
    _ => abort("lexer failed")
  }
  let frontier = frontier_new()
  let _ = frontier_next_closer(
    frontier,
    { token_index: 1, start: 5, length: 1 },
    container,
  )
  inspect(
    frontier.visits == in_container_token_count(container),
    content="true",
  )
}

///|
test "delimiter frontier: ownership remains left to right" {
  let source = "`a` `b`"
  let container = probe_container_from_source(source, source.length()) catch {
    _ => abort("lexer failed")
  }
  let frontier = frontier_new()
  let first = frontier_next_closer(
    frontier,
    { token_index: 0, start: 0, length: 1 },
    container,
  ).unwrap()
  let second = frontier_next_closer(
    frontier,
    { token_index: 4, start: 4, length: 1 },
    container,
  ).unwrap()
  inspect(first.token_index, content="2")
  inspect(first.start, content="2")
  inspect(second.token_index, content="6")
  inspect(second.start, content="6")
}

///|
test "delimiter frontier: third run remains unmatched" {
  let source = "`a` `b"
  let container = probe_container_from_source(source, source.length()) catch {
    _ => abort("lexer failed")
  }
  let frontier = frontier_new()
  let first = frontier_next_closer(
    frontier,
    { token_index: 0, start: 0, length: 1 },
    container,
  ).unwrap()
  let third = frontier_next_closer(
    frontier,
    { token_index: 4, start: 4, length: 1 },
    container,
  )
  inspect(first.token_index, content="2")
  inspect(third is None, content="true")
}

///|
test "parser context baseline token_at scans delimiter facts without moving" {
  let source = "`a\n`b`"
  let tokens = tokenize(source) catch { _ => abort("lexer failed") }
  let ctx = @core.ParserContext::new(tokens, source, markdown_spec)
  let before = ctx.peek_index(0)
  let before_third = ctx.peek_index(2)
  let (first, first_end) = ctx.token_at(0, 0)
  let (second, second_end) = ctx.token_at(first_end, 0)
  let (third, third_end) = ctx.token_at(second_end, 0)
  let (after_boundary, after_boundary_end) = ctx.token_at(third_end, 0)
  inspect(second is Text(_), content="true")
  inspect(before is Backtick, content="true")
  inspect(first is Backtick, content="true")
  inspect(first_end, content="1")
  inspect(second_end, content="2")
  inspect(third is Newline, content="true")
  inspect(third_end, content="3")
  inspect(after_boundary is Backtick, content="true")
  inspect(after_boundary_end, content="4")
  inspect(ctx.peek_index(0) == before, content="true")
  inspect(ctx.peek_index(2) == before_third, content="true")
}
