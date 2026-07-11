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

// ─── Token Stream Helpers ─────────────────────────────────────────────────────

///|
/// Generate a non-EOF content token.
fn gen_content_token(rs : @splitmix.RandomState) -> QcToken {
  match rs.next_uint() % 3 {
    0 => A
    1 => B
    _ => C
  }
}

///|
/// Generate an array of TokenInfo from a list of content tokens plus an EOF
/// sentinel.  `content_tok` is guaranteed to appear at least once (as the
/// first element) so that `RepeatTopLevel("expr", starts=IsToken(t), …)` has
/// a token to match.
fn gen_tokens(
  num_content : Int,
  rs : @splitmix.RandomState,
  content_tok : QcToken,
) -> Array[@core.TokenInfo[QcToken]] {
  let tokens : Array[@core.TokenInfo[QcToken]] = []
  tokens.push(@core.TokenInfo::new(content_tok, 1))
  for _i in 1..<num_content {
    // 50% chance of consumer_tok, so RepeatTopLevel/PrattApp loops
    // have a realistic chance of multiple iterations.
    let t = if rs.next_double() < 0.5 {
      content_tok
    } else {
      gen_content_token(rs)
    }
    tokens.push(@core.TokenInfo::new(t, 1))
  }
  tokens.push(@core.TokenInfo::new(QcToken::Eof, 0))
  tokens
}

// ─── Expression Generator ─────────────────────────────────────────────────────

///|
/// Generate a safe Expr body (single-rule mode: no Ref/RepeatTopLevel/
/// PrattApp/PrattBinary — just the core variants).
fn gen_expr(size : Int, rs : @splitmix.RandomState) -> Expr[QcToken, QcKind] {
  gen_expr_impl(size, rs, [], A, QcKind::Root)
}

///|
/// Internal: full-signature generator with multi-rule support.  See
/// `GrammarWithTokens::arbitrary` for the coordinating caller.
///
/// When `rule_names` has >=2 entries, also produces `Ref`, `RepeatTopLevel`,
/// `PrattApp`, and `PrattBinary` that reference `rule_names[1]` (the "atom"
/// rule, e.g. `"expr"`).  `consumer_tok` and `consumer_knd` specify the
/// token/kind that the atom rule body will emit, so these constructs'
/// predicates can safely reference a token that the body will consume
/// (guaranteeing loop termination).
fn gen_expr_impl(
  size : Int,
  rs : @splitmix.RandomState,
  rule_names : Array[String],
  consumer_tok : QcToken,
  consumer_knd : QcKind,
) -> Expr[QcToken, QcKind] {
  // `rule_names[1]` (not [0]) is the atom rule because the caller passes
  // `["source", "expr"]` — see GrammarWithTokens::arbitrary.
  let has_rules = rule_names.length() >= 2
  let atom_name = if has_rules { rule_names[1] } else { "" }
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
    let num_arms = if has_rules { 21 } else { 18 }
    let pick = (rs.next_uint() % num_arms.reinterpret_as_uint()).reinterpret_as_int()
    if pick == 0 {
      Expr::Node(
        kn(),
        gen_expr_impl(next, rs, rule_names, consumer_tok, consumer_knd),
      )
    } else if pick == 1 {
      Expr::Emit(tk(), kn())
    } else if pick == 2 {
      Expr::Expect(tk(), kn())
    } else if pick == 3 {
      let n = (rs.next_uint() % 3 + 1).reinterpret_as_int()
      let exprs : Array[Expr[QcToken, QcKind]] = []
      for _i in 0..<n {
        exprs.push(
          gen_expr_impl(next, rs, rule_names, consumer_tok, consumer_knd),
        )
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
      Expr::EmitOr(tk(), kn(), "missing")
    } else if pick == 9 {
      Expr::ErrorUntil(Pred::IsToken(tk()), "err-until")
    } else if pick == 10 {
      Expr::WrapIfNext(
        kn(),
        Pred::IsToken(tk()),
        gen_expr_impl(next, rs, rule_names, consumer_tok, consumer_knd),
      )
    } else if pick == 11 {
      Expr::ErrorNodeUntil(kn(), Pred::IsToken(tk()), "err-node")
    } else if pick == 12 {
      let alt1 = Alt::{
        starts: Pred::IsToken(tk()),
        body: gen_expr_impl(next, rs, rule_names, consumer_tok, consumer_knd),
      }
      let alt2 = Alt::{
        starts: Pred::IsToken(tk()),
        body: gen_expr_impl(next, rs, rule_names, consumer_tok, consumer_knd),
      }
      Expr::Choice([alt1, alt2])
    } else if pick == 13 {
      Expr::ExpectSkip(Pred::IsToken(tk()), kn(), tk(), kn())
    } else if pick == 14 {
      Expr::ConsumeGated(Pred::IsToken(tk()), kn(), Pred::IsToken(tk()))
    } else if pick == 15 {
      let pairs : Array[(QcToken, QcKind)] = [(tk(), kn()), (tk(), kn())]
      Expr::RequireSep(
        pairs,
        Pred::IsToken(tk()),
        Pred::IsToken(tk()),
        msg_alt="sep-alt",
        msg_else="sep-else",
      )
    } else if pick == 16 {
      Expr::ManualNewlineAppExpr
    } else if pick == 17 && has_rules {
      Expr::Ref(atom_name)
    } else if pick == 18 && has_rules {
      let delim_tok = tk()
      Expr::RepeatTopLevel(
        atom_name,
        starts=Pred::IsToken(consumer_tok),
        delim=Pred::IsToken(delim_tok),
        delim_kind=kn(),
        between_msg="btwn",
        after_msg="after",
      )
    } else if pick == 19 && has_rules {
      Expr::PrattApp(atom_name, kn(), Pred::IsToken(consumer_tok))
    } else if pick == 20 && has_rules {
      let skip = if rs.next_double() < 0.3 {
        Some((Pred::IsToken(tk()), kn()))
      } else {
        None
      }
      Expr::PrattBinary(atom_name, kn(), [(consumer_tok, kn())], skip~)
    } else {
      gen_expr_impl(next, rs, rule_names, consumer_tok, consumer_knd)
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
  let source_body = if num_rules > 1 && size > 0 && rs.next_double() < 0.4 {
    Expr::Seq([Expr::Ref("expr"), gen_expr(size, rs)])
  } else {
    gen_expr(size, rs)
  }
  rules["source"] = source_body
  if num_rules > 1 {
    rules["expr"] = gen_expr(size, rs)
  }
  GrammarIr::GrammarIr(rules, root="source")
}

///|
impl @qc.Shrink for GrammarIr[QcToken, QcKind] with fn shrink(self) -> Iter[
  GrammarIr[QcToken, QcKind],
] {
  Iter::empty()
}

// ─── GrammarWithTokens (wraps grammar + compatible token stream) ─────────────

///|
/// A grammar IR paired with a token stream that aligns with the grammar's
/// predicates.  The atom rule (`"expr"`) is always `Emit(consumer_tok,
/// consumer_knd)`, so `RepeatTopLevel`/`PrattApp`/`PrattBinary` nodes have a
/// matching token to consume and do not loop infinitely.
struct GrammarWithTokens {
  ir : GrammarIr[QcToken, QcKind]
  tokens : Array[@core.TokenInfo[QcToken]]
} derive(Debug)

///|
impl @coreqc.Arbitrary for GrammarWithTokens with fn arbitrary(size, rs) {
  // Pick the content token that the atom rule will emit.
  // This is the token that RepeatTopLevel/PrattApp/PrattBinary predicates
  // will check for, guaranteeing loop termination.
  let consumer_tok = gen_content_token(rs)
  let consumer_knd = QcKind::arbitrary(0, rs)

  let num_rules = if size <= 0 {
    1
  } else {
    (rs.next_uint() % 2 + 1).reinterpret_as_int()
  }
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  let rule_names : Array[String] = if num_rules > 1 {
    // The atom rule body MUST consume consumer_tok so that
    // RepeatTopLevel/PrattApp loops terminate.
    rules["expr"] = Expr::Emit(consumer_tok, consumer_knd)
    ["source", "expr"]
  } else {
    []
  }

  let source_body = gen_expr_impl(
    size, rs, rule_names, consumer_tok, consumer_knd,
  )
  rules["source"] = source_body

  // Build the token stream. Include consumer_tok first so that
  // RepeatTopLevel/PrattApp have something to match.
  let num_content = if size <= 0 {
    2
  } else {
    (rs.next_uint() % 2 + 2).reinterpret_as_int()
  }
  let tokens = gen_tokens(num_content, rs, consumer_tok)

  GrammarWithTokens::{ ir: GrammarIr::GrammarIr(rules, root="source"), tokens }
}

///|
/// Shrink a GrammarWithTokens by shortening the token stream.
/// The grammar stays identical — only the input is reduced, making
/// counterexamples simpler without changing the structure that caused
/// the failure.
impl @qc.Shrink for GrammarWithTokens with fn shrink(self) -> Iter[
  GrammarWithTokens,
] {
  let tlen = self.tokens.length()
  if tlen <= 2 {
    Iter::empty()
  } else {
    // Build a candidate: remove the last content token (index tlen-2)
    let shorter : Array[@core.TokenInfo[QcToken]] = []
    let limit = tlen - 2
    for i in 0..<limit {
      shorter.push(self.tokens[i])
    }
    shorter.push(self.tokens[tlen - 1]) // preserve EOF
    [GrammarWithTokens::{ ir: self.ir, tokens: shorter }].iter()
  }
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

// ─── Plain GrammarIr Properties (fixed token stream [A, B, Eof]) ──────────────

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

// ─── GrammarWithTokens Properties (random token stream) ───────────────────────

///|
/// Property: interpreting a GrammarWithTokens on its random token stream
/// never crashes (compile errors accepted).
fn prop_interpret_no_crash_tokens(gwt : GrammarWithTokens) -> Bool {
  let parse_root = interpret(gwt.ir) catch { _ => return true }
  let spec = qc_spec(parse_root)
  let ctx = @core.ParserContext::new(gwt.tokens, "", spec)
  parse_root(ctx)
  true
}

///|
/// Property: the reference interpreter matches the real interpreter on the
/// random token stream.
fn prop_reference_matches_tokens(gwt : GrammarWithTokens) -> @qc.Property {
  let tokens = gwt.tokens
  let ir = gwt.ir
  // Reference parse
  let ref_parse = reference_interpret(ir)
  let ref_spec = qc_spec(ref_parse)
  let (ref_tree, _ref_diags) = @core.parse_with(
    "src",
    ref_spec,
    fn(_src) { tokens },
    ref_parse,
  )
  // Real parse
  let real_parse = interpret(ir) catch { _ => return @qc.property(true) }
  let real_spec = qc_spec(real_parse)
  let (real_tree, _real_diags) = @core.parse_with(
    "src",
    real_spec,
    fn(_src) { tokens },
    real_parse,
  )
  // Trees must be structurally equal
  let diffs = @core.tree_diff(ref_tree, real_tree)
  @qc.counterexample(
    diffs.length() == 0,
    "ir = \{@debug.to_string(ir)}\n  tokens = \{@debug.to_string(tokens)}\n  reference vs interpret diffs = \{@debug.to_string(diffs)}",
  )
}

///|
/// Property: `interpret(ir)` and `interpret_compiled(compile(ir))` produce
/// structurally equal CSTs for a GrammarWithTokens on its random stream.
fn prop_cst_equivalence_tokens(gwt : GrammarWithTokens) -> @qc.Property {
  let tokens = gwt.tokens
  let ir = gwt.ir
  // First parse: via interpret
  let parse_root = interpret(ir) catch { _ => return @qc.property(true) }
  let spec = qc_spec(parse_root)
  let (tree1, _diags1) = @core.parse_with(
    "src",
    spec,
    fn(_src) { tokens },
    parse_root,
  )
  // Second parse: via interpret_compiled(compile(ir))
  let compiled = compile(ir) catch { _ => return @qc.property(true) }
  let parse_root2 = interpret_compiled(compiled)
  let spec2 = qc_spec(parse_root2)
  let (tree2, _diags2) = @core.parse_with(
    "src",
    spec2,
    fn(_src) { tokens },
    parse_root2,
  )
  // Trees must be structurally equal
  let diffs = @core.tree_diff(tree1, tree2)
  @qc.counterexample(
    diffs.length() == 0,
    "ir = \{@debug.to_string(ir)}\n  tokens = \{@debug.to_string(tokens)}\n  interpret vs interpret_compiled diffs = \{@debug.to_string(diffs)}",
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

///|
test "property: GrammarWithTokens no-crash on random token stream" {
  @qc.quick_check_fn(prop_interpret_no_crash_tokens, max_success=15, max_size=4)
}

///|
test "property: GrammarWithTokens reference matches real on random stream" {
  @qc.quick_check_fn(prop_reference_matches_tokens, max_success=25, max_size=4)
}

///|
test "property: GrammarWithTokens interpret matches interpret_compiled on random stream" {
  @qc.quick_check_fn(prop_cst_equivalence_tokens, max_success=15, max_size=4)
}

///|
/// Safe wrapper: interpret or return None on compile error.
fn try_interpret(
  ir : GrammarIr[QcToken, QcKind],
) -> ((@core.ParserContext[QcToken, QcKind]) -> Unit)? {
  Some(interpret(ir)) catch {
    _ => None
  }
}

///|
/// Helper: verify reference and real interpreters produce identical CSTs
/// for a given grammar + token stream.
fn check_equiv(
  ir : GrammarIr[QcToken, QcKind],
  tokens : Array[@core.TokenInfo[QcToken]],
  label : String,
) -> Unit raise Failure {
  let ref_parse = reference_interpret(ir)
  let (ref_tree, _) = @core.parse_with(
    "src",
    qc_spec(ref_parse),
    fn(_) { tokens },
    ref_parse,
  )
  let real_parse = try_interpret(ir)
  let real_parse = match real_parse {
    Some(f) => f
    None => fail(label + ": interpret failed")
  }
  let (real_tree, _) = @core.parse_with(
    "src",
    qc_spec(real_parse),
    fn(_) { tokens },
    real_parse,
  )
  let diffs = @core.tree_diff(ref_tree, real_tree)
  if diffs.length() != 0 {
    fail(label + ": trees differ: \{@debug.to_string(diffs)}")
  }
}

///|
test "deterministic: Ref dispatches to sub-rule" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::B, QcKind::NodeA)
  rules["source"] = Expr::Seq([
    Expr::Ref("expr"),
    Expr::Emit(QcToken::C, QcKind::NodeB),
  ])
  let ir = GrammarIr::GrammarIr(rules, root="source")
  let tokens = [
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::C, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  check_equiv(ir, tokens, "Ref")
}

///|
test "deterministic: RepeatTopLevel loops over matching items" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::B, QcKind::NodeA)
  rules["source"] = Expr::RepeatTopLevel(
    "expr",
    starts=Pred::IsToken(QcToken::B),
    delim=Pred::IsToken(QcToken::C),
    delim_kind=QcKind::NodeB,
    between_msg="btwn",
    after_msg="after",
  )
  let ir = GrammarIr::GrammarIr(rules, root="source")
  // Leading delim + 2 items + trailing delim (consumed on next loop check, no next item)
  let tokens = [
    @core.TokenInfo::new(QcToken::C, 1),
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  check_equiv(ir, tokens, "RepeatTopLevel")
}

///|
test "deterministic: PrattApp wraps run in app kind" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::B, QcKind::NodeA)
  rules["source"] = Expr::PrattApp(
    "expr",
    QcKind::NodeB,
    Pred::IsToken(QcToken::B),
  )
  let ir = GrammarIr::GrammarIr(rules, root="source")
  // Two Bs — wrapping fires after first atom, loop runs second atom
  let tokens = [
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  check_equiv(ir, tokens, "PrattApp")
}

///|
test "deterministic: PrattBinary parses infix with operator" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::C, QcKind::NodeA)
  rules["source"] = Expr::PrattBinary(
    "expr",
    QcKind::NodeB,
    [(QcToken::B, QcKind::NodeB)],
    skip=None,
  )
  let ir = GrammarIr::GrammarIr(rules, root="source")
  // Atom C, operator B, atom C
  let tokens = [
    @core.TokenInfo::new(QcToken::C, 1),
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::C, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  check_equiv(ir, tokens, "PrattBinary")
}

///|
test "deterministic: RepeatTopLevel on empty stream skips loop" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::B, QcKind::NodeA)
  rules["source"] = Expr::RepeatTopLevel(
    "expr",
    starts=Pred::IsToken(QcToken::B),
    delim=Pred::IsToken(QcToken::C),
    delim_kind=QcKind::NodeB,
    between_msg="btwn",
    after_msg="after",
  )
  let ir = GrammarIr::GrammarIr(rules, root="source")
  // Only EOF — no starts match, loop body never runs
  let tokens = [@core.TokenInfo::new(QcToken::Eof, 0)]
  check_equiv(ir, tokens, "RepeatTopLevel-empty")
}

///|
test "deterministic: PrattApp with non-matching second token skips wrap" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::B, QcKind::NodeA)
  rules["source"] = Expr::PrattApp(
    "expr",
    QcKind::NodeB,
    Pred::IsToken(QcToken::B),
  )
  let ir = GrammarIr::GrammarIr(rules, root="source")
  // First token B matches Emit, second token C ≠ starts — no wrapping
  let tokens = [
    @core.TokenInfo::new(QcToken::B, 1),
    @core.TokenInfo::new(QcToken::C, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  check_equiv(ir, tokens, "PrattApp-no-wrap")
}

///|
test "deterministic: PrattBinary with no operator exits immediately" {
  let rules : Map[RuleName, Expr[QcToken, QcKind]] = Map([])
  rules["expr"] = Expr::Emit(QcToken::C, QcKind::NodeA)
  rules["source"] = Expr::PrattBinary(
    "expr",
    QcKind::NodeB,
    [(QcToken::B, QcKind::NodeB)],
    skip=None,
  )
  let ir = GrammarIr::GrammarIr(rules, root="source")
  // Just atom C — no B operator follows, no wrapping
  let tokens = [
    @core.TokenInfo::new(QcToken::C, 1),
    @core.TokenInfo::new(QcToken::Eof, 0),
  ]
  check_equiv(ir, tokens, "PrattBinary-no-op")
}
