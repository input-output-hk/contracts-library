//// Third-party logic (withdraw-0) — fail-closed for the event-triggered
//// assets substandard (spec §4.1, §4.6).
////
//// The tokenized bond admits no third-party extraction: the registered
//// certificate moves only under the holder's own transfer chain and is retired
//// by the holder's graduation. The registry node records this credential as
//// the instrument's `third_party_logic_script`, and the predicate rejects
//// every dispatch, so a third-party action on the certificate can never
//// validate.

use cardano/address.{Credential}
use cardano/transaction.{Transaction}
use event_triggered/types.{ThirdPartyParams}

pub fn validate(
  _account: Credential,
  _self: Transaction,
  _params: ThirdPartyParams,
) -> Bool {
  False
}
