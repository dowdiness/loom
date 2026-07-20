///|
/// A hand-written production a `Native(name)` node delegates to. Takes the
/// parser context plus a `try_parse_rule` gate for declared top-level Choice
/// rules. The gate returns whether an arm matched.
pub type NativeRule[T, K] = (@core.ParserContext[T, K], (RuleName) -> Bool) -> Unit

///|
/// A hand-written guard predicate a `HostGuard(name)` node delegates to.
/// Takes the parser context and returns whether the guard passes.
/// Mirrors `NativeRule` in that the name resolves against host code.
pub type HostGuard[T, K] = (@core.ParserContext[T, K]) -> Bool

///|
/// Build a `parse_root` closure from an authored grammar IR.
///
/// Compiles the IR (resolving every `Ref` to a dense slot, raising on an
/// unresolved reference) and returns a tree-walking interpreter over the
/// compiled form. This tree-walker is the only committed backend: the contract
/// reifies predicates as `Pred` data precisely so an analyzing interpreter or a
/// code emitter could be added later, but neither is built here.
///
/// `natives` supplies the host-written productions for any `Native(...)` nodes
/// in `ir` (empty by default — existing callers are unaffected). Its keys are
/// threaded into `compile` as `native_names`, so an IR that references a
/// `Native(name)` absent from `natives` fails here with `MissingNative`,
/// never mid-parse.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] interpret(
  ir : GrammarIr[T, K],
  natives? : Map[RuleName, NativeRule[T, K]] = Map([]),
  guards? : Map[RuleName, HostGuard[T, K]] = Map([]),
  native_rule_refs? : Map[RuleName, Set[RuleName]] = Map([]),
) -> ((@core.ParserContext[T, K]) -> Unit) raise GrammarCompileError {
  let native_names = Set::from_iter(natives.keys())
  let guard_names = Set::from_iter(guards.keys())
  interpret_compiled(
    compile(ir, native_names~, guard_names~, native_rule_refs~),
    natives~,
    guards~,
  )
}

///|
/// Build a `parse_root` closure from an already-compiled grammar. The returned
/// closure dispatches the root rule's compiled body against a parser context.
/// Splitting this from `interpret` lets callers compile once and reuse the
/// dense-slot grammar across parser contexts.
///
/// `natives` must agree with the `native_names` the grammar was compiled
/// with; a `NativeRef(name)` for which `natives` has no entry (e.g. a
/// mismatched registry passed here vs. at `compile` time) degrades to a
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] interpret_compiled(
  grammar : CompiledGrammar[T, K],
  natives? : Map[RuleName, NativeRule[T, K]] = Map([]),
  guards? : Map[RuleName, HostGuard[T, K]] = Map([]),
) -> (@core.ParserContext[T, K]) -> Unit {
  ctx => {
    run_expr(ctx, grammar, natives, guards, grammar.rule(grammar.root_slot()))
  }
}

///|
/// Try one declared native-dispatch target. Only a matching top-level Choice
/// arm executes; a non-match returns false without changing parser state.
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] try_parse_rule(
  ctx : @core.ParserContext[T, K],
  grammar : CompiledGrammar[T, K],
  natives : Map[RuleName, NativeRule[T, K]],
  guards : Map[RuleName, HostGuard[T, K]],
  caller_name : RuleName,
  target_name : RuleName,
) -> Bool {
  guard grammar.names.search(target_name) is Some(slot) else {
    ctx.error(
      "grammar: try_parse_rule(\"" + target_name + "\") is not a grammar rule",
    )
    ctx.emit_error_placeholder()
    return false
  }
  match grammar.native_rule_refs.get(caller_name) {
    None => {
      ctx.error(
        "grammar: native \"" +
        caller_name +
        "\" has no declared dispatch dependencies",
      )
      ctx.emit_error_placeholder()
      return false
    }
    Some(allowed) =>
      if !allowed.contains(target_name) {
        ctx.error(
          "grammar: native \"" +
          caller_name +
          "\" cannot dispatch to \"" +
          target_name +
          "\" — not in declared dependencies",
        )
        ctx.emit_error_placeholder()
        return false
      }
  }
  match grammar.rule(slot) {
    CompiledExpr::Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if pred_matches_ctx(alt.starts, token, ctx, guards) {
          run_expr(ctx, grammar, natives, guards, alt.body)
          return true
        }
      }
      false
    }
    _ => {
      ctx.error(
        "grammar: try_parse_rule(\"" +
        target_name +
        "\") target is not a Choice rule",
      )
      ctx.emit_error_placeholder()
      false
    }
  }
}

///|
/// Test whether `token` satisfies `pred`, resolving `HostGuard` references
/// against the `guards` map. `HostGuard` cannot be resolved by `Pred::matches`
/// alone (which takes only a token), so this function provides the
/// `ParserContext`-aware dispatch path.
fn[T : Eq, K] pred_matches_ctx(
  pred : Pred[T],
  token : T,
  ctx : @core.ParserContext[T, K],
  guards : Map[RuleName, HostGuard[T, K]],
) -> Bool {
  match pred {
    HostGuard(name) =>
      match guards.get(name) {
        Some(f) => f(ctx)
        None => false
      }
    All(left, right) =>
      pred_matches_ctx(left, token, ctx, guards) &&
      pred_matches_ctx(right, token, ctx, guards)
    Any | IsToken(_) | OneOf(_) => pred.matches(token)
    Not(inner) => !pred_matches_ctx(inner, token, ctx, guards)
  }
}

///|
/// Evaluate one compiled grammar expression against a parser context.
///
/// Rule references dispatch by dense slot through `grammar.rule`, so recursion
/// is an array index rather than a map lookup. Predicates are reified `Pred`
/// data tested with `Pred::matches` or `pred_matches_ctx` for HostGuard.
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
  natives : Map[RuleName, NativeRule[T, K]],
  guards : Map[RuleName, HostGuard[T, K]],
  expr : CompiledExpr[T, K],
) -> Unit {
  match expr {
    Empty => ()
    Emit(token, kind) => if ctx.at(token) { ctx.emit_token(kind) }
    Expect(token, kind) => ctx.expect(token, kind) |> ignore
    Node(kind, body) =>
      ctx.node(kind, () => run_expr(ctx, grammar, natives, guards, body))
    RefSlot(slot) => run_expr(ctx, grammar, natives, guards, grammar.rule(slot))
    NativeRef(name) =>
      match natives.get(name) {
        Some(f) =>
          f(ctx, rule_name => {
            try_parse_rule(ctx, grammar, natives, guards, name, rule_name)
          })
        None => {
          ctx.error(
            "grammar: native rule \"" +
            name +
            "\" has no registered implementation",
          )
          ctx.emit_error_placeholder()
        }
      }
    Seq(exprs) =>
      for e in exprs {
        run_expr(ctx, grammar, natives, guards, e)
      }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if pred_matches_ctx(alt.starts, token, ctx, guards) {
          run_expr(ctx, grammar, natives, guards, alt.body)
          break
        }
      }
    }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred.matches(ctx.peek()) {
        run_expr(ctx, grammar, natives, guards, body)
      }
    EmitError(msg) => ctx.error(msg)
    ErrorUntil(stop, msg) =>
      if !stop.matches(ctx.peek()) {
        ctx.error(msg)
        let _ = ctx.skip_until(t => stop.matches(t))
      }
    RepeatTopLevel(slot, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      ctx.consume_while_emit(t => delim.matches(t), delim_kind)
      while !ctx.at_eof() && starts.matches(ctx.peek()) {
        if ctx.try_reuse_repeat_group() {
          ctx.consume_while_emit(t => delim.matches(t), delim_kind)
          continue
        }
        run_expr(ctx, grammar, natives, guards, grammar.rule(slot))
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
        ctx.wrap_at(mark, kind, () => {
          run_expr(ctx, grammar, natives, guards, body)
        })
      } else {
        run_expr(ctx, grammar, natives, guards, body)
      }
    }
    PrattApp(slot, kind, starts) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        run_expr(ctx, grammar, natives, guards, grammar.rule(slot))
        if starts.matches(ctx.peek()) {
          ctx.wrap_at(mark, kind, () => {
            while starts.matches(ctx.peek()) {
              run_expr(ctx, grammar, natives, guards, grammar.rule(slot))
            }
          })
        }
      }
    PrattBinary(slot, kind, ops, skip~) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        run_expr(ctx, grammar, natives, guards, grammar.rule(slot))
        let skip_to_op = () => {
          match skip {
            Some((sep, sep_kind)) =>
              ctx.consume_while_emit_if(t => sep.matches(t), sep_kind, t => {
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
                  run_expr(ctx, grammar, natives, guards, grammar.rule(slot))
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
    RequireSep(delims, stop, alt, msg_alt~, msg_else~) => {
      let had = ctx.consume_while_emit_mapped(delims) > 0
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
    ManualNewlineAppExpr => {
      ctx.error(
        "grammar: ManualNewlineAppExpr is a residue — interpret it with a language-specific probe, not the minimal contract",
      )
      ctx.emit_error_placeholder()
    }
  }
}
