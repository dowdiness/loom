# Advanced E-Graph Topics

> **Prerequisite:** Read the [Introduction](../introduction.md) first.

These documents cover advanced usage patterns, design guidance, and troubleshooting for the e-graph library.

## Topics

| Document | Summary |
|----------|---------|
| [E-Graph-Ready IR](egraph-ready-ir.md) | Transforming source languages into pure, tree-shaped IR suitable for e-graph optimization |
| [Conditional Rewrites](conditional-rewrites.md) | Rewrite rules that only fire when a predicate holds |
| [Analysis-Driven Rewrites](analysis-driven-rewrites.md) | Using e-class analysis (constant folding, type inference) to drive optimization |
| [Controlling E-Graph Growth](controlling-growth.md) | Strategies for managing combinatorial explosion |
| [Custom Cost Functions](custom-cost-functions.md) | Designing extraction cost functions beyond `ast_size` |
| [Multi-Language Patterns](multi-language-patterns.md) | Designing `ENode`/`ENodeRepr` for SQL, tensors, lambda calculus, and other domains |
| [Debugging E-Graphs](debugging-egraphs.md) | Troubleshooting rewrites, inspecting state, and common mistakes |
