///|
const MIN_FIRST_GUARD_CANDIDATES = 16

///|
fn empty_first_info() -> FirstInfo {
  FirstInfo(Finite([]), true)
}

///|
fn any_first_info(nullable : Bool) -> FirstInfo {
  FirstInfo(Any, nullable)
}

///|
fn finite_first_info(unit : UInt16, nullable : Bool) -> FirstInfo {
  FirstInfo(Finite([(unit, unit)]), nullable)
}

///|
fn union_first_units(
  left : FirstCodeUnits,
  right : FirstCodeUnits,
) -> FirstCodeUnits {
  match (left, right) {
    (Any, _) | (_, Any) => Any
    (Finite(left_ranges), Finite(right_ranges)) => {
      let ranges = left_ranges.copy()
      for range in right_ranges {
        ranges.push(range)
      }
      Finite(ranges)
    }
  }
}

///|
fn escape_first_units(pattern : String, span : PatternSpan) -> FirstCodeUnits {
  guard span.start + 1 < span.end else { return Any }
  match pattern[span.start + 1] {
    't' => Finite([(9, 9)])
    'r' => Finite([(13, 13)])
    'n' => Finite([(10, 10)])
    c if is_literal_meta_escape(c) => Finite([(c, c)])
    _ => Any
  }
}

///|
fn class_literal(pattern : String, pos : Int, limit : Int) -> (UInt16, Int)? {
  guard pos < limit else { return None }
  if pattern[pos] != '\\' {
    Some((pattern[pos], pos + 1))
  } else {
    guard pos + 1 < limit else { return None }
    match pattern[pos + 1] {
      't' => Some((9, pos + 2))
      'r' => Some((13, pos + 2))
      'n' => Some((10, pos + 2))
      c if is_literal_meta_escape(c) => Some((c, pos + 2))
      _ => None
    }
  }
}

///|
fn class_first_units(pattern : String, span : PatternSpan) -> FirstCodeUnits {
  guard span.end - span.start >= 3 else { return Any }
  let limit = span.end - 1
  let mut posix_scan = span.start + 1
  while posix_scan + 1 < limit {
    if pattern[posix_scan] == '[' && pattern[posix_scan + 1] == ':' {
      return Any
    }
    posix_scan = posix_scan + 1
  }
  let mut pos = span.start + 1
  if pattern[pos] == '^' {
    return Any
  }
  let ranges : Array[(UInt16, UInt16)] = []
  while pos < limit {
    guard class_literal(pattern, pos, limit) is Some((start, after_start)) else {
      return Any
    }
    pos = after_start
    if pos + 1 < limit && pattern[pos] == '-' {
      guard class_literal(pattern, pos + 1, limit) is Some((end, after_end)) else {
        return Any
      }
      guard start <= end else { return Any }
      ranges.push((start, end))
      pos = after_end
    } else {
      ranges.push((start, start))
    }
  }
  if ranges.length() == 0 {
    Any
  } else {
    Finite(ranges)
  }
}

///|
fn first_of_pattern(pattern : String, node : Pattern) -> FirstInfo {
  match node {
    Pattern::Empty => empty_first_info()
    Pattern::Anchor => empty_first_info()
    Pattern::Literal(span) =>
      if pattern[span.start] == '.' {
        any_first_info(false)
      } else {
        finite_first_info(pattern[span.start], false)
      }
    Pattern::Escape(span) => FirstInfo(escape_first_units(pattern, span), false)
    Pattern::Class(span) => FirstInfo(class_first_units(pattern, span), false)
    Pattern::Group(inner) => first_of_pattern(pattern, inner)
    Pattern::Seq(parts) => {
      let mut units = FirstCodeUnits::Finite([])
      let mut nullable = true
      for part in parts {
        let info = first_of_pattern(pattern, part)
        units = union_first_units(units, info.units)
        if !info.nullable {
          nullable = false
          break
        }
      }
      FirstInfo(units, nullable)
    }
    Pattern::Quantified(inner, quantifier) => {
      let info = first_of_pattern(pattern, inner)
      match quantifier.kind {
        QuantifierKind::ZeroOrMore | QuantifierKind::Optional =>
          FirstInfo(info.units, true)
        QuantifierKind::OneOrMore => FirstInfo(info.units, info.nullable)
        QuantifierKind::Counted(bounds) =>
          match bounds {
            RepeatBounds::Exact(count) =>
              if count.to_int() == 0 {
                empty_first_info()
              } else {
                FirstInfo(info.units, info.nullable)
              }
            RepeatBounds::AtLeast(_) => FirstInfo(info.units, true)
            RepeatBounds::Range(bounds) =>
              if bounds.min.to_int() == 0 && bounds.max.to_int() == 0 {
                empty_first_info()
              } else {
                FirstInfo(info.units, bounds.min.to_int() == 0 || info.nullable)
              }
          }
      }
    }
  }
}

///|
fn ascii_first_units(units : FirstCodeUnits) -> FirstCodeUnits {
  match units {
    FirstCodeUnits::Any => FirstCodeUnits::Any
    FirstCodeUnits::Finite(ranges) =>
      if ranges.iter().any(range => range.0 > 127 || range.1 > 127) {
        FirstCodeUnits::Any
      } else {
        FirstCodeUnits::Finite(ranges)
      }
  }
}

///|
fn first_units_for_pattern(pattern : String) -> FirstCodeUnits {
  match parse_pattern(pattern) {
    Ok(parsed) => ascii_first_units(first_of_pattern(pattern, parsed).units)
    Err(_) => FirstCodeUnits::Any
  }
}

///|
fn first_units_for_lexer_candidate(variant : VariantDecl) -> FirstCodeUnits {
  match effective_pattern(variant) {
    Some(pattern) => first_units_for_pattern(pattern)
    None =>
      match variant.role {
        Some(SyntaxRole::Punct(lit)) =>
          if lit.length() == 0 {
            FirstCodeUnits::Any
          } else {
            ascii_first_units(FirstCodeUnits::Finite([(lit[0], lit[0])]))
          }
        _ => FirstCodeUnits::Any
      }
  }
}

///|
fn is_first_dispatch_candidate(variant : VariantDecl) -> Bool {
  effective_pattern(variant) is Some(_) ||
  variant.role is Some(SyntaxRole::Punct(_))
}

///|
fn should_emit_first_guards(variants : Array[VariantDecl]) -> Bool {
  let mut candidate_count = 0
  let mut finite_count = 0
  let first_sets : Array[FirstCodeUnits] = []
  for variant in variants {
    if is_first_dispatch_candidate(variant) {
      candidate_count = candidate_count + 1
      let units = first_units_for_lexer_candidate(variant)
      match units {
        FirstCodeUnits::Finite(ranges) =>
          if ranges.length() > 0 {
            finite_count = finite_count + 1
            if !first_sets.iter().any(existing => existing == units) {
              first_sets.push(units)
            }
          }
        FirstCodeUnits::Any => ()
      }
    }
  }
  candidate_count >= MIN_FIRST_GUARD_CANDIDATES &&
  finite_count >= 2 &&
  first_sets.length() >= 2
}

///|
/// Keep generated branch count bounded when FIRST sets are highly fragmented.
const MAX_FIRST_REGIONS = 64

///|
/// Keep fallback-candidate replay from multiplying generated source size.
const MAX_FIRST_REGION_EMISSIONS = 512

///|
struct FirstDispatchRegion {
  units : FirstCodeUnits
  variants : Array[VariantDecl]
}

///|
fn FirstDispatchRegion::FirstDispatchRegion(
  units : FirstCodeUnits,
  variants : Array[VariantDecl],
) -> FirstDispatchRegion {
  { units, variants }
}

///|
struct FirstDispatchPlan {
  regions : Array[FirstDispatchRegion]
  fallback : Array[VariantDecl]
}

///|
fn FirstDispatchPlan::FirstDispatchPlan(
  regions : Array[FirstDispatchRegion],
  fallback : Array[VariantDecl],
) -> FirstDispatchPlan {
  { regions, fallback }
}

///|
fn first_units_overlap(left : FirstCodeUnits, right : FirstCodeUnits) -> Bool {
  match (left, right) {
    (FirstCodeUnits::Any, _) | (_, FirstCodeUnits::Any) => true
    (FirstCodeUnits::Finite(left_ranges), FirstCodeUnits::Finite(right_ranges)) =>
      left_ranges.any(left_range => {
        right_ranges.any(right_range => {
          left_range.0 <= right_range.1 && right_range.0 <= left_range.1
        })
      })
  }
}

///|
fn first_dispatch_plan(variants : Array[VariantDecl]) -> FirstDispatchPlan? {
  let candidates : Array[(VariantDecl, FirstCodeUnits)] = []
  for variant in variants {
    if is_first_dispatch_candidate(variant) {
      candidates.push((variant, first_units_for_lexer_candidate(variant)))
    }
  }
  guard candidates.length() >= MIN_FIRST_GUARD_CANDIDATES else { return None }

  let finite_sets : Array[FirstCodeUnits] = []
  let fallback : Array[VariantDecl] = []
  for candidate in candidates {
    let (variant, units) = candidate
    match units {
      FirstCodeUnits::Any => fallback.push(variant)
      FirstCodeUnits::Finite(ranges) => {
        guard ranges.length() > 0 else { return None }
        for existing in finite_sets {
          if units != existing && first_units_overlap(units, existing) {
            return None
          }
        }
        if !finite_sets.iter().any(existing => existing == units) {
          finite_sets.push(units)
        }
      }
    }
  }
  guard finite_sets.length() >= 2 else { return None }
  guard finite_sets.length() <= MAX_FIRST_REGIONS else { return None }
  let emissions = candidates.length() +
    fallback.length() * (finite_sets.length() - 1)
  guard emissions <= MAX_FIRST_REGION_EMISSIONS else { return None }

  let regions = finite_sets.map(units => {
    let region_variants : Array[VariantDecl] = []
    for candidate in candidates {
      let (variant, candidate_units) = candidate
      if candidate_units is FirstCodeUnits::Any || candidate_units == units {
        region_variants.push(variant)
      }
    }
    FirstDispatchRegion(units, region_variants)
  })
  Some(FirstDispatchPlan(regions, fallback))
}
