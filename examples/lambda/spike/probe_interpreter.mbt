///|
/// Spike-local probe interpreter for the reified lambda grammar (loomgen
/// IR-contract, Task 7+8 merged).
///
/// B drives loom's engine through THIS interpreter, not `@grammar.interpret`,
/// for two reasons that `@grammar`'s minimal contract deliberately does not
/// carry (spec §5.1 / §8 — "decide with oracle evidence, do not pre-commit"):
///
///   1. `ManualNewlineAppExpr` — the lone irreducible residue. `@grammar`
///      placeholders it; here it runs the recursive newline-application mode
///      (`parse_newline_app`). A is mode-threaded through paren/if/lambda
///      recursion (cst_parser.mbt parse_expression_with_mode), so a flat
///      `@grammar` node cannot express it without a mode mechanism — kept
///      spike-local so the public contract stays minimal.
///   2. `cripple_reuse` — the reuse-parity positive control. There is no public
///      "disable repeat-group reuse" switch (only `reuse_size_threshold`), so
///      the harness toggles it here, NOT in the grammar value (spec §3.1).
///
/// Tree-shape behavior otherwise follows `@grammar` closely, with compiled
/// predicates evaluated by the probe-local `pred_matches`. This probe does not
/// implement the production interpreter's cursor-progress guards or its
/// `(RuleSlot, cursor position)` cycle stack, so malformed `RepeatWhile`,
/// `RepeatTopLevel`, or `PrattApp` input can spin here instead of producing a
/// grammar-execution diagnostic. It remains an oracle-specific probe, not the
/// execution-safety reference.

///|
/// Resolved-grammar environment threaded through the probe walk.
priv struct ProbeEnv {
  compiled : @grammar.CompiledGrammar[@token.Token, @syntax.SyntaxKind]
  cripple_reuse : Bool
  atom_slot : @grammar.RuleSlot
  binary_slot : @grammar.RuleSlot
}

///|
/// Resolve a named rule to its compiled slot, aborting if missing.
/// Callers know the grammar IR defines every rule they reference.
fn slot(
  compiled : @grammar.CompiledGrammar[@token.Token, @syntax.SyntaxKind],
  name : String,
) -> @grammar.RuleSlot {
  match compiled.slot_for_name(name) {
    Some(s) => s
    None => abort("lambda grammar IR must define a '" + name + "' rule")
  }
}

///|
/// Spike-local token-only matcher for compiled predicates. Lambda IR has no
/// host guards; encountering one is a contract violation, not a non-match.
fn pred_matches(
  pred : @grammar.CompiledPred[@token.Token],
  token : @token.Token,
) -> Bool {
  match pred {
    Any => true
    IsToken(expected) => token == expected
    OneOf(tokens) => tokens.iter().any(t => t == token)
    Not(inner) => !pred_matches(inner, token)
    All(left, right) => pred_matches(left, token) && pred_matches(right, token)
    HostGuardSlot(_) =>
      abort(
        "lambda probe: HostGuardSlot is not supported by token-only matcher",
      )
  }
}

///|
/// Build B's `parse_root` from a compiled lambda grammar. Resolves named rule
/// slots once so the hot path (ProbeEnv::run) never does a string lookup.
pub fn b_parse_root(
  compiled : @grammar.CompiledGrammar[@token.Token, @syntax.SyntaxKind],
  cripple_reuse : Bool,
) -> (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit {
  let env = ProbeEnv::{
    compiled,
    cripple_reuse,
    atom_slot: slot(compiled, "atom"),
    binary_slot: slot(compiled, "binary"),
  }
  let root = compiled.rule_snapshot(compiled.root_slot()).unwrap()
  ctx => env.run(ctx, root)
}

///|
/// Evaluate one compiled expression. It follows `@grammar`'s tree-shape walk
/// with dense-slot dispatch and probe-local `pred_matches`, while diverging for
/// `ManualNewlineAppExpr`, the `RepeatTopLevel` cripple gate, and the omitted
/// production progress/cycle guards documented above.
fn ProbeEnv::run(
  self : ProbeEnv,
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expr : @grammar.CompiledExpr[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  match expr {
    Empty => ()
    Emit(token, kind) => if ctx.at(token) { ctx.emit_token(kind) }
    // `expect` already emits a diagnostic + placeholder on the missing-token
    // path; discard the bool so the path produces exactly one diagnostic.
    Expect(token, kind) => ctx.expect(token, kind) |> ignore
    Node(kind, body) => ctx.node(kind, () => self.run(ctx, body))
    RefSlot(slot) => self.run(ctx, self.compiled.rule_snapshot(slot).unwrap())
    Seq(exprs) =>
      for e in exprs {
        self.run(ctx, e)
      }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if pred_matches(alt.starts, token) {
          self.run(ctx, alt.body)
          break
        }
      }
    }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred_matches(pred, ctx.peek()) {
        self.run(ctx, body)
      }
    EmitError(msg) => ctx.error(msg)
    // Lambda-local recovery residue (mirrors the spike's `parse_error_node_until`
    // / A's parse_atom `_` fallthrough). DIVERGES from `@grammar`'s `ErrorUntil`
    // (`error + skip_until`): when already at a sync point (e.g. EOF after a
    // missing RHS) it opens an `ErrorNode` holding an error placeholder — the
    // missing-construct marker A emits — and only skips tokens otherwise. The
    // node kind is lambda's `@syntax.ErrorNode` (the contract's `ErrorUntil`
    // carries no kind), so this stays probe-local.
    ErrorUntil(stop, msg) => {
      ctx.error(msg)
      if pred_matches(stop, ctx.peek()) {
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        let _ = ctx.skip_until(t => pred_matches(stop, t))
      }
    }
    // Delimited top-level repeat. Identical to `@grammar`'s node EXCEPT the
    // reuse fast-path is gated by `!cripple_reuse` (the positive control).
    RepeatTopLevel(slot, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      ctx.consume_while_emit(t => pred_matches(delim, t), delim_kind)
      while !ctx.at_eof() && pred_matches(starts, ctx.peek()) {
        if !self.cripple_reuse && ctx.try_reuse_repeat_group() {
          ctx.consume_while_emit(t => pred_matches(delim, t), delim_kind)
          continue
        }
        self.run(ctx, self.compiled.rule_snapshot(slot).unwrap())
        let had = pred_matches(delim, ctx.peek())
        ctx.consume_while_emit(t => pred_matches(delim, t), delim_kind)
        if !had && !ctx.at_eof() {
          if pred_matches(starts, ctx.peek()) {
            ctx.error(between_msg)
          } else {
            ctx.error(after_msg)
          }
        }
      }
    }
    WrapIfNext(kind, pred, body) => {
      let mark = ctx.mark()
      if pred_matches(pred, ctx.peek()) {
        ctx.wrap_at(mark, kind, () => self.run(ctx, body))
      } else {
        self.run(ctx, body)
      }
    }
    PrattApp(_slot, kind, starts) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        self.run_atom(ctx, false)
        if pred_matches(starts, ctx.peek()) {
          ctx.wrap_at(mark, kind, () => {
            while pred_matches(starts, ctx.peek()) {
              self.run_atom(ctx, false)
            }
          })
        }
      }
    PrattBinary(slot, kind, ops, skip~) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        self.run(ctx, self.compiled.rule_snapshot(slot).unwrap())
        // Mirrors @grammar's PrattBinary arm: gated soft-separator consume before
        // each operator (lookahead = the op table), matching A's
        // consume_soft_newlines_before_binary_operator.
        let skip_to_op = () => {
          match skip {
            Some((sep, sep_kind)) =>
              ctx.consume_while_emit_if(t => pred_matches(sep, t), sep_kind, t => {
                ops.iter().any(pair => pair.0 == t)
              })
              |> ignore
            None => ()
          }
        }
        skip_to_op()
        if ops.iter().any(pair => pair.0 == ctx.peek()) {
          ctx.wrap_at(mark, kind, () => {
            while true {
              skip_to_op()
              match ops.iter().find_first(pair => pair.0 == ctx.peek()) {
                None => break
                Some(pair) => {
                  ctx.emit_token(pair.1)
                  self.run(ctx, self.compiled.rule_snapshot(slot).unwrap())
                }
              }
            }
          })
        }
      }
    Fail(msg) => {
      ctx.error(msg)
      ctx.emit_error_placeholder()
    }
    EmitOr(token, kind, msg) =>
      if ctx.at(token) {
        ctx.emit_token(kind)
      } else {
        ctx.error(msg)
        ctx.emit_error_placeholder()
      }
    DiagnoseIf(pred, msg) =>
      if pred_matches(pred, ctx.peek()) {
        ctx.error(msg)
      }
    ExpectSkip(skip, skip_kind, expected, kind) => {
      let _ = ctx.expect_after_skip(
        t => pred_matches(skip, t),
        skip_kind,
        expected,
        kind,
      )
    }
    ConsumeGated(skip, skip_kind, look) => {
      let _ = ctx.consume_while_emit_if(t => pred_matches(skip, t), skip_kind, t => {
        pred_matches(look, t)
      })
    }
    RequireSep(delims, stop, alt, msg_alt~, msg_else~) => {
      let had = ctx.consume_while_emit_mapped(delims) > 0
      if !had && !pred_matches(stop, ctx.peek()) {
        if pred_matches(alt, ctx.peek()) {
          ctx.error(msg_alt)
        } else {
          ctx.error(msg_else)
        }
      }
    }
    ErrorNodeUntil(error_kind, stop, msg) => {
      ctx.error(msg)
      ctx.start_node(error_kind)
      while !ctx.at_eof() && !pred_matches(stop, ctx.peek()) {
        ctx.bump_error()
      }
      ctx.finish_node()
    }
    // Residue: recursive newline-application mode (spec §5.1).
    ManualNewlineAppExpr => self.parse_newline_app(ctx)
    // The lambda grammar does not use `Native` — retain the probe-local
    // diagnostic residue for an accidental compiled native slot.
    NativeSlot(slot) => {
      ignore(slot)
      ctx.error("lambda probe: native slot is not supported here")
      ctx.emit_error_placeholder()
    }
  }
}

// ─── Arrow-lambda helpers (#476) ─────────────────────────────────────

///|
/// Whether `(` starts `(params) => body` — scans ahead for matching `)` then `=>`.
/// Mirrors A's `left_paren_starts_arrow_lambda`.
fn is_arrow_lambda(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  token_after_matching_right_paren(ctx) is Some(@token.FatArrow)
}

///|
/// Token after the `)` matching the current `(`, counting paren depth for nesting.
fn token_after_matching_right_paren(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> @token.Token? {
  for index = 1, paren_depth = 0 {
    match ctx.peek_nth(index) {
      @token.EOF => break None
      @token.LeftParen => continue index + 1, paren_depth + 1
      @token.RightParen =>
        if paren_depth == 0 {
          break token_after_soft_newlines(ctx, index + 1)
        } else {
          continue index + 1, paren_depth - 1
        }
      _ => continue index + 1, paren_depth
    }
  }
}

///|
/// Skip Newline tokens from start_index; return first non-Newline token or None.
fn token_after_soft_newlines(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  start_index : Int,
) -> @token.Token? {
  for index = start_index {
    match ctx.peek_nth(index) {
      @token.EOF => break None
      @token.Newline => continue index + 1
      token => break Some(token)
    }
  }
}

///|
/// Parse `(params) => body` arrow lambda wrapping in LambdaExpr, with recovery.
/// Soft-newline handling matches A's `lambda_expect` + `consume_soft_newlines_before_expression`.
fn ProbeEnv::parse_arrow_lambda(
  self : ProbeEnv,
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  ctx.node_with_recovery(
    @syntax.LambdaExpr,
    fn() -> Bool {
      parse_lambda_param_list(ctx)
      // Return false when => is missing so node_with_recovery triggers recovery.
      if !ctx.expect_after_skip(
          t => t == @token.Newline,
          @syntax.NewlineToken,
          @token.FatArrow,
          @syntax.FatArrowToken,
        ) {
        return false
      }
      ctx.node(@syntax.LambdaBody, fn() {
        // Match A: only special-case { when immediately after => (no soft newlines).
        if ctx.peek() == @token.LBrace {
          self.run(ctx, self.compiled.rule_snapshot(self.atom_slot).unwrap())
        } else {
          let expr_starts = lambda_expression_starts()
          let _ = ctx.consume_while_emit_if(
            t => t == @token.Newline,
            @syntax.NewlineToken,
            t => expr_starts.matches(t),
          )
          if allow_newline_application {
            self.parse_newline_app(ctx)
          } else {
            self.run(
              ctx,
              self.compiled.rule_snapshot(self.binary_slot).unwrap(),
            )
          }
        }
      })
      true
    },
    @token.is_sync_point,
  )
}

///|
fn parse_lambda_param_list(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.start_node(@syntax.ParamList)
  ctx.emit_token(@syntax.LeftParenToken)
  if ctx.peek() == @token.RightParen {
    ctx.error("Empty parameter list")
    ctx.emit_error_placeholder()
  } else if ctx.peek() == @token.Identifier {
    parse_lambda_param(ctx)
    while ctx.peek() == @token.Comma {
      ctx.emit_token(@syntax.CommaToken)
      if ctx.peek() == @token.Identifier {
        parse_lambda_param(ctx)
      } else if ctx.peek() == @token.RightParen {
        ctx.error("Trailing comma in parameter list")
        break
      } else {
        ctx.error("Expected parameter name")
        ctx.emit_error_placeholder()
      }
    }
  } else {
    ctx.error("Expected parameter name")
    ctx.emit_error_placeholder()
  }
  let _ = ctx.expect_after_skip(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    @token.RightParen,
    @syntax.RightParenToken,
  )
  ctx.finish_node()
}

///|
/// Parse one lambda param: `ident` or `ident : Type`.
fn parse_lambda_param(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.emit_token(@syntax.IdentToken)
  if ctx.peek() == @token.Colon {
    ctx.start_node(@syntax.TypeAnnot)
    ctx.emit_token(@syntax.ColonToken)
    parse_lambda_type(ctx)
    ctx.finish_node()
  }
}

///|
/// Parse lambda type: right-recursive arrow chains wrapped in nested TypeArrow.
/// Mirrors A's parse_type: `Int -> Unit -> Int` → TypeArrow(TypeInt, ArrowToken,
/// TypeArrow(TypeUnit, ArrowToken, TypeInt)).
fn parse_lambda_type(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_lambda_atom_type(ctx)
  if ctx.peek() == @token.Arrow {
    ctx.emit_token(@syntax.ArrowToken)
    parse_lambda_type(ctx)
    ctx.start_at(mark, @syntax.TypeArrow)
    ctx.finish_node()
  }
}

///|
/// Parse one atom type: Int→TypeInt, Unit→TypeUnit, (Type)→grouped, other→error.
fn parse_lambda_atom_type(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  if ctx.peek() == @token.Identifier {
    let text = ctx.current_token_text().to_owned()
    if text == "Int" {
      ctx.node(@syntax.TypeInt, fn() { ctx.emit_token(@syntax.IdentToken) })
    } else if text == "Unit" {
      ctx.node(@syntax.TypeUnit, fn() { ctx.emit_token(@syntax.IdentToken) })
    } else {
      ctx.error("expected type, got identifier '" + text + "'")
      ctx.emit_error_placeholder()
    }
  } else if ctx.peek() == @token.LeftParen {
    ctx.emit_token(@syntax.LeftParenToken)
    parse_lambda_type(ctx)
    let _ = ctx.expect(@token.RightParen, @syntax.RightParenToken)
  } else {
    ctx.error("expected type")
    ctx.emit_error_placeholder()
  }
}

///|
/// Parse LeftParen as arrow lambda or fall through to the normal atom rule.
/// Threads `allow_newline_application` into the lambda body.
fn ProbeEnv::run_atom(
  self : ProbeEnv,
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  allow_newline_application : Bool,
) -> Unit {
  if ctx.peek() == @token.LeftParen && is_arrow_lambda(ctx) {
    self.parse_arrow_lambda(ctx, allow_newline_application)
  } else {
    self.run(ctx, self.compiled.rule_snapshot(self.atom_slot).unwrap())
  }
}

///|
/// Newline-application binary expression (`allow_newline_application=true`).
/// Mirrors the spike's `parse_newline_app_expr`: a binary layer over a
/// newline-spanning application layer, consuming soft newlines before operators
/// and between atoms.
fn ProbeEnv::parse_newline_app(
  self : ProbeEnv,
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let op_pairs : Array[(@token.Token, @syntax.SyntaxKind)] = [
    (@token.Plus, @syntax.PlusToken),
    (@token.Minus, @syntax.MinusToken),
  ]
  let has_op = t => op_pairs.iter().any(p => t == p.0)
  let mark = ctx.mark()
  self.parse_app_nl(ctx)
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    has_op,
  )
  guard has_op(ctx.peek()) else { return }
  ctx.wrap_at(mark, @syntax.BinaryExpr, () => {
    while true {
      match op_pairs.iter().find_first(p => ctx.peek() == p.0) {
        None => break
        Some(pair) => {
          ctx.emit_token(pair.1)
          self.parse_app_nl(ctx)
          let _ = ctx.consume_while_emit_if(
            t => t == @token.Newline,
            @syntax.NewlineToken,
            has_op,
          )
        }
      }
    }
  })
}

///|
/// Application layer with `allow_newline_application=true`. Mirrors the spike's
/// `parse_app_with_newline`: consumes soft newlines between atoms when an atom
/// follows, retroactively wrapping the run in `AppExpr`.
fn ProbeEnv::parse_app_nl(
  self : ProbeEnv,
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let atom_starts = lambda_atom_starts()
  let mark = ctx.mark()
  self.run_atom(ctx, true)
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    t => atom_starts.matches(t),
  )
  guard atom_starts.matches(ctx.peek()) else { return }
  ctx.wrap_at(mark, @syntax.AppExpr, () => {
    while true {
      self.run_atom(ctx, true)
      let _ = ctx.consume_while_emit_if(
        t => t == @token.Newline,
        @syntax.NewlineToken,
        t => atom_starts.matches(t),
      )
      guard atom_starts.matches(ctx.peek()) else { break }
    }
  })
}
