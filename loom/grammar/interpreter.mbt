///|
pub type HostGuard[T, K] = (@core.ParserContext[T, K]) -> Bool

///|
pub type NativeRule[T, K] = (@core.ParserContext[T, K], NativeDispatcher[T, K]) -> Unit

///|
pub type NativeFactory[T, K] = (NativeCapabilities[T, K]) -> NativeRule[T, K] raise GrammarBindError

///|
pub suberror GrammarBindError {
  MissingNative(RuleName)
  UnexpectedNative(RuleName)
  MissingGuard(RuleName)
  UnexpectedGuard(RuleName)
  CapabilityRejected(RuleName)
} derive(Eq, Debug)

///|
pub suberror GrammarBuildError {
  Compile(GrammarCompileError)
  Bind(GrammarBindError)
} derive(Eq, Debug)

///|
/// Fresh identity brand private to one native in one executable binding.
priv struct NativeCapabilityBrand {
  token : Ref[Unit]
}

///|
/// Opaque capability for one declared native-dispatch target.
pub struct RuleCapability[T, K] {
  priv brand : NativeCapabilityBrand
  priv slot : RuleSlot
  priv marker : (T, K)?
}

///|
/// One active rule invocation and the cursor at which it began.
priv struct RuleFrame {
  slot : RuleSlot
  position : Int
}

///|
/// Parse-local rule call stack shared by interpreter and native dispatch.
priv struct RuleCallStack {
  frames : Array[RuleFrame]
}

///|
/// Named capabilities available to one native factory during binding.
pub struct NativeCapabilities[T, K] {
  priv pairs : Array[(RuleName, RuleCapability[T, K])]
}

///|
pub fn[T, K] NativeCapabilities::require(
  self : Self[T, K],
  name : RuleName,
) -> RuleCapability[T, K] raise GrammarBindError {
  match self.pairs.iter().find_first(pair => pair.0 == name) {
    Some(pair) => pair.1
    None => raise CapabilityRejected(name)
  }
}

///|
/// Opaque dispatcher passed to a native callback at parse time.
pub struct NativeDispatcher[T, K] {
  priv grammar : CompiledGrammar[T, K]
  priv natives : Array[NativeRule[T, K]]
  priv guards : Array[HostGuard[T, K]]
  priv brands : Array[NativeCapabilityBrand]
  priv stack : RuleCallStack
  priv native_slot : NativeSlot
  priv brand : NativeCapabilityBrand
}

///|
/// Opaque executable grammar. Binding is complete before parsing starts.
pub struct ExecutableGrammar[T, K] {
  priv grammar : CompiledGrammar[T, K]
  priv natives : Array[NativeRule[T, K]]
  priv guards : Array[HostGuard[T, K]]
  priv brands : Array[NativeCapabilityBrand]
}

///|
/// Bind host factories and guards to a compiled grammar before parsing.
pub fn[T, K] bind(
  compiled : CompiledGrammar[T, K],
  natives? : Map[RuleName, NativeFactory[T, K]] = Map([]),
  guards? : Map[RuleName, HostGuard[T, K]] = Map([]),
) -> ExecutableGrammar[T, K] raise GrammarBindError {
  for name in compiled.native_names {
    guard natives.get(name) is Some(_) else { raise MissingNative(name) }
  }
  for name in natives.keys() {
    if !compiled.native_names.contains(name) {
      raise UnexpectedNative(name)
    }
  }
  for name in compiled.guard_names {
    guard guards.get(name) is Some(_) else { raise MissingGuard(name) }
  }
  for name in guards.keys() {
    if !compiled.guard_names.contains(name) {
      raise UnexpectedGuard(name)
    }
  }

  let brands : Array[NativeCapabilityBrand] = []
  let bound_natives : Array[NativeRule[T, K]] = []
  for i in 0..<compiled.native_names.length() {
    let name = compiled.native_names[i]
    let brand = NativeCapabilityBrand::{ token: Ref::Ref(()) }
    brands.push(brand)
    let pairs : Array[(RuleName, RuleCapability[T, K])] = []
    for target in compiled.native_dispatch[i] {
      pairs.push(
        (
          compiled.names[target.index],
          RuleCapability::{ brand, slot: target, marker: None },
        ),
      )
    }
    let capabilities = NativeCapabilities::{ pairs, }
    guard natives.get(name) is Some(factory)
    bound_natives.push(factory(capabilities))
  }

  let bound_guards : Array[HostGuard[T, K]] = []
  for name in compiled.guard_names {
    guard guards.get(name) is Some(guard_fn)
    bound_guards.push(guard_fn)
  }
  { grammar: compiled, natives: bound_natives, guards: bound_guards, brands }
}

///|
/// Execute the compiled root against a parser context.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] ExecutableGrammar::parse_root(
  self : Self[T, K],
) -> (@core.ParserContext[T, K]) -> Unit {
  ctx => {
    let stack = RuleCallStack::{ frames: [] }
    run_rule(
      ctx,
      self.grammar,
      self.natives,
      self.guards,
      self.brands,
      stack,
      self.grammar.root,
    )
  }
}

///|
/// Dispatch one opaque capability against the current native's allow-list.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] NativeDispatcher::try_rule(
  self : Self[T, K],
  ctx : @core.ParserContext[T, K],
  capability : RuleCapability[T, K],
) -> Bool {
  ignore(capability.marker)
  if !physical_equal(self.brand.token, capability.brand.token) {
    abort("grammar: native capability belongs to another binding or native")
  }
  let allowed = self.grammar.native_dispatch[self.native_slot.index]
  if !allowed.iter().any(slot => slot == capability.slot) {
    abort("grammar: native capability is not an allowed dispatch target")
  }
  match self.grammar.rules[capability.slot.index] {
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if eval_compiled_pred(alt.starts, token, ctx, self.guards) {
          // The cycle guard consumed nothing, so report the dispatch as
          // unmatched and let the host recover. Answering `true` here would
          // tell the native that a rule it never parsed had succeeded.
          return run_rule_body(
              ctx,
              self.grammar,
              self.natives,
              self.guards,
              self.brands,
              self.stack,
              capability.slot,
              alt.body,
            )
            is Executed
        }
      }
      false
    }
    _ => abort("grammar: native capability target is not a Choice rule")
  }
}

///|
/// Build a parse root by compiling and binding in one setup operation.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] interpret(
  ir : GrammarIr[T, K],
  natives? : Map[RuleName, NativeFactory[T, K]] = Map([]),
  guards? : Map[RuleName, HostGuard[T, K]] = Map([]),
  native_rule_refs? : Map[RuleName, Set[RuleName]] = Map([]),
) -> ((@core.ParserContext[T, K]) -> Unit) raise GrammarBuildError {
  let native_names = Set::from_iter(natives.keys())
  let guard_names = Set::from_iter(guards.keys())
  let compiled = compile(ir, native_names~, guard_names~, native_rule_refs~) catch {
    error => raise GrammarBuildError::Compile(error)
  }
  let executable = bind(compiled, natives~, guards~) catch {
    error => raise GrammarBuildError::Bind(error)
  }
  executable.parse_root()
}

///|
/// Evaluate every compiled predicate variant in parser context.
fn[T : Eq, K] eval_compiled_pred(
  pred : CompiledPred[T],
  token : T,
  ctx : @core.ParserContext[T, K],
  guards : Array[HostGuard[T, K]],
) -> Bool {
  match pred {
    Any => true
    IsToken(expected) => token == expected
    OneOf(tokens) => tokens.iter().any(t => t == token)
    Not(inner) => !eval_compiled_pred(inner, token, ctx, guards)
    All(left, right) =>
      eval_compiled_pred(left, token, ctx, guards) &&
      eval_compiled_pred(right, token, ctx, guards)
    HostGuardSlot(slot) => guards[slot.index](ctx)
  }
}

///|
/// Whether a rule body actually ran, or was stopped by the cycle guard.
///
/// The two outcomes need different recovery, so `run_rule_body` reports the
/// guard instead of choosing a recovery itself: ordinary execution has no caller
/// that can retry and must keep the CST complete with an error placeholder,
/// while native dispatch must report "did not match" and consume nothing so the
/// host's own fallback runs.
priv enum RuleOutcome {
  Executed
  CycleGuarded
}

///|
/// Run one rule body with a parse-local cycle guard.
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] run_rule_body(
  ctx : @core.ParserContext[T, K],
  grammar : CompiledGrammar[T, K],
  natives : Array[NativeRule[T, K]],
  guards : Array[HostGuard[T, K]],
  brands : Array[NativeCapabilityBrand],
  stack : RuleCallStack,
  slot : RuleSlot,
  body : CompiledExpr[T, K],
) -> RuleOutcome {
  let position = ctx.cursor_position()
  if stack.frames
    .iter()
    .any(frame => frame.slot == slot && frame.position == position) {
    ctx.error("grammar: recursive rule re-entered without progress")
    return CycleGuarded
  }
  stack.frames.push(RuleFrame::{ slot, position })
  run_expr(ctx, grammar, natives, guards, brands, stack, body)
  ignore(stack.frames.pop())
  Executed
}

///|
/// Run one complete rule with a parse-local cycle guard.
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] run_rule(
  ctx : @core.ParserContext[T, K],
  grammar : CompiledGrammar[T, K],
  natives : Array[NativeRule[T, K]],
  guards : Array[HostGuard[T, K]],
  brands : Array[NativeCapabilityBrand],
  stack : RuleCallStack,
  slot : RuleSlot,
) -> Unit {
  match
    run_rule_body(
      ctx,
      grammar,
      natives,
      guards,
      brands,
      stack,
      slot,
      grammar.rules[slot.index],
    ) {
    Executed => ()
    CycleGuarded => ctx.emit_error_placeholder()
  }
}

///|
/// Walk one compiled expression using only resolved slots and arrays.
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] run_expr(
  ctx : @core.ParserContext[T, K],
  grammar : CompiledGrammar[T, K],
  natives : Array[NativeRule[T, K]],
  guards : Array[HostGuard[T, K]],
  brands : Array[NativeCapabilityBrand],
  stack : RuleCallStack,
  expr : CompiledExpr[T, K],
) -> Unit {
  match expr {
    Empty => ()
    Emit(token, kind) => if ctx.at(token) { ctx.emit_token(kind) }
    Expect(token, kind) => ctx.expect(token, kind) |> ignore
    Node(kind, body) =>
      ctx.node(kind, () => {
        run_expr(ctx, grammar, natives, guards, brands, stack, body)
      })
    RefSlot(slot) =>
      run_rule(ctx, grammar, natives, guards, brands, stack, slot)
    NativeSlot(slot) => {
      let dispatcher = NativeDispatcher::{
        grammar,
        natives,
        guards,
        brands,
        stack,
        native_slot: slot,
        brand: brands[slot.index],
      }
      natives[slot.index](ctx, dispatcher)
    }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if eval_compiled_pred(alt.starts, token, ctx, guards) {
          run_expr(ctx, grammar, natives, guards, brands, stack, alt.body)
          break
        }
      }
    }
    RepeatTopLevel(slot, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      ctx.consume_while_emit(
        t => eval_compiled_pred(delim, t, ctx, guards),
        delim_kind,
      )
      while !ctx.at_eof() && eval_compiled_pred(starts, ctx.peek(), ctx, guards) {
        if ctx.try_reuse_repeat_group() {
          ctx.consume_while_emit(
            t => eval_compiled_pred(delim, t, ctx, guards),
            delim_kind,
          )
          continue
        }
        let before = ctx.cursor_position()
        run_rule(ctx, grammar, natives, guards, brands, stack, slot)
        if ctx.cursor_position() <= before {
          ctx.error("grammar: RepeatTopLevel body made no progress")
          ctx.emit_error_placeholder()
          break
        }
        let had = eval_compiled_pred(delim, ctx.peek(), ctx, guards)
        ctx.consume_while_emit(
          t => eval_compiled_pred(delim, t, ctx, guards),
          delim_kind,
        )
        if !had && !ctx.at_eof() {
          if eval_compiled_pred(starts, ctx.peek(), ctx, guards) {
            ctx.error(between_msg)
          } else {
            ctx.error(after_msg)
          }
        }
      }
    }
    Seq(exprs) =>
      for expr in exprs {
        run_expr(ctx, grammar, natives, guards, brands, stack, expr)
      }
    PrattApp(slot, kind, starts) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        let before = ctx.cursor_position()
        run_rule(ctx, grammar, natives, guards, brands, stack, slot)
        if ctx.cursor_position() <= before {
          ctx.error("grammar: PrattApp atom made no progress")
          ctx.emit_error_placeholder()
        } else if eval_compiled_pred(starts, ctx.peek(), ctx, guards) {
          ctx.wrap_at(mark, kind, () => {
            while eval_compiled_pred(starts, ctx.peek(), ctx, guards) {
              let before = ctx.cursor_position()
              run_rule(ctx, grammar, natives, guards, brands, stack, slot)
              if ctx.cursor_position() <= before {
                ctx.error("grammar: PrattApp atom made no progress")
                ctx.emit_error_placeholder()
                break
              }
            }
          })
        }
      }
    PrattBinary(slot, kind, ops, skip~) =>
      if ctx.try_reuse_current_node(kind) {
        ()
      } else {
        let mark = ctx.mark()
        run_rule(ctx, grammar, natives, guards, brands, stack, slot)
        let skip_to_op = () => {
          match skip {
            Some((sep, sep_kind)) =>
              ctx.consume_while_emit_if(
                t => eval_compiled_pred(sep, t, ctx, guards),
                sep_kind,
                t => ops.iter().any(pair => pair.0 == t),
              )
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
                  run_rule(ctx, grammar, natives, guards, brands, stack, slot)
                }
              }
            }
          })
        }
      }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && eval_compiled_pred(pred, ctx.peek(), ctx, guards) {
        let before = ctx.cursor_position()
        run_expr(ctx, grammar, natives, guards, brands, stack, body)
        if ctx.cursor_position() <= before {
          ctx.error("grammar: RepeatWhile body made no progress")
          ctx.emit_error_placeholder()
          break
        }
      }
    WrapIfNext(kind, pred, body) => {
      let mark = ctx.mark()
      if eval_compiled_pred(pred, ctx.peek(), ctx, guards) {
        ctx.wrap_at(mark, kind, () => {
          run_expr(ctx, grammar, natives, guards, brands, stack, body)
        })
      } else {
        run_expr(ctx, grammar, natives, guards, brands, stack, body)
      }
    }
    EmitError(msg) => ctx.error(msg)
    ErrorUntil(stop, msg) =>
      if !ctx.at_eof() && !eval_compiled_pred(stop, ctx.peek(), ctx, guards) {
        ctx.error(msg)
        let _ = ctx.skip_until(t => eval_compiled_pred(stop, t, ctx, guards))
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
      if eval_compiled_pred(pred, ctx.peek(), ctx, guards) {
        ctx.error(msg)
      }
    ExpectSkip(skip, skip_kind, expected, kind) => {
      let _ = ctx.expect_after_skip(
        t => eval_compiled_pred(skip, t, ctx, guards),
        skip_kind,
        expected,
        kind,
      )
    }
    ConsumeGated(skip, skip_kind, look) => {
      let _ = ctx.consume_while_emit_if(
        t => eval_compiled_pred(skip, t, ctx, guards),
        skip_kind,
        t => eval_compiled_pred(look, t, ctx, guards),
      )
    }
    RequireSep(delims, stop, alt, msg_alt~, msg_else~) => {
      let had = ctx.consume_while_emit_mapped(delims) > 0
      if !had && !eval_compiled_pred(stop, ctx.peek(), ctx, guards) {
        if eval_compiled_pred(alt, ctx.peek(), ctx, guards) {
          ctx.error(msg_alt)
        } else {
          ctx.error(msg_else)
        }
      }
    }
    ErrorNodeUntil(error_kind, stop, msg) => {
      ctx.error(msg)
      ctx.start_node(error_kind)
      while !ctx.at_eof() && !eval_compiled_pred(stop, ctx.peek(), ctx, guards) {
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
