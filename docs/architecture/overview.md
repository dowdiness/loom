# Architecture Overview

See also: [pipeline](pipeline.md) | [seam model](seam-model.md) | [generic parser](generic-parser.md)

## Layer Diagram

```
                        +-----------------------+
                        |     Edit Protocol     |
                        |  (apply, get_tree)    |
                        +-----------+-----------+
                                    |
                        +-----------v-----------+
                        |   Incremental Engine  |
                        |   - Damage tracking   |
                        |   - Reuse decisions   |
                        |   - Orchestration     |
                        +-----------+-----------+
                                    |
                  +-----------------+------------------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |  Incremental Lexer  |            |  Incremental Parser   |
       |  - Token buffer     |            |  - Subtree reuse at   |
       |  - Edit-aware       |            |    grammar boundaries |
       |  - Only re-lex      |            |  - Checkpoint-based   |
       |    damaged region   |            |    validation         |
       +----------+----------+            +-----------+-----------+
                  |                                    |
       +----------v----------+            +-----------v-----------+
       |    Token Buffer     |            |   Green Tree (CST)    |
       |  - Contiguous array |            |  - Immutable nodes    |
       |  - Position-tracked |            |  - Structural sharing |
       |  - Cheaply sliceable|            |  - Lossless syntax    |
       +---------------------+            +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Red Tree (Facade)   |
                                          |  - Absolute positions |
                                          |  - Parent pointers    |
                                          |  - On-demand          |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Typed AST (Lazy)    |
                                          |  - Semantic analysis  |
                                          |  - Derived from CST   |
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Error Recovery      |
                                          |  - Integrated in      |
                                          |    parser loop        |
                                          |  - Sync point based   |
                                          |  - Multiple errors    |
                                          +-----------------------+
```

## Module Layout

The implementation is split across four MoonBit modules:

- **`dowdiness/seam`** (`seam/`) — language-agnostic CST: `CstNode`, `SyntaxNode`, `EventBuffer`
- **`dowdiness/incr`** (`incr/`) — reactive signals: `Signal`, `Memo`
- **`dowdiness/loom`** (`loom/`) — generic parser framework: `core`, `pipeline`, `incremental`, `viz`; root exports `Grammar`, `new_imperative_parser`, `new_reactive_parser`
- **`dowdiness/lambda`** (`examples/lambda/`) — lambda calculus example: tokenizer, grammar, AST, benchmarks

`loom` depends on `seam` and `incr`. `dowdiness/lambda` depends on `loom` and `seam` via path deps.

## Architectural Principles

1. **No dead infrastructure.** Every cache, buffer, and data structure must be read by something during the parse pipeline. If it's not read, it doesn't exist.

2. **Immutability enables sharing.** Green tree nodes are immutable. When nothing changed, the old node IS the new node - not a copy, the same pointer. This is the foundation of incremental reuse.

3. **Separation of structure and position.** Green tree nodes store widths (relative sizes). Red tree nodes compute absolute positions on demand. This means structural identity is independent of position - moving a subtree doesn't invalidate it.

4. **Incremental lexing is the first real win.** Re-tokenizing only the damaged region, then splicing into the existing token buffer, gives the parser unchanged tokens for free.

5. **Subtree reuse at grammar boundaries.** Recursive descent can't validate arbitrary nodes like LR parsers, but it CAN check: "at this grammar boundary, does the old subtree's kind match, and are both the leading and trailing token contexts unchanged?" If all checks pass, skip parsing and reuse. The trailing context check is essential because a node's parse can depend on what follows it (see Phase 4, section 4.2.1).

6. **Error recovery is part of the parser, not around it.** The parser must be able to record an error, synchronize to a known point, and continue parsing the rest of the input.
