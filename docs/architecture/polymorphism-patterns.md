# Polymorphism Patterns in MoonBit

How to choose between the four polymorphism tools used in this codebase.

---

## The Four Tools

### 1. Generic function with trait bound — "same algorithm, different types"

Use when: the concrete type is known at the call site, and you want the compiler
to specialize the code.

```moonbit
trait Printable {
  print(Self) -> String
}

fn print_twice[T : Printable](x : T) -> String {
  T::print(x) + T::print(x)
}
```

The compiler **monomorphizes** — generates a separate copy for each concrete `T`.
No runtime overhead, but the concrete type cannot be hidden from callers.

**In this codebase:** `parse_tokens_indexed[T, K]` in `@core`. Both `T` (token
type) and `K` (syntax kind) are visible in the signature. Lambda-specific types
flow through at compile time.

---

### 2. Trait object `&Trait` — "hide the concrete type, share one code path"

Use when: you have *multiple concrete types at runtime* and want to treat them
uniformly (e.g., a heterogeneous collection).

```moonbit
trait Animal {
  speak(Self) -> String  // Self = first param, appears once — object-safe
}

let zoo : Array[&Animal] = [duck as &Animal, fox as &Animal]
for a in zoo { println(Animal::speak(a)) }
```

**Object-safety rule:** `Self` must be the first parameter and appear only once.
Methods that return `Self` or take two `Self` parameters are not object-safe.

**Limitation:** MoonBit trait objects have no associated-type syntax, so
`&IncrementalLang[AstNode]` (fixing a type parameter on the trait object) is not
supported. Also, trait objects do not directly support closures that capture
mutable state.

---

### 3. Struct-of-closures (manual vtable) — "erase specific types while keeping others"

Use when:
- You need **selective type erasure** (erase `T`, keep `Ast` visible in the struct)
- The "methods" need **captured mutable state** (closures close over `Ref` values)
- You want to **store the vtable in a struct field** without leaking token types

**Primary API — `Grammar[T,K,Ast]` (src/bridge/grammar.mbt):**

```moonbit
pub struct Grammar[T, K, Ast] {
  spec      : @core.LanguageSpec[T, K]
  tokenize  : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  to_ast    : (@seam.SyntaxNode) -> Ast
}
```

Grammar authors supply only those three things. Bridge factories erase `T`/`K`
internally and produce fully-generic consumers:

```moonbit
// src/examples/lambda/grammar.mbt
pub let lambda_grammar : @bridge.Grammar[...] = @bridge.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { syntax_node_to_ast_node(s, Ref::new(0)) },
)

// Call sites — token type never mentioned again
let parser = @bridge.new_imperative_parser(source, lambda_grammar)
let p      = @bridge.new_parser(source, lambda_grammar)
```

**Escape hatch — `ImperativeLanguage[Ast]` / `Language[Ast]`:**

```moonbit
// src/incremental/incremental_language.mbt
pub struct ImperativeLanguage[Ast] {
  priv full_parse        : (String, ...) -> ParseOutcome
  priv incremental_parse : (String, ...) -> ParseOutcome
  priv to_ast            : (@seam.SyntaxNode) -> Ast
  priv on_lex_error      : (String) -> Ast
}
```

Construct these directly (via `Language::from_closures` / `ImperativeLanguage::new`)
only when you need to customise TokenBuffer lifecycle, lex-error handling, or diagnostic
formatting beyond what the bridge factories provide.

`ImperativeParser[Ast]` is fully generic — it stores `ImperativeLanguage[Ast]`
without ever knowing what `T` or `K` are.

---

### 4. Defunctionalization — "make the function a value you can inspect"

Use when: you want to replace a closure with a **data variant** — an enum case
that can be matched, compared, serialized, or logged.

The core idea: instead of passing `fn(x) -> y`, pass a tag (`enum Fn`) plus a
separate `apply` function that dispatches on it.

```moonbit
// Before: closure (opaque — you can call it but not inspect it)
let f : (Int) -> Int = x => x + 1

// After: defunctionalized (transparent — you can match on it)
enum IntTransform {
  AddOne
  Double
  AddN(Int)
}

fn apply(f : IntTransform, x : Int) -> Int {
  match f {
    AddOne   => x + 1
    Double   => x * 2
    AddN(n)  => x + n
  }
}
```

**Concrete example: named error recovery strategies**

Instead of scattering `ctx.emit_error_placeholder()` inline, you could name the
strategies so they can be logged or compared:

```moonbit
enum Recovery {
  Placeholder        // emit an error node, keep position
  SkipUntilSync      // consume tokens until a stop token
}

fn apply_recovery[T, K](
  strategy : Recovery,
  ctx : @core.ParserContext[T, K],
) -> Unit {
  match strategy {
    Placeholder   => ctx.emit_error_placeholder()
    SkipUntilSync =>
      while not(at_stop_token(ctx)) {
        ctx.bump_error()
      }
  }
}
```

Now `Recovery` is a value — you can log `"used SkipUntilSync at position 11"`,
persist it, or compare two parsers' strategies. A closure cannot do any of this.

**Why defunctionalization does not fit `LanguageSpec.parse_root`**

If `LanguageSpec` stored `enum Grammar { Lambda }` instead of a closure, `@core`
would have to import `@lambda` to dispatch on `Lambda`. That reverses the
dependency arrow:

```
Closure approach (current):        Defunctionalized (breaks layering):
  @lambda → @core                    @core → @lambda  ✗
  (dependency flows outward)         (dependency flows inward)
```

Closures keep `@core` generic by letting `@lambda` push behavior inward at
construction time.

---

## Decision Guide

```
Do you need to store the polymorphic value in a struct field
without the concrete type leaking into the struct's signature?
│
├─ No → Can you list all concrete types at compile time?
│       │
│       ├─ Yes → Generic function [T : Trait]
│       └─ No  → Trait object &Trait  (⚠ object-safety rules apply)
│
└─ Yes → Do you need to inspect, compare, or serialize the behavior?
          │
          ├─ Yes, and the caller CAN know all cases
          │         → Defunctionalization (enum + apply)
          │
          ├─ Yes, but caller must NOT know concrete cases
          │         → Struct-of-closures + a description field (String/tag)
          │
          └─ No  → Does the closure need mutable captured state?
                    ├─ Yes → Struct-of-closures (Ref for mutable captures)
                    └─ No  → Trait object if object-safe, else struct-of-closures
```

---

## Summary Table

| | Generic `[T:Trait]` | Trait object `&Trait` | Struct-of-closures | Defunctionalization |
|---|---|---|---|---|
| Type visible to caller | Yes | No | Selectively | Yes (enum tag) |
| Inspectable / serializable | No | No | No | **Yes** |
| Mutable captured state | No | No | **Yes** (`Ref`) | No (data only) |
| Caller must enumerate all cases | No | No | No | **Yes** |
| Store in struct field without leaking type | No | Yes | Yes | Yes |
| Can reverse dependency arrow? | No | No | No | **Yes — check layers** |

---

## Where Each Pattern Appears in This Codebase

| Pattern | Location | What is abstracted |
|---|---|---|
| Generic `[T, K]` | `@core.parse_tokens_indexed` | token type + kind type |
| Generic `[Ast]` | `@incremental.ImperativeParser` | AST output type |
| Struct-of-closures | `@bridge.Grammar[T,K,Ast]` + bridge factories | token/kind types erased by factory; `Grammar` is the grammar-author API |
| Struct-of-closures | `@incremental.ImperativeLanguage[Ast]` | token type (erased into closures) — used internally by bridge, escape hatch for custom wiring |
| Struct-of-closures | `@core.LanguageSpec[T, K]` | grammar entry point + token predicates |
| Defunctionalization | (not used — would break `@core` ↔ `@lambda` layering) | — |
