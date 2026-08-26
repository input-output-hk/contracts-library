/**
 * Transaction builders for the DAO vote validator (MeshJS).
 *
 * Action set:
 *   - `buildVoteTx`  spend a stake position and mint a vote NFT locked to a choice
 *
 * The vote NFT is later burned during tally (see `buildTallyTx` in proposal.ts).
 */

import {
  applyParamsToScript,
  resolveScriptHash,
  serializePlutusScript,
  type Asset,
  type MeshTxBuilder,
  type PlutusScript,
  type UTxO,
} from "@meshsdk/core";

import {
  mintVoteRedeemer,
  stakePositionDatumToData,
  stakeRedeemerToData,
  voteDatumToData,
  voteParamsToData,
} from "./datum";
import type { StakePositionDatum, VoteDatum, VoteParams } from "./types";
import { voteCompiledCode as voteCode, plutusVersion } from "./blueprint";
import { stakeScriptAddress } from "./stake";

type Network = "mainnet" | "preprod" | "preview";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

const DEFAULT_MIN_UTXO_LOVELACE = 2_000_000n;

/** The Plutus V3 script in the form MeshJS expects (parameterized). */
export function voteScript(params: VoteParams): PlutusScript {
  const code = applyParamsToScript(voteCode, voteParamsToData(params), "Mesh");
  return { code, version: plutusVersion };
}

export function voteScriptAddress(script: PlutusScript, networkId = 0): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

/** Value of a vote artifact UTxO: ada + vote NFT. */
function voteValue(script: PlutusScript, tokenName: string): Asset[] {
  return [
    { unit: "lovelace", quantity: DEFAULT_MIN_UTXO_LOVELACE.toString() },
    {
      unit: resolveScriptHash(script.code, script.version) + tokenName,
      quantity: "1",
    },
  ];
}

export interface VoteBuilderParams {
  txBuilder: MeshTxBuilder;
  /** The vote validator script (its hash is the vote NFT policy). */
  voteScript: PlutusScript;
  /** The stake validator script used to spend the voting stake position. */
  stakeScript: PlutusScript;
  stakeUtxo: UTxO;
  stakeDatum: StakePositionDatum;
  /** The proposal UTxO referenced for the proposal's state. */
  proposalUtxo: UTxO;
  settingsUtxo: UTxO;
  voteDatum: VoteDatum;
  voteTokenName: string;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
}

/** Spend a stake position and mint a vote NFT carrying `voteDatum`. */
export async function buildVoteTx(p: VoteBuilderParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const votePolicy = resolveScriptHash(p.voteScript.code, p.voteScript.version);

  p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", votePolicy, p.voteTokenName)
    .mintRedeemerValue(mintVoteRedeemer())
    .mintingScript(p.voteScript.code)
    .spendingPlutusScriptV3()
    .txIn(
      p.stakeUtxo.input.txHash,
      p.stakeUtxo.input.outputIndex,
      p.stakeUtxo.output.amount,
      p.stakeUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(stakeRedeemerToData({ kind: "VoteProposal" }))
    .txInScript(p.stakeScript.code)
    .readOnlyTxInReference(
      p.proposalUtxo.input.txHash,
      p.proposalUtxo.input.outputIndex,
    )
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    );

  p.txBuilder
    .txOut(
      voteScriptAddress(p.voteScript, networkId),
      voteValue(p.voteScript, p.voteTokenName),
    )
    .txOutInlineDatumValue(voteDatumToData(p.voteDatum))
    .txOut(
      stakeScriptAddress(p.stakeScript, networkId),
      p.stakeUtxo.output.amount,
    )
    .txOutInlineDatumValue(stakePositionDatumToData(p.stakeDatum));

  return await p.txBuilder
    .txInCollateral(
      p.collateralUtxo.input.txHash,
      p.collateralUtxo.input.outputIndex,
      p.collateralUtxo.output.amount,
      p.collateralUtxo.output.address,
    )
    .changeAddress(p.changeAddress)
    .selectUtxosFrom(p.utxos)
    .complete();
}
