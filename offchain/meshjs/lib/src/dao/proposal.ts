/**
 * Transaction builders for the DAO proposal validator (MeshJS).
 *
 * Action set:
 *   - `buildCreateProposalTx`  spend a stake position and mint the proposal NFT
 *   - `buildCosignProposalTx`  add cosigning stake during the draft phase
 *   - `buildAcceptDraftTx`     advance Draft -> Voting
 *   - `buildRejectDraftTx`     burn a proposal that missed the cosign threshold
 *   - `buildEndVotingStageTx`  advance Voting -> Tally
 *   - `buildTallyTx`           spend vote artifacts and burn vote NFTs
 *   - `buildEndProposalTx`     burn the proposal NFT (execute or fail)
 */

import {
  applyParamsToScript,
  resolveScriptHash,
  serializeRewardAddress,
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
  burnProposalRedeemer,
  burnVotesRedeemer,
  mintProposalRedeemer,
  pollEffectRedeemerToData,
  proposalDatumToData,
  proposalParamsToData,
  proposalRedeemerToData,
  stakePositionDatumToData,
  stakeRedeemerToData,
  tallyVoteRedeemer,
} from "./datum";
import type {
  PollEffectRedeemer,
  ProposalDatum,
  ProposalParams,
  ProposalRedeemer,
  StakePositionDatum,
} from "./types";
import {
  proposalCompiledCode as proposalCode,
  plutusVersion,
} from "./blueprint";
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

/** Phase end times (POSIX ms) derived from a proposal's immutable fields. */
function phaseBounds(datum: ProposalDatum) {
  const draftEnd = datum.startTime + datum.timingConfig.draftLength;
  const votingEnd = draftEnd + datum.timingConfig.votingLength;
  const tallyEnd = votingEnd + datum.timingConfig.tallyLength;
  return { draftEnd, votingEnd, tallyEnd };
}

const DEFAULT_MIN_UTXO_LOVELACE = 2_000_000n;

/** The Plutus V3 script in the form MeshJS expects (parameterized). */
export function proposalScript(params: ProposalParams): PlutusScript {
  const code = applyParamsToScript(
    proposalCode,
    proposalParamsToData(params),
    "Mesh",
  );
  return { code, version: plutusVersion };
}

export function proposalScriptAddress(
  script: PlutusScript,
  networkId = 0,
): string {
  return serializePlutusScript(script, undefined, networkId).address;
}

/** Value of a proposal UTxO: ada + proposal NFT. */
function proposalValue(script: PlutusScript, tokenName: string): Asset[] {
  return [
    { unit: "lovelace", quantity: DEFAULT_MIN_UTXO_LOVELACE.toString() },
    {
      unit: resolveScriptHash(script.code, script.version) + tokenName,
      quantity: "1",
    },
  ];
}

/** The proposal NFT token name held by `utxo`, or "" if none. */
function nftNameOf(utxo: UTxO, policyId: string): string {
  const unit = utxo.output.amount
    .map((a) => a.unit)
    .find((u) => u !== "lovelace" && u.startsWith(policyId));
  return unit ? unit.slice(policyId.length) : "";
}

// ---------------------------------------------------- CreateProposal

export interface CreateProposalParams {
  txBuilder: MeshTxBuilder;
  /** The proposal validator script (its hash is the proposal NFT policy). */
  proposalScript: PlutusScript;
  /** The stake validator script used to spend the creating stake position. */
  stakeScript: PlutusScript;
  stakeUtxo: UTxO;
  stakeDatum: StakePositionDatum;
  settingsUtxo: UTxO;
  proposalDatum: ProposalDatum;
  /** Wall-clock used to set `start_time` and the validity lower bound (POSIX ms). */
  now: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
  customSlotConfig?: SlotConfig;
}

/** Spend the creating stake position and mint the proposal NFT. */
export async function buildCreateProposalTx(
  p: CreateProposalParams,
): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const proposalPolicy = resolveScriptHash(
    p.proposalScript.code,
    p.proposalScript.version,
  );
  const bound = slotBound(network, p.now, p.customSlotConfig);
  const proposalTokenName = nftNameFromRef(p.stakeUtxo.input);

  if (p.stakeDatum.owner.kind === "key") {
    p.txBuilder.requiredSignerHash(p.stakeDatum.owner.hash);
  }

  p.txBuilder
    .mintPlutusScriptV3()
    .mint("1", proposalPolicy, proposalTokenName)
    .mintRedeemerValue(mintProposalRedeemer(p.proposalDatum.results, 0))
    .mintingScript(p.proposalScript.code)
    .spendingPlutusScriptV3()
    .txIn(
      p.stakeUtxo.input.txHash,
      p.stakeUtxo.input.outputIndex,
      p.stakeUtxo.output.amount,
      p.stakeUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(stakeRedeemerToData({ kind: "CreateProposal" }))
    .txInScript(p.stakeScript.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    );

  p.txBuilder
    .txOut(
      proposalScriptAddress(p.proposalScript, networkId),
      proposalValue(p.proposalScript, proposalTokenName),
    )
    .txOutInlineDatumValue(proposalDatumToData(p.proposalDatum))
    .txOut(
      stakeScriptAddress(p.stakeScript, networkId),
      p.stakeUtxo.output.amount,
    )
    .txOutInlineDatumValue(stakePositionDatumToData(p.stakeDatum));

  return await p.txBuilder
    .invalidBefore(bound.slot)
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

// ---------------------------------------------------- proposal spends

export interface ProposalSpendParams {
  txBuilder: MeshTxBuilder;
  script: PlutusScript;
  proposalUtxo: UTxO;
  settingsUtxo: UTxO;
  /** The spent proposal's state (for phase-boundary derivation). */
  datum: ProposalDatum;
  /** Wall-clock used for lower-bound validity intervals (POSIX ms). */
  now: number;
  utxos: UTxO[];
  changeAddress: string;
  collateralUtxo: UTxO;
  network?: Network;
  customSlotConfig?: SlotConfig;
}

/**
 * Spend a proposal UTxO with `redeemer` and reproduce it with
 * `continuationDatum` (or close it entirely, burning the NFT, when
 * `continuationDatum` is null).
 */
async function buildProposalSpend(
  p: ProposalSpendParams,
  redeemer: ProposalRedeemer,
  continuationDatum: ProposalDatum | null,
  winnerEffect?: WinnerEffect,
): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const policyId = resolveScriptHash(p.script.code, p.script.version);
  const tokenName = nftNameOf(p.proposalUtxo, policyId);
  const bounds = phaseBounds(p.datum);

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.proposalUtxo.input.txHash,
      p.proposalUtxo.input.outputIndex,
      p.proposalUtxo.output.amount,
      p.proposalUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(proposalRedeemerToData(redeemer))
    .txInScript(p.script.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    );

  if (continuationDatum) {
    p.txBuilder
      .txOut(
        proposalScriptAddress(p.script, networkId),
        proposalValue(p.script, tokenName),
      )
      .txOutInlineDatumValue(proposalDatumToData(continuationDatum));
  } else {
    p.txBuilder
      .mintPlutusScriptV3()
      .mint("-1", policyId, tokenName)
      .mintRedeemerValue(burnProposalRedeemer())
      .mintingScript(p.script.code);
  }

  // Each action has its own validity-interval requirement (see proposal/spend.ak).
  if (redeemer.kind === "AcceptDraft") {
    p.txBuilder.invalidHereafter(
      slotBound(network, bounds.draftEnd, p.customSlotConfig).slot,
    );
  } else if (
    redeemer.kind === "RejectDraft" ||
    redeemer.kind === "EndVotingStage" ||
    redeemer.kind === "EndProposal"
  ) {
    p.txBuilder.invalidBefore(
      slotBound(network, p.now, p.customSlotConfig).slot,
    );
  }

  // The winning effect runs as a withdraw-0 alongside the proposal closure.
  // Its redeemer doubles as the truth-checked claim the proposal validator
  // and the candidate's `am_i_the_winner` both read.
  if (redeemer.kind === "EndProposal" && winnerEffect) {
    const effectHash = resolveScriptHash(
      winnerEffect.script.code,
      winnerEffect.script.version,
    );
    p.txBuilder
      .withdrawalPlutusScriptV3()
      .withdrawal(serializeRewardAddress(effectHash, true, networkId), "0")
      .withdrawalScript(winnerEffect.script.code)
      .withdrawalRedeemerValue(pollEffectRedeemerToData(winnerEffect.claim));
  }

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

// ---------------------------------------------------- Cosign

export interface CosignProposalParams extends ProposalSpendParams {
  /** The stake validator script used to spend the cosigning stake position. */
  stakeScript: PlutusScript;
  stakeUtxo: UTxO;
  stakeDatum: StakePositionDatum;
  /** The continuing proposal datum (status/co-signing stake updated). */
  proposalDatum: ProposalDatum;
}

export async function buildCosignProposalTx(
  p: CosignProposalParams,
): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const policyId = resolveScriptHash(p.script.code, p.script.version);
  const tokenName = nftNameOf(p.proposalUtxo, policyId);
  const authorizer = p.stakeDatum.delegatee ?? p.stakeDatum.owner;

  if (authorizer.kind === "key") {
    p.txBuilder.requiredSignerHash(authorizer.hash);
  }

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.proposalUtxo.input.txHash,
      p.proposalUtxo.input.outputIndex,
      p.proposalUtxo.output.amount,
      p.proposalUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(proposalRedeemerToData({ kind: "Cosign" }))
    .txInScript(p.script.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    )
    .txOut(
      proposalScriptAddress(p.script, networkId),
      proposalValue(p.script, tokenName),
    )
    .txOutInlineDatumValue(proposalDatumToData(p.proposalDatum))
    .spendingPlutusScriptV3()
    .txIn(
      p.stakeUtxo.input.txHash,
      p.stakeUtxo.input.outputIndex,
      p.stakeUtxo.output.amount,
      p.stakeUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(
      stakeRedeemerToData({ kind: "CosignProposal", proposalId: tokenName }),
    )
    .txInScript(p.stakeScript.code)
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

// ---------------------------------------------------- simple transitions

export interface SimpleProposalParams extends ProposalSpendParams {
  continuationDatum: ProposalDatum;
}

/**
 * The winning effect's withdraw-0 execution, required by `EndProposal` when a
 * strict winner above the `execute` threshold exists: the candidate script and
 * its `ExecuteWinner` claim, which both the proposal validator and the
 * candidate's `am_i_the_winner` verify against on-chain reality.
 */
export interface WinnerEffect {
  script: PlutusScript;
  claim: PollEffectRedeemer;
}

export interface EndProposalParams extends ProposalSpendParams {
  /** Required when the poll has a winner above the execute threshold. */
  winnerEffect?: WinnerEffect;
}

export async function buildAcceptDraftTx(
  p: SimpleProposalParams,
): Promise<string> {
  return buildProposalSpend(p, { kind: "AcceptDraft" }, p.continuationDatum);
}

export async function buildRejectDraftTx(
  p: ProposalSpendParams,
): Promise<string> {
  return buildProposalSpend(p, { kind: "RejectDraft" }, null);
}

export async function buildEndVotingStageTx(
  p: SimpleProposalParams,
): Promise<string> {
  return buildProposalSpend(p, { kind: "EndVotingStage" }, p.continuationDatum);
}

export async function buildEndProposalTx(
  p: EndProposalParams,
): Promise<string> {
  return buildProposalSpend(p, { kind: "EndProposal" }, null, p.winnerEffect);
}

// ---------------------------------------------------- Tally

export interface TallyParams extends ProposalSpendParams {
  continuationDatum: ProposalDatum;
  /** The vote validator script used to spend the vote artifacts. */
  voteScript: PlutusScript;
  /** Each vote artifact UTxO and the address to return its ada to. */
  votes: Array<{ voteUtxo: UTxO; ownerAddress: string }>;
}

export async function buildTallyTx(p: TallyParams): Promise<string> {
  const network = p.network ?? "preprod";
  const networkId = networkIdOf(network);
  const policyId = resolveScriptHash(p.script.code, p.script.version);
  const tokenName = nftNameOf(p.proposalUtxo, policyId);
  const votePolicy = resolveScriptHash(p.voteScript.code, p.voteScript.version);
  const bounds = phaseBounds(p.datum);

  for (const { voteUtxo } of p.votes) {
    p.txBuilder
      .spendingPlutusScriptV3()
      .txIn(
        voteUtxo.input.txHash,
        voteUtxo.input.outputIndex,
        voteUtxo.output.amount,
        voteUtxo.output.address,
      )
      .txInInlineDatumPresent()
      .txInRedeemerValue(tallyVoteRedeemer())
      .txInScript(p.voteScript.code);
  }

  const voteNfts = new Set<string>();
  for (const { voteUtxo } of p.votes) {
    for (const a of voteUtxo.output.amount) {
      if (a.unit !== "lovelace" && a.unit.startsWith(votePolicy)) {
        voteNfts.add(a.unit.slice(votePolicy.length));
      }
    }
  }

  if (voteNfts.size > 0) {
    // One fully-specified mint item per burned NFT: Mesh's queueMint merges
    // same-policy items with identical redeemer/script, but every `.mint()`
    // must already carry its script info (queueing the previous item).
    for (const name of voteNfts) {
      p.txBuilder
        .mintPlutusScriptV3()
        .mint("-1", votePolicy, name)
        .mintRedeemerValue(burnVotesRedeemer())
        .mintingScript(p.voteScript.code);
    }
  }

  for (const { voteUtxo, ownerAddress } of p.votes) {
    // Return the vote artifact's ada (minus the NFT, which this tx burns).
    const value = voteUtxo.output.amount.filter(
      (a) => a.unit === "lovelace" || !a.unit.startsWith(votePolicy),
    );
    p.txBuilder.txOut(ownerAddress, value);
  }

  p.txBuilder
    .spendingPlutusScriptV3()
    .txIn(
      p.proposalUtxo.input.txHash,
      p.proposalUtxo.input.outputIndex,
      p.proposalUtxo.output.amount,
      p.proposalUtxo.output.address,
    )
    .txInInlineDatumPresent()
    .txInRedeemerValue(proposalRedeemerToData({ kind: "TallyVotes" }))
    .txInScript(p.script.code)
    .readOnlyTxInReference(
      p.settingsUtxo.input.txHash,
      p.settingsUtxo.input.outputIndex,
    )
    .txOut(
      proposalScriptAddress(p.script, networkId),
      proposalValue(p.script, tokenName),
    )
    .txOutInlineDatumValue(proposalDatumToData(p.continuationDatum));

  return await p.txBuilder
    .invalidHereafter(
      slotBound(network, bounds.tallyEnd, p.customSlotConfig).slot,
    )
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
