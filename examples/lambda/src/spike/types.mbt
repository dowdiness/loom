///|
/// Divergence classification for one oracle step result.
///
/// Severity ordering (highest to lowest):
///   WrongModelStop > ReplicationResidual > NoDivergence
///
/// WrongModelStop: any D1 or D2a structural failure — parse tree or structural
///   diagnostics differ. GO blocker. Investigate before any release.
///
/// ReplicationResidual: D2a structural fields match but diagnostic message
///   strings differ (cross-impl wording). Not a GO blocker. File as known
///   deviation.
///
/// NoDivergence: all oracle booleans are true.
pub enum DivergenceClass {
  NoDivergence
  ReplicationResidual(String)
  WrongModelStop(String)
} derive(Eq, Debug)

///|
pub impl Show for DivergenceClass with fn to_string(self) {
  match self {
    DivergenceClass::NoDivergence => "NoDivergence"
    DivergenceClass::ReplicationResidual(s) => "ReplicationResidual(" + s + ")"
    DivergenceClass::WrongModelStop(s) => "WrongModelStop(" + s + ")"
  }
}

///|
pub impl Show for DivergenceClass with fn output(self, logger) {
  logger.write_string(self.to_string())
}
