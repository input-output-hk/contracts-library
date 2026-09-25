//// The minting credential is frozen at registration and is also the
//// registration authority, so this validator runs in two contexts and
//// cross-checks the claimed mode against the transaction shape

use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{is_entirely_after}
use authorization.{is_authorized}
use cardano/address.{Credential, Inline, Script}
use cardano/assets.{quantity_of, tokens}
use cardano/transaction.{InlineDatum, Output, Transaction}
use event_triggered/registry
use event_triggered/schedule
use event_triggered/types.{
  Burn, MintingAction, MintingParams, PrincipalDatum, ReferenceDatum,
  RegisterAndMint, RegistryNode,
}

pub fn validate(
  action: MintingAction,
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  when action is {
    RegisterAndMint -> validate_register_and_mint(account, self, params)
    Burn -> validate_burn(account, self, params)
  }
}

/// Registration (§4.1): exactly one node for this credential is created, its
/// stance pinned to the frozen deployment, and the first batch minted in the same
/// transaction, the reference output staked to the transformation script with
/// the baked schedule at par (`v0 = scale`).
fn validate_register_and_mint(
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
    policy == params.own_policy,
    quantity_of(self.mint, params.registry_node_cs, policy) == 1,
    pinned_stance(node, params),
    // Registration authority (§4.1): the issuer signature.
    is_authorized(params.issuer, self.extra_signatories, self.withdrawals),
    // First batch: principal × N (N ≥ 1) + reference `222` × 1 — the only
    // two names under the policy (§4.1).
    first_batch(self, params),
    // Principal outputs stake to holders, never to the transformation
    // script (§4.4, I4 — see module docs).
    principals_not_script_staked(self, params),
    // The reference token lands at the transformation script's stake with
    // the baked schedule, mirrored at par (§4.1).
    reference_output(self, params),
  }
}

/// Graduation (§4.5) — event-gated, destination-bound, burn-backed.
fn validate_burn(
  account: Credential,
  self: Transaction,
  params: MintingParams,
) -> Bool {
  expect [Pair(name, quantity)] = tokens(self.mint, params.own_policy)
    |> dict.to_pairs()
  expect Some(final_value) = schedule.final_value(params.schedule)
  expect Some(final_deadline) = schedule.final_deadline(params.schedule)
  expect Some(holdings) = schedule.burned_holdings(
    self.inputs,
    params.own_policy,
    params.principal_name,
  )
  let burned = 0 - quantity
  let shares = schedule.scaled_payouts(holdings, final_value, params.scale)
  and {
    // Burn shape: the principal name only, negative — any other governed
    // name fails closed and survives (I8).
    name == params.principal_name,
    quantity < 0,
    // Whole holdings per name: everything held burns, which makes the
    // per-owner destination attribution exact (§4.5, I5).
    burned == schedule.total(holdings),
    // Pure issuance — never mixed with a registry reconfiguration (I7).
    list.is_empty(
      registry.governing(
        registry.outputs_of(self.inputs),
        params.registry_node_cs,
        account,
      ),
    ),
    // Event gate (Q-RULE-1): the deadline is the transaction's own validity
    // range — no oracle (§5).
    is_entirely_after(self.validity_range, final_deadline - 1),
    // Destination binding + the scaled native mirror (Q-GRAD-2, I5).
    settle(self, params, holdings, shares),
  }
}

// ------------------------------------------------------ RegisterAndMint

/// The registered node pins the frozen stance (§3.4): permissive transfer
/// logic (Q-RULE-3), graduation-only third-party logic, empty unfracking
/// logic and global state, and `key` equal to the governed policy id.
fn pinned_stance(node: RegistryNode, params: MintingParams) -> Bool {
  and {
    node.key == params.own_policy,
    node.transfer_logic_script == Script(params.transfer_logic),
    node.third_party_logic_script == Script(params.third_party_logic),
    node.unfracking_logic == None,
    node.global_state_cs == #"",
  }
}

/// Exactly the two names under the governed policy: the principal (N ≥ 1)
/// and the CIP-68 reference (exactly 1) (§4.1).
fn first_batch(self: Transaction, params: MintingParams) -> Bool {
  and {
    dict.size(tokens(self.mint, params.own_policy)) == 2,
    quantity_of(self.mint, params.own_policy, params.principal_name) >= 1,
    quantity_of(self.mint, params.own_policy, params.reference_name) == 1,
  }
}

/// No output holding principal tokens may stake to the transformation
/// script: tokens born there are owned by the script and could never be
/// transferred, transformed or graduated — the §4.4 update only rewrites the
/// reference datum in place, and graduation binds payouts to holder stakes.
fn principals_not_script_staked(
  self: Transaction,
  params: MintingParams,
) -> Bool {
  list.all(
    self.outputs,
    fn(output: Output) {
      if quantity_of(output.value, params.own_policy, params.principal_name) > 0 {
        !staked_to(output, params.transformation_script)
      } else {
        True
      }
    },
  )
}

/// Exactly one output carries the reference token (and nothing else under
/// the policy), staked to the transformation script, with a datum that
/// mirrors the baked schedule at the initial value `v0 = scale` (§4.1).
fn reference_output(self: Transaction, params: MintingParams) -> Bool {
  let candidates = list.filter(
    self.outputs,
    fn(output: Output) {
      let minted = tokens(output.value, params.own_policy) |> dict.to_pairs()
      minted == [Pair(params.reference_name, 1)]
    },
  )
  when candidates is {
    [output] -> and {
        staked_to(output, params.transformation_script),
        reference_datum(output, params),
      }
    _ -> False
  }
}

fn reference_datum(output: Output, params: MintingParams) -> Bool {
  when output.datum is {
    InlineDatum(data) -> {
      expect ReferenceDatum { version, extra, .. }: ReferenceDatum = data
      and {
        version == 1,
        extra.schedule == params.schedule,
        extra.value == params.scale,
      }
    }
    _ -> False
  }
}

/// Is this output staked to the given script credential?
fn staked_to(output: Output, script: ScriptHash) -> Bool {
  when output.address.stake_credential is {
    Some(Inline(Script(hash))) -> hash == script
    _ -> False
  }
}

// ----------------------------------------------------------------- Burn

/// The graduation's conversion validation, shared by both spend paths
/// (§4.5): the scaled native mirror, per-owner destination attribution and
/// the owner-authorized payment credentials.
///
/// Two checks pin the mint exactly:
/// 1. the mint under the native policy equals the sum of the per-owner
///    shares — the same number the native policy independently derives
///    (`schedule.total_payout`), so the mint cannot deviate in either
///    direction;
/// 2. every burned owner is paid exactly their share, at their current stake
///    credential (I1: the payout rides the inline stake credential, which
///    graduation binds the destination to).
/// Together these also force the new mint fully into owner outputs: any
/// native asset at a non-owner stake would be pass-through only.
///
/// Then every native-bearing output at a burned owner's stake must pay an
/// owner-authorized payment credential (Q-GRAD-2).
fn settle(
  self: Transaction,
  params: MintingParams,
  holdings: List<(Credential, Int)>,
  shares: List<(Credential, Int)>,
) -> Bool {
  and {
    quantity_of(self.mint, params.native_policy, params.principal_name) == schedule.total(
      shares,
    ),
    list.all(
      shares,
      fn(entry) {
        native_at_stake(self.outputs, entry.1st, params) == entry.2nd
      },
    ),
    list.all(
      self.outputs,
      fn(output: Output) {
        if quantity_of(
          output.value,
          params.native_policy,
          params.principal_name,
        ) > 0 {
          when output.address.stake_credential is {
            Some(Inline(owner)) ->
              if list.any(holdings, fn(entry) { entry.1st == owner }) {
                payout_authorized(self, params, owner, output)
              } else {
                True
              }
            _ -> True
          }
        } else {
          True
        }
      },
    ),
  }
}

/// The native assets an owner holds across the outputs (by inline stake
/// credential).
fn native_at_stake(
  outputs: List<Output>,
  owner: Credential,
  params: MintingParams,
) -> Int {
  list.reduce(
    outputs,
    0,
    fn(total: Int, output: Output) {
      if output.address.stake_credential == Some(Inline(owner)) {
        total + quantity_of(
          output.value,
          params.native_policy,
          params.principal_name,
        )
      } else {
        total
      }
    },
  )
}

/// Destination binding for one native-bearing output at a burned owner's
/// stake (Q-GRAD-2): the owner either signs the graduation (owner path — the
/// destination is named in the transaction they sign) or pre-committed a
/// payment credential to the token datum (§4.3, preserved byte-for-byte
/// through the third-party path). Absent both, the transaction is rejected —
/// no fallback.
fn payout_authorized(
  self: Transaction,
  params: MintingParams,
  owner: Credential,
  output: Output,
) -> Bool {
  if is_authorized(owner, self.extra_signatories, self.withdrawals) {
    True
  } else {
    when owner_payout(self, params, owner) is {
      Some(payment) -> output.address.payment_credential == payment
      None -> False
    }
  }
}

/// The payment credential an unsigned owner committed to their token datum
/// (§4.3): every burned input of that owner must carry the **same** one.
/// `None` means no usable commitment — fail closed (Q-GRAD-2).
fn owner_payout(
  self: Transaction,
  params: MintingParams,
  owner: Credential,
) -> Option<Credential> {
  let inputs = list.filter(
    self.inputs,
    fn(input) {
      quantity_of(input.output.value, params.own_policy, params.principal_name) > 0 && input.output.address.stake_credential == Some(
        Inline(owner),
      )
    },
  )
  when list.map(inputs, fn(input) { committed_payment(input.output) }) is {
    [Some(payment), ..rest] ->
      if list.all(rest, fn(credential) { credential == Some(payment) }) {
        Some(payment)
      } else {
        None
      }
    _ -> None
  }
}

/// The owner's committed payout payment credential from one burned input's
/// inline datum (§3.2). Absent datum or a `None` commitment yields `None`.
fn committed_payment(output: Output) -> Option<Credential> {
  when output.datum is {
    InlineDatum(data) -> {
      expect PrincipalDatum { payment_credential }: PrincipalDatum = data
      payment_credential
    }
    _ -> None
  }
}
