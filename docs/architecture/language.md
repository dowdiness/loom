# Lambda Calculus Language Reference

A description of the example language syntax, grammar, operator precedence, and core data types for the Lambda parser.

## Basic Elements

```
Integer    ::= [0-9]+
Identifier ::= [a-zA-Z][a-zA-Z0-9]*
ParamList  ::= '(' Identifier (',' Identifier)* ')'
```

The current surface syntax uses MoonBit-style declarations and arrows:

- `let name = expr` for value declarations
- `fn name(params) { body }` for named function declarations
- `(params) => expr` and `(params) => { body }` for anonymous functions

Legacy `λ` and `\` tokens are still lexed for diagnostics, but they no longer denote lambda abstraction in the parser.

## Grammar

```
SourceFile  ::= Definition* Expression?
Definition  ::= 'let' Identifier '=' Expression
              | 'fn' Identifier ParamList Block

Expression  ::= BinaryOp
BinaryOp    ::= Application (('+' | '-') Application)*
Application ::= Atom Atom*

Atom        ::= Integer
              | Identifier
              | ParamList '=>' Expression
              | ParamList '=>' Block
              | 'if' Expression 'then' Expression 'else' Expression
              | '(' Expression ')'
              | Block
              | '_'

Block       ::= '{' Definition* Expression? '}'
```

Function declarations require brace-delimited bodies, which gives the incremental parser a stable right boundary for block reparse. Anonymous arrows may use either a single-expression body or a brace-delimited block body.

## Operator Precedence (lowest to highest)

1. Conditional expressions (`if … then … else …`)
2. Anonymous arrow lambdas (`(x) => body`) — body extends to the parsed expression or block
3. Binary operators (`+`, `-`) — left associative
4. Function application — left associative
5. Atomic expressions — literals, variables, parenthesized expressions, blocks, holes

## Data Types

### Token

`Token` represents lexical units produced by the lexer from source text:

```moonbit
pub enum Token {
  Lambda        // legacy λ or \; lexed for diagnostics only
  Dot           // legacy . token
  LeftParen     // (
  RightParen    // )
  Plus          // +
  Minus         // -
  If            // if
  Then          // then
  Else          // else
  Fn            // fn
  Let           // let
  Eq            // =
  LBrace        // {
  RBrace        // }
  Comma         // ,
  Semicolon     // ;
  Colon         // :
  Arrow         // ->
  FatArrow      // =>
  Hole          // _
  Identifier    // variable names
  Integer       // integer literals
  Whitespace
  Newline
  Error(String)
  EOF
}
```

### Term

`Term` represents parsed expressions as a semantic AST. Position information is not stored here — it lives in the CST/SyntaxNode layer.

```moonbit
pub enum Bop {
  Plus
  Minus
}

pub enum Term {
  Int(Int)                 // Integer literal
  Var(VarName)            // Variable
  Lam(VarName, Term)      // Lambda abstraction; multi-params lower to nested Lam
  App(Term, Term)         // Function application
  Bop(Bop, Term, Term)    // Binary operation
  If(Term, Term, Term)    // Conditional expression
  LetDef(VarName, Term)   // Projection/display wrapper for a binding row
  Module(Array[(VarName, Term)], Term) // Definitions plus trailing expression
  Unit                    // Empty/definition-only source result
  Unbound(VarName)        // Name-resolution diagnostic term
  Error(String)           // Parse/projection error term
  Hole(Int)               // Placeholder term
}
```

`VarName` is an alias for `String` used to distinguish variable names from other strings.

## Examples

| Source text | `Term` representation |
|---|---|
| `(x) => x` | `Lam("x", Var("x"))` |
| `(f, x) => f (f x)` | `Lam("f", Lam("x", App(Var("f"), App(Var("f"), Var("x")))))` |
| `fn id(x) { x }` | module definition whose init lowers to `Lam("x", Var("x"))` |
| `1 + 2` | `Bop(Plus, Int(1), Int(2))` |
| `f x` | `App(Var("f"), Var("x"))` |
| `if x then y else z` | `If(Var("x"), Var("y"), Var("z"))` |
| `(x) => { let y = x; y }` | `Lam("x", Module([("y", Var("x"))], Var("y")))` |

## Error Types

### TokenizationError

Raised when the lexer encounters an invalid character or encoding issue.

```moonbit
pub suberror TokenizationError String
```

### ParseError

Raised when the parser encounters unexpected tokens or malformed syntax.

```moonbit
pub suberror ParseError (String, Token)
```

The tuple carries a human-readable message and the offending token.
