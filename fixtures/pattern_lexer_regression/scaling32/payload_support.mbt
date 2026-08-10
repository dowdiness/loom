///|
let payload_log : Array[String] = []

///|
fn record_payload(value : String) -> String {
  payload_log.push(value)
  value
}
