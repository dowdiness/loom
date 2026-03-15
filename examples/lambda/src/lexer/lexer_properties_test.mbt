// Property-based tests for incremental lexer/token buffer

///|
fn clamp_pos(pos : Int, len : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > len {
    len
  } else {
    pos
  }
}

///|
fn next_seed(seed : Int) -> Int {
  let a = 1103515245
  let c = 12345
  let m = 2147483647
  (seed * a + c) % m
}

///|
fn build_source_from_seed(seed : Int, count_raw : Int) -> String {
  let pool = [
    "x", "y", "z", "0", "1", "12", "if", "then", "else", "λ", "\\", ".", "(", ")",
    "+", "-", " ",
  ]
  let mut out = ""
  let count = count_raw.abs() % 20
  let mut s = seed
  let pool_len = pool.length()
  for _i = 0; _i < count; _i = _i + 1 {
    s = next_seed(s)
    let idx = s.abs() % pool_len
    out = out + pool[idx]
  }
  out
}

///|
fn slice_string(s : String, start : Int, end : Int) -> String? {
  let res : Result[StringView, Error] = try? s[start:end]
  match res {
    Ok(view) => Some(view.to_string())
    Err(_) => None
  }
}

///|
fn prop_token_buffer_insert(input : (Int, Int, Int, Int)) -> Bool {
  let (seed_base, seed_insert, count_insert, pos_raw) = input
  let base = build_source_from_seed(seed_base, seed_base)
  let insert = build_source_from_seed(seed_insert, count_insert)
  let base_len = base.length()
  let pos = clamp_pos(pos_raw.abs() % (base_len + 1), base_len)
  let left = slice_string(base, 0, pos)
  let right = slice_string(base, pos, base_len)
  match (left, right) {
    (Some(l), Some(r)) => {
      let new_source = l + insert + r
      let edit = @core.Edit::insert(pos, insert.length())
      let buffer_res = try? @core.TokenBuffer::new(
        base,
        tokenize_fn=tokenize_layout,
        eof_token=@token.EOF,
      )
      match buffer_res {
        Ok(buffer) => {
          let update_res : Result[Unit, @core.LexError] = try? buffer.update(
            edit, new_source,
          )
          let full_res : Result[
            Array[@token.TokenInfo[@token.Token]],
            @core.LexError,
          ] = try? tokenize_layout(new_source)
          match (update_res, full_res) {
            (Ok(_), Ok(full)) =>
              @token.print_token_infos(buffer.get_tokens()) ==
              @token.print_token_infos(full)
            _ => true
          }
        }
        Err(_) => true
      }
    }
    _ => true
  }
}

///|
fn prop_token_buffer_delete(input : (Int, Int, Int)) -> Bool {
  let (seed_base, start_raw, end_raw) = input
  let base = build_source_from_seed(seed_base, seed_base)
  let base_len = base.length()
  let start = clamp_pos(start_raw.abs() % (base_len + 1), base_len)
  let end = clamp_pos(end_raw.abs() % (base_len + 1), base_len)
  let from = if start <= end { start } else { end }
  let to = if start <= end { end } else { start }
  let left = slice_string(base, 0, from)
  let right = slice_string(base, to, base_len)
  match (left, right) {
    (Some(l), Some(r)) => {
      let new_source = l + r
      let edit = @core.Edit::delete(from, to)
      let buffer_res = try? @core.TokenBuffer::new(
        base,
        tokenize_fn=tokenize_layout,
        eof_token=@token.EOF,
      )
      match buffer_res {
        Ok(buffer) => {
          let update_res : Result[Unit, @core.LexError] = try? buffer.update(
            edit, new_source,
          )
          let full_res : Result[
            Array[@token.TokenInfo[@token.Token]],
            @core.LexError,
          ] = try? tokenize_layout(new_source)
          match (update_res, full_res) {
            (Ok(_), Ok(full)) =>
              @token.print_token_infos(buffer.get_tokens()) ==
              @token.print_token_infos(full)
            _ => true
          }
        }
        Err(_) => true
      }
    }
    _ => true
  }
}

///|
fn prop_token_buffer_replace(input : (Int, Int, Int, Int)) -> Bool {
  let (seed_base, seed_insert, start_raw, end_raw) = input
  let base = build_source_from_seed(seed_base, seed_base)
  let insert = build_source_from_seed(seed_insert, seed_insert)
  let base_len = base.length()
  let start = clamp_pos(start_raw.abs() % (base_len + 1), base_len)
  let end = clamp_pos(end_raw.abs() % (base_len + 1), base_len)
  let from = if start <= end { start } else { end }
  let to = if start <= end { end } else { start }
  let left = slice_string(base, 0, from)
  let right = slice_string(base, to, base_len)
  match (left, right) {
    (Some(l), Some(r)) => {
      let new_source = l + insert + r
      let edit = @core.Edit::replace(from, to, from + insert.length())
      let buffer_res = try? @core.TokenBuffer::new(
        base,
        tokenize_fn=tokenize_layout,
        eof_token=@token.EOF,
      )
      match buffer_res {
        Ok(buffer) => {
          let update_res : Result[Unit, @core.LexError] = try? buffer.update(
            edit, new_source,
          )
          let full_res : Result[
            Array[@token.TokenInfo[@token.Token]],
            @core.LexError,
          ] = try? tokenize_layout(new_source)
          match (update_res, full_res) {
            (Ok(_), Ok(full)) =>
              @token.print_token_infos(buffer.get_tokens()) ==
              @token.print_token_infos(full)
            _ => true
          }
        }
        Err(_) => true
      }
    }
    _ => true
  }
}

///|
test "property: token buffer insert matches full tokenize_layout" {
  @qc.quick_check_fn(prop_token_buffer_insert)
}

///|
test "property: token buffer delete matches full tokenize_layout" {
  @qc.quick_check_fn(prop_token_buffer_delete)
}

///|
test "property: token buffer replace matches full tokenize_layout" {
  @qc.quick_check_fn(prop_token_buffer_replace)
}
