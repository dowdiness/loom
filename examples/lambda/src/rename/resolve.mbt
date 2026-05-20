///|
/// Walk the parent chain from `scope` upward via `enclosing` edges,
/// returning the closest Def matching `name`.
pub fn resolve_innermost(
  scope : @callers.ScopeId,
  name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> @callers.Def? {
  let visited : @hashset.HashSet[@callers.ScopeId] = @hashset.HashSet([])
  resolve_innermost_from(scope, name, defs, enclosing, visited)
}

///|
fn resolve_innermost_from(
  current : @callers.ScopeId,
  name : String,
  defs : Array[@callers.Def],
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
  visited : @hashset.HashSet[@callers.ScopeId],
) -> @callers.Def? {
  if visited.contains(current) {
    return None
  }
  visited.add(current)
  for d in defs {
    if d.scope == current && d.name == name {
      return Some(d)
    }
  }
  match parent_scope_of(current, enclosing) {
    Some(parent) =>
      resolve_innermost_from(parent, name, defs, enclosing, visited)
    None => None
  }
}

///|
fn parent_scope_of(
  scope : @callers.ScopeId,
  enclosing : Array[(@callers.ScopeId, @callers.ScopeId)],
) -> @callers.ScopeId? {
  for edge in enclosing {
    if edge.0 == scope {
      return Some(edge.1)
    }
  }
  None
}
