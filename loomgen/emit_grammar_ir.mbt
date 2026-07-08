///|
/// Emit `grammar_ir.g.mbt` — a `@grammar.GrammarIr` value built from `#loom.rule`
/// annotations on `#loom.term` variants (#522).
///
/// Each rule string is parsed (`parse_rule_string`), its identifiers resolved
/// against the token enum (terminal) or term enum (rule `Ref`), and lowered to a
/// `@grammar.Expr`. The `#loom.node`/`#loom.root`/`#loom.leaf` role wraps the
/// production body in `Node(kind, body)`. Alternation and repetition need FIRST
/// sets, computed here from the rule map; the emitter fails closed on any
/// out-of-subset construct (unknown symbol, left recursion, unresolvable Ref).

///|
suberror RuleLowerError {
  RuleLowerError(String)
}

///|
/// Resolution + emission context shared across the lowering recursion.
struct LowerCtx {
  /// Token variant name -> its CST leaf kind name (membership = "is a terminal").
  token_kinds : Map[String, String]
  /// Term variant name -> its CST node kind name (from #loom.node/root/leaf).
  term_kind_names : Map[String, String]
  /// Token variant names in declaration order — gives deterministic FIRST-set
  /// emission order (`OneOf([...])`).
  token_order : Array[String]
  /// Parsed rule bodies by rule (term-variant) name, for `Ref` resolution.
  rules : Map[String, RuleAst]
  /// All term-variant names — lets a `Ref` to a ruleless term (e.g. a `#loom.leaf`
  /// with no `#loom.rule`) fail closed with a precise message instead of being
  /// reported as an unknown symbol.
  term_names : @hashset.HashSet[String]
  /// Rule (term-variant) name -> its 1-based line in the `.loomgrammar` file, for
  /// productions supplied by a grammar file (#523). Empty in annotation-only mode,
  /// so `loc` returns "" and every emission diagnostic is byte-identical to the
  /// annotation path. Lets file-mode emission errors carry the same `line N:`
  /// prefix the file's parse errors do.
  file_lines : Map[String, Int]
  token_qual : String
  syntax_qual : String
  grammar_qual : String
}

///|
/// `"line N: "` for a file-supplied rule, or "" for an annotation rule (or any
/// name absent from a grammar file). Shared by every emission-stage diagnostic so
/// a `.loomgrammar` user gets file positions on fragment/role/left-recursion/
/// lowering errors, not just on parse errors.
fn LowerCtx::loc(self : LowerCtx, name : String) -> String {
  match self.file_lines.get(name) {
    Some(line) => "line " + line.to_string() + ": "
    None => ""
  }
}

///|
/// Wrap a rule/token name (always a MoonBit identifier) as a string literal for
/// emission into the generated `Map` keys, `Ref`, and `root=`.
fn quote(s : String) -> String {
  "\"" + s + "\""
}

///|
/// Join a qualifier and name, omitting the dot when qualifier is empty.
/// Used so `--token-qual "" --syntax-qual ""` produces bare type/constructor
/// names for packages that define Token/SyntaxKind in the same compilation unit.
fn qualify(qual : String, name : String) -> String {
  if qual.length() > 0 {
    qual + "." + name
  } else {
    name
  }
}

///|
/// What a symbol in a rule string resolves to. Every walker (`nullable`,
/// `first_set`, `leading_refs`, `lower`) classifies a `Sym` the same way; routing
/// them through one `resolve_sym` keeps that classification — and its diagnostics
/// — defined in exactly one place.
enum SymKind {
  Terminal(String) // a #loom.token variant; carries its CST leaf kind name
  Rule(RuleAst) // a #loom.term variant with a #loom.rule body
  RulelessTerm // a #loom.term variant with no #loom.rule
  Unknown // neither a token nor a term
}

///|
/// Classify a symbol name against the token enum (terminal), the rule map (`Ref`),
/// and the term-name set (ruleless term), falling back to `Unknown`.
fn resolve_sym(name : String, ctx : LowerCtx) -> SymKind {
  match ctx.token_kinds.get(name) {
    Some(kind) => Terminal(kind)
    None =>
      match ctx.rules.get(name) {
        Some(body) => Rule(body)
        None =>
          if ctx.term_names.contains(name) {
            RulelessTerm
          } else {
            Unknown
          }
      }
  }
}

///|
/// Diagnostic for a `Ref` to a term that carries no `#loom.rule`. One definition
/// shared by `first_set` and `lower` so the wording cannot drift between passes.
fn ruleless_term_msg(name : String) -> String {
  "term '" +
  name +
  "' is referenced but has no grammar rule (via #loom.rule or the grammar file) — a referenced #loom.leaf/#loom.node must carry a single rule to derive its body and FIRST set"
}

///|
/// Diagnostic for a symbol that is neither a token nor a term.
fn unknown_symbol_msg(name : String) -> String {
  "unknown symbol '" +
  name +
  "' — it is neither a #loom.token variant nor a #loom.term rule"
}

///|
/// Diagnostic for a left-recursive rule. Shared by `first_set` (demand-driven,
/// inside a Choice/Repeat) and `check_left_recursion` (eager) so one defect has
/// one wording.
fn left_rec_msg(name : String) -> String {
  "left-recursive rule '" +
  name +
  "' — the #loom.rule subset requires non-left-recursive productions; rewrite the recursion (e.g. into a repetition) so its FIRST set is well-defined"
}

///|
/// The prefix of `items` that sits in leading (FIRST) position: every element up
/// to and including the first non-nullable one. Shared by `first_set` and
/// `leading_refs` so the through-nullable-prefix logic lives in one place and the
/// two analyses cannot drift (a drift would silently reopen the left-recursion
/// gap, since `leading_refs` feeds the sole Seq/Node-position left-rec guard).
fn seq_leading(items : Array[RuleAst], ctx : LowerCtx) -> Array[RuleAst] {
  let acc : Array[RuleAst] = []
  for it in items {
    acc.push(it)
    if !nullable(it, ctx, @hashset.HashSet([])) {
      break
    }
  }
  acc
}

///|
/// Whether `ast` can derive the empty string. Drives FIRST-set computation
/// through nullable prefixes. A terminal and a fragment are never nullable; a
/// `Ref` is nullable iff its rule body is. Revisiting a rule (a nullable cycle)
/// returns `false` conservatively — `first_set` raises the real left-recursion
/// error.
fn nullable(
  ast : RuleAst,
  ctx : LowerCtx,
  visiting : @hashset.HashSet[String],
) -> Bool {
  match ast {
    Sym(name) =>
      match resolve_sym(name, ctx) {
        Rule(body) =>
          if visiting.contains(name) {
            false
          } else {
            visiting.add(name)
            let r = nullable(body, ctx, visiting)
            visiting.remove(name)
            r
          }
        Terminal(_) | RulelessTerm | Unknown => false
      }
    Frag(_) => false
    Seq(items) => items.iter().all(it => nullable(it, ctx, visiting))
    Alt(branches) => branches.iter().any(b => nullable(b, ctx, visiting))
    Star(_) | Opt(_) => true
    Plus(inner) => nullable(inner, ctx, visiting)
    Emit(inner) | Emitor(inner) => nullable(inner, ctx, visiting)
    ErrorUntil(_) => false
    PrattApp(_) | PrattBinary(_) => false
  }
}

///|
/// FIRST set of `ast` — the token names that can begin it. Unions left-to-right
/// through nullable prefixes of a `Seq`, stopping at the first non-nullable
/// element. `visiting` detects a left-recursive `Ref` cycle and fails closed.
/// `Frag` references return an empty set — fragments are opaque at emit time,
/// so they cannot gate a `Choice` or `RepeatWhile`; placing a fragment in a
/// gating position triggers the empty-FIRST-set error in `first_names_ordered`.
fn first_set(
  ast : RuleAst,
  ctx : LowerCtx,
  visiting : @hashset.HashSet[String],
) -> @hashset.HashSet[String] raise RuleLowerError {
  match ast {
    Sym(name) =>
      match resolve_sym(name, ctx) {
        Terminal(_) => @hashset.HashSet([name])
        Rule(body) =>
          if visiting.contains(name) {
            raise RuleLowerError(left_rec_msg(name))
          } else {
            visiting.add(name)
            let r = first_set(body, ctx, visiting)
            visiting.remove(name)
            r
          }
        RulelessTerm => raise RuleLowerError(ruleless_term_msg(name))
        Unknown => raise RuleLowerError(unknown_symbol_msg(name))
      }
    Frag(_) => @hashset.HashSet([])
    Seq(items) => {
      let leading = seq_leading(items, ctx)
      // A fragment in a leading (FIRST) position makes the Seq's FIRST set
      // unsound: the fragment's actual body is opaque at emit time and may
      // contribute tokens this pass cannot see. Fail closed rather than emit
      // a predicate that gated on the visible prefix and excluded the fragment's
      // actual FIRST tokens. Trailing fragments (after `leading` ends) are fine.
      for it in leading {
        if it is Frag(_) {
          raise RuleLowerError(
            "@fragment reference in a FIRST-requiring position (e.g. inside a nullable prefix) — the fragment's body is opaque at emit time, so its FIRST set is unknown; restructure to place the fragment in trailing (non-FIRST) position",
          )
        }
      }
      let acc : @hashset.HashSet[String] = @hashset.HashSet([])
      for it in leading {
        for n in first_set(it, ctx, visiting) {
          acc.add(n)
        }
      }
      acc
    }
    Alt(branches) => {
      let acc : @hashset.HashSet[String] = @hashset.HashSet([])
      for b in branches {
        for n in first_set(b, ctx, visiting) {
          acc.add(n)
        }
      }
      acc
    }
    Star(inner) | Plus(inner) | Opt(inner) => first_set(inner, ctx, visiting)
    Emit(inner) | Emitor(inner) => first_set(inner, ctx, visiting)
    ErrorUntil(_) => @hashset.HashSet([])
    PrattApp(spec) => first_set(Sym(spec.prefix), ctx, visiting)
    PrattBinary(spec) => first_set(Sym(spec.prefix), ctx, visiting)
  }
}

///|
/// FIRST set of `ast` as token names in token-declaration order (deterministic
/// emission). Raises if the set is empty (a nullable construct has no FIRST and
/// cannot gate a `Choice`/`RepeatWhile`).
fn first_names_ordered(
  ast : RuleAst,
  ctx : LowerCtx,
  where_ : String,
) -> Array[String] raise RuleLowerError {
  let set = first_set(ast, ctx, @hashset.HashSet([]))
  let ordered = [ for name in ctx.token_order if set.contains(name) => name ]
  guard ordered.length() > 0 else {
    raise RuleLowerError(
      where_ +
      " has an empty FIRST set (a nullable body cannot gate an alternation or repetition)",
    )
  }
  ordered
}

///|
/// Rule names in leading (FIRST) position of `ast`, looking through nullable
/// prefixes. Tokens and fragments are opaque leaves (a fragment contributes no
/// visible leading ref). Drives the build-time left-recursion check, which must
/// fire even when a left-recursive rule never sits inside a `Choice`/`Repeat`
/// (so `first_set` is never consulted on it). Unlike `first_set`, this never
/// raises — it only collects graph edges.
fn leading_refs(ast : RuleAst, ctx : LowerCtx) -> Array[String] {
  match ast {
    Sym(name) =>
      match resolve_sym(name, ctx) {
        Terminal(_) => []
        Rule(_) | RulelessTerm | Unknown => [name]
      }
    Frag(_) => []
    Seq(items) => {
      let acc : Array[String] = []
      for it in seq_leading(items, ctx) {
        for r in leading_refs(it, ctx) {
          acc.push(r)
        }
      }
      acc
    }
    Alt(branches) => {
      let acc : Array[String] = []
      for b in branches {
        for r in leading_refs(b, ctx) {
          acc.push(r)
        }
      }
      acc
    }
    Star(inner) | Plus(inner) | Opt(inner) => leading_refs(inner, ctx)
    Emit(inner) | Emitor(inner) => leading_refs(inner, ctx)
    ErrorUntil(_) => []
    PrattApp(spec) => [spec.prefix]
    PrattBinary(spec) => [spec.prefix]
  }
}

///|
/// DFS for a cycle in the leading-reference graph. `state` maps a rule to 0/1/2
/// (unvisited / on the current stack / done); a back-edge to a stacked rule is a
/// left-recursive cycle. A name with no rule body (a token or ruleless term) is a
/// dead end.
fn left_rec_dfs(
  name : String,
  ctx : LowerCtx,
  state : Map[String, Int],
) -> String? {
  match state.get(name) {
    Some(1) => return Some(name)
    Some(2) => return None
    _ => ()
  }
  let body = match ctx.rules.get(name) {
    Some(b) => b
    None => return None
  }
  state.set(name, 1)
  for r in leading_refs(body, ctx) {
    match left_rec_dfs(r, ctx, state) {
      Some(c) => return Some(c)
      None => ()
    }
  }
  state.set(name, 2)
  None
}

///|
fn has_fragment_refs(rules : Map[String, RuleAst]) -> Bool {
  fn go(ast : RuleAst) -> Bool {
    match ast {
      Frag(_) => true
      Sym(_) => false
      Seq(items) | Alt(items) => items.iter().any(go)
      Star(inner) | Plus(inner) | Opt(inner) => go(inner)
      Emit(inner) | Emitor(inner) => go(inner)
      ErrorUntil(_) => false
      PrattApp(spec) => go(Sym(spec.prefix))
      PrattBinary(spec) => go(Sym(spec.prefix))
    }
  }
  for _, body in rules {
    if go(body) {
      return true
    }
  }
  false
}

///|
/// Reject any left-recursive rule at build time. `first_set` detects left
/// recursion only when consulted (inside a `Choice`/`Repeat`); a left-recursive
/// rule used purely in `Seq`/`Node` position would otherwise generate cleanly and
/// then infinite-loop the interpreter. Fails closed.
fn check_left_recursion(ctx : LowerCtx) -> Result[Unit, String] {
  let state : Map[String, Int] = Map([])
  for name, _ in ctx.rules {
    match left_rec_dfs(name, ctx, state) {
      Some(c) => return Err(ctx.loc(c) + left_rec_msg(c))
      None => ()
    }
  }
  Ok(())
}

///|
/// Reject Pratt productions whose `@prefix` rule is nullable. Nullable prefixes
/// are unsound for PrattApp starts and PrattBinary operand parsing. Phase 2
/// analysis gate — runs before lowering.
fn check_pratt_nullable_prefix(ctx : LowerCtx) -> Result[Unit, String] {
  for name, body in ctx.rules {
    let prefix = match body {
      PrattApp(spec) => spec.prefix
      PrattBinary(spec) => spec.prefix
      _ => continue
    }
    if nullable(Sym(prefix), ctx, @hashset.HashSet([])) {
      return Err(
        ctx.loc(name) +
        "Pratt production '" +
        name +
        "' has a nullable @prefix rule '" +
        prefix +
        "' — a Pratt prefix must be non-nullable",
      )
    }
  }
  Ok(())
}

///|
/// Resolve the CST node kind for a Pratt production: default from the enclosing
/// `#loom.node` role, or `@app` override naming another term variant.
fn resolve_pratt_kind(
  app_kind : String?,
  default_kind : String,
  ctx : LowerCtx,
) -> String raise RuleLowerError {
  match app_kind {
    None => default_kind
    Some(name) =>
      match ctx.term_kind_names.get(name) {
        Some(k) => k
        None =>
          raise RuleLowerError(
            "@app '" + name + "' is not a #loom.term variant with a node kind",
          )
      }
  }
}

///|
/// `@prefix` must name an existing grammar rule, not a terminal.
fn validate_pratt_prefix(
  prefix : String,
  ctx : LowerCtx,
) -> Unit raise RuleLowerError {
  match resolve_sym(prefix, ctx) {
    Rule(_) => ()
    RulelessTerm => raise RuleLowerError(ruleless_term_msg(prefix))
    Unknown => raise RuleLowerError(unknown_symbol_msg(prefix))
    Terminal(_) =>
      raise RuleLowerError(
        "@prefix '" +
        prefix +
        "' must name a grammar rule, not a terminal token",
      )
  }
}

///|
fn lower_pratt_app(
  spec : PrattAppSpec,
  kind_name : String,
  ctx : LowerCtx,
) -> MbtExpr raise RuleLowerError {
  validate_pratt_prefix(spec.prefix, ctx)
  let k = resolve_pratt_kind(spec.app_kind, kind_name, ctx)
  let pred = pred_text(
    first_names_ordered(Sym(spec.prefix), ctx, "a @prefix rule"),
    ctx,
  )
  MbtExpr::Call(ctx.grammar_qual + ".Expr::PrattApp", [
    MbtExpr::StrLit(quote(spec.prefix)),
    MbtExpr::Var(qualify(ctx.syntax_qual, k)),
    pred,
  ])
}

///|
fn lower_pratt_binary(
  spec : PrattBinarySpec,
  kind_name : String,
  ctx : LowerCtx,
) -> MbtExpr raise RuleLowerError {
  validate_pratt_prefix(spec.prefix, ctx)
  guard spec.ops.length() > 0 else {
    raise RuleLowerError(
      "@prec[] is empty — PrattBinary requires at least one operator",
    )
  }
  let pairs : Array[MbtExpr] = []
  let seen : @hashset.HashSet[String] = @hashset.HashSet([])
  for op in spec.ops {
    if seen.contains(op) {
      raise RuleLowerError("duplicate operator '" + op + "' in @prec[...]")
    }
    seen.add(op)
    match resolve_sym(op, ctx) {
      Terminal(kind) =>
        pairs.push(
          MbtExpr::Tuple([
            MbtExpr::Var(qualify(ctx.token_qual, op)),
            MbtExpr::Var(qualify(ctx.syntax_qual, kind)),
          ]),
        )
      Rule(_) =>
        raise RuleLowerError(
          "@prec operator '" +
          op +
          "' must be a terminal token, not a rule reference",
        )
      RulelessTerm => raise RuleLowerError(ruleless_term_msg(op))
      Unknown => raise RuleLowerError(unknown_symbol_msg(op))
    }
  }
  let k = resolve_pratt_kind(spec.app_kind, kind_name, ctx)
  let skip_arg = match spec.skip {
    None => MbtExpr::Var("None")
    Some(tok) =>
      match resolve_sym(tok, ctx) {
        Terminal(kind) => {
          let sep_pred = MbtExpr::Call(ctx.grammar_qual + ".Pred::IsToken", [
            MbtExpr::Var(qualify(ctx.token_qual, tok)),
          ])
          let sep_kind = MbtExpr::Var(qualify(ctx.syntax_qual, kind))
          MbtExpr::Call("Some", [MbtExpr::Tuple([sep_pred, sep_kind])])
        }
        Rule(_) =>
          raise RuleLowerError(
            "@skip '" + tok + "' must be a terminal token, not a rule reference",
          )
        RulelessTerm => raise RuleLowerError(ruleless_term_msg(tok))
        Unknown => raise RuleLowerError(unknown_symbol_msg(tok))
      }
  }
  MbtExpr::Call(ctx.grammar_qual + ".Expr::PrattBinary", [
    MbtExpr::StrLit(quote(spec.prefix)),
    MbtExpr::Var(qualify(ctx.syntax_qual, k)),
    MbtExpr::Array(pairs),
    skip_arg,
  ])
}

///|
/// Emit a `@grammar.Pred` over `names` (already in declaration order): a single
/// token becomes `IsToken`, several become `OneOf`.
fn pred_text(names : Array[String], ctx : LowerCtx) -> MbtExpr {
  if names.length() == 1 {
    MbtExpr::Call(ctx.grammar_qual + ".Pred::IsToken", [
      MbtExpr::Var(qualify(ctx.token_qual, names[0])),
    ])
  } else {
    let toks = names.map(n => MbtExpr::Var(qualify(ctx.token_qual, n)))
    MbtExpr::Call(ctx.grammar_qual + ".Pred::OneOf", [MbtExpr::Array(toks)])
  }
}

///|
/// Resolve a `Sym(name)` inside a postfix `~`/`!` operator and return the
/// `(token_name, kind_name)` pair, or fail closed on non-terminal or compound
/// inner expressions. Shared by the `Emit` and `Emitor` lowering arms.
fn resolve_optional_token(
  inner : RuleAst,
  ctx : LowerCtx,
  postfix : String,
) -> (String, String) raise RuleLowerError {
  match inner {
    Sym(name) =>
      match resolve_sym(name, ctx) {
        Terminal(kind) => (name, kind)
        Rule(_) =>
          raise RuleLowerError(
            "'" +
            postfix +
            "' can only be applied to a terminal token, not a rule reference '" +
            name +
            "'",
          )
        RulelessTerm => raise RuleLowerError(ruleless_term_msg(name))
        Unknown => raise RuleLowerError(unknown_symbol_msg(name))
      }
    _ =>
      raise RuleLowerError(
        "'" +
        postfix +
        "' requires a terminal token as its operand; got a compound expression",
      )
  }
}

///|
/// Lower a parsed rule node to an `MbtExpr` representing a `@grammar.Expr` value.
fn lower(ast : RuleAst, ctx : LowerCtx) -> MbtExpr raise RuleLowerError {
  match ast {
    Sym(name) =>
      match resolve_sym(name, ctx) {
        Terminal(kind) =>
          MbtExpr::Call(ctx.grammar_qual + ".Expr::Expect", [
            MbtExpr::Var(qualify(ctx.token_qual, name)),
            MbtExpr::Var(qualify(ctx.syntax_qual, kind)),
          ])
        Rule(_) =>
          MbtExpr::Call(ctx.grammar_qual + ".Expr::Ref", [
            MbtExpr::StrLit(quote(name)),
          ])
        RulelessTerm => raise RuleLowerError(ruleless_term_msg(name))
        Unknown => raise RuleLowerError(unknown_symbol_msg(name))
      }
    // Fragment references lower to a mangled Ref that the caller supplies
    // via the fragments~ parameter (merged into the rules map before compile).
    Frag(name) =>
      MbtExpr::Call(ctx.grammar_qual + ".Expr::Ref", [
        MbtExpr::StrLit(quote("__loom_frag__" + name)),
      ])
    Seq(items) => {
      let exprs = items.map(fn(it) { lower(it, ctx) })
      MbtExpr::Call(ctx.grammar_qual + ".Expr::Seq", [MbtExpr::Array(exprs)])
    }
    // X* — repeat the body while its FIRST set still gates entry.
    Star(inner) => {
      let pred = pred_text(
        first_names_ordered(inner, ctx, "a '*' repetition body"),
        ctx,
      )
      let body = lower(inner, ctx)
      MbtExpr::Call(ctx.grammar_qual + ".Expr::RepeatWhile", [pred, body])
    }
    // X+ — parse one, then repeat: Seq([X, X*]). Reuses Seq/Star lowering so the
    // formatting and the FIRST gate stay identical to the standalone forms.
    Plus(inner) => lower(Seq([inner, Star(inner)]), ctx)
    // X? — a single-alt Choice with NO fallback: the interpreter peeks once, runs
    // the alt when its FIRST matches, and otherwise does nothing — exactly
    // "optionally X". Absent is valid, so `required` is false.
    Opt(inner) => lower_choice([inner], ctx, required=false)
    Emit(inner) => {
      let (name, kind) = resolve_optional_token(inner, ctx, "~")
      MbtExpr::Call(ctx.grammar_qual + ".Expr::Emit", [
        MbtExpr::Var(qualify(ctx.token_qual, name)),
        MbtExpr::Var(qualify(ctx.syntax_qual, kind)),
      ])
    }
    Emitor(inner) => {
      let (name, kind) = resolve_optional_token(inner, ctx, "!")
      MbtExpr::Call(ctx.grammar_qual + ".Expr::EmitOr", [
        MbtExpr::Var(qualify(ctx.token_qual, name)),
        MbtExpr::Var(qualify(ctx.syntax_qual, kind)),
        MbtExpr::StrLit(quote("expected '" + name + "'")),
      ])
    }
    // @until(Token) — consume tokens (emitting diagnostic) until the sync
    // token is found. Single token -> Pred::IsToken; multi (via |) -> OneOf.
    ErrorUntil(tokens) => {
      let pred = if tokens.length() == 1 {
        MbtExpr::Call(ctx.grammar_qual + ".Pred::IsToken", [
          MbtExpr::Var(qualify(ctx.token_qual, tokens[0])),
        ])
      } else {
        let toks = tokens.map(n => MbtExpr::Var(qualify(ctx.token_qual, n)))
        MbtExpr::Call(ctx.grammar_qual + ".Pred::OneOf", [MbtExpr::Array(toks)])
      }
      // Verify every named token is known before emitting.
      for t in tokens {
        guard ctx.token_kinds.contains(t) else {
          raise RuleLowerError(
            "'" +
            t +
            "' in @until() is not a #loom.token variant — only terminal tokens can be sync points",
          )
        }
      }
      let delim_names = tokens.join("' or '")
      let msg = "expected '" + delim_names + "'"
      MbtExpr::Call(ctx.grammar_qual + ".Expr::ErrorUntil", [
        pred,
        MbtExpr::StrLit(quote(msg)),
      ])
    }
    // (A | B | ...) — one alt per branch, each gated on its own FIRST set, plus a
    // trailing `Any → Fail` branch. A required alternation that matches no branch
    // is an error; without the fallback the interpreter's Choice silently no-ops.
    Alt(branches) => lower_choice(branches, ctx, required=true)
    PrattApp(_) | PrattBinary(_) =>
      raise RuleLowerError(
        "Pratt annotations can only appear as a top-level production body",
      )
  }
}

///|
/// Lower a list of alternatives to a `@grammar.Expr::Choice`, one `Alt` per
/// branch gated on that branch's FIRST set. Shared by `Opt` (one branch,
/// `required=false`) and `Alt` (several, `required=true`).
///
/// When `required`, a trailing `Alt{starts: Pred::Any, body: Fail(...)}` is
/// appended: the interpreter's `Choice` silently runs nothing when no branch's
/// FIRST matches, so a required alternation needs an explicit error branch to
/// surface a diagnostic + placeholder instead of silently accepting the input.
/// An optional construct legitimately matches nothing, so it omits the fallback.
fn lower_choice(
  branches : Array[RuleAst],
  ctx : LowerCtx,
  required~ : Bool,
) -> MbtExpr raise RuleLowerError {
  let alts : Array[MbtExpr] = []
  // Accumulate the FIRST tokens seen across branches: it both gates the
  // disjointness check (a token already claimed by an earlier branch is a
  // FIRST/FIRST conflict that would silently shadow this one) and supplies the
  // `expected one of` message for the required fallback below.
  let expected : Array[String] = []
  for branch in branches {
    // A nullable alternative makes the alternation ε-derivable, but the
    // required fallback below turns "no branch matched" into a Fail — the ε
    // case would silently become a runtime error. Deciding ε needs FOLLOW
    // sets, which this subset does not compute, so fail closed at emit time.
    if required && nullable(branch, ctx, @hashset.HashSet([])) {
      raise RuleLowerError(
        "nullable alternative: an alternative that can match the empty string makes the alternation ε-derivable, but the emitted Choice fails when no branch matches; make each alternative non-nullable and wrap the whole alternation in `?` instead (e.g. rewrite `(A? | B)` as `(A | B)?`)",
      )
    }
    let names = first_names_ordered(branch, ctx, "a choice alternative")
    for n in names {
      if expected.contains(n) {
        raise RuleLowerError(
          "ambiguous alternation: token '" +
          n +
          "' begins more than one alternative; the #loom.rule subset requires alternatives with disjoint FIRST sets — factor the common prefix into a shared rule (e.g. rewrite `(A B | A C)` as `A (B | C)`), or move the pattern into a hand-authored @fragment",
        )
      }
      expected.push(n)
    }
    let pred = pred_text(names, ctx)
    let body = lower(branch, ctx)
    alts.push(
      MbtExpr::Record(ctx.grammar_qual + ".Alt", [
        ("starts", pred),
        ("body", body),
      ]),
    )
  }
  if required {
    let msg = "expected one of: " + expected.join(", ")
    alts.push(
      MbtExpr::Record(ctx.grammar_qual + ".Alt", [
        ("starts", MbtExpr::Call(ctx.grammar_qual + ".Pred::Any", [])),
        (
          "body",
          MbtExpr::Call(ctx.grammar_qual + ".Expr::Fail", [
            MbtExpr::StrLit(quote(msg)),
          ]),
        ),
      ]),
    )
  }
  MbtExpr::Call(ctx.grammar_qual + ".Expr::Choice", [MbtExpr::Array(alts)])
}

///|
/// Wrap a production body in `Node(kind, body)` for the variant's node kind.
fn lower_production(
  kind_name : String,
  body : RuleAst,
  ctx : LowerCtx,
) -> MbtExpr raise RuleLowerError {
  let body_expr = lower(body, ctx)
  MbtExpr::Call(ctx.grammar_qual + ".Expr::Node", [
    MbtExpr::Var(qualify(ctx.syntax_qual, kind_name)),
    body_expr,
  ])
}

///|
/// Build the resolution context: token vocabulary (name -> CST kind) and the
/// parsed rule map. Fails closed if any rule string does not parse.
fn build_lower_ctx(
  term_enum : EnumDecl,
  token_enum : EnumDecl,
  token_qual : String,
  syntax_qual : String,
  grammar_qual : String,
  file_rules? : Map[String, RuleAst] = Map([]),
  file_lines? : Map[String, Int] = Map([]),
) -> Result[LowerCtx, String] {
  let token_kinds : Map[String, String] = Map([])
  let term_kind_names : Map[String, String] = Map([])
  let token_order : Array[String] = []
  for v in token_enum.variants {
    match v.role {
      Some(role) => {
        token_kinds.set(v.name, derive_kind_name(v.name, role, v.kind_override))
        token_order.push(v.name)
      }
      None => ()
    }
  }
  for v in term_enum.variants {
    match v.role {
      Some(role) =>
        term_kind_names.set(
          v.name,
          derive_kind_name(v.name, role, v.kind_override),
        )
      None => ()
    }
  }
  let rules : Map[String, RuleAst] = Map([])
  let term_names : @hashset.HashSet[String] = @hashset.HashSet([])
  for v in term_enum.variants {
    term_names.add(v.name)
    match v.rule {
      Some(rule_str) =>
        // Skip parsing if a grammar-file rule overrides this annotation —
        // allows migrating off a broken #loom.rule by moving to the grammar file.
        if file_rules.get(v.name) is None {
          match parse_rule_string(rule_str, v.name) {
            Ok(ast) => rules.set(v.name, ast)
            Err(m) => return Err(m)
          }
        }
      None => ()
    }
  }
  // #523: a standalone `.loomgrammar` file overrides/extends the annotation rules
  // per production (enabling incremental migration off annotations). Every file
  // production must name a #loom.term variant, because the variant's
  // #loom.node/root/leaf role is what supplies the production's CST kind — a
  // production with no term variant has nowhere to get a kind. Fail closed.
  for name, ast in file_rules {
    guard term_names.contains(name) else {
      let loc = match file_lines.get(name) {
        Some(line) => "line " + line.to_string() + ": "
        None => ""
      }
      return Err(
        loc +
        "grammar file production '" +
        name +
        "' is not a #loom.term variant — every production must name a term variant whose #loom.node/#loom.root/#loom.leaf role supplies its CST kind",
      )
    }
    rules.set(name, ast)
  }
  Ok({
    token_kinds,
    term_kind_names,
    token_order,
    rules,
    term_names,
    file_lines,
    token_qual,
    syntax_qual,
    grammar_qual,
  })
}

///|
/// Emit the generated `grammar_ir.g.mbt` source, or an error describing why the
/// annotations cannot drive a GrammarIr.
fn emit_grammar_ir(
  term_enum : EnumDecl,
  token_enum : EnumDecl,
  token_qual : String,
  syntax_qual : String,
  grammar_qual : String,
  value_name : String,
  file_rules? : Map[String, RuleAst] = Map([]),
  file_lines? : Map[String, Int] = Map([]),
) -> Result[String, String] {
  let ctx = match
    build_lower_ctx(
      term_enum,
      token_enum,
      token_qual,
      syntax_qual,
      grammar_qual,
      file_rules~,
      file_lines~,
    ) {
    Ok(c) => c
    Err(m) => return Err(m)
  }
  // Reject left recursion across all rule bodies before lowering — a
  // left-recursive rule in plain Seq/Node position never consults `first_set`,
  // so this is the only guard that catches it. Fails closed.
  match check_left_recursion(ctx) {
    Err(m) => return Err(m)
    Ok(_) => ()
  }
  match check_pratt_nullable_prefix(ctx) {
    Err(m) => return Err(m)
    Ok(_) => ()
  }
  // Find the single #loom.root variant (the GrammarIr root rule). It must carry
  // a #loom.rule: only rule-bearing variants are emitted into the rules map, so a
  // ruleless root would leave `root=` pointing at a nonexistent production.
  let roots = term_enum.variants.filter(v => v.role is Some(Root))
  let root_name = match roots {
    [r] =>
      if ctx.rules.get(r.name) is Some(_) {
        r.name
      } else {
        return Err(
          "the #loom.root variant '" +
          r.name +
          "' has no grammar rule — the root must carry a production (via #loom.rule or the grammar file) for the GrammarIr to reference",
        )
      }
    [] =>
      return Err(
        "#loom.term enum has no #loom.root variant for the GrammarIr root",
      )
    _ =>
      return Err(
        "#loom.term enum has multiple #loom.root variants; exactly one is required",
      )
  }
  let token_type = token_enum.name
  let syntax_type = "SyntaxKind"
  let has_frags = has_fragment_refs(ctx.rules)
  let gram_ir_type = grammar_qual +
    ".GrammarIr[" +
    qualify(token_qual, token_type) +
    ", " +
    qualify(syntax_qual, syntax_type) +
    "]"
  let expr_type = grammar_qual +
    ".Expr[" +
    qualify(token_qual, token_type) +
    ", " +
    qualify(syntax_qual, syntax_type) +
    "]"
  let rules_type = "Map[String, " + expr_type + "]"
  // Build rule entries: "key": expr,
  let rule_entries : Array[@pretty.Layout[@pretty.SyntaxCategory]] = []
  for v in term_enum.variants {
    match ctx.rules.get(v.name) {
      Some(body) => {
        let kind_name = match v.role {
          Some(role) => derive_kind_name(v.name, role, v.kind_override)
          None =>
            return Err(
              ctx.loc(v.name) +
              "variant " +
              v.name +
              " has a grammar rule but no #loom.node/#loom.root/#loom.leaf role",
            )
        }
        let production = match body {
          PrattApp(spec) =>
            lower_pratt_app(spec, kind_name, ctx) catch {
              RuleLowerError(m) => return Err(ctx.loc(v.name) + m)
            }
          PrattBinary(spec) =>
            lower_pratt_binary(spec, kind_name, ctx) catch {
              RuleLowerError(m) => return Err(ctx.loc(v.name) + m)
            }
          _ =>
            lower_production(kind_name, body, ctx) catch {
              RuleLowerError(m) => return Err(ctx.loc(v.name) + m)
            }
        }
        rule_entries.push(
          @pretty.text(quote(v.name)) +
          @pretty.text(": ") +
          production.to_breakable_layout() +
          @pretty.text(","),
        )
      }
      None => ()
    }
  }
  let rules_content = @pretty.separate(@pretty.hardline(), rule_entries)
  // ── build the top-level declaration as Layout ──
  let header = @pretty.text("// Generated by loomgen (#522) — do not edit.")
  let doc = @pretty.text("///|") +
    @pretty.hardline() +
    @pretty.text("/// Generated GrammarIr initialization from grammar rules.")
  let main : @pretty.Layout[@pretty.SyntaxCategory] = if has_frags {
    // pub fn NAME(fragments~ : Type = Map([]),) -> Type { ... }
    let fn_sig = @pretty.text("pub fn " + value_name + "(") +
      @pretty.nest(
        @pretty.hardline() +
        @pretty.text("fragments~ : " + rules_type + " = Map([]),"),
      ) +
      @pretty.hardline() +
      @pretty.text(") -> " + gram_ir_type + " {")
    let rules_map = @pretty.text("let rules : " + rules_type + " = {") +
      @pretty.nest(@pretty.hardline() + rules_content) +
      @pretty.hardline() +
      @pretty.text("}")
    let for_loop = @pretty.text("for frag, body in fragments {") +
      @pretty.nest(@pretty.hardline() + @pretty.text("rules.set(frag, body)")) +
      @pretty.hardline() +
      @pretty.text("}")
    let ctor = @pretty.text(
      grammar_qual +
      ".GrammarIr::GrammarIr(rules, root=" +
      quote(root_name) +
      ")",
    )
    let body = @pretty.nest(
      @pretty.hardline() +
      rules_map +
      @pretty.hardline() +
      for_loop +
      @pretty.hardline() +
      ctor,
    )
    fn_sig + body + @pretty.hardline() + @pretty.text("}")
  } else {
    // pub let NAME : Type =
    //   GrammarIr::GrammarIr(
    //     { ... }, root="root")
    let let_decl = @pretty.text(
      "pub let " + value_name + " : " + gram_ir_type + " =",
    )
    let rules_map = @pretty.text("{") +
      @pretty.nest(@pretty.hardline() + rules_content) +
      @pretty.hardline() +
      @pretty.char('}')
    let ctor = @pretty.text(grammar_qual + ".GrammarIr::GrammarIr(") +
      @pretty.nest(
        @pretty.hardline() +
        rules_map +
        @pretty.text(",") +
        @pretty.hardline() +
        @pretty.text("root=" + quote(root_name) + ","),
      ) +
      @pretty.hardline() +
      @pretty.text(")")
    let_decl + @pretty.nest(@pretty.hardline() + ctor)
  }
  let final_layout = @pretty.separate(@pretty.hardline(), [
    header,
    @pretty.text(""),
    doc,
    main,
  ])
  Ok(@pretty.render_string(final_layout, width=80))
}
