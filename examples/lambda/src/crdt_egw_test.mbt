// event-graph-walker integration demo.
// EgwPeer wraps a TextDoc (real CRDT) + ImperativeParser.
// local_insert() drives both the CRDT doc and the incremental parser.
// bridge_sync() receives a SyncMessage, converts the resulting text change
// to a TextDelta via text_to_delta, then drives the incremental parser.
//
// Both methods share drive_parser_update() to avoid duplicated loops.

///|
/// Drive an incremental parser from old_text to new_text using the
/// text_to_delta → to_edits pipeline.
///
/// Each edit's start is in the coordinate space of the text after all
/// previous edits have been applied, so current threads state across iterations.
fn drive_parser_update(
  parser : @incremental.ImperativeParser[@seam.SyntaxNode],
  old_text : String,
  new_text : String,
) -> Unit {
  if old_text == new_text {
    return
  }
  let edits = @core.text_to_delta(old_text, new_text) |> @core.to_edits
  let mut current = old_text
  for edit in edits {
    let inserted = try new_text[edit.start:edit.start + edit.new_len] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    let prefix = try current[0:edit.start] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    let suffix = try current[edit.start + edit.old_len:] catch {
      _ => ""
    } noraise {
      v => v.to_string()
    }
    current = prefix + inserted + suffix
    parser.edit(edit, current) |> ignore
  }
}

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
fn EgwPeer::local_insert(self : EgwPeer, pos : @egw.Pos, text : String) -> Unit {
  let old_text = self.doc.text()
  try {
    let _ = self.doc.insert(pos, text)
  } catch {
    _ => return
  }
  drive_parser_update(self.parser, old_text, self.doc.text())
}

///|
/// Apply a SyncMessage to the local doc, compute the resulting TextDelta,
/// and drive the incremental parser with those edits.
fn EgwPeer::bridge_sync(self : EgwPeer, message : @egw.SyncMessage) -> Unit {
  let old_text = self.doc.text()
  let session = self.doc.sync()
  session.apply(message) catch {
    _ => return
  }
  drive_parser_update(self.parser, old_text, self.doc.text())
}

///|
test "egw two peers converge: same text and parse tree after sync" {
  // Peer A types "42" locally — both doc and parser are updated.
  let peer_a = EgwPeer::new("a")
  let peer_b = EgwPeer::new("b")
  peer_a.local_insert(@egw.Pos::at(0), "42")
  // Export peer A's ops and sync to peer B.
  let msg_a = peer_a.doc.sync().export_all() catch {
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
