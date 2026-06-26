///|
/// Persistent append-only RawKind registry (fork i ADR).
/// Tracks tombstoned raws so retired kind numbers are never reused.
pub(all) struct RawKindRegistry {
  mut known : Map[String, Int]
  mut next_raw : Int
  mut tombstones : @hashset.HashSet[Int]
}

///|
pub fn RawKindRegistry::new() -> Self {
  { known: Map([]), next_raw: 0, tombstones: @hashset.HashSet([]) }
}

///|
pub fn RawKindRegistry::assign(self : Self, name : String) -> Int {
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
pub fn RawKindRegistry::reserve(self : Self, name : String, raw : Int) -> Unit {
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
/// Retire a kind by name: removes it from the active set and tombstoned its raw
/// number so it will never be reassigned.
pub fn RawKindRegistry::retire(self : Self, name : String) -> Unit {
  match self.known.get(name) {
    Some(raw) => {
      self.known.remove(name)
      self.tombstones.add(raw)
      if raw >= self.next_raw {
        self.next_raw = raw + 1
      }
    }
    None => ()
  }
}

///|
pub fn RawKindRegistry::seed(
  self : Self,
  entries : Array[(String, Int)],
) -> Unit {
  for pair in entries {
    let (name, raw) = pair
    self.reserve(name, raw)
  }
}

///|
pub fn RawKindRegistry::to_pairs(self : Self) -> Array[(String, Int)] {
  let pairs : Array[(String, Int)] = []
  for pair in self.known {
    pairs.push(pair)
  }
  pairs
}

///|
/// Seed tombstoned raws so they block future reuse across regeneration cycles.
/// `rawns`: raw numbers to block (taken from prior generated output).
pub fn RawKindRegistry::seed_retired(self : Self, rawns : Array[Int]) -> Unit {
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
pub fn RawKindRegistry::tombstoned_rawns(self : Self) -> @hashset.HashSet[Int] {
  self.tombstones
}

///|
pub fn RawKindRegistry::has_retired(self : Self) -> Bool {
  self.tombstones.length() > 0
}
