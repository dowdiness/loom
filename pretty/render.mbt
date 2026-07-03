///|
/// Rendering mode, decided per-Group. Once a Group chooses Break,
/// all Line nodes inside see Break. But nested Groups can independently
/// choose Flat — each Group is a separate decision point.
priv enum Mode {
  Flat
  Break
}

///|
/// Rendered command stream produced by `resolve`.
/// Consumed by `render_string` (ignores annotations) or `render_spans` (collects them).
pub(all) enum Cmd[A] {
  CText(String)
  CNewline(Int)
  CAnnStart(A)
  CAnnEnd(A)
} derive(Debug, Eq)

///|
pub impl[A : Debug] Show for Cmd[A] with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Width of the entire layout when rendered flat (all Lines become spaces).
/// Returns -1 if the layout contains HardLine (cannot be flattened).
/// O(1) — reads from the cached fw field.
pub fn[A] flat_width(layout : Layout[A]) -> Int {
  layout_fw(layout)
}

///|
/// Width of content before the first HardLine in the layout.
/// Used when computing suffix width for the left child of a Concat
/// whose right child contains a HardLine: only the text before that
/// break shares a line with whatever Group is to the left.
pub fn[A] prefix_flat_width(layout : Layout[A]) -> Int {
  match layout {
    Empty(_) => 0
    Text(s, _) => s.length()
    Line(_) => 1
    HardLine(_) => 0
    Nest(_, doc, _) => prefix_flat_width(doc)
    Concat(l, r, _) => {
      let lw = prefix_flat_width(l)
      if has_hardline_trait(l) {
        lw
      } else {
        lw + prefix_flat_width(r)
      }
    }
    Group(doc, _) => layout_fw(doc)
    Annotate(_, doc, _) => prefix_flat_width(doc)
  }
}

///|
/// Wadler-Lindig layout resolution with suffix-aware Group decisions.
///
/// Walks the Layout tree recursively, resolving each Group's Flat/Break
/// decision greedily: if fw(group) + suffix_fw fits in the remaining line
/// width, choose Flat; otherwise Break.
///
/// fw is cached in the Layout constructor (see layout.mbt), so Group
/// decisions are O(1) — no recursive tree traversal at resolution time.
///
/// The suffix_fw parameter carries the flat width of content that follows
/// on the same line — so a Group considers not just its own content but
/// also what comes after it before the next line break.
pub fn[A] resolve(width : Int, layout : Layout[A]) -> Array[Cmd[A]] {
  let cmds : Array[Cmd[A]] = []
  fn go(
    indent : Int,
    mode : Mode,
    column : Int,
    lay : Layout[A],
    suffix_fw : Int,
  ) -> Int {
    match lay {
      Empty(_) => column
      Text(s, _) => {
        cmds.push(CText(s))
        column + s.length()
      }
      Line(_) =>
        match mode {
          Flat => {
            cmds.push(CText(" "))
            column + 1
          }
          Break => {
            cmds.push(CNewline(indent))
            indent
          }
        }
      // HardLine breaks unconditionally — Mode is ignored
      HardLine(_) => {
        cmds.push(CNewline(indent))
        indent
      }
      Nest(i, doc, _) => go(indent + i, mode, column, doc, suffix_fw)
      Concat(l, r, _) => {
        let r_fw = layout_fw(r)
        // When r can be fully flattened, left's suffix is r's width + outer suffix.
        // When r contains HardLine (r_fw < 0), only the content before that
        // break shares a line with l — use prefix_flat_width(r) instead.
        let left_suffix = if r_fw >= 0 {
          r_fw + suffix_fw
        } else {
          prefix_flat_width(r) + suffix_fw
        }
        let col = go(indent, mode, column, l, left_suffix)
        go(indent, mode, col, r, suffix_fw)
      }
      // Group creates a NEW decision point independent of parent's mode.
      // Nested Groups can choose Flat even inside a parent that chose Break.
      Group(doc, _) => {
        let fw = layout_fw(doc)
        let m = if fw >= 0 && fw + suffix_fw <= width - column {
          Flat
        } else {
          Break
        }
        go(indent, m, column, doc, suffix_fw)
      }
      Annotate(ann, doc, _) => {
        cmds.push(CAnnStart(ann))
        let col = go(indent, mode, column, doc, suffix_fw)
        cmds.push(CAnnEnd(ann))
        col
      }
    }
  }

  let _ = go(0, Break, 0, layout, 0)
  cmds
}
