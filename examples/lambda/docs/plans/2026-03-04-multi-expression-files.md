# Multi-Expression Files — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `parse_source_file` / `parse_source_file_term` entry points that parse a sequence of top-level `let x = e` definitions (no `in`) followed by an optional final expression, with each definition as an independent CST subtree enabling genuine incremental reuse.

**Architecture:** New `LetDef` SyntaxKind (distinct from `LetExpr`) + new grammar function `parse_source_file_root` wired to a separate `source_file_spec`. `term_convert` adds `syntax_node_to_source_file_term` which right-folds `LetDef` children with the optional final expression (or `Unit`) as the terminal. The existing `parse_cst`/`parse` path is untouched.

**Tech Stack:** MoonBit, `moon` build system. All `moon` commands run from `examples/lambda/`.

---

## Background

Read before starting:
- `examples/lambda/docs/plans/2026-03-04-multi-expression-files-design.md` — approved design
- `examples/lambda/src/syntax/syntax_kind.mbt` — SyntaxKind enum (LetDef = 27)
- `examples/lambda/src/cst_parser.mbt` — grammar (parse_lambda_root, parse_let_expr patterns)
- `examples/lambda/src/ast/ast.mbt` — Term enum + print_term
- `examples/lambda/src/term_convert.mbt` — syntax_node_to_term, view_to_term

**Key conventions:**
- Tests use `///|` prefix + `test "name" { ... }`
- Assertions use `inspect(expr, content="expected_string")`
- Run tests: `cd examples/lambda && moon test`
- Run single package: `cd examples/lambda && moon test -p dowdiness/lambda`
- CstNode children are `Array[CstElement]` where each element is `Node(CstNode)` or `Token(CstToken)`
- `SyntaxNode.children()` returns only node children (no tokens); `nth_child(0)` = first node child

---

## Task 1: Add `LetDef` to SyntaxKind

**Files:**
- Modify: `src/syntax/syntax_kind.mbt`

### Step 1: Add `LetDef` to the enum

In `src/syntax/syntax_kind.mbt`, add `LetDef` to the enum after `LetExpr`:

```moonbit
pub(all) enum SyntaxKind {
  LambdaToken
  DotToken
  LeftParenToken
  RightParenToken
  PlusToken
  MinusToken
  IfKeyword
  ThenKeyword
  ElseKeyword
  IdentToken
  IntToken
  WhitespaceToken
  ErrorToken
  EofToken
  LambdaExpr
  AppExpr
  BinaryExpr
  IfExpr
  ParenExpr
  IntLiteral
  VarRef
  ErrorNode
  SourceFile
  LetKeyword
  InKeyword
  EqToken
  LetExpr
  LetDef        // NEW: top-level let x = e (no 'in')
} derive(Show, Eq)
```

### Step 2: Add to `to_raw`

In the `to_raw` match, add after `LetExpr => 26`:

```moonbit
    LetDef => 27
```

### Step 3: Add to `from_raw`

In the `from_raw` match, add after `26 => LetExpr`:

```moonbit
    27 => LetDef
```

(`is_token` needs no change — `LetDef` is a node, not a token; the catch-all `_ => false` already handles it.)

### Step 4: Verify it compiles

```bash
cd examples/lambda && moon check
```

Expected: no errors.

---

## Task 2: Add grammar + CST entry point

**Files:**
- Modify: `src/cst_parser.mbt` (append new functions)
- Modify: `src/lambda_spec.mbt` (append `source_file_spec`)
- Test: `src/cst_tree_test.mbt` (append)

### Step 1: Write the failing tests

Append to `src/cst_tree_test.mbt`:

```moonbit
///|
test "source file: two LetDef children" {
  let (cst, _) = parse_source_file("let id = 1\nlet const = 2")
  inspect(@syntax.SyntaxKind::from_raw(cst.kind), content="SourceFile")
  let mut node_count = 0
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) => {
        node_count = node_count + 1
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      }
      _ => ()
    }
  }
  inspect(node_count, content="2")
  inspect(node_kinds[0], content="LetDef")
  inspect(node_kinds[1], content="LetDef")
}

///|
test "source file: LetDef has correct token structure" {
  let (cst, _) = parse_source_file("let id = 1")
  let letdef = for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) => break n
      _ => continue
    }
  } else {
    abort("No LetDef node found")
  }
  inspect(@syntax.SyntaxKind::from_raw(letdef.kind), content="LetDef")
  // Non-whitespace children: LetKeyword, IdentToken, EqToken, IntLiteral node
  let non_ws : Array[String] = []
  for elem in letdef.children {
    match elem {
      @seam.CstElement::Token(t) =>
        if @syntax.SyntaxKind::from_raw(t.kind) != @syntax.WhitespaceToken {
          non_ws.push(@syntax.SyntaxKind::from_raw(t.kind).to_string())
        }
      @seam.CstElement::Node(n) =>
        non_ws.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
    }
  }
  inspect(non_ws, content="[\"LetKeyword\", \"IdentToken\", \"EqToken\", \"IntLiteral\"]")
}

///|
test "source file: single expression (no defs)" {
  let (cst, _) = parse_source_file("42")
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      _ => ()
    }
  }
  inspect(node_kinds, content="[\"IntLiteral\"]")
}

///|
test "source file: def + final expression" {
  let (cst, _) = parse_source_file("let id = 1\nid")
  let node_kinds : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Node(n) =>
        node_kinds.push(@syntax.SyntaxKind::from_raw(n.kind).to_string())
      _ => ()
    }
  }
  inspect(node_kinds, content="[\"LetDef\", \"VarRef\"]")
}
```

### Step 2: Run to verify they fail

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: compile error — `parse_source_file` not found.

### Step 3: Add `parse_let_def` and `parse_source_file_root` to `cst_parser.mbt`

Append after the existing grammar section (after `parse_atom`, after line 280) in `src/cst_parser.mbt`:

```moonbit
// ─── Source-file grammar (LetDef* Expression?) ────────────────────────────────

///|
fn parse_let_def(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  ctx.node(@syntax.LetDef, () => {
    ctx.emit_token(@syntax.LetKeyword)
    match ctx.peek() {
      @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
      _ => {
        ctx.error("Expected variable name after 'let'")
        ctx.emit_error_placeholder()
      }
    }
    lambda_expect(ctx, @token.Eq, @syntax.EqToken)
    parse_expression(ctx)
  })
}

///|
/// Entry point for source-file grammar: LetDef* Expression?
fn parse_source_file_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  while ctx.peek() == @token.Let {
    parse_let_def(ctx)
  }
  match ctx.peek() {
    @token.EOF => ()
    _ => parse_expression(ctx)
  }
  ctx.flush_trivia()
}

///|
/// Parse a source file (LetDef* Expression?). Returns tree with error recovery.
pub fn parse_source_file(
  source : String,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let tokens = @lexer.tokenize(source)
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    source_file_spec,
  )
  (cst, diagnostics)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor (for incremental use).
pub fn parse_source_file_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo[@token.Token]],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    source_file_spec,
    cursor~,
  )
}

///|
/// Make a ReuseCursor for incremental source-file parsing.
pub fn make_source_file_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@token.TokenInfo[@token.Token]],
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    source_file_spec,
  )
}
```

### Step 4: Add `source_file_spec` to `lambda_spec.mbt`

Append to `src/lambda_spec.mbt` after `lambda_spec`:

```moonbit
///|
/// LanguageSpec for source-file grammar (LetDef* Expression?).
/// Identical to lambda_spec except parse_root = parse_source_file_root.
let source_file_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  cst_token_matches=(raw, text, tok) => {
    match @syntax.SyntaxKind::from_raw(raw) {
      IntToken => if tok is Integer(i) { text == i.to_string() } else { false }
      IdentToken => if tok is Identifier(name) { name == text } else { false }
      _ =>
        match syntax_kind_to_token_kind(raw) {
          Some(expected) => expected == tok
          None => false
        }
    }
  },
  parse_root=parse_source_file_root,
)
```

### Step 5: Run to verify tests pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: all tests pass (including the 4 new CST structure tests).

### Step 6: Commit

```bash
cd examples/lambda && git add src/syntax/syntax_kind.mbt src/cst_parser.mbt \
  src/lambda_spec.mbt src/cst_tree_test.mbt
git commit -m "feat(lambda): add LetDef SyntaxKind and parse_source_file entry point"
```

---

## Task 3: Add `Unit` term + full conversion

**Files:**
- Modify: `src/ast/ast.mbt` (Term enum + print_term)
- Modify: `src/term_convert.mbt` (append `syntax_node_to_source_file_term`)
- Modify: `src/parser.mbt` (append `parse_source_file_term`)
- Test: `src/parser_test.mbt` (append)

### Step 1: Write the failing tests

Append to `src/parser_test.mbt`:

```moonbit
///|
test "parse_source_file_term: two defs fold to nested Let with Unit" {
  let (term, _) = parse_source_file_term("let id = 1\nlet const = 2")
  inspect(
    @ast.print_term(term),
    content="let id = 1 in let const = 2 in ()",
  )
}

///|
test "parse_source_file_term: def + final expression" {
  let (term, _) = parse_source_file_term("let id = 1\nid")
  inspect(@ast.print_term(term), content="let id = 1 in id")
}

///|
test "parse_source_file_term: single expression (no defs)" {
  let (term, _) = parse_source_file_term("42")
  inspect(@ast.print_term(term), content="42")
}

///|
test "parse_source_file_term: empty file" {
  let (term, _) = parse_source_file_term("")
  inspect(@ast.print_term(term), content="()")
}
```

### Step 2: Run to verify they fail

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: compile error — `parse_source_file_term` not found.

### Step 3: Add `Unit` to `Term` and update `print_term`

In `src/ast/ast.mbt`, add `Unit` to the enum (after `Let`):

```moonbit
pub(all) enum Term {
  // Integer
  Int(Int)
  // Variable
  Var(VarName)
  // Lambda abstraction
  Lam(VarName, Term)
  // Application
  App(Term, Term)
  // Binary operation
  Bop(Bop, Term, Term)
  // If-then-else
  If(Term, Term, Term)
  // Let binding (non-recursive)
  Let(VarName, Term, Term)
  // Unit — terminal for definition-only source files
  Unit
} derive(Show, Eq)
```

In `print_term`, add `Unit => "()"` inside `go` before the closing brace:

```moonbit
pub fn print_term(term : Term) -> String {
  fn go(t : Term) -> String {
    match t {
      Int(i) => i.to_string()
      Var(x) => x
      Lam(x, t) => "(λ" + x + ". " + go(t) + ")"
      App(t1, t2) => "(" + go(t1) + " " + go(t2) + ")"
      Bop(Plus, t1, t2) => "(" + go(t1) + " + " + go(t2) + ")"
      Bop(Minus, t1, t2) => "(" + go(t1) + " - " + go(t2) + ")"
      If(t1, t2, t3) => "if " + go(t1) + " then " + go(t2) + " else " + go(t3)
      Let(x, init, body) => "let " + x + " = " + go(init) + " in " + go(body)
      Unit => "()"
    }
  }

  go(term)
}
```

### Step 4: Add `syntax_node_to_source_file_term` to `term_convert.mbt`

Append to `src/term_convert.mbt`:

```moonbit
///|
/// Convert a SourceFile SyntaxNode (LetDef* Expression?) to a Term.
///
/// Right-folds definitions: [LetDef(x1,e1), LetDef(x2,e2), Expression(e3)]
/// → Let("x1", e1, Let("x2", e2, e3)).
/// No final expression → uses Unit as terminal.
pub fn syntax_node_to_source_file_term(root : @seam.SyntaxNode) -> @ast.Term {
  let defs : Array[(@ast.VarName, @ast.Term)] = []
  let mut final_term : @ast.Term = @ast.Term::Unit
  for child in root.children() {
    match @syntax.SyntaxKind::from_raw(child.kind()) {
      @syntax.LetDef => {
        let name = child
          .find_token(@syntax.IdentToken.to_raw())
          .map(fn(t) { t.text() })
          .unwrap_or("")
        // The expression is the first (and only) node child of LetDef
        let init = match child.nth_child(0) {
          Some(expr_node) => view_to_term(expr_node)
          None => @ast.Term::Var("<error>")
        }
        defs.push((name, init))
      }
      _ => final_term = view_to_term(child)
    }
  }
  // Right-fold: wrap defs around the terminal from right to left
  let mut result = final_term
  for i = defs.length() - 1; i >= 0; i = i - 1 {
    let (name, init) = defs[i]
    result = @ast.Term::Let(name, init, result)
  }
  result
}
```

### Step 5: Add `parse_source_file_term` to `parser.mbt`

Append to `src/parser.mbt`:

```moonbit
///|
/// Parse a source file (LetDef* Expression?) and convert to Term.
///
/// Definitions are right-folded into nested Let terms with Unit as terminal
/// when no final expression is present.
pub fn parse_source_file_term(
  source : String,
) -> (@ast.Term, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let (cst, diags) = parse_source_file(source)
  let syntax = @seam.SyntaxNode::from_cst(cst)
  (syntax_node_to_source_file_term(syntax), diags)
}
```

### Step 6: Run to verify tests pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: all tests pass (4 new term conversion tests + all previous tests).

### Step 7: Commit

```bash
cd examples/lambda && git add src/ast/ast.mbt src/term_convert.mbt \
  src/parser.mbt src/parser_test.mbt
git commit -m "feat(lambda): add Unit term and parse_source_file_term"
```

---

## Task 4: Add `source_file_grammar` + incremental reuse test

**Files:**
- Modify: `src/grammar.mbt` (append `source_file_grammar`)
- Test: `src/imperative_parser_test.mbt` (append reuse test)

### Step 1: Write the failing test

Append to `src/imperative_parser_test.mbt`:

```moonbit
///|
test "source file: editing first def reuses second def" {
  // source1: two independent defs
  let source1 = "let id = 1\nlet const = 2"
  let tokens1 = @lexer.tokenize(source1)
  let (cst1, _, _) = parse_source_file_recover_with_tokens(source1, tokens1, None)

  // Edit: insert "0" after the "1" in "id = 1" → "id = 10"
  // "let id = 1" is 10 chars; position 10 is the "\n".
  // We replace old_len=1 with new_len=2 (change "1" to "10")
  let source2 = "let id = 10\nlet const = 2"
  let tokens2 = @lexer.tokenize(source2)
  let cursor = make_source_file_reuse_cursor(cst1, 9, 10, tokens2)
  let (_, _, reuse_count) = parse_source_file_recover_with_tokens(
    source2, tokens2, Some(cursor),
  )

  // The "const = 2" LetDef is untouched — it must be reused
  inspect(reuse_count > 0, content="true")
}
```

### Step 2: Run to verify the test fails

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: compile error — `source_file_grammar` not found (or the test runs but reuse_count == 0 if cursor isn't wired).

### Step 3: Add `source_file_grammar` to `grammar.mbt`

Append to `src/grammar.mbt`:

```moonbit
///|
/// Grammar for source-file parsing (LetDef* Expression?).
/// Use with new_imperative_parser or new_reactive_parser.
pub let source_file_grammar : @loom.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @seam.SyntaxNode,
] = @loom.Grammar::new(
  spec=source_file_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { s },
  on_lex_error=fn(_msg) {
    let cst = @seam.CstNode::new(@syntax.ErrorNode.to_raw(), [])
    @seam.SyntaxNode::from_cst(cst)
  },
)
```

### Step 4: Run to verify tests pass

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: all tests pass including the new reuse test.

### Step 5: Commit

```bash
cd examples/lambda && git add src/grammar.mbt src/imperative_parser_test.mbt
git commit -m "feat(lambda): add source_file_grammar and incremental reuse test"
```

---

## Task 5: Extend differential fuzz test

**Files:**
- Modify: `src/imperative_differential_fuzz_test.mbt` (append new fuzz test)

### Step 1: Append a multi-def fuzz test

Append to `src/imperative_differential_fuzz_test.mbt`:

```moonbit
///|
/// Generate a random multi-def source file.
/// Format: "let x0 = <expr>\nlet x1 = <expr>\n..." (2-4 defs)
fn idf_make_source_file(seed : Int) -> String {
  let mut s = seed
  s = idf_next_seed(s)
  let def_count = s.abs() % 3 + 2 // 2 to 4 defs
  let var_names = ["a", "b", "c", "d"]
  let mut out = ""
  for i = 0; i < def_count; i = i + 1 {
    s = idf_next_seed(s)
    let expr = idf_make_fragment(s, allow_invalid=false)
    out = out + "let " + var_names[i % var_names.length()] + " = " + expr + "\n"
  }
  out
}

///|
test "differential fuzz: multi-def source file incremental == full reparse" {
  let iterations = 200
  for iteration = 0; iteration < iterations; iteration = iteration + 1 {
    let base_seed = iteration * 1000 + 42
    let source0 = idf_make_source_file(base_seed)
    let tokens0 = @lexer.tokenize(source0)
    let (cst0, _, _) = parse_source_file_recover_with_tokens(source0, tokens0, None)

    // Apply a random edit
    let mut s = idf_next_seed(base_seed + 1)
    let len0 = source0.length()
    let pos = if len0 > 0 { s.abs() % len0 } else { 0 }
    s = idf_next_seed(s)
    let old_len = if len0 > pos { s.abs() % (len0 - pos).min(5) + 1 } else { 0 }
    s = idf_next_seed(s)
    let fragment = idf_make_fragment(s, allow_invalid=false)
    let new_len = fragment.length()
    let source1 = match idf_slice_string(source0, 0, pos) {
      Some(prefix) =>
        match idf_slice_string(source0, pos + old_len, source0.length()) {
          Some(suffix) => prefix + fragment + suffix
          None => prefix + fragment
        }
      None => fragment
    }
    let tokens1 = @lexer.tokenize(source1)
    let cursor = make_source_file_reuse_cursor(
      cst0, idf_clamp(pos, len0), idf_clamp(pos + old_len, len0), tokens1,
    )
    let (incremental_cst, _, _) = parse_source_file_recover_with_tokens(
      source1, tokens1, Some(cursor),
    )
    let (full_cst, _, _) = parse_source_file_recover_with_tokens(
      source1, tokens1, None,
    )
    if incremental_cst != full_cst {
      abort(
        "Differential fuzz failure at iteration " +
        iteration.to_string() +
        "\nsource0: " +
        source0 +
        "\nsource1: " +
        source1,
      )
    }
  }
  inspect("passed", content="passed")
}
```

### Step 2: Run to verify the fuzz test passes

```bash
cd examples/lambda && moon test -p dowdiness/lambda
```

Expected: all tests pass including the 200-iteration fuzz test.

### Step 3: Commit

```bash
cd examples/lambda && git add src/imperative_differential_fuzz_test.mbt
git commit -m "test(lambda): extend differential fuzz to multi-def source files"
```

---

## Task 6: Update interfaces, format, update README

**Files:**
- Modify: `src/pkg.generated.mbti` (auto-generated)
- Modify: `examples/lambda/docs/plans/2026-03-04-multi-expression-files-design.md` (add Status: Complete)
- Modify: `docs/README.md` (move entry to archive section)

### Step 1: Regenerate interfaces and format

```bash
cd examples/lambda && moon info && moon fmt
```

### Step 2: Check the interface diff

```bash
git diff src/pkg.generated.mbti
```

Expected: new signatures added (`parse_source_file`, `parse_source_file_term`,
`parse_source_file_recover_with_tokens`, `make_source_file_reuse_cursor`,
`source_file_grammar`, `syntax_node_to_source_file_term`). `Unit` in Term.
No existing signatures removed.

### Step 3: Run full test suite

```bash
cd examples/lambda && moon test
```

Expected: all tests pass.

### Step 4: Mark design doc complete and archive it

In `examples/lambda/docs/plans/2026-03-04-multi-expression-files-design.md`,
add `**Status:** Complete` after the first heading.

Then move to archive:

```bash
cd /path/to/loom  # repo root
git mv examples/lambda/docs/plans/2026-03-04-multi-expression-files-design.md \
       docs/archive/completed-phases/2026-03-04-multi-expression-files-design.md
```

Update `docs/README.md`:
- Remove the entry from the Examples section:
  `examples/lambda/docs/plans/2026-03-04-multi-expression-files-design.md`
- Add to the Archive section at the end of the archive bullet:
  `, multi-expression files`
- Also remove/update the implementation plan entry once complete

### Step 5: Run docs check

```bash
bash check-docs.sh
```

Expected: all checks pass.

### Step 6: Final commit

```bash
git add src/pkg.generated.mbti \
        docs/archive/completed-phases/2026-03-04-multi-expression-files-design.md \
        docs/README.md
git commit -m "feat(lambda): complete multi-expression files — LetDef*, Unit term, source_file_grammar"
```

---

## Verification checklist

```bash
cd examples/lambda && moon test     # all lambda tests pass
cd examples/lambda && moon check    # no warnings
git diff src/pkg.generated.mbti     # only additions
bash check-docs.sh                  # all checks pass
```
