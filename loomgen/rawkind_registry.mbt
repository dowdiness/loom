///|
/// Persistent append-only RawKind registry derived from the Fork architecture decision.
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

///|
/// Extract (kind_name, raw) pairs from an existing syntax_kind.mbt file.
/// Scans lines for `Name => number` or `Name => @seam.RawKind(number)` patterns
/// in the ToRawKind impl or equivalent raw-kind assignment arms.
fn extract_raw_pairs(source : String) -> Array[(String, Int)] {
  let pairs : Array[(String, Int)] = []
  let lines = source.split("\n").to_array()
  for line in lines {
    let trimmed = line.trim().to_owned()
    let parts = trimmed.split(" => ").to_array()
    if parts.length() != 2 {
      continue
    }
    let name = parts[0].to_owned()
    if name.length() == 0 {
      continue
    }
    let raw_str = parts[1].to_owned()
    let first_char = name[0]
    if first_char < 'A' || first_char > 'Z' {
      continue
    }
    // Accept bare numbers (Name => 14) or RawKind wrapper (Name => @seam.RawKind(14))
    let raw_val = if is_all_digits(raw_str) {
      Some(parse_int(raw_str))
    } else {
      // Try to extract from RawKind(N) wrapper
      let stripped = raw_str.trim().to_owned()
      // Match @seam.RawKind(N) or bare RawKind(N), no other prefix.
      let inner_text : String? = if stripped.has_prefix("@seam.RawKind(") {
        Some(stripped["@seam.RawKind(".length():].to_owned())
      } else if stripped.has_prefix("RawKind(") {
        Some(stripped["RawKind(".length():].to_owned())
      } else {
        None
      }
      match inner_text {
        Some(body) => {
          // Find closing paren position
          let mut close = -1
          for j = 0; j < body.length(); j = j + 1 {
            if body[j] == ')' {
              close = j
              break
            }
          }
          if close >= 0 {
            let inner = body[:close].trim().to_owned()
            if is_all_digits(inner) {
              Some(parse_int(inner))
            } else {
              None
            }
          } else {
            None
          }
        }
        None => None
      }
    }
    match raw_val {
      Some(raw) => pairs.push((name, raw))
      None => continue
    }
  }
  pairs
}

///|
/// Parse tombstoned raw numbers from a previously-generated syntax_kind.mbt (or .g.mbt).
fn extract_retired_rawns(source : String) -> Array[Int] {
  let raws : Array[Int] = []
  let lines = source.split("\n").to_array()
  for line in lines {
    let trimmed = line.trim().to_owned()
    let prefix = "// #loom.retired: "
    if trimmed.has_prefix(prefix) {
      let suffix = trimmed[prefix.length():].trim().to_owned()
      for part in suffix.split(",").to_array() {
        let raw_str = part.trim().to_owned()
        if is_all_digits(raw_str) {
          raws.push(parse_int(raw_str))
        }
      }
    }
  }
  raws
}

///|
fn parse_int(s : String) -> Int {
  for i = 0, n = 0; i < s.length(); {
    let c = s[i]
    if c >= '0' && c <= '9' {
      continue i + 1, n * 10 + (c.to_int() - '0'.to_int())
    }
    continue i + 1, n
  } nobreak {
    n
  }
}

///|
fn is_all_digits(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  for i in 0..<s.length() {
    if s[i] < '0' || s[i] > '9' {
      return false
    }
  }
  true
}
