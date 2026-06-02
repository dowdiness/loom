///|
pub struct SourceSpan {
  priv start : Int
  priv end : Int
} derive(Eq, Debug)

///|
fn SourceSpan::SourceSpan(start~ : Int, end~ : Int) -> SourceSpan {
  { start, end }
}

///|
pub fn SourceSpan::start(self : SourceSpan) -> Int {
  self.start
}

///|
pub fn SourceSpan::end(self : SourceSpan) -> Int {
  self.end
}

///|
pub fn SourceSpan::length(self : SourceSpan) -> Int {
  self.end - self.start
}

///|
pub(all) enum GraphTokenRole {
  NodeBindingName
  ConstructorName
  ParameterName
  InputReference
  OutputMarker
  OutputName
  NumericParameter
  Unit
  StringField
  EnumField
} derive(Eq, Debug)

///|
pub impl Show for GraphTokenRole with fn output(self, logger) {
  logger.write_string(
    match self {
      NodeBindingName => "NodeBindingName"
      ConstructorName => "ConstructorName"
      ParameterName => "ParameterName"
      InputReference => "InputReference"
      OutputMarker => "OutputMarker"
      OutputName => "OutputName"
      NumericParameter => "NumericParameter"
      Unit => "Unit"
      StringField => "StringField"
      EnumField => "EnumField"
    },
  )
}

///|
pub enum GraphValueKind {
  Numeric
  StringValue
  EnumValue
  InputRef
} derive(Eq, Debug)

///|
pub impl Show for GraphValueKind with fn output(self, logger) {
  logger.write_string(
    match self {
      Numeric => "Numeric"
      StringValue => "StringValue"
      EnumValue => "EnumValue"
      InputRef => "InputRef"
    },
  )
}

///|
pub struct GraphToken {
  priv role : GraphTokenRole
  priv text : String
  priv start : Int
  priv end : Int
} derive(Eq, Debug)

///|
fn GraphToken::GraphToken(
  role~ : GraphTokenRole,
  text~ : String,
  start~ : Int,
  end~ : Int,
) -> GraphToken {
  { role, text, start, end }
}

///|
pub fn GraphToken::role(self : GraphToken) -> GraphTokenRole {
  self.role
}

///|
pub fn GraphToken::text(self : GraphToken) -> String {
  self.text
}

///|
pub fn GraphToken::start(self : GraphToken) -> Int {
  self.start
}

///|
pub fn GraphToken::end(self : GraphToken) -> Int {
  self.end
}

///|
pub fn GraphToken::span(self : GraphToken) -> SourceSpan {
  SourceSpan(start=self.start, end=self.end)
}

///|
pub struct GraphParam {
  priv name : String
  priv name_token : GraphToken
  priv value_kind : GraphValueKind
  priv value_tokens : Array[GraphToken]
} derive(Eq, Debug)

///|
fn GraphParam::GraphParam(
  name~ : String,
  name_token~ : GraphToken,
  value_kind~ : GraphValueKind,
  value_tokens~ : Array[GraphToken],
) -> GraphParam {
  { name, name_token, value_kind, value_tokens: value_tokens.copy() }
}

///|
pub fn GraphParam::name(self : GraphParam) -> String {
  self.name
}

///|
pub fn GraphParam::name_token(self : GraphParam) -> GraphToken {
  self.name_token
}

///|
pub fn GraphParam::value_kind(self : GraphParam) -> GraphValueKind {
  self.value_kind
}

///|
pub fn GraphParam::value_tokens(self : GraphParam) -> Array[GraphToken] {
  self.value_tokens.copy()
}

///|
pub struct GraphNode {
  priv id : String
  priv binding : String
  priv binding_token : GraphToken
  priv constructor_name : String
  priv constructor_token : GraphToken
  priv params : Array[GraphParam]
  priv output_tokens : Array[GraphToken]
  priv start : Int
  priv end : Int
  priv argument_insert_offset : Int
  priv connection_separator : Bool
} derive(Eq, Debug)

///|
fn GraphNode::GraphNode(
  id~ : String,
  binding~ : String,
  binding_token~ : GraphToken,
  constructor_name~ : String,
  constructor_token~ : GraphToken,
  params~ : Array[GraphParam],
  output_tokens~ : Array[GraphToken],
  start~ : Int,
  end~ : Int,
  argument_insert_offset~ : Int,
  connection_separator~ : Bool,
) -> GraphNode {
  {
    id,
    binding,
    binding_token,
    constructor_name,
    constructor_token,
    params: params.copy(),
    output_tokens: output_tokens.copy(),
    start,
    end,
    argument_insert_offset,
    connection_separator,
  }
}

///|
pub fn GraphNode::id(self : GraphNode) -> String {
  self.id
}

///|
pub fn GraphNode::binding(self : GraphNode) -> String {
  self.binding
}

///|
pub fn GraphNode::binding_token(self : GraphNode) -> GraphToken {
  self.binding_token
}

///|
pub fn GraphNode::constructor_name(self : GraphNode) -> String {
  self.constructor_name
}

///|
pub fn GraphNode::constructor_token(self : GraphNode) -> GraphToken {
  self.constructor_token
}

///|
pub fn GraphNode::params(self : GraphNode) -> Array[GraphParam] {
  self.params.copy()
}

///|
pub fn GraphNode::output_tokens(self : GraphNode) -> Array[GraphToken] {
  self.output_tokens.copy()
}

///|
pub fn GraphNode::start(self : GraphNode) -> Int {
  self.start
}

///|
pub fn GraphNode::end(self : GraphNode) -> Int {
  self.end
}

///|
pub struct GraphDoc {
  priv source : String
  priv nodes : Array[GraphNode]
  priv tokens : Array[GraphToken]
} derive(Eq, Debug)

///|
fn GraphDoc::GraphDoc(
  source~ : String,
  nodes~ : Array[GraphNode],
  tokens~ : Array[GraphToken],
) -> GraphDoc {
  { source, nodes: nodes.copy(), tokens: tokens.copy() }
}

///|
pub fn GraphDoc::source(self : GraphDoc) -> String {
  self.source
}

///|
pub fn GraphDoc::nodes(self : GraphDoc) -> Array[GraphNode] {
  self.nodes.copy()
}

///|
pub fn GraphDoc::tokens(self : GraphDoc) -> Array[GraphToken] {
  self.tokens.copy()
}

///|
pub fn GraphDoc::tokens_for_role(
  self : GraphDoc,
  role : GraphTokenRole,
) -> Array[GraphToken] {
  let result : Array[GraphToken] = []
  for token in self.tokens {
    if token.role == role {
      result.push(token)
    }
  }
  result
}

///|
pub fn GraphDoc::find_node(self : GraphDoc, binding : String) -> GraphNode? {
  for node in self.nodes {
    if node.binding == binding {
      return Some(node)
    }
  }
  None
}
