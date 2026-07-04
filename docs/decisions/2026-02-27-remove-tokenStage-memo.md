# ADR: Remove `TokenStage` Memo from the Incremental Pipeline

**Date:** 2026-02-27
**Status:** Accepted — **Reversed by** [2026-03-15: Reintroduce TokenStage Memo](2026-03-15-reintroduce-token-stage-memo.md), itself superseded by [2026-04-17: Unified Parser](2026-04-17-unified-parser-proposal.md)

## tl;dr

- Context: The new two-memo pipeline (@pipeline.ParserDb) was already the default. The old three-memo pipeline (@incremental.ParserDb, with TokenStage) still existed alongside it. We needed to decide whether to archive or delete it.
- Decision: Delete @incremental.ParserDb and TokenStage. Migrate all callers to @lambda.LambdaParserDb.
- Rationale: TokenStage backdating never fires for a whitespace-inclusive lexer.
- Consequences: Overall architecture is simplified, reducing overhead and getting better performance.

## The three-memo pipeline vs The two-memo pipeline

In the old pipeline there were three memos:

```
Signal[String] → Memo[TokenStage] → Memo[CstStage] → Memo[AstNode]
```

The new two-memo pipeline removes TokenStage entirely:

```
Signal[String] → Memo[CstStage] → Memo[AstNode]
```

## TokenStage is always redundant for this lexer

1. The lexer emits Whitespace tokens — whitespace is part of the token stream.
2. Any source change shifts token positions, producing a different TokenStage.
3. The only source change that produces equal TokenStage is the same string.
4. The Signal already handles that case before any memo runs.

## Why no TokenStage?

TokenStage adds a staleness check on every warm call. But it never provides backdating — the only source change that produces equal TokenStage is the same string, and Signal::Eq already handles that before any memo runs. TokenStage is therefore pure overhead.
