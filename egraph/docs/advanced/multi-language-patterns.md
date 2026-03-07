# Multi-Language Patterns

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

## The Design Task

To use this library for a new domain, you define an enum whose variants represent your language's operators, then implement two traits:

- **`ENode`** — structural access to children (arity, indexing, mapping).
- **`ENodeRepr`** — serialization bridge for pattern matching (tag, payload, reconstruction).

```moonbit
trait ENode {
  arity(Self) -> Int
  child(Self, Int) -> Id
  map_children(Self, (Id) -> Id) -> Self
}

trait ENodeRepr {
  op_tag(Self) -> String
  payload(Self) -> String?
  from_op(String, String?, Array[Id]) -> Self?
}
```

Every domain follows the same structure: leaves carry payload, operators carry children. This document walks through four domains — arithmetic, lambda calculus, SQL, and linear algebra — to illustrate the patterns and trade-offs.

## Review: MyLang (Arithmetic Baseline)

The simplest useful language has four variants:

```moonbit
enum MyLang {
  Num(Int)          // leaf: payload = integer value
  Var(String)       // leaf: payload = variable name
  Add(Id, Id)       // operator: 2 children
  Mul(Id, Id)       // operator: 2 children
} derive(Eq, Hash)
```

`Num` and `Var` are **leaves** — they have no children (`arity = 0`) and carry data in their payload. `Add` and `Mul` are **operators** — they have children (`arity = 2`) and no payload.

The `ENodeRepr` implementation encodes this split:

```moonbit
impl ENodeRepr for MyLang with op_tag(self) {
  match self { Num(_) => "Num"; Var(_) => "Var"; Add(..) => "Add"; Mul(..) => "Mul" }
}

impl ENodeRepr for MyLang with payload(self) {
  match self { Num(n) => Some(n.to_string()); Var(s) => Some(s); _ => None }
}

impl ENodeRepr for MyLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Num", Some(s), 0) => Some(Num(@strconv.parse_int(s)))
    ("Var", Some(s), 0) => Some(Var(s))
    ("Add", None, 2)    => Some(Add(children[0], children[1]))
    ("Mul", None, 2)    => Some(Mul(children[0], children[1]))
    _                   => None
  }
}
```

Patterns reference leaf data via the colon syntax: `(Add ?x (Num:0))` matches addition where the right operand is zero. The tag `"Num"` dispatches the variant; the payload `"0"` distinguishes `Num(0)` from `Num(42)`.

## Lambda Calculus (LambdaLang)

Lambda calculus adds binding forms — operators that introduce variable names.

```moonbit
enum LambdaLang {
  LNum(Int)                // leaf: integer literal
  LVar(String)             // leaf: variable reference
  LAdd(Id, Id)             // operator: addition
  LMul(Id, Id)             // operator: multiplication
  LLam(String, Id)         // binder: lambda abstraction (name + body)
  LApp(Id, Id)             // operator: function application
  LLet(String, Id, Id)     // binder: let binding (name + value + body)
} derive(Eq, Hash)
```

### Binders: Payload + Children

`LLam` and `LLet` carry **both** payload and children. The variable name (`"x"` in `LLam("x", body)`) is payload — it is not an e-class, just metadata. The body is a child pointing to an e-class.

This affects `ENodeRepr`:

```moonbit
impl ENodeRepr for LambdaLang with op_tag(self) {
  match self {
    LNum(_) => "Num"; LVar(_) => "Var"; LAdd(..) => "Add"
    LMul(..) => "Mul"; LLam(..) => "Lam"; LApp(..) => "App"; LLet(..) => "Let"
  }
}

impl ENodeRepr for LambdaLang with payload(self) {
  match self {
    LNum(n) => Some(n.to_string())
    LVar(name) | LLam(name, _) | LLet(name, _, _) => Some(name)
    _ => None
  }
}
```

Notice that `LLam("x", body)` has `arity = 1` (one child: the body) and `payload = Some("x")`. The `from_op` function reconstructs it from `("Lam", Some("x"), [body_id])`.

### Binding Representation: Named vs De Bruijn

This library uses **named variables**: `LVar("x")` refers to the nearest enclosing `LLam("x", ...)`. This is human-readable and makes patterns intuitive — `(Lam:x (Add (Var:x) (Num:1)))` clearly means "lambda x, x + 1".

The alternative is **De Bruijn indices**: `LVar(0)` refers to the nearest binder, `LVar(1)` to the next enclosing one. De Bruijn indices are capture-free by construction — renaming is never needed — but patterns become harder to read: `(Lam (Add (Var:0) (Num:1)))`.

For e-graph use, named variables are simpler unless you need to implement substitution as a rewrite rule. If you do, beware of variable capture.

### Substitution and Beta-Reduction

Beta-reduction — `(lambda x. body) arg` reduces to `body[x := arg]` — is a valid equivalence, but it cannot be expressed as a simple pattern rewrite. The right-hand side is not a fixed pattern; it depends on the structure of `body`. Substitution modifies term structure by replacing `LVar("x")` nodes deep inside `body` with `arg`.

For this library, beta-reduction is better handled through the `modify` hook in e-class analysis rather than as a `Rewrite` rule. The analysis can detect application-of-lambda patterns and perform the substitution programmatically.

## SQL Query Optimization

SQL query plans are trees of relational operators — a natural fit for e-graphs.

```moonbit
enum SqlLang {
  Table(String)              // leaf: base table name
  Col(String)                // leaf: column reference
  Select(Id, Id)             // operator: project columns from source
  From(Id)                   // operator: scan a source
  Where(Id, Id)              // operator: filter (source, predicate)
  Join(Id, Id, Id)           // operator: join (left, right, condition)
  And(Id, Id)                // operator: logical AND
  Eq(Id, Id)                 // operator: equality comparison
} derive(Eq, Hash)
```

### Design Decisions

`Table` and `Col` are leaves with string payload — the table or column name is data, not a sub-expression. `Join` has arity 3: left source, right source, and join condition. This is a fixed-arity encoding; each variant always has the same number of children.

### ENode Implementation

```moonbit
impl ENode for SqlLang with arity(self) {
  match self {
    Table(_) | Col(_) => 0
    From(_) => 1
    Select(_, _) | Where(_, _) | And(_, _) | Eq(_, _) => 2
    Join(_, _, _) => 3
  }
}

impl ENode for SqlLang with child(self, i) {
  match self {
    From(s) => s
    Select(a, b) | Where(a, b) | And(a, b) | Eq(a, b) =>
      if i == 0 { a } else { b }
    Join(l, r, c) =>
      if i == 0 { l } else if i == 1 { r } else { c }
    _ => abort("no children")
  }
}

impl ENode for SqlLang with map_children(self, f) {
  match self {
    Table(_) | Col(_) => self
    From(s) => From(f(s))
    Select(a, b) => Select(f(a), f(b))
    Where(a, b) => Where(f(a), f(b))
    And(a, b) => And(f(a), f(b))
    Eq(a, b) => Eq(f(a), f(b))
    Join(l, r, c) => Join(f(l), f(r), f(c))
  }
}
```

### ENodeRepr Implementation

```moonbit
impl ENodeRepr for SqlLang with op_tag(self) {
  match self {
    Table(_) => "Table"; Col(_) => "Col"; Select(..) => "Select"
    From(_) => "From"; Where(..) => "Where"; Join(..) => "Join"
    And(..) => "And"; Eq(..) => "Eq"
  }
}

impl ENodeRepr for SqlLang with payload(self) {
  match self { Table(s) | Col(s) => Some(s); _ => None }
}

impl ENodeRepr for SqlLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Table", Some(s), 0) => Some(Table(s))
    ("Col", Some(s), 0)   => Some(Col(s))
    ("From", None, 1)     => Some(From(children[0]))
    ("Select", None, 2)   => Some(Select(children[0], children[1]))
    ("Where", None, 2)    => Some(Where(children[0], children[1]))
    ("And", None, 2)      => Some(And(children[0], children[1]))
    ("Eq", None, 2)       => Some(Eq(children[0], children[1]))
    ("Join", None, 3)     => Some(Join(children[0], children[1], children[2]))
    _                     => None
  }
}
```

### Example Rewrite: Predicate Pushdown

Predicate pushdown moves a filter closer to the data source, reducing the number of rows processed by a join:

```
Where(Join(a, b, cond), pred)  =>  Join(Where(a, pred), b, cond)
```

As a rewrite rule:

```moonbit
rewrite(
  "pred-pushdown",
  "(Where (Join ?a ?b ?cond) ?pred)",
  "(Join (Where ?a ?pred) ?b ?cond)",
)
```

In practice this rewrite is only valid when `pred` references only columns from `a`. That check would be expressed as a conditional rewrite (see [Conditional Rewrites](conditional-rewrites.md)).

## Tensor / Linear Algebra

Tensor computation graphs optimize matrix operations, transpositions, and reshaping.

```moonbit
enum TensorLang {
  Scalar(Double)           // leaf: scalar constant
  Tensor(String)           // leaf: named tensor
  MatMul(Id, Id)           // operator: matrix multiplication
  ElemAdd(Id, Id)          // operator: element-wise addition
  Transpose(Id)            // operator: matrix transpose
  Reshape(Id)              // operator: reshape tensor
} derive(Eq, Hash)
```

### ENode and ENodeRepr

The implementation follows the same leaf/operator pattern. `Scalar` and `Tensor` are leaves with payload. `MatMul` and `ElemAdd` have arity 2. `Transpose` and `Reshape` have arity 1.

```moonbit
impl ENode for TensorLang with arity(self) {
  match self {
    Scalar(_) | Tensor(_) => 0
    Transpose(_) | Reshape(_) => 1
    MatMul(_, _) | ElemAdd(_, _) => 2
  }
}

impl ENode for TensorLang with map_children(self, f) {
  match self {
    Scalar(_) | Tensor(_) => self
    Transpose(x) => Transpose(f(x))
    Reshape(x) => Reshape(f(x))
    MatMul(a, b) => MatMul(f(a), f(b))
    ElemAdd(a, b) => ElemAdd(f(a), f(b))
  }
}
```

### Example Rewrites

**Double transpose elimination:** `Transpose(Transpose(x))` is equivalent to `x`.

```moonbit
rewrite("transpose-cancel", "(Transpose (Transpose ?x))", "?x")
```

**Matrix multiplication associativity:** `MatMul(MatMul(a, b), c)` is equivalent to `MatMul(a, MatMul(b, c))`. Both groupings are mathematically identical; the cost function decides which is cheaper (e.g., based on matrix dimensions).

```moonbit
rewrite(
  "matmul-assoc",
  "(MatMul (MatMul ?a ?b) ?c)",
  "(MatMul ?a (MatMul ?b ?c))",
)
```

### Shape Metadata

Tensor shapes (e.g., `[3, 4]` for a 3x4 matrix) affect which rewrites are valid and which grouping is cheapest. Rather than encoding shapes in payload, use **e-class analysis** to compute and propagate shape data. The `make` callback infers shapes from operators (e.g., `MatMul` of `[m, k]` and `[k, n]` produces `[m, n]`), and the cost function uses shape data to estimate operation counts.

## Design Principles Summary

**1. Leaves use payload, operators use children.**

`Num(42)` stores `42` as payload (a string `"42"` in `ENodeRepr`). `Add(a, b)` stores `a` and `b` as children (e-class `Id`s). Some variants like `LLam("x", body)` use both — the name is payload, the body is a child.

**2. Fixed arity per variant.**

Each variant always has the same number of children. `Add` is always arity 2. `Transpose` is always arity 1. For variable-length argument lists, use a cons-cell encoding:

```
Call(fn, Args(arg1, Args(arg2, Nil)))
```

This converts variable arity into a chain of fixed-arity nodes.

**3. `op_tag` must be unique per variant.**

The pattern matcher dispatches on `op_tag`. If two variants share the same tag, patterns cannot distinguish them. Use distinct strings: `"Add"`, `"Mul"`, `"MatMul"` — not generic names like `"BinOp"`.

**4. Payload must round-trip.**

The invariant `from_op(op_tag(x), payload(x), children(x)) == Some(x)` must hold for every node. If `payload` encodes an integer as `"42"`, then `from_op` must parse `"42"` back to `42`. Test this invariant explicitly:

```moonbit
test "round-trip" {
  let node = Num(42)
  let reconstructed = MyLang::from_op(
    node.op_tag(), node.payload(), node.children()
  )
  assert_eq(reconstructed, Some(node))
}
```

**5. Keep the language small.**

Only model operators you plan to optimize. A language with 50 variants but 3 rewrite rules wastes implementation effort on 47 variants that never participate in rewrites. Start with the minimum set, add variants when you need new rules.
