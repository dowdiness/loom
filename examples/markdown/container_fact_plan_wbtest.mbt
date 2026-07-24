///|
fn container_fact_context(
  source : String,
) -> @core.ParserContext[Token, SyntaxKind] {
  let tokens = tokenize(source) catch {
    _ => abort("container fact plan test tokenization failed")
  }
  @core.ParserContext::new(tokens, source, markdown_spec)
}

///|
fn root_fact_handler(
  ctx : @core.ParserContext[Token, SyntaxKind],
  consume_calls : Array[Int],
) -> ContinuationHandler[RootContinuationKind] {
  {
    consume: action => {
      consume_calls[0] = consume_calls[0] + 1
      consume_root_continuation(ctx, action)
    },
    observe: offset => observe_root_paragraph_continuation(ctx, offset),
    advance: (offset, action) => {
      advance_root_paragraph_continuation(ctx, offset, action)
    },
  }
}

///|
fn assert_root_plan_action(
  source : String,
  expected_end : Int,
) -> ContainerFactPlan[RootContinuationKind] raise {
  let ctx = container_fact_context(source)
  let consume_calls = [0]
  let before_range = ctx.current_token_range()
  let before_node = ctx.current_node_kind()
  let before_mode = ctx.lex_mode()
  let plan = build_container_fact_plan(
    ctx,
    before_range.start,
    InlineParsePolicy::paragraph(),
    root_fact_handler(ctx, consume_calls),
  )
  inspect(plan.end_offset, content=expected_end.to_string())
  inspect(ctx.current_token_range(), content=before_range.to_string())
  inspect(
    @debug.to_string(ctx.current_node_kind()),
    content=@debug.to_string(before_node),
  )
  inspect(ctx.lex_mode(), content=before_mode.to_string())
  inspect(consume_calls[0], content="0")
  plan
}

///|
test "container fact plan: records root continuation without consuming it" {
  let plan = assert_root_plan_action("alpha\nbeta", 10)
  guard plan.actions.get(5) is Some(RootContinuationKind::NoPrefix) else {
    abort(
      "expected the newline action to retain RootContinuationKind::NoPrefix",
    )
  }
}

///|
test "container fact plan: ends at a Stop newline" {
  let plan = assert_root_plan_action("alpha\n\nbeta", 5)
  inspect(plan.actions.get(5) is None, content="true")
}

///|
test "container fact plan: records every owner with its concrete action type" {
  let root = container_fact_context("root\nchild")
  let root_calls = [0]
  let root_plan = build_container_fact_plan(
    root,
    0,
    InlineParsePolicy::paragraph(),
    root_fact_handler(root, root_calls),
  )
  guard root_plan.actions.get(4) is Some(RootContinuationKind::NoPrefix) else {
    abort("expected root continuation action")
  }

  let setext = container_fact_context("title\n2. child")
  let setext_plan = build_container_fact_plan(
    setext,
    0,
    InlineParsePolicy::setext_heading(),
    {
      consume: action => consume_setext_continuation(setext, action),
      observe: offset => observe_setext_continuation(setext, offset),
      advance: (offset, action) => {
        advance_setext_continuation(setext, offset, action)
      },
    },
  )
  guard setext_plan.actions.get(5)
    is Some(SetextContinuationKind::OrderedMarkerAsText) else {
    abort("expected setext ordered-marker action")
  }

  let quote = container_fact_context("> quote\n> child")
  quote.emit_token(BlockQuoteMarkerToken)
  let quote_plan = build_container_fact_plan(
    quote,
    quote.current_token_range().start,
    InlineParsePolicy::paragraph(),
    {
      consume: action => consume_block_quote_continuation(quote, action),
      observe: offset => {
        observe_block_quote_paragraph_continuation(quote, offset)
      },
      advance: (offset, action) => {
        advance_block_quote_paragraph_continuation(quote, offset, action)
      },
    },
  )
  guard quote_plan.actions.get(7)
    is Some(BlockQuoteContinuationKind::MarkerAndPrefix(NoPrefix)) else {
    abort("expected quoted paragraph marker action")
  }

  let quote_heading = container_fact_context("> title\n> child")
  quote_heading.emit_token(BlockQuoteMarkerToken)
  let quote_heading_plan = build_container_fact_plan(
    quote_heading,
    quote_heading.current_token_range().start,
    InlineParsePolicy::paragraph(),
    {
      consume: action => {
        consume_block_quote_heading_continuation(quote_heading, action)
      },
      observe: offset => {
        observe_block_quote_heading_continuation(quote_heading, offset)
      },
      advance: (offset, action) => {
        advance_block_quote_heading_continuation(quote_heading, offset, action)
      },
    },
  )
  guard quote_heading_plan.actions.get(7)
    is Some(BlockQuoteHeadingContinuationKind::MarkerAndPrefix(NoPrefix)) else {
    abort("expected quoted setext marker action")
  }

  let list = container_fact_context("- item\n  child")
  list.emit_token(ListMarkerToken)
  let list_plan = build_container_fact_plan(
    list,
    list.current_token_range().start,
    InlineParsePolicy::list_item(allow_ordered_marker=true),
    {
      consume: action => consume_list_item_continuation(list, action),
      observe: offset => {
        observe_list_item_continuation(
          list,
          offset,
          2,
          allow_ordered_marker=true,
          has_paragraph_content=true,
        )
      },
      advance: (offset, action) => {
        advance_list_item_continuation(list, offset, action)
      },
    },
  )
  guard list_plan.actions.get(6)
    is Some(ListItemContinuationKind::IndentationPrefix) else {
    abort("expected list-item indentation action")
  }

  let list_setext = container_fact_context("- title\n  child")
  list_setext.emit_token(ListMarkerToken)
  let list_setext_plan = build_container_fact_plan(
    list_setext,
    list_setext.current_token_range().start,
    InlineParsePolicy::list_item_setext_heading(allow_ordered_marker=true),
    {
      consume: action => {
        consume_list_item_setext_continuation(list_setext, action)
      },
      observe: offset => {
        observe_list_item_setext_continuation(
          list_setext,
          offset,
          2,
          allow_ordered_marker=true,
        )
      },
      advance: (offset, action) => {
        advance_list_item_setext_continuation(list_setext, offset, action)
      },
    },
  )
  guard list_setext_plan.actions.get(7)
    is Some(ListItemSetextContinuationKind::IndentationPrefix) else {
    abort("expected list-item setext indentation action")
  }
}

///|
test "container fact plan: preserves equal-length delimiter successors" {
  let ctx = container_fact_context("`a` ``b`` `unmatched")
  let plan = build_line_container_fact_plan(
    ctx,
    0,
    InlineParsePolicy::paragraph(),
  )
  guard plan.delimiters.successors.get(0) is Some(2) &&
    plan.delimiters.successors.get(4) is Some(7) &&
    plan.delimiters.successors.get(10) is None else {
    abort("expected equal-length delimiter successors only")
  }
}

///|
test "container fact plan: keeps escaped openers literal" {
  let ctx = container_fact_context("\\`no` `yes`")
  let plan = build_line_container_fact_plan(
    ctx,
    0,
    InlineParsePolicy::paragraph(),
  )
  guard plan.delimiters.eligible_openers.get(1) is Some(false) &&
    plan.delimiters.eligible_openers.get(6) is Some(true) &&
    plan.delimiters.successors.get(6) is Some(10) else {
    abort("expected escaped opener to stay literal")
  }
}

///|
test "container fact plan: escaped delimiter parser fixture" {
  inspect(
    parse("\\`no` `yes`\n"),
    content="Document([Paragraph([Text(\"`no\"), InlineCode(\" \"), Text(\"yes\"), Text(\"`\")])])",
  )
}

///|
test "container fact plan: continuation resets delimiter escape state" {
  let ctx = container_fact_context("x\\\n`a`")
  let calls = [0]
  let plan = build_container_fact_plan(
    ctx,
    0,
    InlineParsePolicy::paragraph(),
    root_fact_handler(ctx, calls),
  )
  guard plan.delimiters.eligible_openers.get(3) is Some(true) &&
    plan.delimiters.successors.get(3) is Some(5) else {
    abort("expected continued-line backtick to remain an eligible opener")
  }
}

///|
test "container fact plan: line-bound walk records no actions" {
  let ctx = container_fact_context("`a`\n`b`")
  let plan = build_line_container_fact_plan(
    ctx,
    0,
    InlineParsePolicy::paragraph(),
  )
  inspect(plan.end_offset, content="3")
  guard plan.actions.get(3) is None &&
    plan.delimiters.successors.get(0) is Some(2) &&
    plan.delimiters.successors.get(4) is None else {
    abort("expected line-bound facts without continuation action")
  }
}

///|
test "container fact plan: parser consumes a planned action once" {
  let ctx = container_fact_context("alpha\nbeta")
  let calls = [0]
  parse_indexed_inline_container(
    ctx,
    InlineParsePolicy::paragraph(),
    root_fact_handler(ctx, calls),
  )
  inspect(calls[0], content="1")
}

///|
test "container fact plan: root authoritative parser fixture" {
  inspect(
    parse("alpha `a\nb`\n"),
    content="Document([Paragraph([Text(\"alpha \"), InlineCode(\"a b\")])])",
  )
}

///|
test "container fact plan: block quote authoritative CST fixture" {
  let (cst, _) = try! parse_cst("> `a\n> b`\n")
  let syntax = @seam.SyntaxNode::from_cst(cst)
  match syntax.children() {
    [quote] =>
      match quote.children() {
        [paragraph] =>
          match paragraph.children() {
            [inline_code] => {
              let kind : SyntaxKind = @seam.FromRawKind::from_raw(
                inline_code.kind(),
              )
              inspect(kind, content="InlineCodeNode")
              inspect(inline_code.text(), content="`a\n> b`")
            }
            _ =>
              inspect(paragraph.children().length(), content="one inline code")
          }
        _ => inspect(quote.children().length(), content="one quote paragraph")
      }
    _ => inspect(syntax.children().length(), content="one block quote")
  }
}

///|
test "container fact plan: list authoritative parser fixture" {
  inspect(
    parse("- alpha `a\n  b`\n"),
    content="Document([UnorderedList([UnorderedListItem([Text(\"alpha \"), InlineCode(\"a b\")])])])",
  )
}
