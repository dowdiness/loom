# Markdown typed-angle CST compatibility inventory

Issue #891 introduced the append-only compatibility surface; issues #893–#895
completed production migration. This inventory records the final package-wide
audit. `typed authority` marks the single production classification or
projection path, while `proven generic` means no language-specific update is
required.

## Registry and raw conversion

| Site | Classification | Evidence |
| --- | --- | --- |
| `examples/markdown/syntax_kind.mbt`: `SyntaxKind`, `is_token`, `ToRawKind`, `FromRawKind` | changed / proven generic | The three node variants are appended at raw kinds 42–44. `is_token` retains its existing token-only cases and node fallback. |
| `examples/markdown/token.mbt`: `Token::to_raw`, token mapping test | proven generic | No token variant was added; all existing token raw kinds remain unchanged. |
| `examples/markdown/payload_lexer/token_impls.g.mbt`, `payload_fixture/token_impls.g.mbt` | proven generic | Generated lexer token registries are independent of the Markdown CST node registry. |
| `examples/markdown/pkg.generated.mbti` | generated-interface audit | `moon info` retains the three authorized `SyntaxKind` variants with no issue-#895 interface or trait-bound drift. |

## Production text and angle ownership

| Site | Classification | Evidence |
| --- | --- | --- |
| `examples/markdown/inline_angle_semantics.mbt` classifier family | typed authority | The private classifier and delimiter index are called only by the container-local inline plan; the lexer no longer classifies complete inline-angle semantics. |
| `examples/markdown/markdown_ir_lowering.mbt`: `lower_inline_text_token` and `lower_typed_inline_angle_node` | typed authority | Generic `TextToken` lowers only as text. `UriAutolinkNode`, `EmailAutolinkNode`, and `InlineHtmlNode` project through the typed-node helper without spelling-based reclassification. |
| `examples/markdown/inline_convert.mbt`: text conversion and `convert_inline_node` | typed authority | Generic text remains text; typed nodes project through the existing adapter helper. |
| `examples/markdown/lexer.mbt`, `inline_parser.mbt`, `grammar.mbt` | changed / typed authority | Inline lexing exposes unescaped `<`, every `>`, and backtick facts while an escaped `<` remains maximal literal text. The parser's container-local plan is the sole typed emission authority; the source-wide lexer index and collapsed-token branches are removed. |
| `examples/markdown/cst_parser.mbt`, `markdown_spec.mbt` | proven generic | Parser entry points and the language metadata policy require no angle-specific API change. |

## Roles and structural CST consumers

| Site | Classification | Evidence |
| --- | --- | --- |
| `examples/markdown/roles.mbt`: token roles, link phases, recursive traversal | proven generic | Typed angle nodes have no new public role. Their existing `TextToken` children do not match a role-specific parent/token pair, so role output is unchanged. |
| `examples/markdown/roles_attachment.mbt`, role tests, `parser_test.mbt`, `block_convert.mbt` | proven generic | Traversal is through `SyntaxNode` children and existing block/token cases; unknown inline node kinds are not promoted to a role or block. |
| `examples/markdown/code_block_value.mbt`, `reference_definition.mbt`, `block_reparse.mbt`, `block_quote_inline.mbt`, `list_boundary.mbt`, `setext_policy.mbt`, `thematic_policy.mbt` | proven generic | These sites inspect block structure or selected token kinds and do not assume that all node kinds are known. |
| incremental/reference/entity/line-break/delimiter integration tests and native/parser regression tests | proven generic | They consume parser snapshots, CST text, or existing block structure and continue through the final typed production path without consumer-specific changes. |

## MarkdownIR lowering, canonicalization, and adapters

| Site | Classification | Evidence |
| --- | --- | --- |
| `examples/markdown/markdown_ir_lowering.mbt`: `lower_inline_node_with_diags` and direct-node dispatch | changed | Typed nodes lower to existing `Autolink`/`InlineHtml` variants with node and inner source origins. |
| `examples/markdown/markdown_ir.mbt` | proven generic | Existing `MarkdownIR::Autolink` and `MarkdownIR::InlineHtml` constructors/accessors already represent the target semantics. |
| `examples/markdown/markdown_ir_canonical_core.mbt`, `markdown_ir_canonical_validate.mbt` | proven generic | Canonicalization reads MarkdownIR variants, not CST kinds; typed lowering reaches the existing semantic comparison. |
| `examples/markdown/markdown_ir_adapters.mbt`, `markdown_ir_html.mbt`, `markdown_ir_format.mbt`, `markdown_ir_rewrite.mbt` | proven generic | Existing Autolink and InlineHtml adapter branches remain authoritative; no new IR variant or adapter interface exists. |
| `markdown_ir_test.mbt`, `inline_angle_semantics_wbtest.mbt`, mdast/CommonMark fixture tests | proven by regression suite | Source-faithful lexer facts, typed production nodes, and existing adapter output are covered alongside standalone typed fixtures. |

## Projection, identity, and reuse

| Site | Classification | Evidence |
| --- | --- | --- |
| `examples/markdown/markdown_projection_identity.mbt` and its whitebox tests | proven generic | Identity candidates consume MarkdownIR. Existing Autolink and InlineHtml handling remains unchanged; typed lowering therefore preserves existing semantic keys and anchor policy. |
| `examples/markdown/reactive_keyed_markdown_ir.mbt`, `markdown_projection_attachment.mbt`, attachment tests | proven generic | Keyed maps are keyed by `CstNode` and resolve existing MarkdownIR; no typed-kind-specific cache or public projection API is added. |
| `loom/core/parser_reuse.mbt`, `reuse_cursor.mbt`, parser reuse tests, `loom/core/block_reparse.mbt` | proven generic | Reuse compares opaque `RawKind`, token context, edits, and metadata policy. It does not enumerate language `SyntaxKind` values and needs no production typed emission. |
| `seam/cst_node.mbt`, `seam/cst_metadata_policy.mbt`, CST/interner/reuse tests | proven generic | `CstNode::new` validates metadata-policy compatibility independently of node-kind meaning; fixtures use the current policy API. |

## Test seam

`examples/markdown/typed_angle_cst_compatibility_wbtest.mbt` constructs
source-backed typed nodes with `CstNode::new` and a private test helper. The
helper uses the exact metadata domain produced by
`LanguageSpec::new(ErrorToken, ErrorNode, ...)`: trivia
`[ErrorToken.to_raw()]`, error `ErrorNode`, and incomplete `ErrorNode`; a test
also proves typed fixture nodes compose under that equivalent domain. These
are standalone constructed compatibility inputs, not parser output. The
fixture proves raw-kind roundtrip, exact reconstruction, typed URI/email/HTML
lowering and origins, existing role output, Block/mdast/HTML adapter behavior,
and MarkdownIR projection identity. It does not expose or access generic policy
internals: canonical policy provenance remains privately owned by
`LanguageSpec`/#896, while production composition and emission are completed by
#893–#895.

The inventory was checked with the following focused searches from the
repository root:

```sh
rg -n 'SyntaxKind|is_token|FromRawKind|ToRawKind|TextToken|classify_inline_angle|MarkdownIR|MarkdownRole|ProjectionIdentity|ReuseCursor' examples/markdown loom/core seam --glob '*.mbt' --glob '*.mbti'
```
