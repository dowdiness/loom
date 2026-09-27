///|
pub(all) enum Token {
  PayloadShort(String)
  PayloadLong(String)
  CandidateA
  CandidateB
  CandidateC
  CandidateD
  CandidateE
  CandidateF
  CandidateG
  CandidateH
  CandidateI
  CandidateJ
  CandidateK
  CandidateL
  CandidateM
  CandidateN
  CandidateO
  CandidateP
  CandidateQ
  CandidateR
  CandidateS
  CandidateT
  CandidateU
  CandidateV
  CandidateW
  CandidateX
  CandidateY
  CandidateZ
  CandidateAA
  CandidateAB
  CandidateAC
  CandidateAD
  CandidateAE
  CandidateAF
  EOF
} derive(Eq, Debug)

///|
pub extend Token with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Token with Eq::{equal, not_equal}
