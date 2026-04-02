///|
/// FNV-1a hash combination. Used to compute structural hashes for CstNode/CstToken.
pub fn combine_hash(h : Int, value : Int) -> Int {
  let mixed = h ^ value
  mixed * 16777619 // FNV prime
}

///|
/// FNV-1a string hash. Used to hash CstToken text.
pub fn string_hash(s : StringView) -> Int {
  let mut h = -2128831035 // FNV offset basis 2166136261 as signed Int
  for i = 0; i < s.length(); i = i + 1 {
    h = combine_hash(h, s.code_unit_at(i).to_int())
  }
  h
}
