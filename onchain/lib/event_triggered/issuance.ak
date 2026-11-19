//// Minting logic (withdraw-0) for the event-triggered assets substandard —
//// the tokenized bond's issuance and registry-lifecycle authority (spec §4.1,
//// §4.2, §4.5, §4.7).
////
//// The minting credential is frozen at registration and is also the
//// registration authority, so this validator runs in four contexts and
//// cross-checks the claimed mode against the transaction shape. The governed
//// policy id is a hash *of* this script's applied form, so it is never baked:
//// every mode resolves it at runtime from the registry node.
////
//// The module is schedule-agnostic: the certificate's `cnt_policy` selects the
//// coupon terms, and the coupon policy validates time/amount/transition. These
//// modes validate the certificate's own state machine and require the
//// corresponding coupon mint, so no advance or retirement can skip its coupon.

use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite, Interval}
use authorization.{is_authorized}
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use event_triggered/certificate
use event_triggered/registry
use event_triggered/schedule
use event_triggered/types.{
  Advance, CertificateDatum, Deposit, MintingAction, MintingParams, Register,
  RegistryNode, Retire, VaultDatum,
}
use event_triggered/vault_nft.{nft_of}

pub fn validate(
  action: MintingAction,
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  when action is {
    Register -> validate_register(account, self, params)
    Deposit -> validate_deposit(account, self, params)
    Advance -> validate_advance(account, self, params)
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
/// only when the **chosen vault** gains exactly the unit `principal` and
/// continues with its address and datum unchanged, so the certificate and its
/// backing exist atomically (I6). Exactly one step-`0` certificate is minted,
/// carrying the vault's `cnt_policy`, with `commit: None` and `start` pinned
/// to the transaction's finite validity upper bound.
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
  let certs_in = certificate.cert_inputs(self.inputs, policy)
  let certs_out = certificate.cert_outputs(self.outputs, policy)
  and {
    dict.to_pairs(tokens(self.mint, policy)) == [Pair(schedule.step_name(0), 1)],
    list.is_empty(certs_in),
    when certs_out is {
      [(output, _k, d)] -> and {
          quantity_of(output.value, policy, schedule.step_name(0)) == 1,
          d.commit == None,
          d.cnt_policy != policy,
          when upper_bound(self.validity_range) is {
            Some(t) -> d.start == t
            None -> False
          },
          vault_continues(
            self.inputs,
            self.outputs,
            params.vault,
            params.principal,
            d.cnt_policy,
            params.vault_nft_cs,
          ),
        }
      _ -> False
    },
  }
}

/// Advance (§4.5): burns the certificate's current name, mints the next and
/// requires the step's coupon mint under the certificate's `cnt_policy`. The
/// transfer/third-party path authorises who may run it; the coupon policy
/// validates the coupon's amount, deadline and transition.
fn validate_advance(
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
  let certs_in = certificate.cert_inputs(self.inputs, policy)
  let certs_out = certificate.cert_outputs(self.outputs, policy)
  when (certs_in, certs_out) is {
    ([(input, k, d)], [(output, k_out, d_out)]) -> and {
        k_out == k + 1,
        k_out <= 255,
        input.output.address == output.address,
        d_out == d,
        dict.to_pairs(tokens(self.mint, policy)) == [
          Pair(schedule.step_name(k), -1),
          Pair(schedule.step_name(k_out), 1),
        ],
        single_coupon(self.mint, d.cnt_policy),
        authorized_spend(input.output, d, self, params),
      }
    _ -> False
  }
}

/// Retirement (§4.7): the certificate is burned at its current name with no
/// continuation, and the principal coupon mint under the certificate's
/// `cnt_policy` is required. The coupon policy validates the maturity window,
/// the final step and the `principal` amount.
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
  let certs_in = certificate.cert_inputs(self.inputs, policy)
  let certs_out = certificate.cert_outputs(self.outputs, policy)
  when certs_in is {
    [(input, k, d)] -> and {
        list.is_empty(certs_out),
        dict.to_pairs(tokens(self.mint, policy)) == [
          Pair(schedule.step_name(k), -1),
        ],
        single_coupon(self.mint, d.cnt_policy),
        authorized_spend(input.output, d, self, params),
      }
    _ -> False
  }
}

// --------------------------------------------------------------- Register

/// The registered node pins the frozen stance (§4.1): our name-monotone
/// transfer logic, our issuer-triggered third-party logic, the `empty_vkey`
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

/// The chosen vault continues: exactly one vault input and one vault output
/// carrying the vault NFT, same address and datum, output ADA = input ADA +
/// `principal`, and the input's datum binds `cnt` (the certificate's coupon
/// policy) to the vault. The NFT is what authenticates the vault (I10): a fake
/// output at the vault address carries no NFT and can never back a certificate.
fn vault_continues(
  inputs: List<Input>,
  outputs: List<Output>,
  vault: ScriptHash,
  principal: Int,
  cnt: PolicyId,
  nft_cs: PolicyId,
) -> Bool {
  let vins = list.filter(
    inputs,
    fn(input) { nft_of(input.output, nft_cs) != None },
  )
  let vouts = list.filter(
    outputs,
    fn(output) { nft_of(output, nft_cs) != None },
  )
  when (vins, vouts) is {
    ([vin], [vout]) ->
      when (nft_of(vin.output, nft_cs), nft_of(vout, nft_cs)) is {
        (Some(name), Some(name_out)) -> and {
            name == name_out,
            is_vault(vin.output, vault),
            vin.output.address == vout.address,
            vin.output.datum == vout.datum,
            vault_cnt(vin.output) == Some(cnt),
            quantity_of(vout.value, #"", #"") == quantity_of(
              vin.output.value,
              #"",
              #"",
            ) + principal,
          }
        _ -> False
      }
    _ -> False
  }
}

fn is_vault(output: Output, vault: ScriptHash) -> Bool {
  output.address.payment_credential == Script(vault)
}

fn vault_cnt(output: Output) -> Option<PolicyId> {
  when output.datum is {
    InlineDatum(data) -> {
      expect d: VaultDatum = data
      Some(d.cnt_policy)
    }
    _ -> None
  }
}

/// The finite upper bound of the transaction's validity range, if any.
fn upper_bound(range: Interval) -> Option<Int> {
  when range.upper_bound.bound_type is {
    Finite(t) -> Some(t)
    _ -> None
  }
}

// ------------------------------------------------------ Advance / Retire

/// Exactly one positive coupon unit (quantity `1`) under the certificate's
/// `cnt_policy` (any name; the coupon policy validates it). This is the
/// presence rule: no advance or retirement can skip its coupon.
fn single_coupon(mint, cnt: PolicyId) -> Bool {
  when dict.to_pairs(tokens(mint, cnt)) is {
    [Pair(_, 1)] -> True
    _ -> False
  }
}

/// The spend is authorised by the certificate's holder (its inline stake
/// credential) or by the issuer when the certificate commits a payment
/// credential (§4.5, §4.7).
fn authorized_spend(
  output: Output,
  d: CertificateDatum,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  let holder_ok = when output.address.stake_credential is {
    Some(Inline(c)) ->
      is_authorized(c, self.extra_signatories, self.withdrawals)
    _ -> False
  }
  let issuer_ok = when d.commit is {
    Some(_) ->
      is_authorized(params.issuer, self.extra_signatories, self.withdrawals)
    None -> False
  }
  holder_ok || issuer_ok
}
