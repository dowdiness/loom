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
/// Two-space indentation for `depth` levels.
fn indent(depth : Int) -> String {
  "  ".repeat(depth)
}

///|
/// Wrap a rule/token name (always a MoonBit identifier) as a string literal for
/// emission into the generated `Map` keys, `Ref`, and `root=`.
fn quote(s : String) -> String {
  "\"" + s + "\""
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
/// Diagnostic for an unsupported `@fragment` reference. Shared by `lower` and
/// `first_set` (defensive backstops; `check_no_fragments` is the primary gate).
fn fragment_unsupported_msg(frag : String) -> String {
  "fragment @" +
  frag +
  " is not supported by --grammar-ir; the generated GrammarIr is a closed value with no way to bind a hand-authored fragment body"
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
  }
}

///|
/// FIRST set of `ast` — the token names that can begin it. Unions left-to-right
/// through nullable prefixes of a `Seq`, stopping at the first non-nullable
/// element. `visiting` detects a left-recursive `Ref` cycle and fails closed.
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
    // Unreachable for valid input — check_no_fragments rejects fragments before
    // any FIRST set is computed — but kept as a defensive backstop.
    Frag(name) => raise RuleLowerError(fragment_unsupported_msg(name))
    Seq(items) => {
      let acc : @hashset.HashSet[String] = @hashset.HashSet([])
      for it in seq_leading(items, ctx) {
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
/// The first fragment name reached anywhere in `ast`, or None. Fragments are an
/// unfinished feature (see check_no_fragments) so any occurrence is rejected.
fn first_fragment(ast : RuleAst) -> String? {
  match ast {
    Frag(name) => Some(name)
    Sym(_) => None
    Seq(items) | Alt(items) => {
      for it in items {
        match first_fragment(it) {
          Some(n) => return Some(n)
          None => ()
        }
      }
      None
    }
    Star(inner) | Plus(inner) | Opt(inner) => first_fragment(inner)
  }
}

///|
/// Reject any `@fragment` reference at build time. A fragment would lower to
/// `Ref("name")`, but the generated GrammarIr is a closed value (build_lower_ctx
/// only inserts term-rule bodies into the map), so the Ref has no binding and
/// `@grammar.compile` raises `MissingRef`. Until a fragment-binding mechanism
/// exists, fail closed rather than emit an uncompilable grammar.
fn check_no_fragments(ctx : LowerCtx) -> Result[Unit, String] {
  for name, body in ctx.rules {
    match first_fragment(body) {
      Some(frag) =>
        return Err(
          ctx.loc(name) +
          "rule '" +
          name +
          "' references fragment @" +
          frag +
          " — @fragment references are not yet supported by --grammar-ir; the generated GrammarIr is a closed value with no way to bind a hand-authored fragment body, so the reference would dangle. Rewrite the production within the #loom.rule subset.",
        )
      None => ()
    }
  }
  Ok(())
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
/// Emit a `@grammar.Pred` over `names` (already in declaration order): a single
/// token becomes `IsToken`, several become `OneOf`.
fn pred_text(names : Array[String], ctx : LowerCtx) -> String {
  if names.length() == 1 {
    ctx.grammar_qual + ".Pred::IsToken(" + ctx.token_qual + "." + names[0] + ")"
  } else {
    let toks = names.map(n => ctx.token_qual + "." + n)
    ctx.grammar_qual + ".Pred::OneOf([" + toks.join(", ") + "])"
  }
}

///|
/// Lower a parsed rule node to `@grammar.Expr` source text. The returned text's
/// first line is unindented (the caller places it); internal lines are indented
/// absolutely from `depth`.
fn lower(
  ast : RuleAst,
  ctx : LowerCtx,
  depth : Int,
) -> String raise RuleLowerError {
  match ast {
    Sym(name) =>
      match resolve_sym(name, ctx) {
        Terminal(kind) =>
          ctx.grammar_qual +
          ".Expr::Expect(" +
          ctx.token_qual +
          "." +
          name +
          ", " +
          ctx.syntax_qual +
          "." +
          kind +
          ")"
        Rule(_) => ctx.grammar_qual + ".Expr::Ref(" + quote(name) + ")"
        RulelessTerm => raise RuleLowerError(ruleless_term_msg(name))
        Unknown => raise RuleLowerError(unknown_symbol_msg(name))
      }
    // Fragments are rejected up front by check_no_fragments; this arm is a
    // defensive backstop so a fragment can never lower to a dangling Ref.
    Frag(name) => raise RuleLowerError(fragment_unsupported_msg(name))
    Seq(items) => {
      let b = StringBuilder()..write_string(ctx.grammar_qual + ".Expr::Seq([\n")
      for it in items {
        b.write_string(indent(depth + 1) + lower(it, ctx, depth + 1) + ",\n")
      }
      b..write_string(indent(depth) + "])").to_string()
    }
    // X* — repeat the body while its FIRST set still gates entry.
    Star(inner) => {
      let pred = pred_text(
        first_names_ordered(inner, ctx, "a '*' repetition body"),
        ctx,
      )
      StringBuilder()
      ..write_string(ctx.grammar_qual + ".Expr::RepeatWhile(\n")
      ..write_string(indent(depth + 1) + pred + ",\n")
      ..write_string(indent(depth + 1) + lower(inner, ctx, depth + 1) + ",\n")
      ..write_string(indent(depth) + ")")
      .to_string()
    }
    // X+ — parse one, then repeat: Seq([X, X*]). Reuses Seq/Star lowering so the
    // formatting and the FIRST gate stay identical to the standalone forms.
    Plus(inner) => lower(Seq([inner, Star(inner)]), ctx, depth)
    // X? — a single-alt Choice with NO fallback: the interpreter peeks once, runs
    // the alt when its FIRST matches, and otherwise does nothing — exactly
    // "optionally X". Absent is valid, so `required` is false.
    Opt(inner) => lower_choice([inner], ctx, depth, required=false)
    // (A | B | ...) — one alt per branch, each gated on its own FIRST set, plus a
    // trailing `Any → Fail` branch. A required alternation that matches no branch
    // is an error; without the fallback the interpreter's Choice silently no-ops.
    Alt(branches) => lower_choice(branches, ctx, depth, required=true)
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
  depth : Int,
  required~ : Bool,
) -> String raise RuleLowerError {
  let b = StringBuilder()..write_string(ctx.grammar_qual + ".Expr::Choice([\n")
  // Accumulate the FIRST tokens seen across branches: it both gates the
  // disjointness check (a token already claimed by an earlier branch is a
  // FIRST/FIRST conflict that would silently shadow this one) and supplies the
  // `expected one of` message for the required fallback below.
  let expected : Array[String] = []
  for branch in branches {
    let names = first_names_ordered(branch, ctx, "a choice alternative")
    for n in names {
      if expected.contains(n) {
        raise RuleLowerError(
          "ambiguous alternation: token '" +
          n +
          "' begins more than one alternative; the #loom.rule subset requires alternatives with disjoint FIRST sets",
        )
      }
      expected.push(n)
    }
    let pred = pred_text(names, ctx)
    b
    ..write_string(indent(depth + 1) + ctx.grammar_qual + ".Alt::{\n")
    ..write_string(indent(depth + 2) + "starts: " + pred + ",\n")
    ..write_string(
      indent(depth + 2) + "body: " + lower(branch, ctx, depth + 2) + ",\n",
    )
    .write_string(indent(depth + 1) + "},\n")
  }
  if required {
    let msg = "expected one of: " + expected.join(", ")
    b
    ..write_string(indent(depth + 1) + ctx.grammar_qual + ".Alt::{\n")
    ..write_string(
      indent(depth + 2) + "starts: " + ctx.grammar_qual + ".Pred::Any,\n",
    )
    ..write_string(
      indent(depth + 2) +
      "body: " +
      ctx.grammar_qual +
      ".Expr::Fail(" +
      quote(msg) +
      "),\n",
    )
    .write_string(indent(depth + 1) + "},\n")
  }
  b..write_string(indent(depth) + "])").to_string()
}

///|
/// Wrap a production body in `Node(kind, body)` for the variant's node kind.
fn lower_production(
  kind_name : String,
  body : RuleAst,
  ctx : LowerCtx,
  depth : Int,
) -> String raise RuleLowerError {
  StringBuilder()
  ..write_string(ctx.grammar_qual + ".Expr::Node(\n")
  ..write_string(indent(depth + 1) + ctx.syntax_qual + "." + kind_name + ",\n")
  ..write_string(indent(depth + 1) + lower(body, ctx, depth + 1) + ",\n")
  ..write_string(indent(depth) + ")")
  .to_string()
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
  // Reject @fragment references before lowering — they would emit dangling Refs
  // the closed GrammarIr cannot bind. Fails closed.
  match check_no_fragments(ctx) {
    Err(m) => return Err(m)
    Ok(_) => ()
  }
  // Reject left recursion across all rule bodies before lowering — a
  // left-recursive rule in plain Seq/Node position never consults `first_set`,
  // so this is the only guard that catches it. Fails closed.
  match check_left_recursion(ctx) {
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
  let b = StringBuilder()
    ..write_string("// Generated by loomgen (#522) — do not edit.\n\n")
    ..write_string("///|\n")
    ..write_string("/// Generated GrammarIr initialization from grammar rules.\n")
    ..write_string(
      "pub let " +
      value_name +
      " : " +
      grammar_qual +
      ".GrammarIr[" +
      token_qual +
      "." +
      token_type +
      ", " +
      syntax_qual +
      "." +
      syntax_type +
      "] =\n",
    )
    ..write_string(indent(1) + grammar_qual + ".GrammarIr::GrammarIr(\n")
    ..write_string(indent(2) + "{\n")
  for v in term_enum.variants {
    // A variant gets a production when a rule resolves for it — from a #loom.rule
    // annotation or a .loomgrammar file entry (both merged into `ctx.rules`).
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
        let production = lower_production(kind_name, body, ctx, 3) catch {
          RuleLowerError(m) => return Err(ctx.loc(v.name) + m)
        }
        b.write_string(indent(3) + quote(v.name) + ": " + production + ",\n")
      }
      None => ()
    }
  }
  b
  ..write_string(indent(2) + "},\n")
  ..write_string(indent(2) + "root=" + quote(root_name) + ",\n")
  .write_string(indent(1) + ")\n")
  Ok(b.to_string())
}
