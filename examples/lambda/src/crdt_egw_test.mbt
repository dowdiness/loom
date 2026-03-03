// event-graph-walker integration demo.
// EgwPeer wraps a TextDoc (real CRDT) + ImperativeParser.
// local_insert() drives both the CRDT doc and the incremental parser.
// bridge_sync() receives a SyncMessage, converts the resulting text change
// to a TextDelta via text_to_delta, then drives the incremental parser.

///|
struct EgwPeer {
  doc : @egw.TextDoc
  parser : @incremental.ImperativeParser[@seam.SyntaxNode]
}

///|
fn EgwPeer::new(agent_id : String) -> EgwPeer {
  let doc = @egw.TextDoc::new(agent_id)
  let parser = new_imperative_parser("")
  let _ = parser.parse()
  { doc, parser }
}

///|
/// Insert text into the local doc and drive the incremental parser.
fn EgwPeer::local_insert(
  self : EgwPeer,
  pos : @egw.Pos,
  text : String
) -> Unit {
  let old_text = self.doc.text()
  try {
    let _ = self.doc.insert(pos, text)
  } catch {
    _ => return
  }
  let new_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let delta = @core.text_to_delta(old_text, new_text)
  let edits = @core.to_edits(delta)
  let mut current = old_text
  for edit in edits {
    let inserted = try new_text[edit.start:edit.start + edit.new_len] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    let prefix = try current[0:edit.start] catch { _ => "" } noraise {
      v => v.to_string()
    }
    let suffix = try current[edit.start + edit.old_len:] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    current = prefix + inserted + suffix
    let _ = self.parser.edit(edit, current)
  }
}

///|
/// Apply a SyncMessage to the local doc, compute the resulting TextDelta,
/// and drive the incremental parser with those edits.
fn EgwPeer::bridge_sync(self : EgwPeer, message : @egw.SyncMessage) -> Unit {
  let old_text = self.doc.text()
  let session = self.doc.sync()
  try session.apply(message) catch { _ => return }
  let new_text = self.doc.text()
  if old_text == new_text {
    return
  }
  let delta = @core.text_to_delta(old_text, new_text)
  let edits = @core.to_edits(delta)
  let mut current = old_text
  for edit in edits {
    let inserted = try new_text[edit.start:edit.start + edit.new_len] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    let prefix = try current[0:edit.start] catch { _ => "" } noraise {
      v => v.to_string()
    }
    let suffix = try current[edit.start + edit.old_len:] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    current = prefix + inserted + suffix
    let _ = self.parser.edit(edit, current)
  }
}

///|
test "egw two peers converge: same text and parse tree after sync" {
  // Peer A types "42" locally — both doc and parser are updated.
  let peer_a = EgwPeer::new("a")
  let peer_b = EgwPeer::new("b")
  peer_a.local_insert(@egw.Pos::at(0), "42")
  // Export peer A's ops and sync to peer B.
  let msg_a = try {
    peer_a.doc.sync().export_all()
  } catch {
    _ => abort("export_all failed")
  }
  peer_b.bridge_sync(msg_a)
  // Both peers now have the same text.
  inspect(peer_a.doc.text() == peer_b.doc.text(), content="true")
  inspect(peer_a.doc.text(), content="42")
  // Both incremental parse trees are structurally identical.
  let tree_a = peer_a.parser.get_tree().unwrap()
  let tree_b = peer_b.parser.get_tree().unwrap()
  inspect(tree_a.cst_node() == tree_b.cst_node(), content="true")
}
