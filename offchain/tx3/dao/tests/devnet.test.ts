import { afterAll, beforeAll, expect, test } from "vitest";
import {
  TrixDevnet,
  DEVNET_POLL,
  unwrapCborBytes,
  type ChainTip,
  type DevnetKitFactory,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import {
  SETTINGS_TOKEN_NAME,
  nftNameFromRef,
  pollEffectScript,
  proposalScript,
  proposalScriptAddress,
  settingsScript,
  settingsScriptAddress,
  stakeScript,
  stakeScriptAddress,
  voteScript,
  voteScriptAddress,
  type ProposalParams,
  type SettingsParams,
  type StakeParams,
  type VoteParams,
} from "@contracts-library/meshjs";
import { Party, type SubmittedTx, type TxBuilder } from "tx3-sdk";
import { applyCborEncoding, resolveScriptHash } from "@meshsdk/core";
import { Client } from "../codegen/ts-client/dao-governance/protocol";

const ADA = 1_000_000n;

// Governance parameters (staked-token units).
const THRESHOLDS = { create: 10, cosign: 5, accept: 30, vote: 5, execute: 10 };
// Phase durations (POSIX ms). Sized to cover each phase's transaction work
// with margin for trix's block cadence: draft = create + cosign + accept;
// voting = two votes (voter positions are opened during the draft); tally =
// two tallies. The suite sleeps until each deadline, so tighter windows mean
// a faster run.
const DRAFT_LENGTH = 20_000;
const VOTING_LENGTH = 20_000;
const TALLY_LENGTH = 20_000;
const TIMINGS = {
  draft_length: DRAFT_LENGTH,
  voting_length: VOTING_LENGTH,
  tally_length: TALLY_LENGTH,
};

const STAKE_A = 20;
const STAKE_B = 10;

const SEED_ADA = 10n * ADA;
const GAS_ADA = 10n * ADA;
const COLLATERAL = 5n * ADA;

const STAKED_TOKEN_NAME = "53544b"; // hex "STK"
const ALWAYS_TRUE_SCRIPT = "5101010023259800a518a4d136564004ae69";
const ALWAYS_TRUE_HASH = resolveScriptHash(
  applyCborEncoding(ALWAYS_TRUE_SCRIPT),
  "V3",
);

let devnet: TrixDevnet;
/** One registrar per devnet run: `devnet.wallet()` mints a fresh random
 * wallet on every call, so the funded instance must be reused across setups. */
let registrar: DevnetWallet;

const toBytes = (hex: string): Uint8Array => Buffer.from(hex, "hex");

/** Dummy env satisfying the dao protocol's declared env for test-kit txs.
 * `devnet_mint_staked` actually mints under the staked-token policy, so those
 * three fields are the real (constant) values. */
const KIT_ENV = {
  stake_hash: "00",
  stake_script: "00",
  proposal_hash: "00",
  proposal_script: "00",
  vote_hash: "00",
  vote_script: "00",
  settings_hash: "00",
  settings_script: "00",
  staked_token_policy: ALWAYS_TRUE_HASH,
  staked_token_name: STAKED_TOKEN_NAME,
  staked_token_script: ALWAYS_TRUE_SCRIPT,
  effect_script_ref: "00#0",
  effect_reward_address: "00",
};

const daoKit: DevnetKitFactory = (trpUrl, faucet) => {
  const kitClient = () =>
    new Client({ endpoint: trpUrl }, "local").withFaucet(faucet);
  return {
    pay: async (address, quantity) => {
      const submitted = await kitClient()
        .devnetPay({ destination: address, quantity: Number(quantity) })
        .env(KIT_ENV)
        .resolve()
        .then((r) => r.sign())
        .then((s) => s.submit());
      await submitted.waitForConfirmed(DEVNET_POLL);
    },
    deploy: async (publisherAddress, scriptCode, lovelace) => {
      const submitted = await kitClient()
        .withPublisher(Party.address(publisherAddress))
        .devnetDeployAuthorizer({
          script_code: Buffer.from(scriptCode, "hex"),
          lovelace: Number(lovelace),
        } as unknown as Parameters<Client["devnetDeployAuthorizer"]>[0])
        .env(KIT_ENV)
        .resolve()
        .then((r) => r.sign())
        .then((s) => s.submit());
      await submitted.waitForConfirmed(DEVNET_POLL);
    },
    mintTokens: async (address, quantity) => {
      const submitted = await kitClient()
        .devnetMintStaked({ destination: address, quantity: Number(quantity) })
        .env(KIT_ENV)
        .resolve()
        .then((r) => r.sign())
        .then((s) => s.submit());
      await submitted.waitForConfirmed(DEVNET_POLL);
    },
  };
};

beforeAll(async () => {
  devnet = await TrixDevnet.start({ protocolRoot: "dao", kit: daoKit });

  // The publisher funds one poll-effect reference-script deployment per test
  // (the candidate is parameterized by each instance's proposal validator).
  registrar = devnet.wallet("bootstrap/registrar");
  await devnet.payTo(registrar.address, 20n * ADA);

  // Split the faucet UTxO in two so `devnet_mint_staked` can pull its funding
  // and collateral from separate faucet UTxOs (a Plutus mint needs collateral).
  await devnet.payTo(devnet.faucetWallet.address, 2n * ADA);
}, 180_000);

afterAll(() => devnet.stop());

// --------------------------------------------------------------- datum shapes

const keyCred = (keyHashHex: string) => ({
  Key: { hash: toBytes(keyHashHex) },
});
const noneOpt = () => ({ None: {} });
const lock = (nameHex: string, unlockMs: number, stake: number) => ({
  proposal_id: toBytes(nameHex),
  unlock_time: unlockMs,
  stake,
});
const draftStatus = (cosigningStake: number) => ({
  Draft: { cosigning_stake: cosigningStake },
});
const votingStatus = () => ({ Voting: {} });
const tallyStatus = (votes: number[]) => ({ Tally: { votes } });

const stakeDatum = (
  ownerKeyHash: string,
  delegatee: unknown,
  locks: unknown[],
) => ({ owner: keyCred(ownerKeyHash), delegatee, locks });

const proposalDatum = (
  startTime: number,
  status: unknown,
  results: Uint8Array[],
) => ({
  thresholds: THRESHOLDS,
  timing_config: TIMINGS,
  start_time: startTime,
  status,
  results,
});

const voteDatum = (
  ownerKeyHash: string,
  proposalNameHex: string,
  votedOption: number,
  stake: number,
) => ({
  stake_owner: keyCred(ownerKeyHash),
  proposal: toBytes(proposalNameHex),
  voted_option: votedOption,
  stake,
});

const daoSettings = (
  stakeHash: string,
  proposalHash: string,
  voteHash: string,
) => ({
  thresholds: THRESHOLDS,
  timings: TIMINGS,
  stake_validator: toBytes(stakeHash),
  proposal_validator: toBytes(proposalHash),
  vote_validator: toBytes(voteHash),
});

// ------------------------------------------------------------------ harness

/** resolve → sign → submit, without waiting for confirmation. */
function submit(builder: TxBuilder): Promise<SubmittedTx> {
  return builder
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

/** Submit a transaction and wait until the devnet confirms it. */
async function confirm(builder: TxBuilder): Promise<void> {
  await (await submit(builder)).waitForConfirmed(DEVNET_POLL);
}

/** A still-unspent UTxO a rejected attack must have left untouched. */
interface UtxoGuard {
  address: string;
  ref: string;
}

/**
 * A rejected attack must fail for the RIGHT reason (ledger phase-2 script or
 * validity failure surfaced through TRP) and must leave the guarded UTxOs
 * untouched — a generic throw would also catch unrelated build-time failures
 * and prove nothing about the validator.
 */
async function expectAttackRejected(
  attack: Promise<unknown>,
  guards: UtxoGuard[],
): Promise<void> {
  let message = "";
  await expect(
    attack.catch((err: unknown) => {
      message = err instanceof Error ? err.message : String(err);
      throw err;
    }),
  ).rejects.toThrow();
  expect(message).toMatch(
    /script returned failure|-32003|invalid|validity|evaluat/i,
  );
  for (const guard of guards) {
    const stillThere = (await devnet.utxosOf(guard.address)).some(
      (u) => u.ref === guard.ref,
    );
    expect(stillThere, `guarded utxo ${guard.ref} was spent`).toBe(true);
  }
}

async function snapshot(address: string): Promise<Set<string>> {
  return new Set((await devnet.utxosOf(address)).map((u) => u.ref));
}

async function addedSince(
  address: string,
  before: Set<string>,
): Promise<DevnetUtxo[]> {
  return (await devnet.utxosOf(address)).filter((u) => !before.has(u.ref));
}

interface Instance {
  env: Record<string, unknown>;
  results: Uint8Array[];
  effectHash: string;
  settingsRef: string;
  stakeAddr: string;
  proposalAddr: string;
  voteAddr: string;
  settingsAddr: string;
  settings: ReturnType<typeof daoSettings>;
  governor: DevnetWallet;
  a: DevnetWallet;
  b: DevnetWallet;
  seedA: DevnetUtxo;
  seedB: DevnetUtxo;
  client: (signer: DevnetWallet) => Client;
}

async function setup(): Promise<Instance> {
  const governor = devnet.wallet("governor");
  const a = devnet.wallet("stakeholder-a");
  const b = devnet.wallet("stakeholder-b");

  // Governor: settings mint seed + collateral.
  await devnet.payTo(governor.address, SEED_ADA);
  const settingsSeed = await devnet.seedUtxo(governor);
  await devnet.payTo(governor.address, COLLATERAL);

  const settingsParams: SettingsParams = {
    seedUtxo: {
      txHash: settingsSeed.txHash,
      outputIndex: settingsSeed.outputIndex,
    },
    proposeAuth: { kind: "key", hash: governor.keyHash },
    applyAuth: { kind: "key", hash: governor.keyHash },
    applyDelay: 12_000,
    settingsTokenName: SETTINGS_TOKEN_NAME,
  };
  const settingsScriptObj = settingsScript(settingsParams);
  const settingsHash = resolveScriptHash(settingsScriptObj.code, "V3");
  const settingsAddr = settingsScriptAddress(settingsScriptObj);

  const daoParams = {
    stakeTokenPolicy: ALWAYS_TRUE_HASH,
    stakeTokenName: STAKED_TOKEN_NAME,
    settingsPolicy: settingsHash,
    settingsTokenName: SETTINGS_TOKEN_NAME,
  };
  const stakeScriptObj = stakeScript(daoParams as StakeParams);
  const proposalScriptObj = proposalScript(daoParams as ProposalParams);
  const voteScriptObj = voteScript(daoParams as VoteParams);
  const stakeHash = resolveScriptHash(stakeScriptObj.code, "V3");
  const proposalHash = resolveScriptHash(proposalScriptObj.code, "V3");
  const voteHash = resolveScriptHash(voteScriptObj.code, "V3");
  const stakeAddr = stakeScriptAddress(stakeScriptObj);
  const proposalAddr = proposalScriptAddress(proposalScriptObj);
  const voteAddr = voteScriptAddress(voteScriptObj);

  // The poll-effect reference candidate, parameterized by this instance's
  // proposal validator: deployed as a reference script, with its stake
  // credential registered so the withdraw-0 in `end_proposal` is permitted.
  const effect = pollEffectScript({ proposalPolicy: proposalHash });
  const effectHash = resolveScriptHash(effect.code, "V3");
  const effectRef = await devnet.deployReferenceScript({
    publisherAddress: registrar.address,
    scriptCode: unwrapCborBytes(effect.code),
    lovelace: 2n * ADA,
  });
  await devnet.registerScriptStakeCredential(registrar, effectHash);
  const results = [toBytes(effectHash)];

  const env = {
    stake_hash: stakeHash,
    stake_script: unwrapCborBytes(stakeScriptObj.code),
    proposal_hash: proposalHash,
    proposal_script: unwrapCborBytes(proposalScriptObj.code),
    vote_hash: voteHash,
    vote_script: unwrapCborBytes(voteScriptObj.code),
    settings_hash: settingsHash,
    settings_script: unwrapCborBytes(settingsScriptObj.code),
    staked_token_policy: ALWAYS_TRUE_HASH,
    staked_token_name: STAKED_TOKEN_NAME,
    staked_token_script: ALWAYS_TRUE_SCRIPT,
    effect_script_ref: effectRef.ref,
    effect_reward_address: `f0${effectHash}`,
  };

  const client = (signer: DevnetWallet) =>
    new Client({ endpoint: devnet.trpUrl }, "local")
      .withSigner(signer.party)
      .withStake(Party.address(stakeAddr))
      .withProposal(Party.address(proposalAddr))
      .withVote(Party.address(voteAddr))
      .withSettings(Party.address(settingsAddr));

  const settings = daoSettings(stakeHash, proposalHash, voteHash);

  await confirm(
    client(governor)
      .launchSettings({
        seed: settingsSeed.ref,
        dao_settings: settings,
        out_ix: 0,
      } as unknown as Parameters<Client["launchSettings"]>[0])
      .env(env),
  );
  const settingsRef = (await devnet.utxosOf(settingsAddr))[0].ref;

  // Stakeholder A: staked tokens + gas + collateral.
  const beforeA = await snapshot(a.address);
  await devnet.mintTokensTo(a.address, BigInt(STAKE_A));
  const [seedA] = await addedSince(a.address, beforeA);
  await devnet.payTo(a.address, GAS_ADA);
  await devnet.payTo(a.address, COLLATERAL);

  // Stakeholder B: staked tokens + gas + collateral.
  const beforeB = await snapshot(b.address);
  await devnet.mintTokensTo(b.address, BigInt(STAKE_B));
  const [seedB] = await addedSince(b.address, beforeB);
  await devnet.payTo(b.address, GAS_ADA);
  await devnet.payTo(b.address, COLLATERAL);

  return {
    env,
    results,
    effectHash,
    settingsRef,
    stakeAddr,
    proposalAddr,
    voteAddr,
    settingsAddr,
    settings,
    governor,
    a,
    b,
    seedA,
    seedB,
    client,
  };
}

/** Open a stake position for `signer` from their staked-token seed. */
async function createPosition(
  inst: Instance,
  signer: DevnetWallet,
  seed: DevnetUtxo,
  stake: number,
): Promise<{ utxo: DevnetUtxo; nftName: string }> {
  const nftName = nftNameFromRef({
    txHash: seed.txHash,
    outputIndex: seed.outputIndex,
  });
  const before = await snapshot(inst.stakeAddr);
  await confirm(
    inst
      .client(signer)
      .createStakePosition({
        seed: seed.ref,
        owner_utxo: {
          transaction_id: toBytes(seed.txHash),
          output_index: seed.outputIndex,
        },
        owner: keyCred(signer.keyHash),
        stake_amount: stake,
        stake_nft_name: toBytes(nftName),
        out_ix: 0,
      } as unknown as Parameters<Client["createStakePosition"]>[0])
      .env(inst.env),
  );
  const [position] = await addedSince(inst.stakeAddr, before);
  return { utxo: position, nftName };
}

interface ProposalState {
  utxo: DevnetUtxo;
  /** The continuing stake position (holds the draft lock). */
  stakeUtxo: DevnetUtxo;
  tokenName: string;
  startTime: number;
}

/** Build and submit the create-proposal transaction (no confirmation wait). */
async function createProposalTx(
  inst: Instance,
  signer: DevnetWallet,
  stakeUtxo: DevnetUtxo,
  stakeAmount: number,
  tip: ChainTip,
): Promise<SubmittedTx> {
  const tokenName = nftNameFromRef({
    txHash: stakeUtxo.txHash,
    outputIndex: stakeUtxo.outputIndex,
  });
  return submit(
    inst
      .client(signer)
      .createProposal({
        settings_ref: inst.settingsRef,
        stake_ref: stakeUtxo.ref,
        proposal_token_name: toBytes(tokenName),
        results: inst.results,
        new_stake_datum: stakeDatum(signer.keyHash, noneOpt(), [
          lock(tokenName, tip.timeMs + DRAFT_LENGTH, stakeAmount),
        ]),
        new_proposal_datum: proposalDatum(
          tip.timeMs,
          draftStatus(stakeAmount),
          inst.results,
        ),
        since_slot: tip.slot,
        out_ix: 1,
      } as unknown as Parameters<Client["createProposal"]>[0])
      .env(inst.env),
  );
}

/** Create a proposal and wait until it is confirmed on-chain. */
async function createProposal(
  inst: Instance,
  signer: DevnetWallet,
  stakeUtxo: DevnetUtxo,
  stakeAmount: number,
): Promise<ProposalState> {
  const before = await snapshot(inst.proposalAddr);
  const beforeStake = await snapshot(inst.stakeAddr);
  const tip = await devnet.tip();
  const submitted = await createProposalTx(
    inst,
    signer,
    stakeUtxo,
    stakeAmount,
    tip,
  );
  await submitted.waitForConfirmed(DEVNET_POLL);
  const [utxo] = await addedSince(inst.proposalAddr, before);
  const [stakeContinuation] = await addedSince(inst.stakeAddr, beforeStake);
  return {
    utxo,
    stakeUtxo: stakeContinuation,
    tokenName: nftNameFromRef({
      txHash: stakeUtxo.txHash,
      outputIndex: stakeUtxo.outputIndex,
    }),
    startTime: tip.timeMs,
  };
}

/** Build and submit the accept-draft transaction (no confirmation wait). */
async function acceptDraftTx(
  inst: Instance,
  proposal: ProposalState,
  signer: DevnetWallet,
): Promise<SubmittedTx> {
  return submit(
    inst
      .client(signer)
      .acceptDraft({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal.utxo.ref,
        new_proposal_datum: proposalDatum(
          proposal.startTime,
          votingStatus(),
          inst.results,
        ),
        until_slot: devnet.slotAtTimeMs(proposal.startTime + DRAFT_LENGTH),
      } as unknown as Parameters<Client["acceptDraft"]>[0])
      .env(inst.env),
  );
}

/** Accept a draft proposal and wait until it is confirmed on-chain. */
async function acceptDraft(
  inst: Instance,
  proposal: ProposalState,
  signer: DevnetWallet,
): Promise<{ utxo: DevnetUtxo }> {
  const before = await snapshot(inst.proposalAddr);
  const submitted = await acceptDraftTx(inst, proposal, signer);
  await submitted.waitForConfirmed(DEVNET_POLL);
  const [utxo] = await addedSince(inst.proposalAddr, before);
  return { utxo };
}

/** Build and submit a vote transaction (no confirmation wait). */
async function voteTx(
  inst: Instance,
  signer: DevnetWallet,
  proposalRef: string,
  stakeUtxo: DevnetUtxo,
  proposalTokenName: string,
  votingEnd: number,
  stake: number,
): Promise<SubmittedTx> {
  const voteNftName = nftNameFromRef({
    txHash: stakeUtxo.txHash,
    outputIndex: stakeUtxo.outputIndex,
  });
  return submit(
    inst
      .client(signer)
      .vote({
        settings_ref: inst.settingsRef,
        proposal_ref: proposalRef,
        stake_ref: stakeUtxo.ref,
        proposal_id: toBytes(proposalTokenName),
        voted_option: 0,
        vote_nft_name: toBytes(voteNftName),
        vote_datum: voteDatum(signer.keyHash, proposalTokenName, 0, stake),
        new_stake_datum: stakeDatum(signer.keyHash, noneOpt(), [
          lock(proposalTokenName, votingEnd, stake),
        ]),
        since_slot: (await devnet.tip()).slot,
        until_slot: devnet.slotAtTimeMs(votingEnd),
        out_ix: 1,
      } as unknown as Parameters<Client["vote"]>[0])
      .env(inst.env),
  );
}

/** Cast a vote and wait until it is confirmed on-chain. */
async function vote(
  inst: Instance,
  signer: DevnetWallet,
  proposalRef: string,
  stakeUtxo: DevnetUtxo,
  proposalTokenName: string,
  votingEnd: number,
  stake: number,
): Promise<{ utxo: DevnetUtxo; nftName: string }> {
  const before = await snapshot(inst.voteAddr);
  const submitted = await voteTx(
    inst,
    signer,
    proposalRef,
    stakeUtxo,
    proposalTokenName,
    votingEnd,
    stake,
  );
  await submitted.waitForConfirmed(DEVNET_POLL);
  const [voteUtxo] = await addedSince(inst.voteAddr, before);
  return {
    utxo: voteUtxo,
    nftName: nftNameFromRef({
      txHash: stakeUtxo.txHash,
      outputIndex: stakeUtxo.outputIndex,
    }),
  };
}

// ---------------------------------------------------------------- happy path

/**
 * Drive one full proposal lifecycle (create -> cosign -> accept -> two votes
 * -> tally) with the instance's poll_effect candidate as the single option,
 * parking the proposal past the tally deadline where `end_proposal` becomes
 * legal. A position that already locks a proposal cannot vote on it
 * (`!has_proposal` in the stake validator), so voters open fresh positions
 * from newly minted tokens.
 */
async function lifecycleToTally(): Promise<{
  inst: Instance;
  proposal6: DevnetUtxo;
  proposalTokenName: string;
}> {
  const inst = await setup();

  // 1. Stake positions for A (20) and B (10) to create and co-sign with.
  const posA = await createPosition(inst, inst.a, inst.seedA, STAKE_A);
  const posB = await createPosition(inst, inst.b, inst.seedB, STAKE_B);

  // Extra staked tokens for the voting positions.
  const beforeMintA = await snapshot(inst.a.address);
  await devnet.mintTokensTo(inst.a.address, BigInt(STAKE_A));
  const [seedA2] = await addedSince(inst.a.address, beforeMintA);
  const beforeMintB = await snapshot(inst.b.address);
  await devnet.mintTokensTo(inst.b.address, BigInt(STAKE_B));
  const [seedB2] = await addedSince(inst.b.address, beforeMintB);

  // Voter positions: they only need tokens, so they are opened during the
  // draft phase and the voting window only has to cover the two vote txs.
  const voterPosA = await createPosition(inst, inst.a, seedA2, STAKE_A);
  const voterPosB = await createPosition(inst, inst.b, seedB2, STAKE_B);

  // 2. A creates the proposal (single option -> the poll_effect candidate).
  const created = await createProposal(inst, inst.a, posA.utxo, STAKE_A);
  const startTime = created.startTime;
  const proposalTokenName = created.tokenName;
  const proposal1 = created.utxo;
  const posA2 = created.stakeUtxo;

  // 3. B co-signs, reaching the accept threshold (20 + 10 = 30).
  const beforeStake2 = await snapshot(inst.stakeAddr);
  const beforeProposal2 = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.b)
      .cosign({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal1.ref,
        stake_ref: posB.utxo.ref,
        proposal_token_name: toBytes(proposalTokenName),
        new_proposal_datum: proposalDatum(
          startTime,
          draftStatus(STAKE_A + STAKE_B),
          inst.results,
        ),
        new_stake_datum: stakeDatum(inst.b.keyHash, noneOpt(), [
          lock(proposalTokenName, startTime + DRAFT_LENGTH, STAKE_B),
        ]),
        until_slot: devnet.slotAtTimeMs(startTime + DRAFT_LENGTH),
      } as unknown as Parameters<Client["cosign"]>[0])
      .env(inst.env),
  );
  const [posB2] = await addedSince(inst.stakeAddr, beforeStake2);
  const [proposal2] = await addedSince(inst.proposalAddr, beforeProposal2);

  // 4. Accept the draft (still within the draft window).
  const voting = await acceptDraft(
    inst,
    {
      ...created,
      utxo: proposal2,
    },
    inst.a,
  );
  const proposal3 = voting.utxo;

  // 5. A and B vote (option 0) from FRESH positions, during the voting
  //    window. The vote continuation only carries the new vote lock.
  const votingEnd = startTime + DRAFT_LENGTH + VOTING_LENGTH;
  const { utxo: voteA, nftName: voteNftA } = await vote(
    inst,
    inst.a,
    proposal3.ref,
    voterPosA.utxo,
    proposalTokenName,
    votingEnd,
    STAKE_A,
  );

  const { utxo: voteB, nftName: voteNftB } = await vote(
    inst,
    inst.b,
    proposal3.ref,
    voterPosB.utxo,
    proposalTokenName,
    votingEnd,
    STAKE_B,
  );

  // 6. End the voting stage after the voting window.
  await devnet.waitForChainTimeMs(votingEnd + 1_000);
  const votingEndSlot = (await devnet.tip()).slot;
  const beforeProposal4 = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.a)
      .endVotingStage({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal3.ref,
        new_proposal_datum: proposalDatum(
          startTime,
          tallyStatus([0]),
          inst.results,
        ),
        since_slot: votingEndSlot,
      } as unknown as Parameters<Client["endVotingStage"]>[0])
      .env(inst.env),
  );
  const [proposal4] = await addedSince(inst.proposalAddr, beforeProposal4);

  // 7. Tally both votes (one vote per tally transaction).
  const tallyEnd = startTime + DRAFT_LENGTH + VOTING_LENGTH + TALLY_LENGTH;
  const beforeProposal5 = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.a)
      .tally({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal4.ref,
        vote_ref: voteA.ref,
        vote_nft_name: toBytes(voteNftA),
        refund: inst.a.address,
        new_proposal_datum: proposalDatum(
          startTime,
          tallyStatus([STAKE_A]),
          inst.results,
        ),
        until_slot: devnet.slotAtTimeMs(tallyEnd),
      } as unknown as Parameters<Client["tally"]>[0])
      .env(inst.env),
  );
  const [proposal5] = await addedSince(inst.proposalAddr, beforeProposal5);

  const beforeProposal6 = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.a)
      .tally({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal5.ref,
        vote_ref: voteB.ref,
        vote_nft_name: toBytes(voteNftB),
        refund: inst.b.address,
        new_proposal_datum: proposalDatum(
          startTime,
          tallyStatus([STAKE_A + STAKE_B]),
          inst.results,
        ),
        until_slot: devnet.slotAtTimeMs(tallyEnd),
      } as unknown as Parameters<Client["tally"]>[0])
      .env(inst.env),
  );
  const [proposal6] = await addedSince(inst.proposalAddr, beforeProposal6);

  // The end_proposal window opens once the tally deadline has passed.
  await devnet.waitForChainTimeMs(tallyEnd + 1_000);

  return { inst, proposal6, proposalTokenName };
}

test("executes the winning effect via the poll_effect candidate", async () => {
  const { inst, proposal6, proposalTokenName } = await lifecycleToTally();

  // The withdrawal runs the candidate's own validator, which re-derives the
  // verdict with `am_i_the_winner`, while the proposal validator checks the
  // truthful `ExecuteWinner` claim.
  await confirm(
    inst
      .client(inst.a)
      .endProposal({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal6.ref,
        proposal_token_name: toBytes(proposalTokenName),
        winner_option: 0,
        since_slot: (await devnet.tip()).slot,
      } as unknown as Parameters<Client["endProposal"]>[0])
      .env(inst.env),
  );

  // The proposal NFT is burned; no proposal UTxO remains.
  expect(await devnet.utxosOf(inst.proposalAddr)).toHaveLength(0);
  // Votes were burned during tally; no vote UTxOs remain.
  expect(await devnet.utxosOf(inst.voteAddr)).toHaveLength(0);
  // The four stake positions survive (create/cosign + voting positions).
  expect(await devnet.utxosOf(inst.stakeAddr)).toHaveLength(4);
}, 300_000);

test("rejects EndProposal with a lying effect claim", async () => {
  const { inst, proposal6, proposalTokenName } = await lifecycleToTally();

  // The declared claim (option 1) does not match the actual winner (option 0):
  // rejected by the proposal validator's claim check and by the candidate's
  // own am_i_the_winner.
  await expectAttackRejected(
    submit(
      inst
        .client(inst.a)
        .endProposal({
          settings_ref: inst.settingsRef,
          proposal_ref: proposal6.ref,
          proposal_token_name: toBytes(proposalTokenName),
          winner_option: 1,
          since_slot: (await devnet.tip()).slot,
        } as unknown as Parameters<Client["endProposal"]>[0])
        .env(inst.env),
    ),
    [{ address: inst.proposalAddr, ref: proposal6.ref }],
  );

  // The failed attempt consumed nothing: a truthful claim still executes.
  await confirm(
    inst
      .client(inst.a)
      .endProposal({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal6.ref,
        proposal_token_name: toBytes(proposalTokenName),
        winner_option: 0,
        since_slot: (await devnet.tip()).slot,
      } as unknown as Parameters<Client["endProposal"]>[0])
      .env(inst.env),
  );
  expect(await devnet.utxosOf(inst.proposalAddr)).toHaveLength(0);
}, 300_000);

// ---------------------------------------------------------------- mechanics

test("supports deposit, withdraw, delegate and close position", async () => {
  const inst = await setup();

  const pos = await createPosition(inst, inst.a, inst.seedA, STAKE_A);

  // Mint extra staked tokens to deposit.
  await devnet.mintTokensTo(inst.a.address, 5n);

  // Deposit: add 5 staked tokens (no locks, so the datum is unchanged).
  const beforeStake = await snapshot(inst.stakeAddr);
  await confirm(
    inst
      .client(inst.a)
      .deposit({
        settings_ref: inst.settingsRef,
        stake_ref: pos.utxo.ref,
        added: 5,
        new_datum: stakeDatum(inst.a.keyHash, noneOpt(), []),
        since_slot: (await devnet.tip()).slot,
      } as unknown as Parameters<Client["deposit"]>[0])
      .env(inst.env),
  );
  const [posDeposited] = await addedSince(inst.stakeAddr, beforeStake);

  // Withdraw: pull back 5 free staked tokens.
  const beforeStake2 = await snapshot(inst.stakeAddr);
  await confirm(
    inst
      .client(inst.a)
      .withdraw({
        settings_ref: inst.settingsRef,
        stake_ref: posDeposited.ref,
        amount: 5,
        new_datum: stakeDatum(inst.a.keyHash, noneOpt(), []),
        since_slot: (await devnet.tip()).slot,
      } as unknown as Parameters<Client["withdraw"]>[0])
      .env(inst.env),
  );
  const [posWithdrawn] = await addedSince(inst.stakeAddr, beforeStake2);

  // Delegate voting power to B.
  const delegatee = { Some: { credential: keyCred(inst.b.keyHash) } };
  const beforeStake3 = await snapshot(inst.stakeAddr);
  await confirm(
    inst
      .client(inst.a)
      .delegate({
        settings_ref: inst.settingsRef,
        stake_ref: posWithdrawn.ref,
        delegatee,
        new_datum: stakeDatum(inst.a.keyHash, delegatee, []),
      } as unknown as Parameters<Client["delegate"]>[0])
      .env(inst.env),
  );
  const [posDelegated] = await addedSince(inst.stakeAddr, beforeStake3);

  // Close the position (no locks, so it is free to burn).
  await confirm(
    inst
      .client(inst.a)
      .closePosition({
        settings_ref: inst.settingsRef,
        stake_ref: posDelegated.ref,
        stake_nft_name: toBytes(pos.nftName),
        since_slot: (await devnet.tip()).slot,
      } as unknown as Parameters<Client["closePosition"]>[0])
      .env(inst.env),
  );

  expect(await devnet.utxosOf(inst.stakeAddr)).toHaveLength(0);
}, 300_000);

// --------------------------------------------------- rejects (mesh parity)

test("rejects a proposal mint with insufficient stake", async () => {
  const inst = await setup();
  const beforeMint = await snapshot(inst.a.address);
  await devnet.mintTokensTo(inst.a.address, BigInt(THRESHOLDS.create - 1));
  const [seed] = await addedSince(inst.a.address, beforeMint);
  const pos = await createPosition(inst, inst.a, seed, THRESHOLDS.create - 1);

  const tip = await devnet.tip();
  await expectAttackRejected(
    createProposalTx(inst, inst.a, pos.utxo, THRESHOLDS.create - 1, tip),
    [{ address: inst.stakeAddr, ref: pos.utxo.ref }],
  );
}, 300_000);

test("rejects a vote below the vote threshold", async () => {
  const inst = await setup();
  const posA = await createPosition(inst, inst.a, inst.seedA, STAKE_A);
  const posB = await createPosition(inst, inst.b, inst.seedB, STAKE_B);
  const created = await createProposal(inst, inst.a, posA.utxo, STAKE_A);
  // B co-signs so the draft reaches the accept threshold (20 + 10 = 30).
  const beforeProposal = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.b)
      .cosign({
        settings_ref: inst.settingsRef,
        proposal_ref: created.utxo.ref,
        stake_ref: posB.utxo.ref,
        proposal_token_name: toBytes(created.tokenName),
        new_proposal_datum: proposalDatum(
          created.startTime,
          draftStatus(STAKE_A + STAKE_B),
          inst.results,
        ),
        new_stake_datum: stakeDatum(inst.b.keyHash, noneOpt(), [
          lock(created.tokenName, created.startTime + DRAFT_LENGTH, STAKE_B),
        ]),
        until_slot: devnet.slotAtTimeMs(created.startTime + DRAFT_LENGTH),
      } as unknown as Parameters<Client["cosign"]>[0])
      .env(inst.env),
  );
  const [proposal2] = await addedSince(inst.proposalAddr, beforeProposal);
  const voting = await acceptDraft(
    inst,
    { ...created, utxo: proposal2 },
    inst.a,
  );

  // A fresh position holding fewer tokens than the vote threshold.
  const beforeMint = await snapshot(inst.b.address);
  await devnet.mintTokensTo(inst.b.address, BigInt(THRESHOLDS.vote - 1));
  const [seedLow] = await addedSince(inst.b.address, beforeMint);
  const lowPos = await createPosition(
    inst,
    inst.b,
    seedLow,
    THRESHOLDS.vote - 1,
  );
  const votingEnd = created.startTime + DRAFT_LENGTH + VOTING_LENGTH;

  await expectAttackRejected(
    voteTx(
      inst,
      inst.b,
      voting.utxo.ref,
      lowPos.utxo,
      created.tokenName,
      votingEnd,
      THRESHOLDS.vote - 1,
    ),
    [
      { address: inst.proposalAddr, ref: voting.utxo.ref },
      { address: inst.stakeAddr, ref: lowPos.utxo.ref },
    ],
  );
}, 300_000);

test("rejects an accept-draft after the draft phase ends", async () => {
  const inst = await setup();
  const posA = await createPosition(inst, inst.a, inst.seedA, STAKE_A);
  const created = await createProposal(inst, inst.a, posA.utxo, STAKE_A);

  await devnet.waitForChainTimeMs(created.startTime + DRAFT_LENGTH + 1_000);

  await expectAttackRejected(acceptDraftTx(inst, created, inst.a), [
    { address: inst.proposalAddr, ref: created.utxo.ref },
  ]);
}, 300_000);

test("rejects a close while locks are active", async () => {
  const inst = await setup();
  const posA = await createPosition(inst, inst.a, inst.seedA, STAKE_A);
  const created = await createProposal(inst, inst.a, posA.utxo, STAKE_A);

  // The creator's position carries the live draft lock.
  await expectAttackRejected(
    submit(
      inst
        .client(inst.a)
        .closePosition({
          settings_ref: inst.settingsRef,
          stake_ref: created.stakeUtxo.ref,
          stake_nft_name: toBytes(posA.nftName),
          since_slot: (await devnet.tip()).slot,
        } as unknown as Parameters<Client["closePosition"]>[0])
        .env(inst.env),
    ),
    [{ address: inst.stakeAddr, ref: created.stakeUtxo.ref }],
  );
}, 300_000);
