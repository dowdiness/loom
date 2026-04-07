// Edit representation for incremental parsing
// Represents a change to the source text

///|
/// Represents an edit to the source
pub(all) struct Edit {
  start : Int // Start position in old source
  old_len : Int // Code units removed  (was: old_end - start)
  new_len : Int // Code units inserted (was: new_end - start)
} derive(Debug, Eq)

///|
/// Create a new edit
pub fn Edit::new(start : Int, old_len : Int, new_len : Int) -> Edit {
  { start, old_len, new_len }
}

///|
/// Computed endpoint: end position in old source
pub fn Edit::old_end(self : Edit) -> Int {
  self.start + self.old_len
}

///|
/// Computed endpoint: end position in new source
pub fn Edit::new_end(self : Edit) -> Int {
  self.start + self.new_len
}

///|
/// Get the length of deleted text
pub fn Edit::deleted_length(self : Edit) -> Int {
  self.old_len
}

///|
/// Get the length of inserted text
pub fn Edit::inserted_length(self : Edit) -> Int {
  self.new_len
}

///|
/// Get the delta (change in length)
pub fn Edit::delta(self : Edit) -> Int {
  self.new_len - self.old_len
}

///|
/// Apply edit to a position, returning the new position
pub fn Edit::apply_to_position(self : Edit, pos : Int) -> Int {
  if pos < self.start {
    // Position is before the edit
    pos
  } else if pos <= self.old_end() {
    // Position is within the edited range
    // Map to start of new text
    self.start
  } else {
    // Position is after the edit
    pos + self.delta()
  }
}

///|
/// Check if a position is affected by this edit
pub fn Edit::affects_position(self : Edit, pos : Int) -> Bool {
  pos >= self.start && pos <= self.old_end()
}

///|
/// Check if a range overlaps with this edit
pub fn Edit::overlaps_range(self : Edit, start : Int, end : Int) -> Bool {
  // Ranges overlap if one starts before the other ends
  self.start < end && start < self.old_end()
}

///|
/// Create an edit for inserting text
pub fn Edit::insert(position : Int, length : Int) -> Edit {
  { start: position, old_len: 0, new_len: length }
}

///|
/// Create an edit for deleting text
pub fn Edit::delete(start : Int, end : Int) -> Edit {
  { start, old_len: end - start, new_len: 0 }
}

///|
/// Create an edit for replacing text
pub fn Edit::replace(start : Int, old_end : Int, new_end : Int) -> Edit {
  { start, old_len: old_end - start, new_len: new_end - start }
}

///|
/// Print edit as a string
pub fn Edit::to_string(self : Edit) -> String {
  "Edit { start: " +
  self.start.to_string() +
  ", old_end: " +
  self.old_end().to_string() +
  ", new_end: " +
  self.new_end().to_string() +
  ", delta: " +
  self.delta().to_string() +
  " }"
}

///|
pub trait Editable {
  start(Self) -> Int
  old_len(Self) -> Int
  new_len(Self) -> Int
}

///|
pub impl Editable for Edit with start(self) {
  self.start
}

///|
pub impl Editable for Edit with old_len(self) {
  self.old_len
}

///|
pub impl Editable for Edit with new_len(self) {
  self.new_len
}
