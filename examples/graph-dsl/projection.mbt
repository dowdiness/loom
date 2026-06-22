///|
priv struct RawGraphNode {
  binding : String
  binding_token : GraphToken
  constructor_name : String
  constructor_token : GraphToken
  params : Array[GraphParam]
  output_tokens : Array[GraphToken]
  start : Int
  end : Int
  argument_insert_offset : Int
  connection_separator : Bool
} derive(Eq)

///|
fn RawGraphNode::RawGraphNode(
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
) -> RawGraphNode {
  {
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
priv struct RawGraphProjection {
  source : String
  nodes : Array[RawGraphNode]
  tokens : Array[GraphToken]
} derive(Eq)

///|
fn RawGraphProjection::RawGraphProjection(
  source~ : String,
  nodes~ : Array[RawGraphNode],
  tokens~ : Array[GraphToken],
) -> RawGraphProjection {
  { source, nodes: nodes.copy(), tokens: tokens.copy() }
}

///|
fn shape_error(error : @seam.ProjectionShapeError) -> String {
  error.message +
  " at " +
  error.start.to_string() +
  ".." +
  error.end.to_string()
}

///|
fn required_token(
  node : @seam.SyntaxNode,
  kind : SyntaxKind,
  message : String,
) -> Result[@seam.SyntaxToken, String] {
  match node.required_direct_token_of_kind(kind.to_raw(), message~) {
    Ok(token) => Ok(token)
    Err(error) => Err(shape_error(error))
  }
}

///|
fn required_child(
  node : @seam.SyntaxNode,
  kind : SyntaxKind,
  message : String,
) -> Result[@seam.SyntaxNode, String] {
  match node.required_direct_child_of_kind(kind.to_raw(), message~) {
    Ok(child) => Ok(child)
    Err(error) => Err(shape_error(error))
  }
}

///|
fn token_with_role(
  role : GraphTokenRole,
  token : @seam.SyntaxToken,
) -> GraphToken {
  GraphToken(role~, text=token.text(), start=token.start(), end=token.end())
}

///|
fn is_input_param(name : String) -> Bool {
  name == "input" || name == "from" || name == "source"
}

///|
fn project_argument(
  arg : @seam.SyntaxNode,
) -> Result[(GraphParam, Array[GraphToken]), String] {
  let name_syntax = match
    required_token(
      arg,
      IdentifierToken,
      "graph argument requires exactly one direct name token",
    ) {
    Ok(token) => token
    Err(message) => return Err(message)
  }
  let value = match
    required_child(
      arg,
      ValueNode,
      "graph argument requires exactly one direct value node",
    ) {
    Ok(child) => child
    Err(message) => return Err(message)
  }
  let name = name_syntax.text()
  let name_token = token_with_role(ParameterName, name_syntax)
  let value_tokens : Array[GraphToken] = []
  let value_kind = match value.direct_token_of_kind(NumberToken.to_raw()) {
    Some(number) => {
      value_tokens.push(token_with_role(NumericParameter, number))
      for unit in value.direct_tokens_of_kind(IdentifierToken.to_raw()) {
        value_tokens.push(token_with_role(Unit, unit))
      }
      GraphValueKind::Numeric
    }
    None =>
      match value.direct_token_of_kind(StringToken.to_raw()) {
        Some(string_token) => {
          value_tokens.push(token_with_role(StringField, string_token))
          GraphValueKind::StringValue
        }
        None =>
          match value.direct_token_of_kind(IdentifierToken.to_raw()) {
            Some(identifier) =>
              if is_input_param(name) {
                value_tokens.push(token_with_role(InputReference, identifier))
                GraphValueKind::InputRef
              } else {
                value_tokens.push(token_with_role(EnumField, identifier))
                GraphValueKind::EnumValue
              }
            None => return Err("argument '" + name + "' has no value token")
          }
      }
  }
  let all_tokens : Array[GraphToken] = [name_token]
  for token in value_tokens {
    all_tokens.push(token)
  }
  Ok((GraphParam(name~, name_token~, value_kind~, value_tokens~), all_tokens))
}

///|
fn project_output(
  output : @seam.SyntaxNode,
) -> Result[Array[GraphToken], String] {
  let arrow = match
    required_token(
      output,
      ArrowToken,
      "graph output requires exactly one direct arrow token",
    ) {
    Ok(token) => token
    Err(message) => return Err(message)
  }
  let name = match
    required_token(
      output,
      IdentifierToken,
      "graph output requires exactly one direct output name token",
    ) {
    Ok(token) => token
    Err(message) => return Err(message)
  }
  Ok([token_with_role(OutputMarker, arrow), token_with_role(OutputName, name)])
}

///|
fn project_binding(node : @seam.SyntaxNode) -> Result[RawGraphNode, String] {
  let binding_syntax = match
    required_token(
      node,
      IdentifierToken,
      "graph binding requires exactly one direct binding name token",
    ) {
    Ok(token) => token
    Err(message) => return Err(message)
  }
  let call = match
    required_child(
      node,
      CallNode,
      "graph binding requires exactly one direct constructor call",
    ) {
    Ok(child) => child
    Err(message) => return Err(message)
  }
  let constructor_syntax = match
    required_token(
      call,
      IdentifierToken,
      "graph call requires exactly one direct constructor token",
    ) {
    Ok(token) => token
    Err(message) => return Err(message)
  }
  let rparen = match
    required_token(
      call,
      RParenToken,
      "graph call requires a direct closing parenthesis",
    ) {
    Ok(token) => token
    Err(message) => return Err(message)
  }
  let params : Array[GraphParam] = []
  let node_tokens : Array[GraphToken] = [
    token_with_role(NodeBindingName, binding_syntax),
    token_with_role(ConstructorName, constructor_syntax),
  ]
  for arg in call.direct_children_of_kind(ArgumentNode.to_raw()) {
    match project_argument(arg) {
      Ok((param, tokens)) => {
        params.push(param)
        for token in tokens {
          node_tokens.push(token)
        }
      }
      Err(message) => return Err(message)
    }
  }
  let output_tokens : Array[GraphToken] = []
  match node.direct_child_of_kind(OutputNode.to_raw()) {
    Some(output) =>
      match project_output(output) {
        Ok(tokens) =>
          for token in tokens {
            output_tokens.push(token)
            node_tokens.push(token)
          }
        Err(message) => return Err(message)
      }
    None => ()
  }
  Ok(
    RawGraphNode(
      binding=binding_syntax.text(),
      binding_token=token_with_role(NodeBindingName, binding_syntax),
      constructor_name=constructor_syntax.text(),
      constructor_token=token_with_role(ConstructorName, constructor_syntax),
      params~,
      output_tokens~,
      start=node.start(),
      end=node.end(),
      argument_insert_offset=rparen.start(),
      connection_separator=!params.is_empty(),
    ),
  )
}

///|
fn contains_string(items : Array[String], target : String) -> Bool {
  for item in items {
    if item == target {
      return true
    }
  }
  false
}

///|
fn validate_projection(raw : RawGraphProjection) -> Array[String] {
  let errors : Array[String] = []
  let bindings : Array[String] = []
  for node in raw.nodes {
    if contains_string(bindings, node.binding) {
      errors.push("duplicate graph binding: " + node.binding)
    } else {
      bindings.push(node.binding)
    }
  }
  for node in raw.nodes {
    for param in node.params {
      if param.value_kind == GraphValueKind::InputRef {
        for token in param.value_tokens {
          if token.role == InputReference &&
            !contains_string(bindings, token.text) {
            errors.push(
              "unknown input reference '" + token.text + "' in " + node.binding,
            )
          }
        }
      }
    }
  }
  errors
}

///|
fn raw_node_to_leaf(raw : RawGraphNode) -> @loom.ProjectionLeaf {
  @loom.ProjectionLeaf::new(
    raw.binding_token.start,
    raw.binding_token.end,
    raw.binding,
  )
}

///|
fn make_node_id(key : String, occurrence : Int) -> String {
  "node#" + occurrence.to_string() + ":" + key
}

///|
fn build_doc_from_stable(
  raw : RawGraphProjection,
  stable : Array[@loom.StableProjectionLeaf[String]],
) -> GraphDoc {
  let nodes : Array[GraphNode] = []
  for i, raw_node in raw.nodes {
    nodes.push(
      GraphNode(
        id=stable[i].id,
        binding=raw_node.binding,
        binding_token=raw_node.binding_token,
        constructor_name=raw_node.constructor_name,
        constructor_token=raw_node.constructor_token,
        params=raw_node.params,
        output_tokens=raw_node.output_tokens,
        start=raw_node.start,
        end=raw_node.end,
        argument_insert_offset=raw_node.argument_insert_offset,
        connection_separator=raw_node.connection_separator,
      ),
    )
  }
  GraphDoc(source=raw.source, nodes~, tokens=raw.tokens)
}

///|
fn build_doc_with_fresh_ids(raw : RawGraphProjection) -> GraphDoc {
  let stable : Array[@loom.StableProjectionLeaf[String]] = []
  for i, raw_node in raw.nodes {
    let leaf = raw_node_to_leaf(raw_node)
    stable.push(
      @loom.StableProjectionLeaf::new(
        leaf.start,
        leaf.end,
        leaf.key,
        make_node_id(leaf.key, i),
      ),
    )
  }
  build_doc_from_stable(raw, stable)
}

///|
fn project_graph_raw(
  source : String,
  root : @seam.SyntaxNode,
) -> Result[RawGraphProjection, Array[String]] {
  let nodes : Array[RawGraphNode] = []
  let tokens : Array[GraphToken] = []
  let errors : Array[String] = []
  for binding in root.direct_children_of_kind(BindingNode.to_raw()) {
    match project_binding(binding) {
      Ok(node) => {
        nodes.push(node)
        tokens.push(node.binding_token)
        tokens.push(node.constructor_token)
        for param in node.params {
          tokens.push(param.name_token)
          for token in param.value_tokens {
            tokens.push(token)
          }
        }
        for token in node.output_tokens {
          tokens.push(token)
        }
      }
      Err(message) => errors.push(message)
    }
  }
  if !errors.is_empty() {
    return Err(errors)
  }
  let raw = RawGraphProjection(source~, nodes~, tokens~)
  let validation_errors = validate_projection(raw)
  if validation_errors.is_empty() {
    Ok(raw)
  } else {
    Err(validation_errors)
  }
}

///|
pub fn project_graph_source(source : String) -> Result[GraphDoc, Array[String]] {
  let parser = @loom.new_parser(source, graph_grammar)
  let diagnostics = parser.diagnostics().read_or_abort()
  if !diagnostics.is_empty() {
    return Err(diagnostics.format())
  }
  let syntax = parser.syntax_tree().read_or_abort()
  match project_graph_raw(source, syntax) {
    Ok(raw) => Ok(build_doc_with_fresh_ids(raw))
    Err(messages) => Err(messages)
  }
}
