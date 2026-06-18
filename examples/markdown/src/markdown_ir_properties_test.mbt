///|
fn markdown_property_small_nonnegative(seed : Int) -> Int {
  let n = seed % 1000
  if n < 0 {
    -n
  } else {
    n
  }
}

///|
fn markdown_property_safe_text(prefix : String, seed : Int) -> String {
  prefix + markdown_property_small_nonnegative(seed).to_string()
}

///|
fn markdown_property_list_item_source(seed : Int, index : Int) -> String {
  "- " + markdown_property_safe_text("item", seed + index)
}

///|
fn markdown_property_unordered_list_source(
  item_count : Int,
  seed : Int,
  trailing_newline? : Bool = true,
) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < item_count; i = i + 1 {
    buf.write_string(markdown_property_list_item_source(seed, i))
    if trailing_newline || i + 1 < item_count {
      buf.write_string("\n")
    }
  }
  buf.to_string()
}

///|
fn markdown_property_unordered_list_source_with_replacement(
  item_count : Int,
  seed : Int,
  target_index : Int,
  replacement : String,
) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < item_count; i = i + 1 {
    if i == target_index {
      buf.write_string("- " + replacement)
    } else {
      buf.write_string(markdown_property_list_item_source(seed, i))
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
fn assert_markdown_property_heading_case(depth : Int, seed : Int) -> Unit raise {
  let text = markdown_property_safe_text("Title", seed)
  let marker = "#".repeat(depth)
  let source = marker + " " + text + "\n"
  let ir = markdown_ir_from_source(source)
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  inspect(
    experimental_markdown_ir_canonical_format(ir),
    content=marker + " " + text,
  )
  match ir.children() {
    [heading] =>
      match heading.content_origin() {
        Some(origin) => {
          let replacement = markdown_property_safe_text("Renamed", seed)
          let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
            ir,
            source,
            target_origin=origin,
            replacement_text=replacement,
          )
          inspect(local_rewrite, content=marker + " " + replacement + "\n")
          inspect(local_rewrite != source, content="true")
          inspect(
            local_rewrite != experimental_markdown_ir_canonical_format(ir),
            content="true",
          )
        }
        None => inspect("missing", content="heading content origin")
      }
    _ => inspect("unexpected child count", content="one heading")
  }
}

///|
fn assert_markdown_property_list_case(
  item_count : Int,
  seed : Int,
) -> Unit raise {
  let source = markdown_property_unordered_list_source(item_count, seed)
  let canonical_source = markdown_property_unordered_list_source(
    item_count,
    seed,
    trailing_newline=false,
  )
  let ir = markdown_ir_from_source(source)
  inspect(experimental_markdown_ir_preserve_rewrite(ir, source), content=source)
  let canonical = experimental_markdown_ir_canonical_format(ir)
  inspect(canonical, content=canonical_source)
  inspect(
    experimental_markdown_ir_canonical_format(
      markdown_ir_from_source(canonical),
    ),
    content=canonical,
  )
  match ir.children() {
    [list] =>
      match list.children() {
        [] => inspect("unexpected list children", content="at least one item")
        items => {
          for i = 0; i < items.length(); i = i + 1 {
            let item = items[i]
            inspect(
              experimental_markdown_ir_preserve_rewrite(item, source),
              content=markdown_property_list_item_source(seed, i),
            )
          }
          let target_indices = if item_count == 1 {
            [0]
          } else if item_count == 2 {
            [0, 1]
          } else {
            [0, item_count / 2, item_count - 1]
          }
          for target_index in target_indices {
            let target_item = items[target_index]
            match target_item.content_origin() {
              Some(origin) => {
                let replacement = markdown_property_safe_text(
                  "changed",
                  seed + target_index,
                )
                let local_rewrite = experimental_markdown_ir_local_transform_rewrite(
                  ir,
                  source,
                  target_origin=origin,
                  replacement_text=replacement,
                )
                inspect(
                  local_rewrite,
                  content=markdown_property_unordered_list_source_with_replacement(
                    item_count, seed, target_index, replacement,
                  ),
                )
                inspect(local_rewrite != source, content="true")
                inspect(local_rewrite != canonical, content="true")
              }
              None => inspect("missing", content="list item content origin")
            }
          }
        }
      }
    _ => inspect("unexpected child count", content="one list")
  }
}

///|
test "property: MarkdownIR heading rewrite modes preserve ATX depth" {
  for depth in [1, 2, 3, 4, 5, 6] {
    assert_markdown_property_heading_case(depth, depth)
  }
  let seeds : Array[Int] = @quickcheck.samples(64)
  for seed in seeds {
    let depth = markdown_property_small_nonnegative(seed) % 6 + 1
    assert_markdown_property_heading_case(depth, seed)
  }
}

///|
test "property: MarkdownIR unordered list rewrite modes preserve item origins" {
  for item_count in [1, 2, 3, 4, 5, 6, 7, 8] {
    assert_markdown_property_list_case(item_count, item_count)
  }
  let seeds : Array[Int] = @quickcheck.samples(64)
  for seed in seeds {
    let item_count = markdown_property_small_nonnegative(seed) % 8 + 1
    assert_markdown_property_list_case(item_count, seed)
  }
}
