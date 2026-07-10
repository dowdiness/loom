///|
/// QuickCheck property tests for GrammarIr: multi-rule grammars with Ref,
/// CST equivalence, and a reference interpreter for output validation.

// ─── Test Token Type ──────────────────────────────────────────────────────────

priv enum QcToken {
  A
  B
  C
  Eof
} derive(Eq, Debug)

///|
impl Show for QcToken with fn output(self, logger) {
  logger.write_string(
    match self {
      A => "A"
      B => "B"
      C => "C"
      Eof => "Eof"
    },
  )
}

///|
impl @seam.IsTrivia for QcToken with fn is_trivia(_self) {
  false
}

///|
impl @seam.IsEof for QcToken with fn is_eof(self) {
  self == Eof
}

///|
impl @seam.ToRawKind for QcToken with fn to_raw(self) {
  @seam.RawKind(
    match self {
      A => 0
      B => 1
      C => 2
      Eof => 3
    },
  )
}

///|
impl @coreqc.Arbitrary for QcToken with fn arbitrary(_size, rs) {
  match rs.next_uint() % 4 {
    0 => A
    1 => B
    2 => C
    _ => Eof
  }
}

///|
impl @qc.Shrink for QcToken with fn shrink(self) -> Iter[QcToken] {
  Iter::empty()
}

// ─── Test Kind Type ───────────────────────────────────────────────────────────

///|
priv enum QcKind {
  Root
  NodeA
  NodeB
  Error
} derive(Debug)

///|
impl @seam.ToRawKind for QcKind with fn to_raw(self) {
  @seam.RawKind(
    match self {
      Root => 0
      NodeA => 1
      NodeB => 2
      Error => 3
    },
  )
}

///|
impl @coreqc.Arbitrary for QcKind with fn arbitrary(_size, rs) {
  match rs.next_uint() % 4 {
    0 => Root
    1 => NodeA
    2 => NodeB
    _ => Error
  }
}

///|
impl @qc.Shrink for QcKind with fn shrink(self) -> Iter[QcKind] {
  Iter::empty()
}

// ─── Expression Generator ─────────────────────────────────────────────────────

///|
/// Generate a safe Expr body.  No `Pred::Any` in predicates — only
/// `Pred::IsToken` with explicit tokens.
fn gen_expr(
  size : Int,
  rs : @splitmix.RandomState,
  _rule_names : Array[String],
) -> Expr[QcToken, QcKind] {
  let tk = fn() { QcToken::arbitrary(0, rs) }
  let kn = fn() { QcKind::arbitrary(0, rs) }
  if size <= 0 {
    let branch = (rs.next_uint() % 3).reinterpret_as_int()
    if branch == 0 {
      Expr::Emit(tk(), kn())
    } else if branch == 1 {
      Expr::Expect(tk(), kn())
    } else {
      Expr::Empty
    }
  } else {
    let next = size - 1
    let pick = (rs.next_uint() % 19).reinterpret_as_int()
    if pick == 0 {
      Expr::Node(kn(), gen_expr(next, rs, _rule_names))
    } else if pick == 1 {
      Expr::Emit(tk(), kn())
    } else if pick == 2 {
      Expr::Expect(tk(), kn())
    } else if pick == 3 {
      let n = (rs.next_uint() % 3 + 1).reinterpret_as_int()
      let exprs : Array[Expr[QcToken, QcKind]] = []
      for _i in 0..<n {
        exprs.push(gen_expr(next, rs, _rule_names))
      }
      Expr::Seq(exprs)
    } else if pick == 4 {
      Expr::Empty
    } else if pick == 5 {
      Expr::EmitError("err")
    } else if pick == 6 {
      Expr::Fail("fail")
    } else if pick == 7 {
      Expr::DiagnoseIf(Pred::IsToken(tk()), "diag")
    } else if pick == 8 {
      Expr::RepeatWhile(Pred::IsToken(tk()), gen_expr(next, rs, _rule_names))
    } else if pick == 9 {
      Expr::EmitOr(tk(), kn(), "missing")
    } else if pick == 10 {
      Expr::ErrorUntil(Pred::IsToken(tk()), "err-until")
    } else if pick == 11 {
      Expr::WrapIfNext(
        kn(),
        Pred::IsToken(tk()),
        gen_expr(next, rs, _rule_names),
      )
    } else if pick == 12 {
      Expr::ErrorNodeUntil(kn(), Pred::IsToken(tk()), "err-node")
    } else if pick == 13 {
      let alt1 = Alt::{
        starts: Pred::IsToken(tk()),
        body: gen_expr(next, rs, _rule_names),
      }
      let alt2 = Alt::{
        starts: Pred::IsToken(tk()),
        body: gen_expr(next, rs, _rule_names),
      }
      Expr::Choice([alt1, alt2])
    } else if pick == 14 {
      Expr::ExpectSkip(Pred::IsToken(tk()), kn(), tk(), kn())
    } else if pick == 15 {
      Expr::ConsumeGated(Pred::IsToken(tk()), kn(), Pred::IsToken(tk()))
    } else if pick == 16 {
      let pairs : Array[(QcToken, QcKind)] = [(tk(), kn()), (tk(), kn())]
      Expr::RequireSep(
        pairs,
        Pred::IsToken(tk()),
        Pred::IsToken(tk()),
        msg_alt="sep-alt",
        msg_else="sep-else",
      )
    } else if pick == 17 {
      Expr::ManualNewlineAppExpr
    } else {
      gen_expr(next, rs, _rule_names)
    }
  }
}

// ─── Grammar IR Generator ─────────────────────────────────────────────────────

///|
/// Generate a multi-rule grammar IR.  When `size > 0` and the dice rolls
/// multi-rule, "source" may Ref "expr", which always exists.
impl @coreqc.Arbitrary for GrammarIr[QcToken, QcKind] with fn arbitrary(
  size,
  rs,
) {
  let num_rules = if size <= 0 {
    1
  } else {
    (rs.next_uint() % 2 + 1).reinterpret_as_int()
  }
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  // Peer rule names for rule-referencing nodes (RepeatTopLevel, PrattApp, PrattBinary).
  // Excludes the root name to prevent self-reference loops.
  let source_peers : Array[String] = if num_rules > 1 { ["expr"] } else { [] }
  let source_body = if num_rules > 1 && size > 0 && rs.next_double() < 0.4 {
    Expr::Seq([Expr::Ref("expr"), gen_expr(size, rs, source_peers)])
  } else {
    gen_expr(size, rs, source_peers)
  }
  rules["source"] = source_body
  if num_rules > 1 {
    rules["expr"] = gen_expr(size, rs, ["source"])
  }
  GrammarIr::GrammarIr(rules, root="source")
}

///|
impl @qc.Shrink for GrammarIr[QcToken, QcKind] with fn shrink(self) -> Iter[
  GrammarIr[QcToken, QcKind],
] {
  Iter::empty()
}

// ─── LanguageSpec Builder ─────────────────────────────────────────────────────

///|
fn qc_spec(
  parse_root : (@core.ParserContext[QcToken, QcKind]) -> Unit,
) -> @core.LanguageSpec[QcToken, QcKind] {
  @core.LanguageSpec::new(
    QcKind::Root,
    QcKind::Error,
    QcKind::Root,
    QcToken::Eof,
    incomplete_kind=QcKind::Error,
    parse_root~,
  )
}

// ─── Properties ───────────────────────────────────────────────────────────────

// ─── Reference Interpreter ────────────────────────────────────────────────────

///|
/// Walk an `Expr` directly (no `compile` step) and resolve `Ref(name)` by
/// looking up the grammar rule map.  Mirrors the real `run_expr` behavior but
/// has no incremental reuse, no slot resolution — the CST should be identical.
pub fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] reference_interpret(
  ir : GrammarIr[T, K],
) -> (@core.ParserContext[T, K]) -> Unit {
  fn(ctx) { run_expr_ref(ctx, ir.rules, ir.root) }
}

///|
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] run_expr_ref(
  ctx : @core.ParserContext[T, K],
  rules : Map[RuleName, Expr[T, K]],
  name : RuleName,
) -> Unit {
  match rules.get(name) {
    Some(expr) => run_expr_ref_body(ctx, rules, expr)
    None => {
      ctx.error("reference: missing rule \"" + name + "\"")
      ctx.emit_error_placeholder()
    }
  }
}

///|
fn[
  T : Eq + Show + @seam.IsTrivia + @seam.IsEof + @seam.ToRawKind,
  K : @seam.ToRawKind,
] run_expr_ref_body(
  ctx : @core.ParserContext[T, K],
  rules : Map[RuleName, Expr[T, K]],
  expr : Expr[T, K],
) -> Unit {
  match expr {
    Empty => ()
    Emit(t, k) => if ctx.at(t) { ctx.emit_token(k) }
    Expect(t, k) => {
      let _ = ctx.expect(t, k)
    }
    Node(kind, body) =>
      ctx.node(kind, fn() { run_expr_ref_body(ctx, rules, body) })
    Ref(name) => run_expr_ref(ctx, rules, name)
    Native(_name) => {
      // Native rules are supplied out-of-band and not available in the
      // reference — emit a diagnostic placeholder.
      ctx.error("reference: Native not supported")
      ctx.emit_error_placeholder()
    }
    Seq(exprs) =>
      for e in exprs {
        run_expr_ref_body(ctx, rules, e)
      }
    Choice(alts) => {
      let token = ctx.peek()
      for alt in alts {
        if alt.starts.matches(token) {
          run_expr_ref_body(ctx, rules, alt.body)
          break
        }
      }
    }
    RepeatWhile(pred, body) =>
      while !ctx.at_eof() && pred.matches(ctx.peek()) {
        run_expr_ref_body(ctx, rules, body)
      }
    RepeatTopLevel(name, starts~, delim~, delim_kind~, between_msg~, after_msg~) => {
      ctx.consume_while_emit(t => delim.matches(t), delim_kind)
      while !ctx.at_eof() && starts.matches(ctx.peek()) {
        run_expr_ref(ctx, rules, name)
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
    PrattApp(name, kind, starts) => {
      let mark = ctx.mark()
      run_expr_ref(ctx, rules, name)
      if starts.matches(ctx.peek()) {
        ctx.wrap_at(mark, kind, fn() {
          while starts.matches(ctx.peek()) {
            run_expr_ref(ctx, rules, name)
          }
        })
      }
    }
    PrattBinary(name, kind, ops, skip~) => {
      let mark = ctx.mark()
      run_expr_ref(ctx, rules, name)
      let skip_to_op = fn() {
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
        ctx.wrap_at(mark, kind, fn() {
          while true {
            skip_to_op()
            match ops.iter().find_first(pair => pair.0 == ctx.peek()) {
              None => break
              Some(pair) => {
                ctx.emit_token(pair.1)
                run_expr_ref(ctx, rules, name)
              }
            }
          }
        })
      }
    }
    WrapIfNext(kind, pred, body) => {
      let mark = ctx.mark()
      if pred.matches(ctx.peek()) {
        ctx.wrap_at(mark, kind, fn() { run_expr_ref_body(ctx, rules, body) })
      } else {
        run_expr_ref_body(ctx, rules, body)
      }
    }
    EmitError(msg) => ctx.error(msg)
    ErrorUntil(stop, msg) =>
      if !stop.matches(ctx.peek()) {
        ctx.error(msg)
        let _ = ctx.skip_until(t => stop.matches(t))
      }
    Fail(msg) => {
      ctx.error(msg)
      ctx.emit_error_placeholder()
    }
    EmitOr(t, k, msg) =>
      if ctx.at(t) {
        ctx.emit_token(k)
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
        "grammar: ManualNewlineAppExpr is a residue — interpret with a language-specific probe",
      )
      ctx.emit_error_placeholder()
    }
  }
}

///|
/// Property: compiling any grammar IR never crashes (compile errors are
/// accepted — the generator may produce broken grammars).
fn prop_compile_well_formed(ir : GrammarIr[QcToken, QcKind]) -> Bool {
  try {
    let _ = compile(ir)
    true
  } catch {
    _ => true
  }
}

///|
/// Property: interpreting a grammar IR on an empty token stream never crashes
/// (compile errors are accepted).
fn prop_interpret_no_crash(ir : GrammarIr[QcToken, QcKind]) -> Bool {
  let parse_root = interpret(ir) catch { _ => return true }
  let spec = qc_spec(parse_root)
  let tokens = [@core.TokenInfo::new(QcToken::Eof, 0)]
  let ctx = @core.ParserContext::new(tokens, "", spec)
  parse_root(ctx)
  true
}

///|
/// Property: `interpret(ir)` and `interpret_compiled(compile(ir))` produce
/// structurally equal CSTs for any grammar with a fixed token stream.
fn prop_cst_equivalence(ir : GrammarIr[QcToken, QcKind]) -> @qc.Property {
  let tokens = [
    @core.TokenInfo::new(QcToken::A, 1),
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  // First parse: via interpret
  let parse_root = interpret(ir) catch { _ => return @qc.property(true) }
  let spec = qc_spec(parse_root)
  let (tree1, _diags1) = @core.parse_with(
    "ab",
    spec,
    fn(_src) { tokens },
    parse_root,
  )
  // Second parse: via interpret_compiled(compile(ir))
  let compiled = compile(ir) catch { _ => return @qc.property(true) }
  let parse_root2 = interpret_compiled(compiled)
  let spec2 = qc_spec(parse_root2)
  let (tree2, _diags2) = @core.parse_with(
    "ab",
    spec2,
    fn(_src) { tokens },
    parse_root2,
  )
  // Trees must be structurally equal
  let diffs = @core.tree_diff(tree1, tree2)
  @qc.counterexample(
    diffs.length() == 0,
    "ir = \{@debug.to_string(ir)}\n  interpret vs interpret_compiled diffs = \{@debug.to_string(diffs)}",
  )
}

///|
/// Property: the reference interpreter (Expr-direct walk) and the real
/// interpreter (compile + interpret_compiled) produce structurally equal
/// CSTs for any grammar with a fixed token stream.
fn prop_reference_matches(ir : GrammarIr[QcToken, QcKind]) -> @qc.Property {
  let tokens = [
    @core.TokenInfo::new(QcToken::A, 1),
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  // Reference parse
  let ref_parse = reference_interpret(ir)
  let ref_spec = qc_spec(ref_parse)
  let (ref_tree, _ref_diags) = @core.parse_with(
    "ab",
    ref_spec,
    fn(_src) { tokens },
    ref_parse,
  )
  // Real parse
  let real_parse = interpret(ir) catch { _ => return @qc.property(true) }
  let real_spec = qc_spec(real_parse)
  let (real_tree, _real_diags) = @core.parse_with(
    "ab",
    real_spec,
    fn(_src) { tokens },
    real_parse,
  )
  // Trees must be structurally equal
  let diffs = @core.tree_diff(ref_tree, real_tree)
  @qc.counterexample(
    diffs.length() == 0,
    "ir = \{@debug.to_string(ir)}\n  reference vs interpret diffs = \{@debug.to_string(diffs)}",
  )
}

// ─── Test Blocks ──────────────────────────────────────────────────────────────

///|
test "property: compiling any grammar IR never crashes" {
  @qc.quick_check_fn(prop_compile_well_formed, max_success=25, max_size=4)
}

///|
test "property: interpreting grammar IR on empty context never crashes" {
  @qc.quick_check_fn(prop_interpret_no_crash, max_success=15, max_size=3)
}

///|
test "property: interpret matches interpret_compiled(compile(ir)) CST" {
  @qc.quick_check_fn(prop_cst_equivalence, max_success=15, max_size=3)
}

///|
test "property: reference interpreter matches real interpreter CST" {
  @qc.quick_check_fn(prop_reference_matches, max_success=25, max_size=3)
}
