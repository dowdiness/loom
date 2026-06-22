///|
/// Build a `parse_root` closure from an authored grammar IR.
///
/// Compiles the IR (resolving every `Ref` to a dense slot, raising on an
/// unresolved reference) and returns a tree-walking interpreter over the
/// compiled form. This tree-walker is the only committed backend: the contract
/// reifies predicates as `Pred` data precisely so an analyzing interpreter or a
/// code emitter could be added later, but neither is built here.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] interpret(
  ir : GrammarIr[T, K],
) -> ((@core.ParserContext[T, K]) -> Unit) raise GrammarCompileError {
  interpret_compiled(compile(ir))
}

///|
/// Build a `parse_root` closure from an already-compiled grammar. The returned
/// closure dispatches the root rule's compiled body against a parser context.
/// Splitting this from `interpret` lets callers compile once and reuse the
/// dense-slot grammar across parser contexts.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] interpret_compiled(
  grammar : CompiledGrammar[T, K],
) -> (@core.ParserContext[T, K]) -> Unit {
  ctx => run_expr(ctx, grammar, grammar.rule(grammar.root_slot()))
}

///|
/// Evaluate one compiled grammar expression against a parser context.
///
/// Rule references dispatch by dense slot through `grammar.rule`, so recursion
/// is an array index rather than a map lookup. Predicates are reified `Pred`
/// data tested with `Pred::matches`, never host closures.
///
/// Covers the core and incremental-reuse nodes. The `ManualNewlineAppExpr`
/// residue (the lone irreducible escape hatch, evidence-gated by the lambda
/// spike probe — spec §5.3) is not interpreted here; reaching it surfaces a
/// diagnostic placeholder so a grammar that uses it via the minimal contract
/// fails loudly instead of silently producing a wrong tree.
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] run_expr(
  ctx : @core.ParserContext[T, K],
  grammar : CompiledGrammar[T, K],
  expr : CompiledExpr[T, K],
) -> Unit {
  match expr {
    Empty => ()
    Emit(token, kind) => if ctx.at(token) { ctx.emit_token(kind) }
    Expect(token, kind, msg) =>
      if !ctx.expect(token, kind) && msg.length() > 0 {
        ctx.error(msg)
      }
    Node(kind, body) => ctx.node(kind, () => run_expr(ctx, grammar, body))
    RefSlot(slot) => run_expr(ctx, grammar, grammar.rule(slot))
    Seq(exprs) =>
      for e in exprs {
        run_expr(ctx, grammar, e)
      }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if alt.starts.matches(token) {
          run_expr(ctx, grammar, alt.body)
          break
        }
      }
    }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred.matches(ctx.peek()) {
        run_expr(ctx, grammar, body)
      }
    EmitError(msg) => ctx.error(msg)
    ErrorUntil(stop, msg) => {
      ctx.error(msg)
      let _ = ctx.skip_until(t => stop.matches(t))
    }
    // Delimited top-level repeat. Consume leading delimiters, then loop while
    // `starts` holds. Each iteration tries repeat-group reuse first — consuming
    // delimiters after a hit so the reused group's trailing separator does not
    // exit the loop early — and parses the item rule on a miss. When a parsed
    // item is not followed by a delimiter and we are not at EOF, emit the
    // between/after diagnostic. Trailing expr + garbage recovery compose in the
    // caller.
    RepeatTopLevel(slot, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      ctx.consume_while_emit(t => delim.matches(t), delim_kind)
      while !ctx.at_eof() && starts.matches(ctx.peek()) {
        if ctx.try_reuse_repeat_group() {
          ctx.consume_while_emit(t => delim.matches(t), delim_kind)
          continue
        }
        run_expr(ctx, grammar, grammar.rule(slot))
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
    // Mark before peeking: when the next token matches, wrap the inner expr in
    // the node kind from that mark; otherwise run it unwrapped.
    WrapIfNext(kind, pred, body) => {
      let mark = ctx.mark()
      if pred.matches(ctx.peek()) {
        ctx.wrap_at(mark, kind, () => run_expr(ctx, grammar, body))
      } else {
        run_expr(ctx, grammar, body)
      }
    }
    // Pratt application: parse one atom; while the start predicate still holds,
    // retroactively wrap the run in the app kind and parse further atoms.
    PrattApp(slot, kind, starts) => {
      let mark = ctx.mark()
      run_expr(ctx, grammar, grammar.rule(slot))
      if starts.matches(ctx.peek()) {
        ctx.wrap_at(mark, kind, () => {
          while starts.matches(ctx.peek()) {
            run_expr(ctx, grammar, grammar.rule(slot))
          }
        })
      }
    }
    // Pratt binary: parse one prefix; while the peek matches an operator table
    // entry, wrap from the mark in the binary kind, emit the operator, and
    // parse the next prefix.
    PrattBinary(slot, kind, ops) => {
      let mark = ctx.mark()
      run_expr(ctx, grammar, grammar.rule(slot))
      if ops.iter().any(pair => pair.0 == ctx.peek()) {
        ctx.wrap_at(mark, kind, () => {
          while true {
            match ops.iter().find_first(pair => pair.0 == ctx.peek()) {
              None => break
              Some(pair) => {
                ctx.emit_token(pair.1)
                run_expr(ctx, grammar, grammar.rule(slot))
              }
            }
          }
        })
      }
    }
    // Emit a diagnostic and an error placeholder (required construct missing).
    Fail(msg) => {
      ctx.error(msg)
      ctx.emit_error_placeholder()
    }
    // Emit the token as the kind when present, else report it missing.
    EmitOr(token, kind, msg) =>
      if ctx.at(token) {
        ctx.emit_token(kind)
      } else {
        ctx.error(msg)
        ctx.emit_error_placeholder()
      }
    // Conditional lookahead diagnostic, no consume.
    DiagnoseIf(pred, msg) => if pred.matches(ctx.peek()) { ctx.error(msg) }
    // Soft-separator-aware expect: consume skip tokens when the expected token
    // follows the run, then expect it.
    ExpectSkip(skip, skip_kind, expected, kind) => {
      let _ = ctx.expect_after_skip(
        t => skip.matches(t),
        skip_kind,
        expected,
        kind,
      )
    }
    // Consume a soft-separator run only when the lookahead holds after it.
    ConsumeGated(skip, skip_kind, look) => {
      let _ = ctx.consume_while_emit_if(t => skip.matches(t), skip_kind, t => {
        look.matches(t)
      })
    }
    // Require a separator run; if none preceded and `stop` does not hold, emit
    // `msg_alt` when `alt` matches the current token, else `msg_else`.
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
    // Open an error node and bump tokens into it until `stop` (or EOF). Callers
    // guard the stop-already-holds case with a `Choice`, so this never opens an
    // empty node.
    ErrorNodeUntil(error_kind, stop, msg) => {
      ctx.error(msg)
      ctx.start_node(error_kind)
      while !ctx.at_eof() && !stop.matches(ctx.peek()) {
        ctx.bump_error()
      }
      ctx.finish_node()
    }
    ManualNewlineAppExpr => {
      ctx.error(
        "grammar: ManualNewlineAppExpr is a residue — interpret it with a language-specific probe, not the minimal contract",
      )
      ctx.emit_error_placeholder()
    }
  }
}
