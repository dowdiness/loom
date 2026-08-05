# ADR: Core collection ownership boundary

**Date:** 2026-08-05
**Status:** Proposed
**Implementation plan:** [Core collection ownership migration](../plans/2026-08-05-core-collection-ownership-migration.md)
**Issue:** [#783](https://github.com/dowdiness/loom/issues/783)

## Context

Loom treats CST nodes and lexer results as validated values. That contract is
not currently enforceable because several of those values either retain an
input `Array` or expose an owned `Array` through a public field.

The highest-risk case is `CstNode`. It caches text length, structural hash,
non-trivia token count, and error presence while exposing its mutable child
array. Mutating a retained constructor input or a public field can make the
cached metadata disagree with the tree.

Reconstruction compounds the problem. Its optional trivia, error, and
incomplete classifiers allow a caller to rebuild a classified subtree as an
unclassified one accidentally.

`LexResult` validates parallel token and start arrays and then stores the input
arrays directly. `TokenBuffer` normally contains that risk with defensive
copies. The mode-aware path instead passes its owned start-offset array to a
callback and may subsequently patch that array in place.

A callback can retain the array or return it as the replacement array. Either
action defeats the stated exclusive ownership precondition.

The initial design considered requiring an immutable metadata policy for
reconstruction without storing it in each node. Independent review rejected
that middle position: a parent trusts cached child metadata, so a required
argument alone cannot detect a child constructed under a different policy.

## Invariants

The migration must establish these invariants:

1. No public API returns or retains a mutable alias to an array reachable from
   an invariant-bearing snapshot value.
2. Every classified `CstNode` records the metadata policy under which its
   cached fields were computed.
3. Parent construction and path-copy reconstruction reject child nodes whose
   metadata policy differs from the parent's policy.
4. Intentionally unclassified CST construction is explicit in the API and
   cannot be selected by omitting optional arguments.
5. Internal no-copy construction is package-private and is used only when the
   package created and exclusively owns the input arrays.
6. Mode re-lex callbacks can inspect old offsets but cannot mutate or recover
   the `TokenBuffer`'s owned offset array.
7. Every public CST reconstruction entry either requires a metadata policy or
   inherits one from the value being reconstructed. No classified path can
   silently fall back to unclassified metadata.
8. A mode-aware `TokenBuffer` retains the factory capability needed to replace
   a session after any failed partial attempt. It never treats the possibly
   mutated session that produced an invalid result as a full-lex fallback.
9. A mode-aware `TokenBuffer` has exactly one lexing authority. Its initial
   result, detached full lex, and fresh-session reset all originate from the
   same `ModeRelexFactory`; no plain lexer result participates in that buffer.
10. Public raw collection construction either returns an intrinsically valid
    opaque lexer result or raises `LexResultError`. A diagnostic never serves
    as permission to retain malformed parallel arrays or negative spans.

## Decision

### CST metadata policy is stored, not merely required

Add an opaque immutable `CstMetadataPolicy` in `seam`. It owns canonical copies
of the trivia kinds and error/incomplete classifiers used to compute CST
metadata. Normalized semantic content defines equality and avoids a
process-global mutable identifier.

Every `CstNode` stores its policy. The policy participates in node equality and
the structural hash so the interner cannot treat nodes with different cached
metadata semantics as interchangeable.

Parent construction checks every node child against the requested policy. A
mismatch is a programmer error and aborts construction.

`CstNode::new` becomes the classified construction boundary and requires a
policy. `CstNode::new_unclassified` is the distinct language-agnostic boundary;
it uses a canonical unclassified policy.

`with_replaced_child` drops its classifier parameters. It reconstructs with the
receiver's stored policy and rejects a replacement child built under another
policy.

The same rule applies to every other public reconstruction entry.
`build_tree`, `build_tree_interned`, `build_tree_fully_interned`, and their
`EventBuffer` methods require a policy. Language-agnostic callers pass
`CstMetadataPolicy::unclassified()` explicitly instead of omitting classifier
arguments.

`CstElement::map` drops its classifier parameters and preserves each rebuilt
node's stored policy automatically. If the mapping callback substitutes a node
built under another policy, construction of its nearest parent rejects the
mixed-policy tree. The transformed root may deliberately change policy only
when the callback replaces the root itself.

All `CstNode` fields become private. Named scalar accessors expose kind, text
length, structural hash, non-trivia token count, and cached error presence.
Child observation uses `ArrayView[CstElement]` or existing iterators.

The stored policy is not exposed through a public accessor. Callers that create
classified trees retain the policy they created; callers that reconstruct
existing values use policy-preserving operations. This keeps policy extraction
and re-injection out of the public interface.

Public construction defensively copies child arrays. A package-private constructor
accepts an exclusively owned child array for `EventBuffer` and other audited
`seam` hot paths.

### Lexer results and mode re-lexing form one ownership boundary

`LexResult`, `ModeRelexResult`, `ModeRelexState`, and `ModeRelexFactory` become
opaque outside `loom/core`. Public result constructors validate and copy input
arrays. Existing `tokens()`, `starts()`, and diagnostic accessors retain their
defensive-copy behavior.

Public constructors copy all array inputs before validation and retain only the
owned copies. Intrinsic collection-shape failure raises the concrete
`LexResultError`; no opaque result is returned. Package-private constructors
validate and transfer arrays only from audited producers inside `loom/core`.

`LexResultError` is an adapter-contract error, not a user-text diagnostic. It
covers token/start cardinality, negative token lengths or starts, decreasing or
overlapping starts, and negative mode convergence. Lexer recovery for malformed
source still returns a complete `LexResult` plus structured diagnostics.

`Grammar::new` continues to accept a total lexer callback. An adapter that calls
a raising raw-result constructor inside that callback catches `LexResultError`
inside the installed closure. It must either construct a structurally valid,
language-specific recovery result plus diagnostics or abort explicitly for the
adapter defect; Loom cannot synthesize an arbitrary fallback token of type `T`.
The typed construction error does not escape through the total grammar callback,
and the callback never returns a malformed result.

`LexResult::from_located_tokens` remains a total repair adapter. It copies
positioned input into new arrays, diagnoses and clamps invalid external spans,
and returns a structurally valid result. That diagnostic describes repaired
adapter input; it does not permit malformed parallel arrays inside the returned
value. The implementation completes through the validated package-private owned
constructor, so the public `with_starts` error effect does not escape this total
helper.

Indexed access and read-only iteration serve callers that do not need owning
copies. Package-private constructors transfer arrays created inside `loom/core`
without copying.

The mode re-lex callback no longer receives `Array[Int]`. It receives an opaque
invocation-scoped `OldTokenStarts` capability with only `length()` and
`start_at(Int)` observations.

`start_at` aborts as a programmer error when its index is outside
`[0, length())`; it never exposes an array or an iterator backed by the owned
array.

The capability may be retained by a callback, so
its contract does not promise snapshot stability after the callback returns;
it guarantees that no mutable array can be recovered from it.

Public `ModeRelexResult` construction copies arrays and diagnostics, preventing
a callback from returning an alias to buffer-owned storage. The built-in mode
lexer uses the package-private owned path with freshly allocated replacement
arrays and diagnostics.

Validation is split by available context. `ModeRelexResult::new` validates
intrinsic properties such as parallel-array cardinality, non-negative lengths,
ordered starts, and non-negative convergence, and raises `LexResultError` on
failure. `ModeRelexState::new` therefore accepts a `relex_from` callback that
may raise that exact error. `TokenBuffer` catches it as an invalid partial
attempt. `TokenBuffer` separately validates source bounds, upper convergence
bounds, damage bounds, and patch eligibility because those depend on the
invocation.

`TokenBuffer` validates the complete partial result before mutating its tokens,
starts, diagnostics, source, or version. A valid but non-patchable result takes
the fresh-array rebuild path.

An intrinsically or contextually invalid partial result is never spliced. The
buffer discards it and never invokes `tokenize` on the session that produced
it. The buffer asks its retained `ModeRelexFactory` capability for a fresh
session and initializes that session against `new_source`. A package-private
factory fast path may create the session and its initial result together.
Otherwise the buffer creates a fresh session and invokes that session's first
full `tokenize`. Both paths are factory-owned; neither consults a grammar's
plain lexer or compares results from two authorities.

The private session slot has two states: `Ready(ModeRelexState[T])` and
`ResetRequired`. Partial re-lex is permitted only in `Ready`. A successful
fresh reset that satisfies the normal token/start/EOF invariants atomically
commits tokens, starts, diagnostics, source, version, and the replacement
`Ready` session. The failed partial attempt increments internal instrumentation
but adds no incremental-only public diagnostic, preserving full/incremental
diagnostic parity.

Session-state and commit-eligibility decisions live in a deterministic internal
transition function. The `TokenBuffer` shell invokes session/factory closures,
passes their validated outcomes to that function, and applies the returned
decision atomically. Validation and transition tests therefore do not depend on
mutable closure wiring; shell tests cover only factory calls and commit order.
The implementation groups source, tokens, starts, diagnostics, version, and the
session slot in one private committed-state value where practical, so a
successful reset publishes them with one assignment after all fallible work.

If fallback tokenization still cannot establish the full-lex invariants,
`TokenBuffer::update` raises `LexError`, leaves its previously committed
observable buffer state unchanged, and marks the mode session as requiring a
full reset. A later update in `ResetRequired` bypasses partial re-lex and asks
the factory for another fresh session. No invalid partial or full result is
committed merely because it carries a diagnostic.

Public mode-aware `TokenBuffer` construction accepts a `ModeRelexFactory`, not
a standalone `ModeRelexState`. This makes session replacement a capability the
buffer owns instead of a promise left to callers. It uses a dedicated
`new_from_mode_relex` constructor. `new_from_lex` cannot accept a mode factory,
and the existing public `new_with_mode_relex` constructor is removed. This
type-level split prevents a caller from supplying both a plain lexer and a mode
factory for one buffer. A package-private constructor may accept an already
initialized session/result pair together with the same factory-derived reset
capability so the facade keeps a single-full-lex initialization fast path.

`ModeRelexFactory::new` accepts only a fresh-session constructor. Its detached
`tokenize` operation is implemented by creating a fresh session and invoking
that session's full tokenizer. Built-in adapters may install a package-private
combined session/result initializer, but cannot install a second token or
diagnostic producer. A grammar that carries both its ordinary lexer and an
optional mode factory treats the factory as authoritative whenever the mode
path is selected; the ordinary lexer is not a fallback for that buffer.

`Grammar::incremental_relex_enabled=false` remains the authoritative mode-path
opt-out. In that case the facade constructs a plain buffer from the ordinary
lexer and does not create, initialize, or invoke the optional mode factory. When
incremental re-lex is enabled and a factory is present, the facade selects
`new_from_mode_relex`. This preserves the existing HTML and JSX behavior while
ensuring that every constructed buffer still has exactly one lexing authority.

Both `new_from_lex` and `new_from_mode_relex` validate the complete initial
result before exposing the buffer. An invalid initial
token/start/source-bound/EOF shape is a lexer-adapter contract defect and aborts
construction with a path-specific invariant message: there is no previous
committed snapshot or token-type-independent lossless fallback. Incremental
reset failure remains the recoverable `LexError` path described above because
an existing committed buffer can be retained safely.

Opaque mode-relex values expose constructors and named operations, not their
stored closures or arrays. A custom lexer constructs a `ModeRelexState`,
returns `ModeRelexResult` values, and installs the state through a
`ModeRelexFactory`. Loom's facade passes that factory lifecycle capability into
`TokenBuffer`; the buffer invokes factories and sessions through `tokenize`,
`new_session`, and the package-private combined initializer. Observable
behavior is tested through `TokenBuffer` or a parser rather than by inspecting
stored fields.

The remote throwaway MoonBit
[prototype commit](https://github.com/dowdiness/loom/commit/d35c5e1429a3a04b213a31cee6048ce0ad6e2a05)
on branch `prototype/mode-relex-constructor-split` explored a simplified version
of the factory-authority and reset-state model. Within that model, its TUI
exercised raw-shape rejection, detached tokenization through a fresh factory
session, mutation then failure of the old partial session, successful fresh
commit, failed fresh reset with every committed field retained, and a later
`ResetRequired` retry that bypasses partial re-lex. Separate runs exercised the
path-specific invariant abort for malformed plain and mode-aware initial
results.

This prototype is feasibility evidence only. It does not validate the exact
public signatures below, cross-package opacity, `OldTokenStarts`, production
partial-splice and convergence behavior, or integration with the existing
`TokenBuffer`. Those properties are acceptance criteria for the real Phase 1
implementation and its automated tests, not claims established by the
prototype.

The equal-cardinality in-place patch remains internal. Before mutation,
`TokenBuffer` validates token/start cardinality, convergence bounds, and start
offset consistency. If those preconditions do not hold, it uses the existing
fresh-array rebuild path.

An exported constructor that claims to consume caller-owned arrays is rejected:
MoonBit has no linear ownership with which to enforce that promise. If release
benchmarks show that defensive copies materially regress external lexer
construction under the migration-specific release gate, a separate proposal
may add an opaque `LexResultBuilder`.

A builder can own private arrays populated through methods and transfer them at
`finish`, without accepting a caller-retained raw array.

### LanguageSpec owns policy; DamageTracker stays mutable

`LanguageSpec` becomes opaque and copies its trivia-kind input. Its constructor
adds the existing parser-side `K : ToRawKind` bound and builds the language's
single `CstMetadataPolicy`.

Only capabilities required outside `loom/core` are exposed: the EOF token,
reuse threshold, and a copying raw-trivia projection. Parser-only fields and
the stored policy remain private. Parser and event construction use the stored
policy internally, making policy reuse the normal grammar path.

`DamageTracker` remains an intentionally mutable imperative-shell object. Its
range array becomes private; callers observe damage through existing predicates
plus `range_count`, `range_at`, or a read-only iterator. A retained tracker
reference continues to have mutable-object semantics.

### Target public shape

The signatures below fix the ownership-relevant public names and capabilities.
Implementation may adjust only syntax required by the compiler; changing a
name, operation, ownership rule, or error mode requires updating this ADR
before implementation proceeds.

```moonbit
pub struct CstMetadataPolicy { /* private fields */ }
pub fn CstMetadataPolicy::new(
  trivia_kinds : Array[RawKind],
  error_kind? : RawKind,
  incomplete_kind? : RawKind,
) -> CstMetadataPolicy
pub fn CstMetadataPolicy::unclassified() -> CstMetadataPolicy

pub struct CstNode { /* private fields, including policy */ }
pub fn CstNode::new(
  RawKind,
  Array[CstElement],
  policy~ : CstMetadataPolicy,
) -> CstNode
pub fn CstNode::new_unclassified(RawKind, Array[CstElement]) -> CstNode
pub fn CstNode::with_replaced_child(Self, Int, CstElement) -> CstNode
pub fn CstNode::kind(Self) -> RawKind
pub fn CstNode::text_len(Self) -> Int
pub fn CstNode::structural_hash(Self) -> Int
pub fn CstNode::token_count(Self) -> Int
pub fn CstNode::has_any_error(Self) -> Bool
pub fn CstNode::children(Self) -> ArrayView[CstElement]
pub fn CstElement::map(Self, (CstElement) -> CstElement) -> CstElement

pub fn build_tree(
  Array[ParseEvent],
  RawKind,
  policy~ : CstMetadataPolicy,
) -> CstNode raise EventStreamError
pub fn build_tree_interned(
  Array[ParseEvent],
  RawKind,
  Interner,
  policy~ : CstMetadataPolicy,
) -> CstNode raise EventStreamError
pub fn build_tree_fully_interned(
  Array[ParseEvent],
  RawKind,
  Interner,
  NodeInterner,
  policy~ : CstMetadataPolicy,
) -> CstNode raise EventStreamError

pub fn EventBuffer::build_tree(
  Self,
  RawKind,
  policy~ : CstMetadataPolicy,
) -> CstNode raise EventStreamError
pub fn EventBuffer::build_tree_interned(
  Self,
  RawKind,
  Interner,
  policy~ : CstMetadataPolicy,
) -> CstNode raise EventStreamError
pub fn EventBuffer::build_tree_fully_interned(
  Self,
  RawKind,
  Interner,
  NodeInterner,
  policy~ : CstMetadataPolicy,
) -> CstNode raise EventStreamError

pub struct OldTokenStarts { /* private fields */ }
pub fn OldTokenStarts::length(Self) -> Int
pub fn OldTokenStarts::start_at(Self, Int) -> Int

pub(all) suberror LexResultError {
  TokenStartCountMismatch(Int, Int)
  NegativeTokenLength(Int, Int)
  NegativeStart(Int, Int)
  DecreasingStart(Int, Int, Int)
  OverlappingToken(Int, Int, Int)
  NegativeConvergence(Int)
}

pub struct LexResult[T] { /* private fields */ }
pub fn[T] LexResult::LexResult(
  Array[TokenInfo[T]],
  diagnostics? : DiagnosticSet,
) -> LexResult[T] raise LexResultError
pub fn[T] LexResult::with_starts(
  Array[TokenInfo[T]],
  Array[Int],
  diagnostics~ : DiagnosticSet,
) -> LexResult[T] raise LexResultError
pub fn[T] LexResult::length(Self[T]) -> Int
pub fn[T] LexResult::token_at(Self[T], Int) -> TokenInfo[T]?
pub fn[T] LexResult::start_at(Self[T], Int) -> Int?
pub fn[T] LexResult::iter(Self[T]) -> Iter[(TokenInfo[T], Int)]
pub fn[T] LexResult::tokens(Self[T]) -> Array[TokenInfo[T]]
pub fn[T] LexResult::starts(Self[T]) -> Array[Int]
pub fn[T] LexResult::diagnostics(Self[T]) -> DiagnosticSet

pub struct ModeRelexResult[T] { /* private fields */ }
pub fn[T] ModeRelexResult::new(
  tokens : Array[TokenInfo[T]],
  starts : Array[Int],
  diagnostics : DiagnosticSet,
  converged_at_old_token~ : Int,
) -> ModeRelexResult[T] raise LexResultError

pub struct ModeRelexState[T] { /* private fields */ }
pub fn[T] ModeRelexState::new(
  tokenize~ : (String) -> LexResult[T],
  relex_from~ : (
    String,
    Int,
    Int,
    Int,
    OldTokenStarts,
    Int,
    Int,
  ) -> ModeRelexResult[T] raise LexResultError,
) -> ModeRelexState[T]
pub fn[T] ModeRelexState::tokenize(Self[T], String) -> LexResult[T]

pub struct ModeRelexFactory[T] { /* private fields */ }
pub fn[T] ModeRelexFactory::new(
  new_session~ : (SourceId) -> ModeRelexState[T],
) -> ModeRelexFactory[T]
pub fn[T] ModeRelexFactory::tokenize(
  Self[T],
  SourceId,
  String,
) -> LexResult[T]
pub fn[T] ModeRelexFactory::new_session(
  Self[T],
  SourceId,
) -> ModeRelexState[T]

pub fn[T : Eq] TokenBuffer::new_from_lex(
  SourceId,
  String,
  lex_fn~ : (String) -> LexResult[T],
  eof_token~ : T,
  incremental_relex_enabled? : Bool,
) -> TokenBuffer[T]
pub fn[T : Eq] TokenBuffer::new_from_mode_relex(
  SourceId,
  String,
  factory~ : ModeRelexFactory[T],
  eof_token~ : T,
) -> TokenBuffer[T]

pub struct LanguageSpec[T, K] { /* private fields */ }
pub fn[T, K : ToRawKind] LanguageSpec::new(
  whitespace_kind : K,
  error_kind : K,
  root_kind : K,
  eof_token : T,
  incomplete_kind? : K,
  parse_root? : (ParserContext[T, K]) -> Unit,
  reuse_size_threshold? : Int,
  trivia_kinds_spec? : Array[K],
) -> LanguageSpec[T, K]
pub fn[T, K] LanguageSpec::eof_token(Self[T, K]) -> T
pub fn[T, K] LanguageSpec::reuse_size_threshold(Self[T, K]) -> Int
pub fn[T, K : ToRawKind] LanguageSpec::trivia_kinds_raw(
  Self[T, K],
) -> Array[RawKind]

pub struct DamageTracker { /* private fields */ }
pub fn DamageTracker::range_count(Self) -> Int
pub fn DamageTracker::range_at(Self, Int) -> Range?
```

## Release and compatibility boundary

This is a breaking public API migration. The repository currently declares
version `0.1.0` and has no GitHub releases or tags as of 2026-08-05.

The change uses a clean source migration on the next maintainer-approved
pre-1.0 release boundary. The unsafe fields receive no compatibility layer.

The implementation must not begin until this ADR is accepted. Acceptance
authorizes first-party call-site migration. A repeat consumer audit must still
check for external consumers because indexed public-code search is incomplete.

The implementation plan also owns the generated-interface diff, changelog
entry, and exact migration examples.

## Rationale

Stored policy makes the metadata contract locally checkable. Requiring policy
at each reconstruction call would move responsibility to every caller while
leaving mixed-policy children undetectable.

Semantic policy equality avoids a
global identity allocator and permits separately created but equivalent
language specifications to interoperate deliberately.

The public-copy/package-private-owned split places cost at the trust boundary.
Internal node construction keeps its current no-copy behavior. The mode re-lex
capability closes the live outbound alias without copying the complete old
offset array on every incremental edit.

An opaque builder is the viable future public zero-copy construction API
because callers cannot retain its backing arrays.

## Consequences

- `seam` and `loom/core` generated `.mbti` files will change substantially.
- First-party tests, benchmarks, examples, grammar helpers, and the `@loom`
  facade must migrate in coordinated slices.
- Each CST node stores one additional immutable policy reference. Release
  benchmarks must measure construction, interning, traversal, full parse, and
  incremental parse before this layout is accepted.
- Callers that intentionally build language-agnostic trees must spell
  `new_unclassified`; classified reconstruction becomes safer and shorter.
- External lexers initially pay defensive-copy cost at result construction.
  Builder work remains deferred until measurements demonstrate a real problem.
- Raw lexer adapters must handle `LexResultError` before supplying Loom's total
  lexer callbacks. Malformed user text remains a diagnostic-bearing success;
  only malformed result structure uses the error channel.
- `DamageTracker` remains mutable by design, but its representation is no
  longer part of the public API.

## Alternatives rejected

- **Require but do not store metadata policy:** cannot detect cross-policy
  subtree splicing and adds repeated caller obligations without enforcement.
- **Expose public consuming or unsafe constructors:** MoonBit cannot prove the
  input arrays are unaliased.
- **Copy the old start-offset array on every mode re-lex:** safe but discards the
  current equal-cardinality optimization before measurement.
- **Keep mode re-lex types out of scope:** leaves the concrete outbound alias
  path that can violate `TokenBuffer`'s parallel-array invariant.
- **One constructor with both a plain lexer and optional mode factory:** leaves
  two candidate authorities for tokens and diagnostics, requires an equality
  policy for disagreements, and makes fresh-session recovery depend on caller
  coordination. Separate constructors make the invalid combination
  unrepresentable.
- **Attach diagnostics to malformed result arrays and return them:** callers
  could still receive an opaque value whose parallel-array invariant is false.
  Typed construction failure keeps invalid structure out of the value domain;
  diagnostics remain reserved for complete recovered lexer output.
