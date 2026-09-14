///|
/// Allocated only when a parser gains its first semantic attachment. Each
/// registration advances private pending evidence, never author code.
priv struct SemanticHub {
  mut revision : Int
  mut next_registration : Int
  mut busy : Bool
  registrations : Map[Int, (String, Int, @core.Edit?) -> Unit]
}

///|
fn SemanticHub::SemanticHub() -> SemanticHub {
  { revision: 0, next_registration: 0, busy: false, registrations: {} }
}

///|
fn SemanticHub::require_idle(self : SemanticHub) -> Unit raise Failure {
  guard !self.busy else {
    fail("reentrant semantic settlement or parser update")
  }
}

///|
fn[Ast] Parser::require_semantic_idle(self : Parser[Ast]) -> Unit raise Failure {
  match self.semantic_hub {
    Some(hub) => hub.require_idle()
    None => ()
  }
}

///|
fn[Ast] Parser::advance_semantics(
  self : Parser[Ast],
  source : String,
  edit : @core.Edit?,
) -> Unit {
  match self.semantic_hub {
    None => ()
    Some(hub) => {
      hub.revision += 1
      for advance in hub.registrations.values() {
        advance(source, hub.revision, edit)
      }
    }
  }
}

///|
/// Existing identity alignment accepts one conservative edit window. Preserve
/// explicit intent across a validated batch without introducing a second
/// composition algorithm or allocating a per-character provenance structure.
fn semantic_change_envelope(changes : @text_change.ChangeSet) -> @core.Edit? {
  let mut first = None
  let mut last_end = 0
  changes.each(change => {
    match change {
      @text_change.TextChange::ReplaceRange(start~, delete_len~, ..) => {
        if first is None {
          first = Some(start)
        }
        last_end = start + delete_len
      }
      @text_change.TextChange::ReplaceAll(_) => ()
    }
  })
  first.map(start => {
    let old_len = last_end - start
    @core.Edit::new(
      start,
      old_len,
      old_len + changes.result_length() - changes.source_length(),
    )
  })
}
