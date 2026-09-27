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
pub impl Show for JsonValue with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend JsonValue with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend JsonValue with Eq::{equal, not_equal}

///|
pub extend JsonValue with Show::{output, to_string}

///|
pub extend JsonValue with ToJson::{to_json}
