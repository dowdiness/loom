///|
pub impl @quickcheck.Arbitrary for Term with arbitrary(_size, rs) {
  gen_term(rs, 3)
}

///|
pub impl @qc.Shrink for Term

///|
/// Bounded-depth recursive generator for well-formed lambda terms.
fn gen_term(rs : @splitmix.RandomState, depth : Int) -> Term {
  let names = ["x", "y", "f", "n"]
  let name = names[rs.split().next_uint64().to_int().abs() % names.length()]
  if depth <= 0 {
    match rs.split().next_uint64().to_int().abs() % 3 {
      0 => Int(rs.split().next_uint64().to_int().abs() % 100)
      1 => Var(name)
      _ => Unit
    }
  } else {
    match rs.split().next_uint64().to_int().abs() % 7 {
      0 => Int(rs.split().next_uint64().to_int().abs() % 100)
      1 => Var(name)
      2 => Lam(name, gen_term(rs, depth - 1))
      3 => App(gen_term(rs, depth - 1), gen_term(rs, depth - 1))
      4 => {
        let op : Bop = if rs.split().next_uint64().to_int().abs() % 2 == 0 {
          Plus
        } else {
          Minus
        }
        Bop(op, gen_term(rs, depth - 1), gen_term(rs, depth - 1))
      }
      5 =>
        If(
          gen_term(rs, depth - 1),
          gen_term(rs, depth - 1),
          gen_term(rs, depth - 1),
        )
      _ => {
        let num_defs = rs.split().next_uint64().to_int().abs() % 3 + 1
        let defs : Array[(VarName, Term)] = []
        for i = 0; i < num_defs; i = i + 1 {
          let def_name = names[i % names.length()]
          defs.push((def_name, gen_term(rs, depth - 1)))
        }
        Module(defs, gen_term(rs, depth - 1))
      }
    }
  }
}
