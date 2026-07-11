///|
/// Emit `sync_point.g.mbt` — `is_sync_point(Token)` for error-recovery sync points.
/// Generated from `#loom.recovery("sync")` annotations (#627).

///|
fn emit_sync_point(token_enum : EnumDecl) -> String {
  let sync_variants = token_enum.variants.filter(fn(v) { v.is_sync })
  let b = StringBuilder()
    ..write_string("///|\n")
    ..write_string(
      "/// Returns `true` if `token` is an error-recovery synchronization point.\n",
    )
    ..write_string(
      "/// Generated from `#loom.recovery(\"sync\")` annotations.\n",
    )
    ..write_string(
      "pub fn is_sync_point(token : " + token_enum.name + ") -> Bool {\n",
    )
  if sync_variants.length() == 0 {
    b.write_string("  false\n")
  } else {
    b.write_string("  match token {\n")
    let arms = sync_variants
      .map(fn(v) { if v.arg_count > 0 { v.name + "(_)" } else { v.name } })
      .join(" | ")
    b.write_string("    " + arms + " => true\n")
    b.write_string("    _ => false\n")
    b.write_string("  }\n")
  }
  b.write_string("}\n")
  b.to_string()
}
