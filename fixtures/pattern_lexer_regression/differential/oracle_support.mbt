///|
let payload_log : Array[String] = []

///|
fn record_payload(value : String) -> String {
  payload_log.push(value)
  value
}

///|
let custom_log : Array[String] = []

///|
fn custom_first(source : String, pos : Int) -> @core.LexStep[Token] {
  custom_log.push("first")
  let cursor = @core.LexCursor::new(source, pos)
  if cursor.starts_with("#") {
    cursor.advance_code_units(1)
    cursor.produced(CustomFirst)
  } else {
    Done
  }
}

///|
fn custom_second(source : String, pos : Int) -> @core.LexStep[Token] {
  custom_log.push("second")
  let cursor = @core.LexCursor::new(source, pos)
  if cursor.starts_with("@") {
    cursor.advance_code_units(1)
    cursor.produced(CustomSecond)
  } else {
    Done
  }
}
