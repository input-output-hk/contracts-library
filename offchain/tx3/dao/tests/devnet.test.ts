import { afterAll, beforeAll, expect, test } from "vitest";
import {
  TrixDevnet,
  DEVNET_POLL,
  unwrapCborBytes,
  type DevnetKitFactory,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import {
  SETTINGS_TOKEN_NAME,
  nftNameFromRef,
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
import { Party, type TxBuilder } from "tx3-sdk";
import { applyCborEncoding, resolveScriptHash } from "@meshsdk/core";
import { Client } from "../codegen/ts-client/dao-governance/protocol";

const ADA = 1_000_000n;

// Governance parameters (staked-token units).
const THRESHOLDS = { create: 10, cosign: 5, accept: 30, vote: 5, execute: 10 };
// Phase durations (POSIX ms). Long enough that a tx submitted a block later
// (~5s on trix devnets) still lands inside its window.
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
let authorizerRef: DevnetUtxo;

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
  effect_script_hash: "00",
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

  const registrar = devnet.wallet("bootstrap/registrar");
  await devnet.payTo(registrar.address, 10n * ADA);
  await devnet.payTo(registrar.address, COLLATERAL);
  authorizerRef = await devnet.deployReferenceScript({
    publisherAddress: registrar.address,
    scriptCode: ALWAYS_TRUE_SCRIPT,
    lovelace: 2n * ADA,
  });
  // The execution-effect script's stake credential must exist for the
  // withdraw-0 keyed to it in `end_proposal`.
  await devnet.registerScriptStakeCredential(registrar, ALWAYS_TRUE_HASH);

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
const lock = (nameHex: string, unlockMs: number, stake: number) => [
  toBytes(nameHex),
  unlockMs,
  stake,
];
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

async function confirm(builder: TxBuilder): Promise<void> {
  const submitted = await builder
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
  await submitted.waitForConfirmed(DEVNET_POLL);
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
    effect_script_ref: authorizerRef.ref,
    effect_script_hash: ALWAYS_TRUE_HASH,
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

// ---------------------------------------------------------------- happy path

test("runs the full proposal lifecycle from stake to execution", async () => {
  const inst = await setup();

  // 1. Stake positions for A (20) and B (10).
  const posA = await createPosition(inst, inst.a, inst.seedA, STAKE_A);
  const posB = await createPosition(inst, inst.b, inst.seedB, STAKE_B);

  // 2. A creates a proposal (single option -> always-true execution effect).
  const startTip = await devnet.tip();
  const startTime = startTip.timeMs;
  const proposalTokenName = nftNameFromRef({
    txHash: posA.utxo.txHash,
    outputIndex: posA.utxo.outputIndex,
  });
  const results = [toBytes(ALWAYS_TRUE_HASH)];

  const beforeStake1 = await snapshot(inst.stakeAddr);
  const beforeProposal1 = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.a)
      .createProposal({
        settings_ref: inst.settingsRef,
        stake_ref: posA.utxo.ref,
        proposal_token_name: toBytes(proposalTokenName),
        results,
        new_stake_datum: stakeDatum(inst.a.keyHash, noneOpt(), [
          lock(proposalTokenName, startTime + DRAFT_LENGTH, STAKE_A),
        ]),
        new_proposal_datum: proposalDatum(
          startTime,
          draftStatus(STAKE_A),
          results,
        ),
        since_slot: startTip.slot,
        out_ix: 1,
      } as unknown as Parameters<Client["createProposal"]>[0])
      .env(inst.env),
  );
  const [posA2] = await addedSince(inst.stakeAddr, beforeStake1);
  const [proposal1] = await addedSince(inst.proposalAddr, beforeProposal1);

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
          results,
        ),
        new_stake_datum: stakeDatum(inst.b.keyHash, noneOpt(), [
          lock(proposalTokenName, startTime + DRAFT_LENGTH, STAKE_B),
        ]),
      } as unknown as Parameters<Client["cosign"]>[0])
      .env(inst.env),
  );
  const [posB2] = await addedSince(inst.stakeAddr, beforeStake2);
  const [proposal2] = await addedSince(inst.proposalAddr, beforeProposal2);
  // 4. Accept the draft (still within the draft window).
  const draftEnd = startTime + DRAFT_LENGTH;
  const beforeProposal3 = await snapshot(inst.proposalAddr);
  await confirm(
    inst
      .client(inst.a)
      .acceptDraft({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal2.ref,
        new_proposal_datum: proposalDatum(startTime, votingStatus(), results),
        until_slot: devnet.slotAtTimeMs(draftEnd),
      } as unknown as Parameters<Client["acceptDraft"]>[0])
      .env(inst.env),
  );
  const [proposal3] = await addedSince(inst.proposalAddr, beforeProposal3);

  // 5. A and B vote (option 0), during the voting window.
  const votingEnd = startTime + DRAFT_LENGTH + VOTING_LENGTH;
  const voteNftA = nftNameFromRef({
    txHash: posA2.txHash,
    outputIndex: posA2.outputIndex,
  });
  const beforeStake3 = await snapshot(inst.stakeAddr);
  const beforeVote1 = await snapshot(inst.voteAddr);
  await confirm(
    inst
      .client(inst.a)
      .vote({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal3.ref,
        stake_ref: posA2.ref,
        proposal_id: toBytes(proposalTokenName),
        voted_option: 0,
        vote_nft_name: toBytes(voteNftA),
        vote_datum: voteDatum(inst.a.keyHash, proposalTokenName, 0, STAKE_A),
        new_stake_datum: stakeDatum(inst.a.keyHash, noneOpt(), [
          lock(proposalTokenName, startTime + DRAFT_LENGTH, STAKE_A),
          lock(proposalTokenName, votingEnd, STAKE_A),
        ]),
        since_slot: (await devnet.tip()).slot,
        until_slot: devnet.slotAtTimeMs(votingEnd),
        out_ix: 1,
      } as unknown as Parameters<Client["vote"]>[0])
      .env(inst.env),
  );
  await addedSince(inst.stakeAddr, beforeStake3);
  const [voteA] = await addedSince(inst.voteAddr, beforeVote1);

  const voteNftB = nftNameFromRef({
    txHash: posB2.txHash,
    outputIndex: posB2.outputIndex,
  });
  const beforeStake4 = await snapshot(inst.stakeAddr);
  const beforeVote2 = await snapshot(inst.voteAddr);
  await confirm(
    inst
      .client(inst.b)
      .vote({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal3.ref,
        stake_ref: posB2.ref,
        proposal_id: toBytes(proposalTokenName),
        voted_option: 0,
        vote_nft_name: toBytes(voteNftB),
        vote_datum: voteDatum(inst.b.keyHash, proposalTokenName, 0, STAKE_B),
        new_stake_datum: stakeDatum(inst.b.keyHash, noneOpt(), [
          lock(proposalTokenName, startTime + DRAFT_LENGTH, STAKE_B),
          lock(proposalTokenName, votingEnd, STAKE_B),
        ]),
        since_slot: (await devnet.tip()).slot,
        until_slot: devnet.slotAtTimeMs(votingEnd),
        out_ix: 1,
      } as unknown as Parameters<Client["vote"]>[0])
      .env(inst.env),
  );
  await addedSince(inst.stakeAddr, beforeStake4);
  const [voteB] = await addedSince(inst.voteAddr, beforeVote2);

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
        new_proposal_datum: proposalDatum(startTime, tallyStatus([0]), results),
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
          results,
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
          results,
        ),
        until_slot: devnet.slotAtTimeMs(tallyEnd),
      } as unknown as Parameters<Client["tally"]>[0])
      .env(inst.env),
  );
  const [proposal6] = await addedSince(inst.proposalAddr, beforeProposal6);

  // 8. End the proposal after the tally window: the winning option (0, with
  //    30 votes >= execute 10) must run its bound effect (withdraw-0).
  await devnet.waitForChainTimeMs(tallyEnd + 1_000);
  const tallyEndSlot = (await devnet.tip()).slot;
  await confirm(
    inst
      .client(inst.a)
      .endProposal({
        settings_ref: inst.settingsRef,
        proposal_ref: proposal6.ref,
        proposal_token_name: toBytes(proposalTokenName),
        since_slot: tallyEndSlot,
      } as unknown as Parameters<Client["endProposal"]>[0])
      .env(inst.env),
  );

  // The proposal NFT is burned; no proposal UTxO remains.
  expect(await devnet.utxosOf(inst.proposalAddr)).toHaveLength(0);
  // Votes were burned during tally; no vote UTxOs remain.
  expect(await devnet.utxosOf(inst.voteAddr)).toHaveLength(0);
  // The two stake positions survive with their vote locks recorded.
  expect(await devnet.utxosOf(inst.stakeAddr)).toHaveLength(2);
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
