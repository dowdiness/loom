///|
/// Persistent append-only RawKind registry (fork i ADR).
/// Tracks tombstoned raws so retired kind numbers are never reused.
struct RawKindRegistry {
  known : Map[String, Int]
  mut next_raw : Int
  tombstones : @hashset.HashSet[Int]
}

///|
fn RawKindRegistry::new() -> Self {
  { known: Map([]), next_raw: 0, tombstones: @hashset.HashSet([]) }
}

///|
fn RawKindRegistry::assign(self : Self, name : String) -> Int {
  match self.known.get(name) {
    Some(raw) => raw
    None => {
      let raw = self.next_raw
      self.known.set(name, raw)
      self.next_raw = raw + 1
      raw
    }
  }
}

///|
fn RawKindRegistry::reserve(self : Self, name : String, raw : Int) -> Unit {
  match self.known.get(name) {
    Some(existing) if existing == raw => ()
    Some(_) => abort("raw conflict for name: " + name)
    None => {
      // Also check tombstones and existing known raws
      if self.tombstones.contains(raw) {
        abort("raw " + raw.to_string() + " is tombstoned")
      }
      for pair in self.known {
        let (_n, r) = pair
        if r == raw {
          abort("raw " + raw.to_string() + " already used")
        }
      }
      self.known.set(name, raw)
      if raw >= self.next_raw {
        self.next_raw = raw + 1
      }
    }
  }
}

///|
fn RawKindRegistry::seed(self : Self, entries : Array[(String, Int)]) -> Unit {
  for pair in entries {
    let (name, raw) = pair
    self.reserve(name, raw)
  }
}

///|
/// Seed tombstoned raws so they block future reuse across regeneration cycles.
/// `rawns`: raw numbers to take from prior generated output.
fn RawKindRegistry::seed_retired(self : Self, rawns : Array[Int]) -> Unit {
  for raw in rawns {
    // Sanity-check: a tombstoned raw must not be in the active set.
    for pair in self.known {
      let (_n, r) = pair
      if r == raw {
        abort("seed_retired: raw " + raw.to_string() + " is still active")
      }
    }
    self.tombstones.add(raw)
    if raw >= self.next_raw {
      self.next_raw = raw + 1
    }
  }
}

///|
/// Return the set of tombstoned raws as a sorted array (copy, not live reference).
fn RawKindRegistry::tombstoned_rawns(self : Self) -> Array[Int] {
  let raws = self.tombstones.to_array()
  raws.sort()
  raws
}
