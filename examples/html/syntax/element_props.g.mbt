///|
fn classify_element_ascii_lower(name : String) -> String {
  let out = StringBuilder()
  for c in name {
    out.write_char(if c >= 'A' && c <= 'Z' { c.to_ascii_lowercase() } else { c })
  }
  out.to_string()
}

///|
pub fn classify_element(name : String) -> SyntaxKind? {
  match classify_element_ascii_lower(name) {
    "div" => Some(Div)
    "br" => Some(Br)
    "img" => Some(Img)
    "area" => Some(Area)
    "base" => Some(Base)
    "col" => Some(Col)
    "embed" => Some(Embed)
    "hr" => Some(Hr)
    "input" => Some(Input)
    "link" => Some(Link)
    "meta" => Some(Meta)
    "param" => Some(Param)
    "source" => Some(Source)
    "track" => Some(Track)
    "wbr" => Some(Wbr)
    "script" => Some(Script)
    "style" => Some(Style)
    _ => None
  }
}

///|
pub fn is_void_element(kind : SyntaxKind) -> Bool {
  match kind {
    Br | Img | Area | Base | Col | Embed | Hr | Input | Link | Meta | Param | Source | Track | Wbr => true
    _ => false
  }
}

///|
pub fn is_raw_text_element(kind : SyntaxKind) -> Bool {
  match kind {
    Script | Style => true
    _ => false
  }
}
