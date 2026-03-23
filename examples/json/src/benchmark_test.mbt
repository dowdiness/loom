// JSON incremental parser benchmarks.
//
// Exercises realistic JSON structures: nested objects, arrays, mixed types.
// Compares full reparse vs incremental for edits at different positions.
//
// Run with: cd loom/examples/json && moon bench --release

///|
/// Generate a realistic JSON object with n members.
/// Each member has a string key and a value that varies by type:
/// objects, arrays, strings, numbers, booleans, nulls.
fn make_json_object(n : Int) -> String {
  let members : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    let value = match i % 6 {
      // Nested object
      0 =>
        "{\"inner_a\": \{i}, \"inner_b\": \"hello\", \"inner_c\": true}"
      // Array of numbers
      1 => "[\{i}, \{i + 1}, \{i + 2}, \{i + 3}, \{i + 4}]"
      // String
      2 => "\"value_\{i}_with_some_longer_text\""
      // Number
      3 => "\{i * 100 + 42}"
      // Boolean
      4 => if i % 2 == 0 { "true" } else { "false" }
      // Null
      _ => "null"
    }
    members.push("\"key_\{i}\": " + value)
  }
  "{\n  " + members.join(",\n  ") + "\n}"
}

///|
/// Generate a JSON array of n mixed elements.
fn make_json_array(n : Int) -> String {
  let elements : Array[String] = []
  for i = 0; i < n; i = i + 1 {
    let elem = match i % 4 {
      0 =>
        "{\"id\": \{i}, \"name\": \"item_\{i}\", \"active\": true}"
      1 => "[\{i}, \{i + 1}, \{i + 2}]"
      2 => "\"element_\{i}\""
      _ => "\{i * 7}"
    }
    elements.push(elem)
  }
  "[\n  " + elements.join(",\n  ") + "\n]"
}

///|
/// Helper: replace one byte at pos.
fn json_replace_at(source : String, pos : Int, replacement : String) -> String {
  let before : String = try {
    source[:pos].to_string()
  } catch {
    _ => abort("slice error")
  }
  let after : String = try {
    source[pos + 1:].to_string()
  } catch {
    _ => abort("slice error")
  }
  before + replacement + after
}

// ─── Object benchmarks ──────────────────────────────────────────────────────

///|
test "json: 20-member object - full reparse" (b : @bench.T) {
  let source = make_json_object(20)
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "json: 20-member object - incremental (edit last value)" (b : @bench.T) {
  let source = make_json_object(20)
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  // Find "342" (from i=3: 3*100+42=342) and change "3" to "4"
  let edit_target = "342"
  let mut edit_pos = -1
  for i = 0; i < source.length() - 2; i = i + 1 {
    let ch0 : String = try {
      source[i:i + 3].to_string()
    } catch {
      _ => continue
    }
    if ch0 == edit_target {
      edit_pos = i // position of "3" in "342"
      break
    }
  }
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = json_replace_at(source, edit_pos, "4")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "json: 50-member object - full reparse" (b : @bench.T) {
  let source = make_json_object(50)
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "json: 50-member object - incremental (edit inner object)" (b : @bench.T) {
  let source = make_json_object(50)
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  // Edit inside the first nested object (i=0): change "0" to "1" in "inner_a": 0
  let target = "\"inner_a\": 0"
  let mut edit_pos = -1
  for i = 0; i < source.length() - target.length(); i = i + 1 {
    let sub : String = try {
      source[i:i + target.length()].to_string()
    } catch {
      _ => continue
    }
    if sub == target {
      edit_pos = i + target.length() - 1 // position of "0"
      break
    }
  }
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = json_replace_at(source, edit_pos, "1")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

///|
test "json: 100-member object - full reparse" (b : @bench.T) {
  let source = make_json_object(100)
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "json: 100-member object - incremental (edit inner object)" (b : @bench.T) {
  let source = make_json_object(100)
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  let target = "\"inner_a\": 0"
  let mut edit_pos = -1
  for i = 0; i < source.length() - target.length(); i = i + 1 {
    let sub : String = try {
      source[i:i + target.length()].to_string()
    } catch {
      _ => continue
    }
    if sub == target {
      edit_pos = i + target.length() - 1
      break
    }
  }
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = json_replace_at(source, edit_pos, "1")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}

// ─── Array benchmarks ────────────────────────────────────────────────────────

///|
test "json: 50-element array - full reparse" (b : @bench.T) {
  let source = make_json_array(50)
  b.bench(fn() {
    let (cst, _) = parse_cst(source) catch { _ => abort("failed") }
    b.keep(cst)
  })
}

///|
test "json: 50-element array - incremental (edit nested object)" (b : @bench.T) {
  let source = make_json_array(50)
  let parser = @loom.new_imperative_parser(source, json_grammar)
  let _ = parser.parse()
  // Edit "id": 0 → "id": 1 in the first object element
  let target = "\"id\": 0"
  let mut edit_pos = -1
  for i = 0; i < source.length() - target.length(); i = i + 1 {
    let sub : String = try {
      source[i:i + target.length()].to_string()
    } catch {
      _ => continue
    }
    if sub == target {
      edit_pos = i + target.length() - 1
      break
    }
  }
  guard edit_pos >= 0 else { abort("edit target not found") }
  let edited = json_replace_at(source, edit_pos, "1")
  let edit = @core.Edit::replace(edit_pos, edit_pos + 1, edit_pos + 1)
  b.bench(fn() {
    let tree = parser.edit(edit, edited)
    b.keep(tree)
    let _ = parser.edit(edit, source)
  })
}
