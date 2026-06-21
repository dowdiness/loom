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
/// This is the core interpreter stage. The structural / incremental-reuse nodes
/// (`RepeatTopLevel`, `WrapIfNext`, `PrattApp`, `PrattBinary`), the counted
/// `CountedRepeat`, and the `ManualNewlineAppExpr` residue are not handled here;
/// reaching one surfaces a diagnostic placeholder so a grammar that uses them
/// before those interpreter stages exist fails loudly instead of silently
/// producing a wrong tree.
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
    RepeatTopLevel(_, _, _)
    | WrapIfNext(_, _, _)
    | PrattApp(_, _, _)
    | PrattBinary(_, _, _)
    | CountedRepeat(_, _, min=_, missing_message=_)
    | ManualNewlineAppExpr => {
      ctx.error("grammar: expression not handled by the core interpreter")
      ctx.emit_error_placeholder()
    }
  }
}
