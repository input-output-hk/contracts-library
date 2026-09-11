//// Issuance logic (withdraw-0) — mint/burn authority and registry lifecycle
//// for the event-triggered assets substandard (§2 P3, §4).
////
//// The issuance credential is frozen at registration and is also the registry
//// lifecycle authority, so this validator runs in four contexts (Register /
//// UpdateNode / Mint / Burn) and cross-checks the claimed mode against the
//// transaction shape (09-DEVELOPING-SUBSTANDARDS.md, "Your issuance logic
//// must know why it is running"). Graduation (`Burn`) is deliberately
//// *event-gated, not issuer-gated*: the final validator wires the same
//// pluggable event rule here that the third-party logic uses (§4, Q-RULE-1),
//// so graduation fires only once the event condition the rules enforce is
//// on-chain true — settlement, never a discretionary lever (Q-GRAD-2).
////
//// Stances baked in (triage inputs for §7):
//// - Q-GRAD-1: per-holder migration — burn `k` instrument tokens, mint `k`
////   graduated tokens 1:1 per asset name when `graduated_policy` is set;
////   `None` is a retire-only instrument. Identity/fungibility across the
////   swap, DEX pools and price history stay open for triage.
//// - Q-GRAD-2: burn is gated by the event rule (`rule_check` hook, wired by
////   the final validator with the deployment's `rule` credential — the same
////   gate the third-party logic applies on the PLB side of a keeper-driven
////   burn), never by the issuer.
//// - Q-RULE-2: third-party logic pinned to the governed-extraction script
////   (keeper actions admitted only through the event rule); no global
////   state, no companion assets.
//// - Q-RULE-3: transfer logic pinned to the permissive script — P1 can
////   never be silently replaced by a gate.
//// - The per-holder datum is deployer-defined `Data`, never interpreted
////   here: the substandard governs custody-level actions only.
////
//// Relies on the base-layer guarantee that a transaction spending a registry
//// node never mints or burns that node's own token; graduation is therefore
//// pure issuance, never mixed with a registry reconfiguration (§3.1).

use aiken/collection/dict
use aiken/collection/list
use authorization.{is_authorized}
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId, Value, quantity_of, tokens}
use cardano/transaction.{Transaction}
use event_triggered/registry
use event_triggered/types.{
  Burn, IssuanceAction, IssuanceParams, Mint, Register, RegistryNode, UpdateNode,
}

pub fn validate(
  action: IssuanceAction,
  account: Credential,
  self: Transaction,
  params: IssuanceParams,
  rule_check: fn(Transaction) -> Bool,
) -> Bool {
  when action is {
    Register -> validate_register(account, self, params)
    UpdateNode -> validate_update_node(account, self, params)
    Mint -> validate_mint(account, self, params)
    Burn -> validate_burn(account, self, params, rule_check)
  }
}

/// Registration: exactly one node for this credential is being created, its
/// logic fields pinned to the frozen stance, and no co-mint of the new token
/// (strict register-then-mint — a deliberate choice, not an accident).
fn validate_register(
  account: Credential,
  self: Transaction,
  params: IssuanceParams,
) -> Bool {
  expect [(policy, node)] = registry.governing(
    self.outputs,
    params.registry_node_cs,
    account,
  )
  and {
    pinned_stance(node, params),
    dict.is_empty(tokens(self.mint, policy)),
    is_authorized(params.issuer, self.extra_signatories, self.withdrawals),
  }
}

/// In-place node update: the node is spent and re-created in the same
/// transaction, and the new state must keep the frozen stance. `key`, `next`
/// and `minting_logic_script` are frozen by the core's `registry_spend`.
fn validate_update_node(
  account: Credential,
  self: Transaction,
  params: IssuanceParams,
) -> Bool {
  expect [(_, _)] = registry.governing(
    registry.outputs_of(self.inputs),
    params.registry_node_cs,
    account,
  )
  expect [(_, node)] = registry.governing(
    self.outputs,
    params.registry_node_cs,
    account,
  )
  and {
    pinned_stance(node, params),
    is_authorized(params.issuer, self.extra_signatories, self.withdrawals),
  }
}

/// Mint: the claimed mode must match a positive mint under the governed
/// policy, no registry node may be spent alongside issuance (the base-layer
/// separation kept strict), and the issuer authorizes. The per-holder datum
/// is deployer-defined `Data` — the substandard does not police its shape.
fn validate_mint(
  account: Credential,
  self: Transaction,
  params: IssuanceParams,
) -> Bool {
  let own_policy = governed_policy(account, self, params)
  let minted = tokens(self.mint, own_policy) |> dict.to_pairs()
  and {
    !list.is_empty(minted),
    list.all(minted, fn(entry) { entry.2nd > 0 }),
    list.is_empty(
      registry.governing(
        registry.outputs_of(self.inputs),
        params.registry_node_cs,
        account,
      ),
    ),
    is_authorized(params.issuer, self.extra_signatories, self.withdrawals),
  }
}

/// Burn — graduation or retirement (P3). Event-gated (Q-GRAD-2): the pluggable
/// event rule must hold for the transaction — the same condition the P2 rules
/// enforce — whether the burn is keeper-driven (`SpendViaThirdParty`, also
/// gated by the third-party logic, which additionally pins graduated payouts
/// to the burned holders) or holder-signed (the permissive transfer path).
/// Graduation conserves 1:1 into the graduated policy per asset name; a
/// retire-only instrument simply burns. Nothing self-executes: a keeper or
/// the holder submits, the predicate approves (§5).
fn validate_burn(
  account: Credential,
  self: Transaction,
  params: IssuanceParams,
  rule_check: fn(Transaction) -> Bool,
) -> Bool {
  let own_policy = governed_policy(account, self, params)
  let burned = tokens(self.mint, own_policy) |> dict.to_pairs()
  and {
    !list.is_empty(burned),
    list.all(burned, fn(entry) { entry.2nd < 0 }),
    list.is_empty(
      registry.governing(
        registry.outputs_of(self.inputs),
        params.registry_node_cs,
        account,
      ),
    ),
    // Event gate (Q-GRAD-2): the same event condition the P2 rules enforce.
    rule_check(self),
    graduated_conservation(self.mint, burned, params.graduated_policy),
  }
}

// ----------------------------------------------------------------- helpers

/// Resolve the governed policy id from this token's `RegistryNode`,
/// referenced by the transaction (the base layer needs it on any transaction
/// that moves the token). Strictly one node — one instrument per substandard
/// instance; a credential governing several tokens must resolve per instance.
fn governed_policy(
  account: Credential,
  self: Transaction,
  params: IssuanceParams,
) -> PolicyId {
  expect [(policy, _)] = registry.governing(
    registry.outputs_of(self.reference_inputs),
    params.registry_node_cs,
    account,
  )
  policy
}

/// The registered/updated node must pin the frozen stance: permissive
/// transfer logic (Q-RULE-3), governed-extraction third-party logic
/// (Q-RULE-2), no global state, and no protected prefixes (this profile
/// mints no companion assets).
fn pinned_stance(node: RegistryNode, params: IssuanceParams) -> Bool {
  and {
    node.transfer_logic_script == Script(params.transfer_logic),
    node.third_party_logic_script == Script(params.third_party_logic),
    node.global_state_cs == #"",
    node.protected_prefixes == [],
  }
}

/// 1:1 identity swap (Q-GRAD-1): every burned asset name must be re-minted
/// in equal quantity under the graduated policy, and nothing else. The
/// graduated policy itself is a plain native policy outside this substandard;
/// it must consent to the swap on its own (e.g. by requiring the burn).
fn graduated_conservation(
  mint: Value,
  burned: Pairs<AssetName, Int>,
  graduated_policy: Option<PolicyId>,
) -> Bool {
  when graduated_policy is {
    None -> True
    Some(policy) -> {
      let minted = tokens(mint, policy) |> dict.to_pairs()
      list.length(minted) == list.length(burned) && list.all(
        burned,
        fn(entry) { quantity_of(mint, policy, entry.1st) == -entry.2nd },
      )
    }
  }
}
