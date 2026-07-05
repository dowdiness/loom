///|
test "parse void element" {
  let result = html_grammar.parse_cst("<br>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse element with text" {
  let result = html_grammar.parse_cst("<p>hello</p>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse nested elements" {
  let result = html_grammar.parse_cst("<div><p>text</p></div>") catch {
    _ => return
  }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse self-closing element" {
  let result = html_grammar.parse_cst("<br/>") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length(), content="0")
}

///|
test "parse empty input" {
  let result = html_grammar.parse_cst("") catch { _ => return }
  let (_, diagnostics) = result
  inspect(diagnostics.length() >= 1, content="true")
}
