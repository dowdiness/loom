///|
/// A hand-written production a `Native(name)` node delegates to. Takes the
/// parser context plus a `call_rule` re-entry handle so the native can parse
/// its own context-sensitive residue (e.g. an HTML open-tag stack) while
/// delegating context-free sub-productions back to the declarative grammar.
pub type NativeRule[T, K] = (@core.ParserContext[T, K], (RuleName) -> Unit) -> Unit

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
) -> ((@core.ParserContext[T, K]) -> Unit) raise GrammarCompileError {
  let native_names = Set::from_iter(natives.keys())
  interpret_compiled(compile(ir, native_names~), natives~)
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
/// diagnostic placeholder rather than aborting — see `run_expr`.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] interpret_compiled(
  grammar : CompiledGrammar[T, K],
  natives? : Map[RuleName, NativeRule[T, K]] = Map([]),
) -> (@core.ParserContext[T, K]) -> Unit {
  ctx => run_expr(ctx, grammar, natives, grammar.rule(grammar.root_slot()))
}

///|
/// Resolve `name` to its dense slot and run it, for a native's `call_rule`
/// re-entry handle. `name` is grammar-rule-only by contract (natives cannot
/// call other natives through this handle); an unknown name reports a
/// diagnostic rather than aborting, since the name came from host code the
/// interpreter does not control.
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] call_rule(
  ctx : @core.ParserContext[T, K],
  grammar : CompiledGrammar[T, K],
  natives : Map[RuleName, NativeRule[T, K]],
  name : RuleName,
) -> Unit {
  match grammar.names.search(name) {
    Some(slot) => run_expr(ctx, grammar, natives, grammar.rule(slot))
    None =>
      ctx.error(
        "grammar: native call_rule(\"" + name + "\") is not a grammar rule",
      )
  }
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
  natives : Map[RuleName, NativeRule[T, K]],
  expr : CompiledExpr[T, K],
) -> Unit {
  match expr {
    Empty => ()
    Emit(token, kind) => if ctx.at(token) { ctx.emit_token(kind) }
    // `expect` already emits a diagnostic + placeholder on the missing-token
    // path; discard the bool so the path produces exactly one diagnostic.
    Expect(token, kind) => ctx.expect(token, kind) |> ignore
    Node(kind, body) =>
      ctx.node(kind, () => run_expr(ctx, grammar, natives, body))
    RefSlot(slot) => run_expr(ctx, grammar, natives, grammar.rule(slot))
    // Delegate to a host-written production. `call_rule` re-enters the
    // declarative grammar by name (grammar-rule-only — see `call_rule`
    // above); an unregistered name degrades to a diagnostic placeholder
    // instead of aborting, matching `ManualNewlineAppExpr`'s defensive style.
    // Unreachable when `natives` matches the `native_names` the grammar was
    // compiled with (validated in `compile`), but a mismatched registry
    // passed to `interpret_compiled` can still reach here.
    NativeRef(name) =>
      match natives.get(name) {
        Some(f) =>
          f(ctx, rule_name => call_rule(ctx, grammar, natives, rule_name))
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
        run_expr(ctx, grammar, natives, e)
      }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if alt.starts.matches(token) {
          run_expr(ctx, grammar, natives, alt.body)
          break
        }
      }
    }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred.matches(ctx.peek()) {
        run_expr(ctx, grammar, natives, body)
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
        run_expr(ctx, grammar, natives, grammar.rule(slot))
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
        ctx.wrap_at(mark, kind, () => run_expr(ctx, grammar, natives, body))
      } else {
        run_expr(ctx, grammar, natives, body)
      }
    }
    // Pratt application: parse one atom; while the start predicate still holds,
    // retroactively wrap the run in the app kind and parse further atoms.
    PrattApp(slot, kind, starts) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        run_expr(ctx, grammar, natives, grammar.rule(slot))
        if starts.matches(ctx.peek()) {
          ctx.wrap_at(mark, kind, () => {
            while starts.matches(ctx.peek()) {
              run_expr(ctx, grammar, natives, grammar.rule(slot))
            }
          })
        }
      }
    // Pratt binary: parse one prefix; while the peek matches an operator table
    // entry, wrap from the mark in the binary kind, emit the operator, and
    // parse the next prefix.
    PrattBinary(slot, kind, ops, skip~) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        run_expr(ctx, grammar, natives, grammar.rule(slot))
        // Mirrors A's consume_soft_newlines_before_binary_operator: consume a
        // gated run of `skip` tokens when an operator from the table follows, so
        // a separator that does NOT precede an operator (a statement break) is
        // left intact. The lookahead is the op table, so skipping is scoped to
        // the listed operators (e.g. +/-, not *,/).
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
                  run_expr(ctx, grammar, natives, grammar.rule(slot))
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
    // `msg_alt` when `alt` matches the current token, else `msg_else`. The delim
    // run emits each token with its own kind (newline vs `;`); the consumed
    // count tells whether a separator preceded.
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
