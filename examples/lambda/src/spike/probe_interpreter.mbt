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
/// Every other node mirrors `@grammar`'s tree-walking interpreter exactly. The
/// duplication is the price of holding the residue spike-local; it is removed
/// when the §5/§8 migration target is chosen.

///|
/// Resolved-grammar environment threaded through the probe walk.
priv struct ProbeEnv {
  compiled : @grammar.CompiledGrammar[@token.Token, @syntax.SyntaxKind]
  cripple_reuse : Bool
  atom_slot : Int
}

///|
/// Build B's `parse_root` from a compiled lambda grammar. Resolves the `atom`
/// slot once (the newline-application probe re-enters it); raises if the
/// compiled grammar somehow lacks it.
pub fn b_parse_root(
  compiled : @grammar.CompiledGrammar[@token.Token, @syntax.SyntaxKind],
  cripple_reuse : Bool,
) -> (@core.ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit {
  // `compile` resolves the `Ref("atom")` / `PrattApp("atom")` targets, so a
  // compiled lambda grammar always defines `atom`; the None branch is
  // unreachable and signals a corrupted grammar.
  let atom_slot = match compiled.names.search("atom") {
    Some(slot) => slot
    None => abort("lambda grammar IR must define an 'atom' rule")
  }
  let env = ProbeEnv::{ compiled, cripple_reuse, atom_slot }
  let root = compiled.rule(compiled.root_slot())
  ctx => env.run(ctx, root)
}

///|
/// Evaluate one compiled expression. Mirrors `@grammar`'s `run_expr` (rule
/// dispatch by dense slot, `Pred` data tested with `matches`), diverging only at
/// `ManualNewlineAppExpr` (residue) and `RepeatTopLevel` (cripple gate).
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
    RefSlot(slot) => self.run(ctx, self.compiled.rule(slot))
    Seq(exprs) =>
      for e in exprs {
        self.run(ctx, e)
      }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if alt.starts.matches(token) {
          self.run(ctx, alt.body)
          break
        }
      }
    }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred.matches(ctx.peek()) {
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
      if stop.matches(ctx.peek()) {
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        let _ = ctx.skip_until(t => stop.matches(t))
      }
    }
    // Delimited top-level repeat. Identical to `@grammar`'s node EXCEPT the
    // reuse fast-path is gated by `!cripple_reuse` (the positive control).
    RepeatTopLevel(slot, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      ctx.consume_while_emit(t => delim.matches(t), delim_kind)
      while !ctx.at_eof() && starts.matches(ctx.peek()) {
        if !self.cripple_reuse && ctx.try_reuse_repeat_group() {
          ctx.consume_while_emit(t => delim.matches(t), delim_kind)
          continue
        }
        self.run(ctx, self.compiled.rule(slot))
        let had = delim.matches(ctx.peek())
        ctx.consume_while_emit(t => delim.matches(t), delim_kind)
        if !had && !ctx.at_eof() {
          if starts.matches(ctx.peek()) {
            ctx.error(between_msg)
          } else {
            ctx.error(after_msg)
          }
        }
      }
    }
    WrapIfNext(kind, pred, body) => {
      let mark = ctx.mark()
      if pred.matches(ctx.peek()) {
        ctx.wrap_at(mark, kind, () => self.run(ctx, body))
      } else {
        self.run(ctx, body)
      }
    }
    PrattApp(slot, kind, starts) => {
      let mark = ctx.mark()
      self.run(ctx, self.compiled.rule(slot))
      if starts.matches(ctx.peek()) {
        ctx.wrap_at(mark, kind, () => {
          while starts.matches(ctx.peek()) {
            self.run(ctx, self.compiled.rule(slot))
          }
        })
      }
    }
    PrattBinary(slot, kind, ops) => {
      let mark = ctx.mark()
      self.run(ctx, self.compiled.rule(slot))
      if ops.iter().any(pair => pair.0 == ctx.peek()) {
        ctx.wrap_at(mark, kind, () => {
          while true {
            match ops.iter().find_first(pair => pair.0 == ctx.peek()) {
              None => break
              Some(pair) => {
                ctx.emit_token(pair.1)
                self.run(ctx, self.compiled.rule(slot))
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
    DiagnoseIf(pred, msg) => if pred.matches(ctx.peek()) { ctx.error(msg) }
    ExpectSkip(skip, skip_kind, expected, kind) => {
      let _ = ctx.expect_after_skip(
        t => skip.matches(t),
        skip_kind,
        expected,
        kind,
      )
    }
    ConsumeGated(skip, skip_kind, look) => {
      let _ = ctx.consume_while_emit_if(t => skip.matches(t), skip_kind, t => {
        look.matches(t)
      })
    }
    RequireSep(skip, skip_kind, stop, alt, msg_alt~, msg_else~) => {
      let had = skip.matches(ctx.peek())
      ctx.consume_while_emit(t => skip.matches(t), skip_kind)
      if !had && !stop.matches(ctx.peek()) {
        if alt.matches(ctx.peek()) {
          ctx.error(msg_alt)
        } else {
          ctx.error(msg_else)
        }
      }
    }
    ErrorNodeUntil(error_kind, stop, msg) => {
      ctx.error(msg)
      ctx.start_node(error_kind)
      while !ctx.at_eof() && !stop.matches(ctx.peek()) {
        ctx.bump_error()
      }
      ctx.finish_node()
    }
    // Residue: recursive newline-application mode (spec §5.1).
    ManualNewlineAppExpr => self.parse_newline_app(ctx)
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
  let atom = self.compiled.rule(self.atom_slot)
  let mark = ctx.mark()
  self.run(ctx, atom)
  let _ = ctx.consume_while_emit_if(
    t => t == @token.Newline,
    @syntax.NewlineToken,
    t => atom_starts.matches(t),
  )
  guard atom_starts.matches(ctx.peek()) else { return }
  ctx.wrap_at(mark, @syntax.AppExpr, () => {
    while true {
      self.run(ctx, atom)
      let _ = ctx.consume_while_emit_if(
        t => t == @token.Newline,
        @syntax.NewlineToken,
        t => atom_starts.matches(t),
      )
      guard atom_starts.matches(ctx.peek()) else { break }
    }
  })
}
