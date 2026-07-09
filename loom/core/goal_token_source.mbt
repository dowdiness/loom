// Goal-directed tokenization support.
//
// GoalTokenSource is an overlay on TokenBuffer for parser-directed
// lexical goal queries. See docs/architecture/goal-token-source.md.
//
// The cache maps (source_offset, goal_int) → (token, end_exclusive_offset),
// storing results from goal-directed lex steps. Cache is cleared on
// source edit via TokenBuffer.update().

///|
/// Internal cache entry for one goal-directed token result.
priv struct GoalCacheEntry[T] {
  offset : Int
  goal : Int
  token : T
  end_offset : Int
}

///|
/// Cache for parser-directed goal tokenization results.
/// Lives on TokenBuffer; cleared on source edit.
pub(all) struct GoalCache[T] {
  priv entries : Array[GoalCacheEntry[T]]
}

///|
/// Create an empty goal tokenization cache.
fn[T] GoalCache::new() -> GoalCache[T] {
  { entries: [] }
}

///|
/// Clear all cached entries. Called on TokenBuffer::update().
fn[T] GoalCache::invalidate(self : GoalCache[T]) -> Unit {
  self.entries.clear()
}

///|
/// Look up a cached goal-directed token result.
/// Returns None on cache miss.
fn[T] GoalCache::lookup(
  self : GoalCache[T],
  offset : Int,
  goal : Int,
) -> (T, Int)? {
  self.entries
  .iter()
  .find_first(fn(entry) { entry.offset == offset && entry.goal == goal })
  .map(fn(entry) { (entry.token, entry.end_offset) })
}

///|
/// Insert a goal-directed token result into the cache.
fn[T] GoalCache::insert(
  self : GoalCache[T],
  offset : Int,
  goal : Int,
  token : T,
  end_offset : Int,
) -> Unit {
  self.entries.push({ offset, goal, token, end_offset })
}

///|
/// Check if the given offset falls inside any cached goal-produced token span.
/// Returns `(start, end_exclusive)` of the containing span, or None.
/// O(N) in cache size — cache is bounded by goal queries per parse pass.
fn[T] GoalCache::goal_span_containing(
  self : GoalCache[T],
  offset : Int,
) -> (Int, Int)? {
  self.entries
  .iter()
  .find_first(fn(entry) { offset >= entry.offset && offset < entry.end_offset })
  .map(fn(entry) { (entry.offset, entry.end_offset) })
}
