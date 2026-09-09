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
  SLOT_CONFIG_NETWORK,
  type Asset,
  type MeshTxBuilder,
  type PlutusScript,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";

import { enclosingSlotBound, nftNameFromRef } from "../common";
import {
  mintVoteRedeemer,
  stakePositionDatumToData,
  stakeRedeemerToData,
  voteDatumToData,
  voteParamsToData,
} from "./datum";
import type {
  ProposalDatum,
  StakePositionDatum,
  VoteDatum,
  VoteParams,
} from "./types";
import { voteCompiledCode as voteCode, plutusVersion } from "./blueprint";
import { stakeScriptAddress } from "./stake";

type Network = "mainnet" | "preprod" | "preview";

function networkIdOf(network: Network): 0 | 1 {
  return network === "mainnet" ? 1 : 0;
}

/** The enclosing slot + start time for `now` on the given network/devnet. */
function slotBound(
  network: Network,
  now: number,
  customSlotConfig?: SlotConfig,
) {
  return enclosingSlotBound(
    now,
    customSlotConfig ?? SLOT_CONFIG_NETWORK[network],
  );
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
  /** The referenced proposal's datum (for the voting-phase unlock time). */
  proposalDatum: ProposalDatum;
  settingsUtxo: UTxO;
  voteDatum: VoteDatum;
  /** Wall-clock used for the validity lower bound (POSIX ms). */
  now: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
  customSlotConfig?: SlotConfig;
}

/** Spend a stake position and mint a vote NFT carrying `voteDatum`. */
export async function buildVoteTx(p: VoteBuilderParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const votePolicy = resolveScriptHash(p.voteScript.code, p.voteScript.version);
  const voteTokenName = nftNameFromRef(p.stakeUtxo.input);
  const proposalId = p.voteDatum.proposal;
  const votedOption = p.voteDatum.votedOption;
  const unlock =
    p.proposalDatum.startTime +
    p.proposalDatum.timingConfig.draftLength +
    p.proposalDatum.timingConfig.votingLength;
  const authorizer = p.stakeDatum.delegatee ?? p.stakeDatum.owner;

  if (authorizer.kind === "key") {
    p.txBuilder.requiredSignerHash(authorizer.hash);
  }

  p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", votePolicy, voteTokenName)
    .mintRedeemerValue(mintVoteRedeemer(0))
    .mintingScript(p.voteScript.code)
    .spendingPlutusScriptV3()
    .txIn(
      p.stakeUtxo.input.txHash,
      p.stakeUtxo.input.outputIndex,
      p.stakeUtxo.output.amount,
      p.stakeUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      stakeRedeemerToData({ kind: "VoteProposal", proposalId, votedOption }),
    )
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
      voteValue(p.voteScript, voteTokenName),
    )
    .txOutInlineDatumValue(voteDatumToData(p.voteDatum))
    .txOut(
      stakeScriptAddress(p.stakeScript, networkId),
      p.stakeUtxo.output.amount,
    )
    .txOutInlineDatumValue(stakePositionDatumToData(p.stakeDatum));

  return await p.txBuilder
    .invalidBefore(slotBound(network, p.now, p.customSlotConfig).slot)
    .invalidHereafter(slotBound(network, unlock, p.customSlotConfig).slot)
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
