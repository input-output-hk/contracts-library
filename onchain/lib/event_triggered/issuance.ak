//// Minting logic (withdraw-0) for the event-triggered assets substandard —
//// the tokenized bond's issuance and registry-lifecycle authority (spec §4.1,
//// §4.2, §4.6).
////
//// The minting credential is frozen at registration and is also the
//// registration authority, so this validator runs in three contexts and
//// cross-checks the claimed mode against the transaction shape. The governed
//// policy id is a hash *of* this script's applied form, so it is never baked:
//// every mode resolves it at runtime from the registry node.

use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{is_entirely_after}
use authorization.{is_authorized}
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{Input, Output, Transaction}
use event_triggered/certificate
use event_triggered/registry
use event_triggered/schedule
use event_triggered/types.{
  Deposit, MintingAction, MintingParams, Register, RegistryNode, Retire,
}

pub fn validate(
  action: MintingAction,
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  when action is {
    Register -> validate_register(account, self, params)
    Deposit -> validate_deposit(account, self, params)
    Retire -> validate_retire(account, self, params)
  }
}

/// Registration (§4.1): exactly one node for this credential is created, its
/// stance pinned to the frozen deployment, and no certificate is minted — so
/// the same registration serves every later deposit. Register-only is enforced
/// by refusing any `cip_policy` entry in `tx.mint`, and in-place node updates
/// are refused by rejecting a governed node among the inputs.
fn validate_register(
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  expect [(policy, node)] = registry.governing(
    self.outputs,
    params.registry_node_cs,
    account,
  )
  and {
    quantity_of(self.mint, params.registry_node_cs, policy) == 1,
    pinned_stance(node, policy, params),
    is_authorized(params.issuer, self.extra_signatories, self.withdrawals),
    // Register-only: no token under the governed policy is minted here.
    dict.is_empty(tokens(self.mint, policy)),
    // Refuse in-place node updates: no governed node may be spent.
    list.is_empty(
      registry.governing(
        registry.outputs_of(self.inputs),
        params.registry_node_cs,
        account,
      ),
    ),
  }
}

/// Deposit (§4.2): permissionless and per unit. The certificate is admitted
/// only when the vault gains exactly the unit `principal`, so the certificate
/// and its backing exist atomically (I6). Exactly one certificate is minted to
/// a new UTxO with `step: 0`, and no certificate input is spent (I8).
fn validate_deposit(
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  let referenced = registry.outputs_of(self.reference_inputs)
  expect [(policy, _)] = registry.governing(
    referenced,
    params.registry_node_cs,
    account,
  )
  and {
    dict.size(tokens(self.mint, policy)) == 1,
    quantity_of(self.mint, policy, params.certificate_name) == 1,
    list.is_empty(
      certificate.cert_inputs(self.inputs, policy, params.certificate_name),
    ),
    deposit_certificate(self.outputs, policy, params),
    vault_net_gain(self.inputs, self.outputs, params.vault) == Some(
      params.principal,
    ),
    vault_preserved(self.inputs, self.outputs, params.vault),
  }
}

/// Retirement (§4.6): the certificate is burned at its final `step` within the
/// `d4` window, with no continuation. The principal coupon mint is validated by
/// the coupon policy in the same transaction (I5).
fn validate_retire(
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  let referenced = registry.outputs_of(self.reference_inputs)
  expect [(policy, _)] = registry.governing(
    referenced,
    params.registry_node_cs,
    account,
  )
  expect Some(final_deadline) = schedule.final_deadline(params.schedule)
  let final_step = schedule.final_step(params.schedule)
  let inputs = certificate.cert_inputs(
    self.inputs,
    policy,
    params.certificate_name,
  )
  let outputs = certificate.cert_outputs(
    self.outputs,
    policy,
    params.certificate_name,
  )
  and {
    // Burn shape: exactly one certificate unit, negative.
    dict.size(tokens(self.mint, policy)) == 1,
    quantity_of(self.mint, policy, params.certificate_name) == -1,
    when inputs is {
      [input] ->
        quantity_of(input.output.value, policy, params.certificate_name) == 1 && certificate.step_of(
          input.output,
        ) == Some(final_step)
      _ -> False
    },
    // No continuation: the certificate is retired.
    list.is_empty(outputs),
    // Event gate (§4.6): the validity range must reach `d4`.
    is_entirely_after(self.validity_range, final_deadline - 1),
  }
}

// --------------------------------------------------------------- Register

/// The registered node pins the frozen stance (§4.1): our step-monotone
/// transfer logic, our fail-closed third-party logic, the `empty_vkey`
/// unfracking hook (forbidden) and empty global state, with `key` equal to the
/// governed policy id.
fn pinned_stance(
  node: RegistryNode,
  policy: PolicyId,
  params: MintingParams,
) -> Bool {
  and {
    node.key == policy,
    node.transfer_logic_script == Script(params.transfer_logic),
    node.third_party_logic_script == Script(params.third_party_logic),
    node.unfracking_logic_script == VerificationKey(#""),
    node.global_state_cs == #"",
  }
}

// ---------------------------------------------------------------- Deposit

/// Exactly one output carries the certificate — quantity `1`, inline datum
/// `{ step: 0 }`. Custody at the PLB is the core `issuance_logic`'s business.
fn deposit_certificate(
  outputs: List<Output>,
  policy: PolicyId,
  params: MintingParams,
) -> Bool {
  let certs = certificate.cert_outputs(outputs, policy, params.certificate_name)
  when certs is {
    [output] ->
      quantity_of(output.value, policy, params.certificate_name) == 1 && certificate.step_of(
        output,
      ) == Some(0)
    _ -> False
  }
}

/// The vault's net ADA gain across the transaction: outputs minus inputs whose
/// payment credential is the vault script (I6).
fn vault_net_gain(
  inputs: List<Input>,
  outputs: List<Output>,
  vault: ScriptHash,
) -> Option<Int> {
  Some(ada_at_outputs(outputs, vault) - ada_at_inputs(inputs, vault))
}

/// The vault UTxO's address and datum are carried across the deposit
/// unchanged: exactly one vault input pairs with exactly one vault output.
fn vault_preserved(
  inputs: List<Input>,
  outputs: List<Output>,
  vault: ScriptHash,
) -> Bool {
  let vin = list.filter(inputs, fn(input) { is_vault(input.output, vault) })
  let vout = list.filter(outputs, fn(output) { is_vault(output, vault) })
  when (vin, vout) is {
    ([input], [output]) ->
      input.output.address == output.address && input.output.datum == output.datum
    _ -> False
  }
}

fn is_vault(output: Output, vault: ScriptHash) -> Bool {
  output.address.payment_credential == Script(vault)
}

fn ada_at_outputs(outputs: List<Output>, vault: ScriptHash) -> Int {
  list.foldl(
    outputs,
    0,
    fn(output: Output, total: Int) {
      if is_vault(output, vault) {
        total + quantity_of(output.value, #"", #"")
      } else {
        total
      }
    },
  )
}

fn ada_at_inputs(inputs: List<Input>, vault: ScriptHash) -> Int {
  list.foldl(
    inputs,
    0,
    fn(input: Input, total: Int) {
      if is_vault(input.output, vault) {
        total + quantity_of(input.output.value, #"", #"")
      } else {
        total
      }
    },
  )
}
