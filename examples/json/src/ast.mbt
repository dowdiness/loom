///|
pub(all) enum JsonValue {
  Null
  Bool(Bool)
  Number(Double)
  String(String)
  Array(Array[JsonValue])
  Object(Array[(String, JsonValue)])
  Error(String)
} derive(Eq, Debug, ToJson)

///|
pub impl Show for JsonValue with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
