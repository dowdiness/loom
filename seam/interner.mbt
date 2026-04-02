///|
/// Session-scoped token intern table.
///
/// Deduplicates CstToken objects by (kind, text): every call to
/// intern_token with the same arguments returns a structurally equal token.
///
/// Lifetime: own one Interner per parse session (e.g. per IncrementalParser).
/// The GC collects the Interner and all its tokens when the owner is dropped.
/// Not thread-safe.
///
/// Key design: two-level map (RawKind → (StringView → CstToken)).
/// On the hot hit path, lookup uses the caller's StringView directly
/// with zero allocation. Stored keys are auto-coerced from CstToken.text
/// (owned String), so old source strings are not retained by the interner.
///
/// Tuple struct: single-field wrapper is automatically unboxed at runtime —
/// Interner IS the HashMap, no wrapper allocation or indirection.
pub struct Interner(
  @hashmap.HashMap[RawKind, @hashmap.HashMap[StringView, CstToken]]
)

///|
/// Create a new empty Interner.
pub fn Interner::new() -> Interner {
  Interner(@hashmap.HashMap::new())
}

///|
/// Return the canonical CstToken for (kind, text).
/// On first call for a given pair: allocates a CstToken and stores it.
/// On subsequent calls: returns the stored object (same heap reference).
/// Hit path is zero-alloc — StringView lookup, no String materialization.
pub fn Interner::intern_token(
  self : Interner,
  kind : RawKind,
  text : StringView,
) -> CstToken {
  match self.0.get(kind) {
    Some(inner) =>
      match inner.get(text) {
        Some(token) => token
        None => {
          let token = CstToken(kind, text)
          inner.set(token.text, token)
          token
        }
      }
    None => {
      let token = CstToken(kind, text)
      let inner : @hashmap.HashMap[StringView, CstToken] = @hashmap.HashMap::new()
      inner.set(token.text, token)
      self.0.set(kind, inner)
      token
    }
  }
}

///|
/// Number of distinct (kind, text) pairs currently interned.
pub fn Interner::size(self : Interner) -> Int {
  let mut total = 0
  self.0.each(fn(_kind, inner) { total = total + inner.length() })
  total
}

///|
/// Clear all interned tokens. The Interner can be reused after this call,
/// e.g. when starting a new document in a long-lived language server session.
pub fn Interner::clear(self : Interner) -> Unit {
  self.0.clear()
}
