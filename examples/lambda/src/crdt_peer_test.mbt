// Simulated two-peer CRDT convergence test.
// Each peer has a String (the text) and an ImperativeParser.
// We manually apply TextDelta sequences to both peers and assert convergence.

///|
struct Peer {
  mut text : String
  parser : @incremental.ImperativeParser[@ast.Term]
}

///|
fn Peer::new(source : String) -> Peer {
  let parser = new_imperative_parser(source)
  let _ = parser.parse()
  { text: source, parser }
}

///|
/// Apply a TextDelta to a String, producing the new text.
fn build_new_text(source : String, delta : Array[@core.TextDelta]) -> String {
  let buf = StringBuilder::new()
  let mut cursor = 0
  for d in delta {
    match d {
      @core.TextDelta::Retain(n) => {
        let s = try source[cursor:cursor + n] catch {
          _ => ""
        } noraise {
          v => v.to_string()
        }
        buf.write_string(s)
        cursor += n
      }
      @core.TextDelta::Delete(n) => cursor += n
      @core.TextDelta::Insert(s) => buf.write_string(s)
    }
  }
  let tail = try source[cursor:] catch {
    _ => ""
  } noraise {
    v => v.to_string()
  }
  buf.write_string(tail)
  buf.to_string()
}

///|
/// Apply a TextDelta to a peer: update text and drive the incremental parser.
///
/// Applies each Edit from to_edits() sequentially. For each edit, the inserted
/// content is extracted from new_text at the edit's start position.
fn apply_peer_delta(peer : Peer, delta : Array[@core.TextDelta]) -> Unit {
  let new_text = build_new_text(peer.text, delta)
  let edits = @core.to_edits(delta)
  let mut current = peer.text
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
    let _ = peer.parser.edit(edit, current)
  }
  peer.text = new_text
}

///|
test "two peers converge after sequential sync" {
  // Both peers start empty
  let peer_a = Peer::new("")
  let peer_b = Peer::new("")
  // Peer A types "λx. x"
  let delta_a = [@core.TextDelta::Insert("λx. x")]
  apply_peer_delta(peer_a, delta_a)
  // Peer B receives A's edit
  apply_peer_delta(peer_b, delta_a)
  // Both should have same text
  inspect(peer_a.text == peer_b.text, content="true")
  // Both should parse to the same Term
  let tree_a = peer_a.parser.get_tree().unwrap()
  let tree_b = peer_b.parser.get_tree().unwrap()
  inspect(tree_a == tree_b, content="true")
}

///|
test "two peers converge after two rounds of sync" {
  let peer_a = Peer::new("")
  let peer_b = Peer::new("")
  // Round 1: A types initial expression, B gets it
  let delta1 = [@core.TextDelta::Insert("42")]
  apply_peer_delta(peer_a, delta1)
  apply_peer_delta(peer_b, delta1)
  // Round 2: A extends, B gets it
  let delta2 = [@core.TextDelta::Retain(2), @core.TextDelta::Insert(" + 1")]
  apply_peer_delta(peer_a, delta2)
  apply_peer_delta(peer_b, delta2)
  // Both converge
  inspect(peer_a.text, content="42 + 1")
  inspect(peer_b.text, content="42 + 1")
  let tree_a = peer_a.parser.get_tree().unwrap()
  let tree_b = peer_b.parser.get_tree().unwrap()
  inspect(tree_a == tree_b, content="true")
}

///|
test "tree_diff confirms incremental parse matches full reparse after sync" {
  // After applying a delta, the incremental parse and a fresh full parse
  // should produce identical Terms.
  let peer = Peer::new("42")
  let delta = [@core.TextDelta::Retain(2), @core.TextDelta::Insert(" + 1")]
  apply_peer_delta(peer, delta)
  // Full reparse of final text using parse (public API) — both return Term now
  let full_term = parse(peer.text) catch { _ => abort("parse failed") }
  let incremental_term = peer.parser.get_tree().unwrap()
  inspect(incremental_term == full_term, content="true")
}
