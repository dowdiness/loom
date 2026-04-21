# dowdiness/pretty

A Wadler-Lindig pretty-printer for MoonBit. Build one document that
encodes both flat and broken layouts; the engine picks based on
available width.

Generic over an annotation type `A` — `Layout[Unit]` for plain text,
`Layout[SyntaxCategory]` for syntax highlighting, or any custom type
for metadata.

> The canonical, doctested documentation is [`README.mbt.md`](README.mbt.md)
> — it runs under `moon test`. This file is a brief landing for GitHub.

## Install

```json
{
  "deps": {
    "dowdiness/pretty": "0.1.0"
  }
}
```

## Quick Start

```moonbit
using @pretty { text, line, group, bracket, separate, render_string, type Layout }

let items : Layout[Unit] = separate(text(",") + line(), [
  text("1"), text("2"), text("3"),
])
let doc = bracket("[", "]", items)

render_string(doc, width=80)   // "[ 1, 2, 3 ]"
render_string(doc, width=5)    // "[\n  1,\n  2,\n  3\n]"
```

## Core API

- **Constructors:** `text`, `char`, `line`, `hardline`, `softline`
- **Combinators:** `group`, `nest`, `concat` (`+`), `annotate`,
  `separate`, `surround`, `parens`, `brackets`, `braces`, `bracket`
- **Renderers:** `render_string`, `render_spans`, `resolve`
- **Traits:** `Source`, `Pretty`, `Printable` — implement `Pretty` to
  get `pretty_print(value, width=80)` and `pretty_spans(value,
  width=80)` for free
- **Types:** `Layout[A]`, `Cmd[A]`, `Span`, `SyntaxCategory`

Full signatures: [`pkg.generated.mbti`](pkg.generated.mbti).

## When to Read the Full Tutorial

See [`README.mbt.md`](README.mbt.md) for:

- The `group` / `line` / `nest` / `hardline` semantics and the
  suffix-aware flattening rule
- `Layout[A]` annotations and `render_spans` for syntax highlighting
- The `Source` / `Pretty` / `Printable` trait hierarchy
- Worked end-to-end expression pretty-printer
- Algebraic properties verified by the property tests
- References (Wadler 1998, Porncharoenwase et al. OOPSLA 2023)

## Used In

- [`examples/json`](../examples/json/) — `JsonValue` implements
  `@pretty.Pretty`, `@pretty.Printable`, `@pretty.Source`

## Running

```bash
cd pretty
moon check && moon test    # includes doctest runs from README.mbt.md
```

## License

Apache-2.0.
