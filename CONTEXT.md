# Loom Core

Vocabulary for Loom's parser-core ownership and CST metadata boundaries.

## Language

**CST metadata policy**:
The immutable classification contract under which a CST node's cached metadata
is valid. Equivalent policies have the same trivia kind set and the same
role-specific error and incomplete kinds; they may be created independently
and still belong to the same metadata domain. Its semantic hash is fixed when
the policy is created. Policy compatibility is observed through successful CST
composition, not through a caller-facing comparison interface.
_Avoid_: Classifier options, metadata arguments

**Metadata domain**:
The equivalence class defined only by CST metadata classification semantics.
It is not a language, grammar, or syntax-kind namespace: unrelated languages
with equal classification policies belong to the same metadata domain.
_Avoid_: Language identity, grammar brand

**Trivia kind set**:
The unordered set of token kinds classified as trivia by a CST metadata policy.
Declaration order and duplicate entries have no meaning in this set.
_Avoid_: Trivia kind list, trivia priority

**Metadata classification axes**:
Trivia membership governs semantic token counting, while error and incomplete
roles govern whether a subtree is problem-bearing. These axes are independent,
so one token kind may participate in both.
_Avoid_: Classification precedence, exclusive token category

**Unclassified policy**:
The shared CST metadata policy with no trivia, error, or incomplete
classification. It is the explicit metadata domain for language-agnostic CSTs.
_Avoid_: Default policy, missing policy

**CST structural equality**:
Position-independent, collision-safe equality of a node's metadata policy,
kind, and children. A cached hash may reject unequal nodes quickly but is not
an identity or a public value.
_Avoid_: Hash equality, stable node ID

**CST hash contribution**:
The process-local collection hash supplied for a CST node. Equal nodes supply
equal contributions and collisions are resolved by structural equality, but
the numeric contribution is not a persistent fingerprint or a cross-version
identifier.
_Avoid_: Structural ID, serialized node hash

**Policy mismatch**:
An attempt to compose CST nodes from different metadata domains. The attempted
parent or reconstruction is rejected before a new node becomes observable or
a caller-supplied interner is mutated.
_Avoid_: Parse error, policy conversion

## Markdown

**Parser snapshot**:
A coherent source, CST/syntax, and diagnostic view produced by one parser
revision. These values must not be combined from independently changing reads.
_Avoid_: Parser state, operation

**Source-bound document**:
The read-only representation that keeps a source snapshot, its syntax snapshot,
and its diagnostics together so source-aware consumers cannot pair semantic data
with unrelated source text.
_Avoid_: Source/IR pair, document wrapper

**Semantic read**:
An owning, detached read of a source-bound document that captures one coherent
parser snapshot and lowers its MarkdownIR exactly once when the read is
created. Multiple target adapters may consume the same read, and it remains
valid after the originating document or parser lifecycle ends. Source-aware
target selection comes from read-bound semantic nodes and selections, not from
free origins.
_Avoid_: Semantic operation, per-target lowering, borrowed read, free origin

**Read-bound semantic node**:
An opaque node view produced by one semantic read. It retains that read's
ownership while allowing source-aware consumers to navigate semantic children
and request a bound selection.
_Avoid_: MarkdownIR node, raw semantic node

**Semantic selection**:
An opaque source-aware rewrite target produced by a read-bound semantic node. It
retains the owning semantic read and cannot be constructed from a
`MarkdownIROrigin` value.
_Avoid_: Target origin, free origin

**Source-aware IR-backed Block adapter**:
The existing compatibility projection that combines MarkdownIR with the exact
source context needed to preserve the established `Block` / `Inline` behavior.
_Avoid_: Document projection

**IR-only target**:
A semantic target whose result requires MarkdownIR but no concrete source facts,
such as source spelling or exact source positions.
_Avoid_: Source-preserving target

**Document-backed target**:
A target that requires both semantic meaning and concrete facts from the same
source-bound document, such as legacy Block projection or source-preserving
rewrite.
_Avoid_: IR-only target
