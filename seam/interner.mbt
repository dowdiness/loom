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
/// with zero allocation. Misses copy the token text once into a canonical
/// short string owned by the interner, then store both the key and token as
/// spans into that canonical text. This keeps global interners from retaining
/// full historical source buffers when callers pass source-backed spans.
///
/// Tuple struct: single-field wrapper is automatically unboxed at runtime —
/// Interner IS the HashMap, no wrapper allocation or indirection.
pub struct Interner(
  @hashmap.HashMap[RawKind, @hashmap.HashMap[StringView, CstToken]]
)

///|
/// Create a new empty Interner.
pub fn Interner::new() -> Interner {
  Interner(@hashmap.HashMap([]))
}

///|
/// Return the canonical CstToken for (kind, text).
/// On first call for a given pair: owns one canonical copy of `text` and stores
/// a token spanning that copy. On subsequent calls: returns the stored object
/// (same heap reference). Hit path is zero-alloc — StringView lookup, no String
/// materialization.
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
          let owned = text.to_owned()
          let token = CstToken(kind, owned)
          inner.set(token.text(), token)
          token
        }
      }
    None => {
      let owned = text.to_owned()
      let token = CstToken(kind, owned)
      let inner : @hashmap.HashMap[StringView, CstToken] = @hashmap.HashMap([])
      inner.set(token.text(), token)
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
