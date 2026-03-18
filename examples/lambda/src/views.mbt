///|
// Typed SyntaxNode view types for the lambda calculus grammar.
//
// Each view wraps a SyntaxNode and exposes named, typed accessors.
// Use ViewType::cast(n) to narrow a SyntaxNode to a specific view;
// cast returns None when the node's kind doesn't match.
//
// Pattern:
//   let syn = parser.parse()    // SyntaxNode
//   let source = syn.children()[0]
//   match LambdaExprView::cast(source) {
//     Some(v) => println(v.param())
//     None    => ...
//   }

// ─── LambdaExpr ──────────────────────────────────────────────────────────────

///|
pub struct LambdaExprView {
  node : @seam.SyntaxNode
}

///|
pub fn LambdaExprView::cast(n : @seam.SyntaxNode) -> LambdaExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.LambdaExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for LambdaExprView with syntax_node(self) {
  self.node
}

///|
/// The bound parameter name (e.g. "x" in λx. body).
pub fn LambdaExprView::param(self : LambdaExprView) -> String {
  self.node.token_text(@syntax.IdentToken.to_raw())
}

///|
/// The body expression (first interior-node child, skipping tokens).
pub fn LambdaExprView::body(self : LambdaExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub impl ToJson for LambdaExprView with to_json(self) -> Json {
  let body_json : Json = match self.body() {
    Some(b) => b.to_json()
    None => Json::null()
  }
  {
    "kind": "LambdaExpr",
    "param": self.param(),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "body": body_json,
  }
}

// ─── AppExpr ─────────────────────────────────────────────────────────────────

///|
pub struct AppExprView {
  node : @seam.SyntaxNode
}

///|
pub fn AppExprView::cast(n : @seam.SyntaxNode) -> AppExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.AppExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for AppExprView with syntax_node(self) {
  self.node
}

///|
/// The function being applied (first interior-node child).
pub fn AppExprView::func(self : AppExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
/// The first argument (second interior-node child). Covers the common n=2 case.
/// For chains like `f x y z`, use `args()` to access all arguments.
pub fn AppExprView::arg(self : AppExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
/// All argument nodes (children[1..]).
/// The grammar produces flat n-ary AppExpr nodes for chains like `f x y z`.
/// Use this method to access all arguments; `func()` gives the callee.
pub fn AppExprView::args(self : AppExprView) -> Array[@seam.SyntaxNode] {
  self.node.children_from(1)
}

///|
pub impl ToJson for AppExprView with to_json(self) -> Json {
  let func_json : Json = match self.func() {
    Some(n) => n.to_json()
    None => Json::null()
  }
  {
    "kind": "AppExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "func": func_json,
    "args": self.args().map(fn(n) { n.to_json() }),
  }
}

// ─── BinaryExpr ──────────────────────────────────────────────────────────────

///|
pub struct BinaryExprView {
  node : @seam.SyntaxNode
}

///|
pub fn BinaryExprView::cast(n : @seam.SyntaxNode) -> BinaryExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.BinaryExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for BinaryExprView with syntax_node(self) {
  self.node
}

///|
/// First operand (leftmost, nth_child(0)).
pub fn BinaryExprView::lhs(self : BinaryExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
/// Second operand (nth_child(1)). For chains like `1 + 2 + 3` the CST is
/// flat (3 operand children); use `operands()` to access all of them.
pub fn BinaryExprView::rhs(self : BinaryExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
/// All operand nodes in source order. For `1 + 2 + 3` this returns [1, 2, 3].
pub fn BinaryExprView::operands(
  self : BinaryExprView,
) -> Array[@seam.SyntaxNode] {
  self.node.children()
}

///|
/// The first operator token kind (Plus or Minus).
/// For the full operator sequence use `ops()`.
pub fn BinaryExprView::op(self : BinaryExprView) -> @ast.Bop? {
  let ops = self.ops()
  if ops.length() > 0 {
    Some(ops[0])
  } else {
    None
  }
}

///|
/// All operator kinds in source order. For `1 + 2 - 3` returns [Plus, Minus].
pub fn BinaryExprView::ops(self : BinaryExprView) -> Array[@ast.Bop] {
  let (_nodes, tokens) = self.node.nodes_and_tokens()
  let result : Array[@ast.Bop] = []
  for t in tokens {
    if t.kind() == @syntax.PlusToken.to_raw() {
      result.push(@ast.Bop::Plus)
    } else if t.kind() == @syntax.MinusToken.to_raw() {
      result.push(@ast.Bop::Minus)
    }
  }
  result
}

///|
pub impl ToJson for BinaryExprView with to_json(self) -> Json {
  let ops_json : Array[Json] = self
    .ops()
    .map(fn(op) {
      match op {
        @ast.Bop::Plus => ("+" : Json)
        @ast.Bop::Minus => ("-" : Json)
      }
    })
  {
    "kind": "BinaryExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "operands": self.operands().map(fn(n) { n.to_json() }),
    "ops": ops_json,
  }
}

// ─── IfExpr ──────────────────────────────────────────────────────────────────

///|
pub struct IfExprView {
  node : @seam.SyntaxNode
}

///|
pub fn IfExprView::cast(n : @seam.SyntaxNode) -> IfExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.IfExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for IfExprView with syntax_node(self) {
  self.node
}

///|
pub fn IfExprView::condition(self : IfExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub fn IfExprView::then_branch(self : IfExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(1)
}

///|
pub fn IfExprView::else_branch(self : IfExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(2)
}

///|
pub impl ToJson for IfExprView with to_json(self) -> Json {
  let cond_json : Json = match self.condition() {
    Some(n) => n.to_json()
    None => Json::null()
  }
  let then_json : Json = match self.then_branch() {
    Some(n) => n.to_json()
    None => Json::null()
  }
  let else_json : Json = match self.else_branch() {
    Some(n) => n.to_json()
    None => Json::null()
  }
  {
    "kind": "IfExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "condition": cond_json,
    "then": then_json,
    "else": else_json,
  }
}

// ─── ParenExpr ───────────────────────────────────────────────────────────────

///|
pub struct ParenExprView {
  node : @seam.SyntaxNode
}

///|
pub fn ParenExprView::cast(n : @seam.SyntaxNode) -> ParenExprView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.ParenExpr {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for ParenExprView with syntax_node(self) {
  self.node
}

///|
pub fn ParenExprView::inner(self : ParenExprView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub impl ToJson for ParenExprView with to_json(self) -> Json {
  let inner_json : Json = match self.inner() {
    Some(n) => n.to_json()
    None => Json::null()
  }
  {
    "kind": "ParenExpr",
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "inner": inner_json,
  }
}

// ─── IntLiteral ──────────────────────────────────────────────────────────────

///|
pub struct IntLiteralView {
  node : @seam.SyntaxNode
}

///|
pub fn IntLiteralView::cast(n : @seam.SyntaxNode) -> IntLiteralView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.IntLiteral {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for IntLiteralView with syntax_node(self) {
  self.node
}

///|
/// Parse and return the integer value. Returns None if the token text is not
/// a valid integer (should not happen in a well-formed tree).
pub fn IntLiteralView::value(self : IntLiteralView) -> Int? {
  match self.node.find_token(@syntax.IntToken.to_raw()) {
    None => None
    Some(t) => {
      let n = @strconv.parse_int(t.text()) catch { _ => return None }
      Some(n)
    }
  }
}

///|
pub impl ToJson for IntLiteralView with to_json(self) -> Json {
  let v : Int = self.value().unwrap_or(0)
  {
    "kind": "IntLiteral",
    "value": (v : Int),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
  }
}

// ─── VarRef ──────────────────────────────────────────────────────────────────

///|
pub struct VarRefView {
  node : @seam.SyntaxNode
}

///|
pub fn VarRefView::cast(n : @seam.SyntaxNode) -> VarRefView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.VarRef {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for VarRefView with syntax_node(self) {
  self.node
}

///|
pub fn VarRefView::name(self : VarRefView) -> String {
  self.node.token_text(@syntax.IdentToken.to_raw())
}

///|
pub impl ToJson for VarRefView with to_json(self) -> Json {
  {
    "kind": "VarRef",
    "name": self.name(),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
  }
}

// ─── LetDef ──────────────────────────────────────────────────────────────────

///|
pub struct LetDefView {
  node : @seam.SyntaxNode
}

///|
pub fn LetDefView::cast(n : @seam.SyntaxNode) -> LetDefView? {
  if @syntax.SyntaxKind::from_raw(n.kind()) == @syntax.LetDef {
    Some({ node: n })
  } else {
    None
  }
}

///|
pub impl @core.AstView for LetDefView with syntax_node(self) {
  self.node
}

///|
/// The binding name (first IdentToken in the node).
pub fn LetDefView::name(self : LetDefView) -> String {
  self.node.token_text(@syntax.IdentToken.to_raw())
}

///|
/// The init expression (first node child of LetDef).
pub fn LetDefView::init(self : LetDefView) -> @seam.SyntaxNode? {
  self.node.nth_child(0)
}

///|
pub impl ToJson for LetDefView with to_json(self) -> Json {
  let init_json : Json = match self.init() {
    Some(n) => n.to_json()
    None => Json::null()
  }
  {
    "kind": "LetDef",
    "name": self.name(),
    "start": (self.node.start() : Int),
    "end": (self.node.end() : Int),
    "init": init_json,
  }
}
