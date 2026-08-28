/**
 * The reference poll-effect candidate (`onchain/validators/dao/poll_effect.ak`).
 *
 * A candidate guards its whole execution with `am_i_the_winner`: its withdraw-0
 * approval is only valid inside a transaction that genuinely closes the poll it
 * won. Off-chain, using it as one of a proposal's `results` scripts means
 * deriving its hash *after* parameterizing it with the proposal validator's own
 * hash (pinned at compile time on-chain, provided at apply-params time here).
 */

import { applyParamsToScript, type PlutusScript } from "@meshsdk/core";

import { pollEffectCompiledCode, plutusVersion } from "./blueprint";
import { pollEffectParamsToData } from "./datum";
import type { PollEffectParams } from "./types";

/** The Plutus V3 poll-effect candidate in the form MeshJS expects. */
export function pollEffectScript(params: PollEffectParams): PlutusScript {
  const code = applyParamsToScript(
    pollEffectCompiledCode,
    pollEffectParamsToData(params),
    "Mesh",
  );
  return { code, version: plutusVersion };
}
