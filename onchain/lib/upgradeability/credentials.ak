//// The credential that witnesses a certificate or casts a vote.

use cardano/address.{Credential, VerificationKey}
use cardano/certificate.{
  AuthorizeConstitutionalCommitteeProxy, Certificate, DelegateCredential,
  RegisterAndDelegateCredential, RegisterCredential,
  RegisterDelegateRepresentative, RegisterStakePool,
  RetireFromConstitutionalCommittee, RetireStakePool, UnregisterCredential,
  UnregisterDelegateRepresentative, UpdateDelegateRepresentative,
}
use cardano/governance.{
  ConstitutionalCommitteeMember, DelegateRepresentative, StakePool, Voter,
}

pub fn certificate_credential(certificate: Certificate) -> Credential {
  when certificate is {
    RegisterCredential { credential, .. } -> credential
    UnregisterCredential { credential, .. } -> credential
    DelegateCredential { credential, .. } -> credential
    RegisterAndDelegateCredential { credential, .. } -> credential
    RegisterDelegateRepresentative { delegate_representative, .. } ->
      delegate_representative
    UpdateDelegateRepresentative { delegate_representative } ->
      delegate_representative
    UnregisterDelegateRepresentative { delegate_representative, .. } ->
      delegate_representative
    AuthorizeConstitutionalCommitteeProxy {
      constitutional_committee_member,
      ..
    } -> constitutional_committee_member
    RetireFromConstitutionalCommittee { constitutional_committee_member } ->
      constitutional_committee_member
    RegisterStakePool { stake_pool, .. } -> VerificationKey(stake_pool)
    RetireStakePool { stake_pool, .. } -> VerificationKey(stake_pool)
  }
}

pub fn voter_credential(voter: Voter) -> Credential {
  when voter is {
    ConstitutionalCommitteeMember(credential) -> credential
    DelegateRepresentative(credential) -> credential
    StakePool(pool) -> VerificationKey(pool)
  }
}
