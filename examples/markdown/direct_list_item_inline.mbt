///|
/// Direct list-item marker lines containing only spaces or tabs do not start
/// or retain a paragraph. Structured inline nodes still count as content so
/// whitespace-bearing syntax such as `` ` ` `` and empty links stay visible.
fn direct_list_item_text_has_non_blank_content(text : String) -> Bool {
  !text.trim(chars=" \t").is_empty()
}

///|
fn[T] retain_direct_list_item_inline_children(
  children : Array[T],
  has_non_blank_content : (T) -> Bool,
) -> Array[T] {
  if children.iter().any(has_non_blank_content) {
    children
  } else {
    []
  }
}
