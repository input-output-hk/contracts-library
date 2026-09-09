/**
 * Pinned on-chain blueprint for the event-triggered assets validator
 * (CIP-113 substandard scaffold, docs/explorations/event-triggered-assets.md).
 *
 * GENERATED ARTIFACT — do not hand-edit. Regenerate from onchain/plutus.json
 * when the validator changes.
 *
 * Source: onchain/plutus.json (event_triggered_assets.event_triggered_assets)
 * Compiler: Aiken v1.1.22+39d6b04
 * Plutus version: V3
 * Unparameterized: the spend and mint endpoints share one script.
 */

/** Raw, single-CBOR-encoded compiled code as emitted by Aiken (unparameterized). */
export const compiledCode =
  "58da01010029800aba2aba1aab9faab9eaab9dab9a488888966002646465300130053754003370e90004c02000e601000491112cc004cdc3a4004009132332259800980318061baa0048acc004c034dd50024528c5900e45900b18068009806980700098051baa0058acc004c00c01233001375c601860146ea80162b300130033009375400314a314a2804260126ea8005222598009803000c566002601a6ea801200516403915980099b87480080062b3001300d37540090028b201c8b2016402c8b201040203007300800130070013003375400f149a26cac8009";

/** Blake2b-224 hash of the validator script (= script's payment credential). */
export const validatorHash =
  "40533b698f483e1a4806e590068ef9bd93f2eec26f68dd2aa9c412e3";

export const plutusVersion = "V3" as const;
