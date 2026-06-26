///|
/// Persistent append-only RawKind registry (fork i ADR).
pub(all) struct RawKindRegistry {
  mut known : Map[String, Int]
  mut next_raw : Int
}

///|
pub fn RawKindRegistry::new() -> Self {
  { known: Map([]), next_raw: 0 }
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
pub fn RawKindRegistry::retire(_self : Self, _name : String) -> Unit {

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
