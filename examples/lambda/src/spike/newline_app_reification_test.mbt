///|
/// Task 8: evidence-gate the `ManualNewlineAppExpr` residue.
///
/// The plan accepts any DivergenceClass arm — the point is to *classify with
/// oracle evidence*, not to assume a result. The recorded outcome is
/// `NoDivergence`: A and B agree on the newline-application CST. But that parity
/// is achieved by the spike-local probe (`parse_newline_app`), NOT by the
/// minimal `@grammar` contract, which placeholders `ManualNewlineAppExpr`. The
/// residue is therefore "reducible to behavior parity only via a spike-local
/// recursive-mode mechanism" — exactly the §5/§8 signal that informs whether the
/// migration is a target-(i) drop-in or a target-(ii) re-baseline.
test "newline application reification attempt is evidence gated" {
  let result = run_newline_application_reification_probe()
  match result.divergence {
    DivergenceClass::NoDivergence => ()
    DivergenceClass::ReplicationResidual(_) => ()
    DivergenceClass::WrongModelStop(message) => fail(message)
  }
}

///|
/// Pin the recorded classification so a regression that silently breaks
/// newline-application parity (e.g. dropping the probe's `parse_newline_app`)
/// surfaces here rather than hiding behind the permissive match above.
test "newline application residue holds A-vs-B parity via the spike probe" {
  let result = run_newline_application_reification_probe()
  inspect(result.divergence, content="NoDivergence")
}
