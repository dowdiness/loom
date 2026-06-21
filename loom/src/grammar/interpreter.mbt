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
/// Covers the core and incremental-reuse nodes. The counted `CountedRepeat`
/// (escape-hatch reification stage) and the `ManualNewlineAppExpr` residue
/// (evidence-gated) are not interpreted here; reaching one surfaces a
/// diagnostic placeholder so a grammar that uses them before those stages
/// exist fails loudly instead of silently producing a wrong tree.
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
    // Top-level repeat with per-group reuse: try to reuse the prior repeat
    // group at each item; on a miss, parse the item rule. The trailing expr
    // runs once after the loop (`Empty` to reject a tail).
    RepeatTopLevel(slot, starts, tail) => {
      while !ctx.at_eof() && starts.matches(ctx.peek()) {
        if !ctx.try_reuse_repeat_group() {
          run_expr(ctx, grammar, grammar.rule(slot))
        }
      }
      run_expr(ctx, grammar, tail)
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
    CountedRepeat(_, _, min=_, missing_message=_) | ManualNewlineAppExpr => {
      ctx.error("grammar: expression not yet interpreted by this stage")
      ctx.emit_error_placeholder()
    }
  }
}
