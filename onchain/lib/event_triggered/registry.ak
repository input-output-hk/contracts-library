//// Registry-node lookup for the event-triggered assets substandard.
////
//// The CIP-113 core registry is a sorted linked list of `RegistryNode` UTxOs,
//// each carrying an NFT under the registry's node policy whose asset name is
//// the governed token's policy id. Substandard withdraw-0 validators receive
//// their own credential as `account`, so "which policy do I govern?" resolves
//// to "find the node whose issuance-logic field is me and read its NFT asset
//// name" (09-DEVELOPING-SUBSTANDARDS.md, "Finding your own policy id").
////
//// Lookups scan inputs and outputs — no positional assumptions
//// (ARCHITECTURE.md §1). One substandard credential can govern several
//// tokens; these helpers return every match, and the issuance logic expects
//// exactly one — the strict choice for a single-instrument instance.

use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Credential}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{InlineDatum, Input, Output}
use event_triggered/types.{RegistryNode}

/// Strip `Input` wrappers down to their outputs, so one scan helper serves
/// spent inputs, reference inputs, and created outputs alike.
pub fn outputs_of(inputs: List<Input>) -> List<Output> {
  list.map(inputs, fn(input) { input.output })
}

/// Decode an output as a registry-node UTxO, if it is one. Node datums are
/// assumed inline (the base layer reads them the same way); an output holding
/// a registry NFT whose datum does not decode aborts the transaction.
pub fn node(output: Output, registry_node_cs: PolicyId) -> Option<RegistryNode> {
  if dict.is_empty(tokens(output.value, registry_node_cs)) {
    None
  } else {
    when output.datum is {
      InlineDatum(data) -> {
        expect node: RegistryNode = data
        Some(node)
      }
      _ -> None
    }
  }
}

/// The policy id a node output governs: the asset name of its registry NFT
/// (the node's `key`).
pub fn node_policy(
  output: Output,
  registry_node_cs: PolicyId,
) -> Option<PolicyId> {
  when tokens(output.value, registry_node_cs) |> dict.to_pairs() is {
    [Pair(name, 1)] -> {
      let policy: PolicyId = name
      Some(policy)
    }
    _ -> None
  }
}

/// All `(policy id, node)` pairs among these outputs whose node's
/// issuance-logic field is `logic` — "find all nodes referencing me". Pass
/// `outputs_of(self.inputs)` for spent nodes, `self.reference_inputs |>
/// outputs_of` for referenced ones, or `self.outputs` for created ones.
pub fn governing(
  outputs: List<Output>,
  registry_node_cs: PolicyId,
  logic: Credential,
) -> List<(PolicyId, RegistryNode)> {
  list.filter_map(
    outputs,
    fn(output) {
      when node(output, registry_node_cs) is {
        Some(node) ->
          if node.minting_logic_script == logic {
            when node_policy(output, registry_node_cs) is {
              Some(policy) -> Some((policy, node))
              None -> None
            }
          } else {
            None
          }
        None -> None
      }
    },
  )
}
