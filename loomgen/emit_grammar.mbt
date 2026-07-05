///|
fn parse_rule_fn_name(name : String) -> String {
  "parse_" + name
}

///|
/// Emit a grammar to MoonBit source. `native_names` declares which names a
/// `Native(...)` node may delegate to (empty by default). A `Native(name)`
/// lowers to a literal `name(ctx)` call — no `parse_` prefix, no generated
/// stub — because the consumer must hand-write `fn name(ctx) -> Unit` in the
/// generated file's package; see the emitted header comment when any native
/// is present.
pub fn[T, K] emit_grammar(
  ir : @grammar.GrammarIr[T, K],
  token_type~ : String,
  syntax_type~ : String,
  core_qual~ : String,
  token_ref~ : (T) -> String,
  kind_ref~ : (K) -> String,
  native_names? : Set[String] = Set::Set([]),
) -> Result[String, String] {
  emit_grammar_module(
    ir,
    token_type~,
    syntax_type~,
    core_qual~,
    token_ref~,
    kind_ref~,
    native_names~,
  ).map(fn(m) { @pretty.render_string(m.to_layout(), width=80) })
}

///|
/// Emit a grammar to an MbtModule AST for structural inspection.
/// Returns the module before rendering, allowing tests to assert on
/// structure rather than formatted output.
pub fn[T, K] emit_grammar_module(
  ir : @grammar.GrammarIr[T, K],
  token_type~ : String,
  syntax_type~ : String,
  core_qual~ : String,
  token_ref~ : (T) -> String,
  kind_ref~ : (K) -> String,
  native_names? : Set[String] = Set::Set([]),
) -> Result[MbtModule, String] {
  let compiled = @grammar.compile(ir, native_names~) catch {
    @grammar.MissingRoot(name) =>
      return Err("grammar emitter: missing root rule \"" + name + "\"")
    @grammar.MissingRef(name) =>
      return Err("grammar emitter: missing ref \"" + name + "\"")
    @grammar.MissingFragment(name) => {
      let bare = name.replace(old="__loom_frag__", new="")
      return Err(
        "grammar emitter: fragment @" +
        bare +
        " is not bound — provide its body via the fragments~ parameter",
      )
    }
    @grammar.MissingNative(name) =>
      return Err("grammar emitter: missing native \"" + name + "\"")
    @grammar.AmbiguousRule(name) =>
      return Err(
        "grammar emitter: \"" + name + "\" is both a grammar rule and a native",
      )
  }
  // `AmbiguousRule` above only rejects a name that is literally both a rule
  // and a native. It can't see the `parse_` prefix the rule-stub generator
  // adds below — that's a loomgen-only naming convention, not something
  // `compile` (language-agnostic) knows about. A native named exactly
  // `parse_<other rule>` would otherwise silently collide with that rule's
  // generated stub in the emitted file, so check it here instead.
  for name in compiled.names {
    let stub_name = parse_rule_fn_name(name)
    if native_names.contains(stub_name) {
      return Err(
        "grammar emitter: native \"" +
        stub_name +
        "\" collides with the generated stub for rule \"" +
        name +
        "\"",
      )
    }
  }
  let root_name = compiled.names[compiled.root_slot()]
  if root_name == "root" {
    return Err(
      "grammar emitter: root rule name \"root\" produces \"parse_root\" which collides with the generated root entry point",
    )
  }
  let root_fn = parse_rule_fn_name(root_name)
  let parser_context = core_qual +
    ".ParserContext[" +
    token_type +
    ", " +
    syntax_type +
    "]"

  // Build native consumer comments
  let native_comments : Array[String] = []
  if native_names.length() > 0 {
    let names = native_names.iter().collect()
    names.sort()
    for name in names {
      native_comments.push(name)
    }
  }

  // Build all function declarations
  let fns : Array[MbtFnDecl] = []

  // Root function
  let root_decl = MbtFnDecl::{
    pub_fn: true,
    name: "parse_root",
    params: [MbtParam::{ name: "ctx", type_: parser_context }],
    return_type: "Unit",
    body: MbtBlock::{ stmts: [ExprStmt(Call(root_fn, [Var("ctx")]))] },
  }
  fns.push(root_decl)

  // Rule functions
  for i, name in compiled.names {
    let expr = compiled.rule(i)
    let body_stmts = match
      emit_compiled_expr(expr, compiled~, token_ref~, kind_ref~) {
      Ok(s) => s
      Err(msg) => return Err(msg)
    }
    let fn_decl = MbtFnDecl::{
      pub_fn: false,
      name: parse_rule_fn_name(name),
      params: [MbtParam::{ name: "ctx", type_: parser_context }],
      return_type: "Unit",
      body: MbtBlock::{ stmts: body_stmts },
    }
    fns.push(fn_decl)
  }

  let mbt_mod = MbtModule::{ native_comments, parser_context, fns }
  Ok(mbt_mod)
}

///|
fn string_lit(s : String) -> String {
  let escaped = s
    .replace_all(old="\\", new="\\\\")
    .replace_all(old="\n", new="\\n")
    .replace_all(old="\r", new="\\r")
    .replace_all(old="\t", new="\\t")
    .replace_all(old="\"", new="\\\"")
  "\"" + escaped + "\""
}

///|
fn[T] pred_to_expr(
  pred : @grammar.Pred[T],
  token_expr : MbtExpr,
  token_ref : (T) -> String,
) -> MbtExpr {
  match pred {
    @grammar.Pred::Any => Bool(true)
    @grammar.Pred::IsToken(token) =>
      BinOp(token_expr, "==", Var(token_ref(token)))
    @grammar.Pred::OneOf(tokens) =>
      if tokens.length() == 0 {
        Bool(false)
      } else {
        let mut expr = BinOp(token_expr, "==", Var(token_ref(tokens[0])))
        for i in 1..<tokens.length() {
          expr = BinOp(
            expr,
            "||",
            BinOp(token_expr, "==", Var(token_ref(tokens[i]))),
          )
        }
        expr
      }
    @grammar.Pred::Not(inner) =>
      UnOp("!", pred_to_expr(inner, token_expr, token_ref))
  }
}

///|
fn[T] pred_closure_expr(
  pred : @grammar.Pred[T],
  token_ref : (T) -> String,
) -> MbtExpr {
  let body_expr = pred_to_expr(pred, Var("t"), token_ref)
  Closure([MbtParam::{ name: "t", type_: "" }], MbtBlock::{
    stmts: [ExprStmt(body_expr)],
  })
}

///|
fn[T, K] pair_array_expr(
  pairs : Array[(T, K)],
  token_ref : (T) -> String,
  kind_ref : (K) -> String,
) -> MbtExpr {
  let items = pairs.map(fn(pair) {
    Tuple([Var(token_ref(pair.0)), Var(kind_ref(pair.1))])
  })
  Array(items)
}

///|
fn[T, K] rule_call_expr(
  slot : Int,
  compiled~ : @grammar.CompiledGrammar[T, K],
) -> MbtExpr {
  Call(parse_rule_fn_name(compiled.names[slot]), [Var("ctx")])
}

///|
fn[T, K] emit_compiled_expr(
  expr : @grammar.CompiledExpr[T, K],
  compiled~ : @grammar.CompiledGrammar[T, K],
  token_ref~ : (T) -> String,
  kind_ref~ : (K) -> String,
) -> Result[Array[MbtStmt], String] {
  match expr {
    @grammar.CompiledExpr::Node(kind, body) => {
      let body_stmts = match
        emit_compiled_expr(body, compiled~, token_ref~, kind_ref~) {
        Ok(s) => s
        Err(msg) => return Err(msg)
      }
      let closure = Closure([], MbtBlock::{ stmts: body_stmts })
      Ok([
        ExprStmt(MethodCall(Var("ctx"), "node", [Var(kind_ref(kind)), closure])),
      ])
    }
    @grammar.CompiledExpr::Emit(token, kind) =>
      Ok([
        MbtStmt::If(
          MethodCall(Var("ctx"), "at", [Var(token_ref(token))]),
          MbtBlock::{
            stmts: [
              ExprStmt(
                MethodCall(Var("ctx"), "emit_token", [Var(kind_ref(kind))]),
              ),
            ],
          },
          [],
        ),
      ])
    @grammar.CompiledExpr::RefSlot(slot) =>
      Ok([
        ExprStmt(Call(parse_rule_fn_name(compiled.names[slot]), [Var("ctx")])),
      ])
    // Literal call, no `parse_` prefix and no generated stub: the consumer
    // hand-writes `fn name(ctx) -> Unit` (documented in the emitted header).
    // Re-entry is free here — the native calls sibling `parse_<rule>(ctx)`
    // functions directly, so no `call_rule` plumbing needs to be emitted.
    @grammar.CompiledExpr::NativeRef(name) =>
      Ok([ExprStmt(Call(name, [Var("ctx")]))])
    @grammar.CompiledExpr::Choice(alts) => {
      let stmts : Array[MbtStmt] = []
      if alts.length() > 0 {
        stmts.push(Let("token", MethodCall(Var("ctx"), "peek", [])))
        let else_chain : Array[MbtElseBranch] = []
        for i, alt in alts {
          let body_stmts = match
            emit_compiled_expr(alt.body, compiled~, token_ref~, kind_ref~) {
            Ok(s) => s
            Err(msg) => return Err(msg)
          }
          let cond = pred_to_expr(alt.starts, Var("token"), token_ref)
          if i == 0 {
            stmts.push(MbtStmt::If(cond, MbtBlock::{ stmts: body_stmts }, []))
          } else {
            else_chain.push(ElseIf(cond, MbtBlock::{ stmts: body_stmts }))
          }
        }
        if alts.length() > 1 {
          // Wire the else-if chain onto the first If statement
          let first_if = stmts[1]
          match first_if {
            MbtStmt::If(cond, blk, _) =>
              stmts[1] = MbtStmt::If(cond, blk, else_chain)
            _ => ()
          }
        }
      }
      Ok(stmts)
    }
    @grammar.CompiledExpr::Seq(exprs) => {
      let mut stmts : Array[MbtStmt] = []
      for e in exprs {
        let part = match
          emit_compiled_expr(e, compiled~, token_ref~, kind_ref~) {
          Ok(s) => s
          Err(msg) => return Err(msg)
        }
        stmts = stmts + part
      }
      Ok(stmts)
    }
    @grammar.CompiledExpr::Expect(token, kind) =>
      Ok([
        ExprStmt(
          Pipe(
            MethodCall(Var("ctx"), "expect", [
              Var(token_ref(token)),
              Var(kind_ref(kind)),
            ]),
            Call("ignore", []),
          ),
        ),
      ])
    @grammar.CompiledExpr::RepeatWhile(pred, body) => {
      let body_stmts = match
        emit_compiled_expr(body, compiled~, token_ref~, kind_ref~) {
        Ok(s) => s
        Err(msg) => return Err(msg)
      }
      let peek_expr : MbtExpr = MethodCall(Var("ctx"), "peek", [])
      let cond = BinOp(
        UnOp("!", MethodCall(Var("ctx"), "at_eof", [])),
        "&&",
        pred_to_expr(pred, peek_expr, token_ref),
      )
      Ok([While(cond, MbtBlock::{ stmts: body_stmts })])
    }
    @grammar.CompiledExpr::Empty => Ok([])
    @grammar.CompiledExpr::EmitError(msg) =>
      Ok([ExprStmt(MethodCall(Var("ctx"), "error", [StrLit(string_lit(msg))]))])
    @grammar.CompiledExpr::ErrorUntil(stop, msg) =>
      Ok([
        ExprStmt(MethodCall(Var("ctx"), "error", [StrLit(string_lit(msg))])),
        ExprStmt(
          Pipe(
            MethodCall(Var("ctx"), "skip_until", [
              pred_closure_expr(stop, token_ref),
            ]),
            Call("ignore", []),
          ),
        ),
      ])
    @grammar.CompiledExpr::Fail(msg) =>
      Ok([
        ExprStmt(MethodCall(Var("ctx"), "error", [StrLit(string_lit(msg))])),
        ExprStmt(MethodCall(Var("ctx"), "emit_error_placeholder", [])),
      ])
    @grammar.CompiledExpr::EmitOr(token, kind, msg) =>
      Ok([
        MbtStmt::If(
          MethodCall(Var("ctx"), "at", [Var(token_ref(token))]),
          MbtBlock::{
            stmts: [
              ExprStmt(
                MethodCall(Var("ctx"), "emit_token", [Var(kind_ref(kind))]),
              ),
            ],
          },
          [
            Else(MbtBlock::{
              stmts: [
                ExprStmt(
                  MethodCall(Var("ctx"), "error", [StrLit(string_lit(msg))]),
                ),
                ExprStmt(MethodCall(Var("ctx"), "emit_error_placeholder", [])),
              ],
            }),
          ],
        ),
      ])
    @grammar.CompiledExpr::DiagnoseIf(pred, msg) =>
      Ok([
        MbtStmt::If(
          pred_to_expr(pred, MethodCall(Var("ctx"), "peek", []), token_ref),
          MbtBlock::{
            stmts: [
              ExprStmt(
                MethodCall(Var("ctx"), "error", [StrLit(string_lit(msg))]),
              ),
            ],
          },
          [],
        ),
      ])
    @grammar.CompiledExpr::ExpectSkip(skip, skip_kind, expected, kind) =>
      Ok([
        ExprStmt(
          Pipe(
            MethodCall(Var("ctx"), "expect_after_skip", [
              pred_closure_expr(skip, token_ref),
              Var(kind_ref(skip_kind)),
              Var(token_ref(expected)),
              Var(kind_ref(kind)),
            ]),
            Call("ignore", []),
          ),
        ),
      ])
    @grammar.CompiledExpr::ConsumeGated(skip, skip_kind, look) =>
      Ok([
        ExprStmt(
          Pipe(
            MethodCall(Var("ctx"), "consume_while_emit_if", [
              pred_closure_expr(skip, token_ref),
              Var(kind_ref(skip_kind)),
              pred_closure_expr(look, token_ref),
            ]),
            Call("ignore", []),
          ),
        ),
      ])
    @grammar.CompiledExpr::RequireSep(delims, stop, alt, msg_alt~, msg_else~) => {
      let peek_expr : MbtExpr = MethodCall(Var("ctx"), "peek", [])
      let had_expr = BinOp(
        MethodCall(Var("ctx"), "consume_while_emit_mapped", [
          pair_array_expr(delims, token_ref, kind_ref),
        ]),
        ">",
        Var("0"),
      )
      let stop_cond = pred_to_expr(stop, peek_expr, token_ref)
      let alt_cond = pred_to_expr(alt, peek_expr, token_ref)
      Ok([
        Let("had", had_expr),
        MbtStmt::If(
          BinOp(UnOp("!", Var("had")), "&&", UnOp("!", stop_cond)),
          MbtBlock::{
            stmts: [
              MbtStmt::If(
                alt_cond,
                MbtBlock::{
                  stmts: [
                    ExprStmt(
                      MethodCall(Var("ctx"), "error", [
                        StrLit(string_lit(msg_alt)),
                      ]),
                    ),
                  ],
                },
                [
                  Else(MbtBlock::{
                    stmts: [
                      ExprStmt(
                        MethodCall(Var("ctx"), "error", [
                          StrLit(string_lit(msg_else)),
                        ]),
                      ),
                    ],
                  }),
                ],
              ),
            ],
          },
          [],
        ),
      ])
    }
    @grammar.CompiledExpr::ErrorNodeUntil(error_kind, stop, msg) =>
      Ok([
        ExprStmt(MethodCall(Var("ctx"), "error", [StrLit(string_lit(msg))])),
        ExprStmt(
          MethodCall(Var("ctx"), "start_node", [Var(kind_ref(error_kind))]),
        ),
        While(
          BinOp(
            UnOp("!", MethodCall(Var("ctx"), "at_eof", [])),
            "&&",
            UnOp(
              "!",
              pred_to_expr(stop, MethodCall(Var("ctx"), "peek", []), token_ref),
            ),
          ),
          MbtBlock::{
            stmts: [ExprStmt(MethodCall(Var("ctx"), "bump_error", []))],
          },
        ),
        ExprStmt(MethodCall(Var("ctx"), "finish_node", [])),
      ])
    @grammar.CompiledExpr::WrapIfNext(kind, pred, body) => {
      let body_stmts = match
        emit_compiled_expr(body, compiled~, token_ref~, kind_ref~) {
        Ok(s) => s
        Err(msg) => return Err(msg)
      }
      Ok([
        Let("mark", MethodCall(Var("ctx"), "mark", [])),
        MbtStmt::If(
          pred_to_expr(pred, MethodCall(Var("ctx"), "peek", []), token_ref),
          MbtBlock::{
            stmts: [
              ExprStmt(
                MethodCall(Var("ctx"), "wrap_at", [
                  Var("mark"),
                  Var(kind_ref(kind)),
                  Closure([], MbtBlock::{ stmts: body_stmts }),
                ]),
              ),
            ],
          },
          [Else(MbtBlock::{ stmts: body_stmts })],
        ),
      ])
    }
    @grammar.CompiledExpr::RepeatTopLevel(
      slot,
      starts~,
      delim~,
      delim_kind~,
      between_msg~,
      after_msg~
    ) => {
      let delim_closure = pred_closure_expr(delim, token_ref)
      let consume_delim = ExprStmt(
        MethodCall(Var("ctx"), "consume_while_emit", [
          delim_closure,
          Var(kind_ref(delim_kind)),
        ]),
      )
      let peek_expr : MbtExpr = MethodCall(Var("ctx"), "peek", [])
      let starts_cond = pred_to_expr(starts, peek_expr, token_ref)
      let cond = BinOp(
        UnOp("!", MethodCall(Var("ctx"), "at_eof", [])),
        "&&",
        starts_cond,
      )
      let reuse_body = MbtBlock::{ stmts: [consume_delim, ExprStmt(Continue)] }
      let item_call = ExprStmt(rule_call_expr(slot, compiled~))
      let while_body = MbtBlock::{
        stmts: [
          MbtStmt::If(
            MethodCall(Var("ctx"), "try_reuse_repeat_group", []),
            reuse_body,
            [],
          ),
          item_call,
          Let(
            "had",
            pred_to_expr(delim, MethodCall(Var("ctx"), "peek", []), token_ref),
          ),
          consume_delim,
          MbtStmt::If(
            BinOp(
              UnOp("!", Var("had")),
              "&&",
              UnOp("!", MethodCall(Var("ctx"), "at_eof", [])),
            ),
            MbtBlock::{
              stmts: [
                MbtStmt::If(
                  starts_cond,
                  MbtBlock::{
                    stmts: [
                      ExprStmt(
                        MethodCall(Var("ctx"), "error", [
                          StrLit(string_lit(between_msg)),
                        ]),
                      ),
                    ],
                  },
                  [
                    Else(MbtBlock::{
                      stmts: [
                        ExprStmt(
                          MethodCall(Var("ctx"), "error", [
                            StrLit(string_lit(after_msg)),
                          ]),
                        ),
                      ],
                    }),
                  ],
                ),
              ],
            },
            [],
          ),
        ],
      }
      Ok([consume_delim, While(cond, while_body)])
    }
    @grammar.CompiledExpr::PrattApp(slot, kind, starts) => {
      let starts_cond = pred_to_expr(
        starts,
        MethodCall(Var("ctx"), "peek", []),
        token_ref,
      )
      Ok([
        MbtStmt::If(
          MethodCall(Var("ctx"), "try_reuse_current_node", [Var(kind_ref(kind))]),
          MbtBlock::{ stmts: [] },
          [
            Else(MbtBlock::{
              stmts: [
                Let("mark", MethodCall(Var("ctx"), "mark", [])),
                ExprStmt(rule_call_expr(slot, compiled~)),
                MbtStmt::If(
                  starts_cond,
                  MbtBlock::{
                    stmts: [
                      ExprStmt(
                        MethodCall(Var("ctx"), "wrap_at", [
                          Var("mark"),
                          Var(kind_ref(kind)),
                          Closure([], MbtBlock::{
                            stmts: [
                              While(starts_cond, MbtBlock::{
                                stmts: [
                                  ExprStmt(rule_call_expr(slot, compiled~)),
                                ],
                              }),
                            ],
                          }),
                        ]),
                      ),
                    ],
                  },
                  [],
                ),
              ],
            }),
          ],
        ),
      ])
    }
    @grammar.CompiledExpr::PrattBinary(slot, kind, ops, skip~) => {
      let op_tokens = ops.map(fn(pair) { pair.0 })
      let pairs_expr = pair_array_expr(ops, token_ref, kind_ref)
      let skip_to_op_expr : MbtExpr = match skip {
        Some((sep, sep_kind)) => {
          let op_match_closure = fn(t_expr : MbtExpr) -> MbtExpr {
            let mut matching = Bool(false)
            for op_t in op_tokens {
              matching = BinOp(
                matching,
                "||",
                BinOp(t_expr, "==", Var(token_ref(op_t))),
              )
            }
            matching
          }
          let closure_body = op_match_closure(Var("t"))
          Pipe(
            MethodCall(Var("ctx"), "consume_while_emit_if", [
              pred_closure_expr(sep, token_ref),
              Var(kind_ref(sep_kind)),
              Closure([MbtParam::{ name: "t", type_: "" }], MbtBlock::{
                stmts: [ExprStmt(closure_body)],
              }),
            ]),
            Call("ignore", []),
          )
        }
        None => Var("()")
      }

      let op_cond_expr = pred_to_expr(
        @grammar.Pred::OneOf(op_tokens),
        MethodCall(Var("ctx"), "peek", []),
        token_ref,
      )
      // Build the match expression for find_first
      let scrutinee = MethodCall(
        MethodCall(Var("ops"), "iter", []),
        "find_first",
        [
          Closure([MbtParam::{ name: "pair", type_: "" }], MbtBlock::{
            stmts: [
              ExprStmt(
                BinOp(
                  FieldAccess(Var("pair"), "0"),
                  "==",
                  MethodCall(Var("ctx"), "peek", []),
                ),
              ),
            ],
          }),
        ],
      )
      Ok([
        MbtStmt::If(
          MethodCall(Var("ctx"), "try_reuse_current_node", [Var(kind_ref(kind))]),
          MbtBlock::{ stmts: [] },
          [
            Else(MbtBlock::{
              stmts: [
                Let("ops", pairs_expr),
                Let("mark", MethodCall(Var("ctx"), "mark", [])),
                ExprStmt(
                  Call(parse_rule_fn_name(compiled.names[slot]), [Var("ctx")]),
                ),
                ExprStmt(skip_to_op_expr),
                MbtStmt::If(
                  op_cond_expr,
                  MbtBlock::{
                    stmts: [
                      ExprStmt(
                        MethodCall(Var("ctx"), "wrap_at", [
                          Var("mark"),
                          Var(kind_ref(kind)),
                          Closure([], MbtBlock::{
                            stmts: [
                              While(Bool(true), MbtBlock::{
                                stmts: [
                                  ExprStmt(skip_to_op_expr),
                                  ExprStmt(
                                    Match(scrutinee, [
                                      MbtMatchArm::{
                                        pat: Nullary("None"),
                                        body: Break,
                                      },
                                      MbtMatchArm::{
                                        pat: Constructor("Some", Bind("pair")),
                                        body: Block(MbtBlock::{
                                          stmts: [
                                            ExprStmt(
                                              MethodCall(
                                                Var("ctx"),
                                                "emit_token",
                                                [FieldAccess(Var("pair"), "1")],
                                              ),
                                            ),
                                            ExprStmt(
                                              Call(
                                                parse_rule_fn_name(
                                                  compiled.names[slot],
                                                ),
                                                [Var("ctx")],
                                              ),
                                            ),
                                          ],
                                        }),
                                      },
                                    ]),
                                  ),
                                ],
                              }),
                            ],
                          }),
                        ]),
                      ),
                    ],
                  },
                  [],
                ),
              ],
            }),
          ],
        ),
      ])
    }
    @grammar.CompiledExpr::ManualNewlineAppExpr =>
      Err(
        "grammar emitter: ManualNewlineAppExpr is a lambda-specific residue and cannot be emitted",
      )
  }
}
