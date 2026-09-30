// Minimum flow tests for the transfer and third-party gates (§4.2/§4.5,
// Q-RULE-1). The governed policy id resolves at runtime from the referenced
// registry node. Fixture style mirrors `lib/dao/proposal/proposal.test.ak`.

use aiken/interval
use cardano/address.{Credential, Script, VerificationKey, from_script}
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction, placeholder,
}
use event_triggered/third_party
use event_triggered/transfer
use event_triggered/types.{RegistryNode, ThirdPartyParams, TransferParams}

// ------------------------------------------------------------------- fixtures

const cip_policy = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const node_policy = #"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const transfer_script =
  #"11111111111111111111111111111111111111111111111111111111"

const third_party_script =
  #"22222222222222222222222222222222222222222222222222222222"

const principal_name = "BOND"

const tx_id =
  #"0000000000000000000000000000000000000000000000000000000000000000"

fn transfer_params() -> TransferParams {
  TransferParams { registry_node_cs: node_policy, final_deadline: 4000 }
}

fn third_party_params() -> ThirdPartyParams {
  ThirdPartyParams { registry_node_cs: node_policy, final_deadline: 4000 }
}

fn node_datum(
  minting: Credential,
  transfer: Credential,
  third_party: Credential,
) -> RegistryNode {
  RegistryNode {
    key: cip_policy,
    next: cip_policy,
    minting_logic_script: minting,
    transfer_logic_script: transfer,
    third_party_logic_script: third_party,
    unfracking_logic_script: VerificationKey(#""),
    global_state_cs: #"",
  }
}

fn node_reference(
  index: Int,
  minting: Credential,
  transfer: Credential,
  third_party: Credential,
) -> Input {
  Input {
    output_reference: OutputReference {
      transaction_id: tx_id,
      output_index: index,
    },
    output: Output {
      address: from_script(node_policy),
      value: assets.from_asset(node_policy, cip_policy, 1),
      datum: InlineDatum(node_datum(minting, transfer, third_party)),
      reference_script: None,
    },
  }
}

fn transfer_account() -> Credential {
  Script(transfer_script)
}

fn third_party_account() -> Credential {
  Script(third_party_script)
}

fn burning(mint: assets.Value, node: Input, now: Int) -> Transaction {
  Transaction {
    ..placeholder,
    reference_inputs: [node],
    mint,
    validity_range: interval.after(now),
  }
}

// ------------------------------------------------------------ transfer logic

test transfer_ok() {
  // permissive: an ordinary transfer reads no time bound (§4.2)
  transfer.validate(
    transfer_account(),
    burning(
      assets.zero,
      node_reference(
        90,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      5000,
    ),
    transfer_params(),
  )
}

test rejects_graduation_transfer_before_d4() {
  // a burn-shaped transfer is a graduation and must reach d4
  !transfer.validate(
    transfer_account(),
    burning(
      assets.from_asset(cip_policy, principal_name, -1000),
      node_reference(
        90,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      3000,
    ),
    transfer_params(),
  )
}

test graduation_transfer_at_d4_ok() {
  transfer.validate(
    transfer_account(),
    burning(
      assets.from_asset(cip_policy, principal_name, -1000),
      node_reference(
        90,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      4000,
    ),
    transfer_params(),
  )
}

// ------------------------------------------------------ third-party logic

test third_party_dispatch_ok() {
  third_party.validate(
    third_party_account(),
    burning(
      assets.from_asset(cip_policy, principal_name, -1000),
      node_reference(
        91,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      4000,
    ),
    third_party_params(),
  )
}

test rejects_dispatch_without_burn() {
  !third_party.validate(
    third_party_account(),
    burning(
      assets.zero,
      node_reference(
        91,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      4000,
    ),
    third_party_params(),
  )
}

test rejects_transfer_unmatched_account() fail {
  // a withdraw-0 by a credential no node names cannot run the gate
  let stranger = Script(
    #"99999999999999999999999999999999999999999999999999999999",
  )
  !transfer.validate(
    stranger,
    burning(
      assets.zero,
      node_reference(
        90,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      5000,
    ),
    transfer_params(),
  )
}

test transfer_ok_before_d4() {
  // no burn → permissive regardless of time (§4.2)
  transfer.validate(
    transfer_account(),
    burning(
      assets.zero,
      node_reference(
        90,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      1,
    ),
    transfer_params(),
  )
}

test rejects_third_party_before_d4() {
  // a burn-shaped dispatch is a graduation and must reach d4
  !third_party.validate(
    third_party_account(),
    burning(
      assets.from_asset(cip_policy, principal_name, -1000),
      node_reference(
        91,
        VerificationKey(#""),
        transfer_account(),
        third_party_account(),
      ),
      3000,
    ),
    third_party_params(),
  )
}

test rejects_transfer_no_node() fail {
  // no referenced registry node → the policy cannot resolve → abort
  !transfer.validate(
    transfer_account(),
    Transaction {
      ..placeholder,
      mint: assets.zero,
      validity_range: interval.after(5000),
    },
    transfer_params(),
  )
}
