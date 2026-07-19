///|
pub fn is_value_start(token : Token) -> Bool {
  match token {
    LBrace | LBracket | StringLit | NumberLit | True | False | Null => true
    _ => false
  }
}
