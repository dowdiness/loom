///|
/// Observer-seam tests: `GraphAttachment::subscribe` notifies listeners once
/// per `settle`, regardless of mutation origin or projection outcome, and the
/// returned subscription detaches idempotently.

///|
test "subscribe fires the listener on set_source" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let _sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  attachment.set_source("osc = sine(freq: 880Hz)")
  inspect(count.val, content="1")
}

///|
test "subscribe fires the listener on apply_edit" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let before = ok_current(attachment.current_result())
  let lowered = ok_lowered(before.lower_set_numeric("osc", "freq", "880"))
  let edit = match lowered.incremental_edit() {
    Some(edit) => edit
    None => abort("expected exact edit")
  }
  let count : Ref[Int] = { val: 0 }
  let _sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  attachment.apply_edit(edit, lowered.new_source())
  inspect(count.val, content="1")
}

///|
test "the constructor settle does not fire listeners subscribed afterwards" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let _sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  inspect(count.val, content="0")
}

///|
test "every listener fires on a single settle" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let a : Ref[Int] = { val: 0 }
  let b : Ref[Int] = { val: 0 }
  let _s1 = attachment.subscribe(fn() { a.val = a.val + 1 })
  let _s2 = attachment.subscribe(fn() { b.val = b.val + 1 })
  attachment.set_source("osc = sine(freq: 880Hz)")
  inspect(a.val, content="1")
  inspect(b.val, content="1")
}

///|
test "the listener fires when the new source is parser-blocked" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let _sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  attachment.set_source("osc = sine(freq: )")
  inspect(attachment.state(), content="ParserBlocked")
  inspect(count.val, content="1")
}

///|
test "a listener may unsubscribe itself during notification" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let holder : Ref[GraphAttachmentSubscription?] = { val: None }
  let sub = attachment.subscribe(fn() {
    count.val = count.val + 1
    match holder.val {
      Some(subscription) => subscription.unsubscribe()
      None => ()
    }
  })
  holder.val = Some(sub)
  // Fires once, then detaches itself from inside the notification turn (the
  // snapshot copy keeps that safe).
  attachment.set_source("osc = sine(freq: 880Hz)")
  inspect(count.val, content="1")
  attachment.set_source("osc = sine(freq: 220Hz)")
  inspect(count.val, content="1")
}

///|
test "the listener fires even when the new source is projection-blocked" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let _sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  attachment.set_source("osc = sine(input: missing)")
  inspect(attachment.state(), content="ProjectionBlocked")
  inspect(count.val, content="1")
}

///|
test "unsubscribe stops notifications" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  attachment.set_source("osc = sine(freq: 880Hz)")
  inspect(count.val, content="1")
  sub.unsubscribe()
  attachment.set_source("osc = sine(freq: 220Hz)")
  inspect(count.val, content="1")
}

///|
test "unsubscribe is idempotent" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  sub.unsubscribe()
  sub.unsubscribe()
  attachment.set_source("osc = sine(freq: 880Hz)")
  inspect(count.val, content="0")
}

///|
test "one listener detaching does not affect the others" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let a : Ref[Int] = { val: 0 }
  let b : Ref[Int] = { val: 0 }
  let s1 = attachment.subscribe(fn() { a.val = a.val + 1 })
  let _s2 = attachment.subscribe(fn() { b.val = b.val + 1 })
  s1.unsubscribe()
  attachment.set_source("osc = sine(freq: 880Hz)")
  inspect(a.val, content="0")
  inspect(b.val, content="1")
}

///|
test "dispose clears listeners and unsubscribe stays safe afterwards" {
  let attachment = GraphAttachment::GraphAttachment(SAMPLE_SOURCE)
  let count : Ref[Int] = { val: 0 }
  let sub = attachment.subscribe(fn() { count.val = count.val + 1 })
  attachment.dispose()
  sub.unsubscribe()
  inspect(count.val, content="0")
}
