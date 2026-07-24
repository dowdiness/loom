///|
/// Whitebox tests for `#loom.recovery("sync")` sync-point generation (#627).

///|
fn tok_enum_of(src : String) -> EnumDecl {
  match parse_annotations(src) {
    Ok(a) =>
      match a.token_enum {
        Some(te) => te
        None => abort("expected a #loom.token enum")
      }
    Err(m) => abort("parse failed: " + m)
  }
}

///|
/// No sync variants → `is_sync_point` always returns `false`.
test "emit_sync_point: no sync variants" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct(",")
    #|  Comma
    #|  #loom.eof
    #|  EOF
    #|}
  let te = tok_enum_of(src)
  let got = emit_sync_point(te)
  let want =
    #|///|
    #|/// Returns `true` if `token` is an error-recovery synchronization point.
    #|/// Generated from `#loom.recovery("sync")` annotations.
    #|pub fn is_sync_point(_token : Tok) -> Bool {
    #|  false
    #|}
    #|
  assert_eq(got, want)
}

///|
/// Single sync variant with args → single arm with wildcard pattern.
test "emit_sync_point: one sync variant with args" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("<") #loom.recovery("sync")
    #|  OpenTag(String, Int)
    #|  #loom.eof
    #|  EOF
    #|}
  let te = tok_enum_of(src)
  let got = emit_sync_point(te)
  let want =
    #|///|
    #|/// Returns `true` if `token` is an error-recovery synchronization point.
    #|/// Generated from `#loom.recovery("sync")` annotations.
    #|pub fn is_sync_point(token : Tok) -> Bool {
    #|  match token {
    #|    OpenTag(_, _) => true
    #|    _ => false
    #|  }
    #|}
    #|
  assert_eq(got, want)
}

///|
/// Multiple sync variants — args and no-args combined with `|`.
test "emit_sync_point: multiple sync variants mixed args" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("<") #loom.recovery("sync")
    #|  OpenTag(String)
    #|  #loom.punct(">")
    #|  CloseTag(String)
    #|  #loom.eof #loom.recovery("sync")
    #|  EOF
    #|  #loom.literal("TextToken")
    #|  Text
    #|}
  let te = tok_enum_of(src)
  let got = emit_sync_point(te)
  let want =
    #|///|
    #|/// Returns `true` if `token` is an error-recovery synchronization point.
    #|/// Generated from `#loom.recovery("sync")` annotations.
    #|pub fn is_sync_point(token : Tok) -> Bool {
    #|  match token {
    #|    OpenTag(_) | EOF => true
    #|    _ => false
    #|  }
    #|}
    #|
  assert_eq(got, want)
}

///|
/// All variants are sync points — no non-sync variants remain.
test "emit_sync_point: all variants sync" {
  let src =
    #|#loom.token
    #|pub(all) enum Tok {
    #|  #loom.punct("x") #loom.recovery("sync")
    #|  X
    #|  #loom.punct("y") #loom.recovery("sync")
    #|  Y
    #|}
  let te = tok_enum_of(src)
  let got = emit_sync_point(te)
  let want =
    #|///|
    #|/// Returns `true` if `token` is an error-recovery synchronization point.
    #|/// Generated from `#loom.recovery("sync")` annotations.
    #|pub fn is_sync_point(token : Tok) -> Bool {
    #|  match token {
    #|    X | Y => true
    #|    _ => false
    #|  }
    #|}
    #|
  assert_eq(got, want)
}
