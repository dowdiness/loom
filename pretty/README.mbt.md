# Pretty

A Wadler-Lindig pretty-printer for MoonBit. Build a document that describes
both flat and broken layouts, then let the engine choose based on available width.

## Install

Add the dependency to your `moon.mod.json`:

```json
{
  "deps": {
    "dowdiness/pretty": "0.1.0"
  }
}
```

Import in your package (`moon.pkg` or `moon.pkg.json`):

```
import {
  "dowdiness/pretty" @pretty,
}
```

Then use as `@pretty.text(...)`, `@pretty.group(...)`, `@pretty.render_string(...)`, etc.

To use combinators without the `@pretty.` prefix, add a `using` declaration in your
`.mbt` file:

```mbt nocheck
///|
using @pretty {
  text,
  char,
  line,
  hardline,
  softline,
  nest,
  group,
  concat,
  annotate,
  separate,
  surround,
  parens,
  brackets,
  braces,
  bracket,
  render_string,
  render_spans,
  resolve,
  pretty_print,
  pretty_spans,
  type Layout,
  type Cmd,
  type SyntaxCategory,
  type Span,
  Keyword,
  Identifier,
  Number,
  StringLit,
  Operator,
  Punctuation,
  Comment,
  Error,
}
```

All examples below use bare names assuming this `using` declaration.

## Core Concepts

The key idea: you build **one document** that encodes **two layouts** simultaneously
— flat (single-line) and broken (multi-line). The engine picks which one to use
based on available width.

### `line()` — the choice point

`line()` represents a **potential break**. It becomes a space when rendered flat,
or a newline (plus indentation) when broken:

```
flat mode:   line()  →  " "
broken mode: line()  →  "\n" + indent
```

### `group(doc)` — the decision maker

`group` tries to render its content flat. If it fits within the remaining line
width (including what comes after), it stays flat. Otherwise it breaks:

```mbt check
///|
test "group + line flat" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect(render_string(doc, width=80), content="a b")
}

///|
test "group + line break" {
  let doc : Layout[Unit] = group(text("a") + line() + text("b"))
  inspect(
    render_string(doc, width=2),
    content=(
      #|a
      #|b
    ),
  )
}
```

Nested groups make **independent** decisions — an inner group can stay flat even
when an outer group breaks.

### `nest(doc)` — indentation after breaks

`nest` increases indentation for line breaks inside `doc`. Only affects broken
mode — in flat mode, there are no line breaks to indent:

```mbt check
///|
test "nest in group flat" {
  let doc : Layout[Unit] = group(
    text("f(") + nest(line() + text("x")) + line() + text(")"),
  )
  inspect(render_string(doc, width=80), content="f( x )")
}

///|
test "nest in group break" {
  let doc : Layout[Unit] = group(
    text("f(") + nest(line() + text("x")) + line() + text(")"),
  )
  inspect(
    render_string(doc, width=2),
    content=(
      #|f(
      #|  x
      #|)
    ),
  )
}
```

Default indent is 2 spaces. Override with `nest(doc, indent=4)`.

### `hardline()` — unconditional break

Always produces a newline regardless of mode. Forces any enclosing group to break.
Use for constructs that must be on separate lines (e.g., top-level definitions).

### `line()` outside `group` is always a newline

The top level starts in Break mode. A bare `line()` not inside any `group`
always produces a newline regardless of width:

```mbt check
///|
test "line outside group is always newline" {
  let doc : Layout[Unit] = text("a") + line() + text("b")
  inspect(
    render_string(doc, width=80),
    content=(
      #|a
      #|b
    ),
  )
}
```

Wrap in `group(...)` to enable the flat/break choice.

### Suffix awareness

Groups consider not just their own width but also trailing content on the same line.
`group("a b") + "c"` at width 3: the group's flat width is 3, plus suffix "c" is 1,
total 4 > 3, so the group breaks even though it alone would fit.

## Example: Pretty-Printing a List

The `bracket` combinator handles the common pattern of delimited, indented content.

Wide output — everything fits on one line.
Narrow output — breaks with indentation:

```mbt check
///|
test "bracket flat" {
  let items : Layout[Unit] = separate(text(",") + line(), [
    text("1"),
    text("2"),
    text("3"),
  ])
  let doc = bracket("[", "]", items)
  inspect(render_string(doc, width=80), content="[ 1, 2, 3 ]")
}

///|
test "bracket break" {
  let items : Layout[Unit] = separate(text(",") + line(), [
    text("1"),
    text("2"),
    text("3"),
  ])
  let doc = bracket("[", "]", items)
  inspect(
    render_string(doc, width=5),
    content=(
      #|[
      #|  1,
      #|  2,
      #|  3
      #|]
    ),
  )
}
```

Nesting composes naturally:

```mbt check
///|
test "nested brackets flat" {
  let inner : Layout[Unit] = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("a"), text("b")]),
  )
  let outer = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("x"), inner, text("y")]),
  )
  inspect(render_string(outer, width=80), content="[ x, [ a, b ], y ]")
}

///|
test "nested brackets break" {
  let inner : Layout[Unit] = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("a"), text("b")]),
  )
  let outer = bracket(
    "[",
    "]",
    separate(text(",") + line(), [text("x"), inner, text("y")]),
  )
  inspect(
    render_string(outer, width=10),
    content=(
      #|[
      #|  x,
      #|  [
      #|    a,
      #|    b
      #|  ],
      #|  y
      #|]
    ),
  )
}
```

## Annotations

`Layout[A]` is generic over an annotation type `A`. Annotations attach semantic
metadata to document regions without affecting layout decisions.

**If you just want formatted text**, ignore annotations — use `Layout[Unit]`:

```mbt check
///|
test "Layout[Unit] hello world" {
  let doc : Layout[Unit] = group(text("hello") + line() + text("world"))
  inspect(render_string(doc), content="hello world")
}
```

**For syntax highlighting**, use `Layout[SyntaxCategory]`:

```mbt check
///|
test "annotated render_string ignores annotations" {
  let doc = annotate(@pretty.Keyword, text("let")) +
    text(" ") +
    annotate(@pretty.Identifier, text("x"))
  inspect(render_string(doc), content="let x")
}

///|
test "annotated render_spans" {
  let doc = annotate(@pretty.Keyword, text("let")) +
    text(" ") +
    annotate(@pretty.Identifier, text("x"))
  inspect(
    render_spans(doc),
    content="[({start: 0, end: 3}, Keyword), ({start: 4, end: 5}, Identifier)]",
  )
}
```

**For custom metadata**, use any type as `A`:

```moonbit nocheck
let doc = annotate(my_node_id, text("expr"))
render_spans(doc)  // [({start: 0, end: 4}, my_node_id)]
```

`render_string` ignores all annotations. `render_spans` collects them as
`Array[(Span, A)]` where `Span` offsets match `String::length()` semantics
(UTF-16 code units) in the string that `render_string` would produce.

Annotations nest correctly — inner spans close before outer spans.

Note: `render_spans` on `Layout[Unit]` always returns `[]` — there are no
annotations to collect. Use `render_string` if you don't need span information.

```mbt check
///|
test "render_spans on Layout[Unit] returns empty" {
  let doc : Layout[Unit] = group(text("hello") + line() + text("world"))
  inspect(render_spans(doc), content="[]")
}
```

## Traits

The package provides three `pub(open)` traits for types that have text
representations. Any package can implement these for its own types:

| Trait | Method | Purpose |
|-------|--------|---------|
| `Source` | `to_source(Self) -> String` | Compact parseable text that roundtrips through a parser |
| `Pretty` | `to_layout(Self) -> Layout[SyntaxCategory]` | Width-aware formatted layout with syntax annotations |
| `Printable` | (extends Show + Debug + Source + Pretty) | All four representations in one |

**`Pretty`** is the main one. Types implementing it get two convenience functions:

```moonbit nocheck
pretty_print(value, width=80)  // -> String
pretty_spans(value, width=80)  // -> Array[(Span, SyntaxCategory)]
```

**`Source`** is for compact, machine-parseable output — no extra whitespace, no
annotations. Implementors should maintain the roundtrip invariant
`parse(to_source(term)) == term`, but the trait itself does not enforce it.

**`Printable`** bundles all four: `Show` (human-readable), `Debug` (constructor-style),
`Source` (parseable), `Pretty` (formatted). Use when a type needs all representations.

### End-to-end example

Define layout builders for expressions, then render at different widths:

```mbt check
///|
test "end-to-end Expr pretty-print flat" {
  fn expr_lit(n : Int) -> Layout[@pretty.SyntaxCategory] {
    annotate(@pretty.Number, text(n.to_string()))
  }
  fn expr_add(
    l : Layout[@pretty.SyntaxCategory],
    r : Layout[@pretty.SyntaxCategory],
  ) -> Layout[@pretty.SyntaxCategory] {
    group(
      l + text(" ") + annotate(@pretty.Operator, text("+")) + nest(line() + r),
    )
  }
  let expr = expr_add(expr_lit(1), expr_add(expr_lit(2), expr_lit(3)))
  inspect(render_string(expr, width=80), content="1 + 2 + 3")
}

///|
test "end-to-end Expr pretty-print break" {
  fn expr_lit(n : Int) -> Layout[@pretty.SyntaxCategory] {
    annotate(@pretty.Number, text(n.to_string()))
  }
  fn expr_add(
    l : Layout[@pretty.SyntaxCategory],
    r : Layout[@pretty.SyntaxCategory],
  ) -> Layout[@pretty.SyntaxCategory] {
    group(
      l + text(" ") + annotate(@pretty.Operator, text("+")) + nest(line() + r),
    )
  }
  let expr = expr_add(expr_lit(1), expr_add(expr_lit(2), expr_lit(3)))
  inspect(
    render_string(expr, width=5),
    content=(
      #|1 +
      #|  2 +
      #|    3
    ),
  )
}
```

## API Reference

### Layout Constructors

| Function | Description |
|----------|-------------|
| `text(s)` | Literal text (must not contain newlines) |
| `char(c)` | Single character |
| `line()` | Space when flat, newline + indent when broken |
| `hardline()` | Always newline; forces enclosing group to break |
| `softline()` | A line break that decides independently whether to flatten (`group(line())`) |

### Combinators

| Function | Description |
|----------|-------------|
| `group(doc)` | Try flat; break if content + trailing suffix exceeds width |
| `nest(doc, indent=N)` | Increase indent for line breaks (default 2) |
| `concat(l, r)` / `l + r` | Sequential composition |
| `annotate(ann, doc)` | Attach metadata (transparent to layout) |
| `separate(sep, docs)` | Join with separator: `a sep b sep c` (empty array → `Empty`) |
| `surround(l, r, doc)` | Wrap: `l + doc + r` |
| `parens(doc)` | `(doc)` |
| `brackets(doc)` | `[doc]` |
| `braces(doc)` | `{doc}` |
| `bracket(l, r, doc)` | Indented block: flat `[ x, y ]`, broken `[\n  x,\n  y\n]`, empty `[]` |

### Renderers

| Function | Returns | Description |
|----------|---------|-------------|
| `resolve(width, layout)` | `Array[Cmd[A]]` | Layout resolution — intermediate command stream |
| `render_string(layout, width=N)` | `String` | Plain text (ignores annotations, default width 80) |
| `render_spans(layout, width=N)` | `Array[(Span, A)]` | Annotated spans (offsets into rendered string, default width 80) |

### Types

| Type | Description |
|------|-------------|
| `Layout[A]` | Document tree (build via combinators, not constructors): Empty, Text, Line, HardLine, Nest, Concat, Group, Annotate |
| `Cmd[A]` | Command stream: CText, CNewline, CAnnStart, CAnnEnd |
| `SyntaxCategory` | Keyword, Identifier, Number, StringLit, Operator, Punctuation, Comment, Error |
| `Span` | `{ start: Int, end: Int }` — offsets in rendered output (UTF-16 code units, matching `String::length()`) |

## Algorithm

Wadler-Lindig with suffix-aware group flattening. The `resolve` function walks the
`Layout` tree, greedily deciding each `Group`'s mode: if `flat_width(group) +
suffix_width` fits in the remaining line width, choose flat; otherwise break.

Algebraic properties verified by property-based tests:
- No output line exceeds target width (unless forced by an indivisible token)
- `group` is idempotent: `group(group(doc))` = `group(doc)`
- `Empty` is identity for `+`: `Empty + doc` = `doc` = `doc + Empty`
- `flat_width` matches actual flat rendering width
- Wider target width never produces wider output lines
- `render_string` and `render_spans` share consistent offset coordinates

Designed for future extension toward Πe (Porncharoenwase et al., OOPSLA 2023) via
a `Choice` constructor and pluggable cost factory.

## References

- Wadler, "A prettier printer" (1998)
- Porncharoenwase, Pombrio, Torlak, "A Pretty Expressive Printer" (OOPSLA 2023)

## License

Apache-2.0
