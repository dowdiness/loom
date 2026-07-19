///|
/// Emit `sync_point.g.mbt` — `is_sync_point(Token)` for error-recovery sync points.
/// Generated from `#loom.recovery("sync")` annotations (#627).

///|
fn emit_sync_point(token_enum : EnumDecl) -> String {
  let sync_variants = token_enum.variants.filter(fn(v) { v.is_sync })
  emit_token_membership_function(
    token_enum.name,
    "is_sync_point",
    sync_variants,
    Some(
      "Returns `true` if `token` is an error-recovery synchronization point.\n" +
      "/// Generated from `#loom.recovery(\"sync\")` annotations.",
    ),
  )
}
