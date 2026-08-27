/**
 * End-to-end tests for the DAO governance contracts (proposal / stake / vote)
 * against a Yaci DevKit devnet.
 */

import {
  buildAcceptDraftTx,
  buildClosePositionTx,
  buildCosignProposalTx,
  buildCreateProposalTx,
  buildCreateStakePositionTx,
  buildDepositTx,
  buildDelegateTx,
  buildEndProposalTx,
  buildEndVotingStageTx,
  buildTallyTx,
  buildVoteTx,
  buildWithdrawTx,
  daoSettingsToData,
  enclosingSlotBound,
  mintRedeemer,
  nftNameFromRef,
  proposalScript,
  proposalScriptAddress,
  SETTINGS_TOKEN_NAME,
  settingsDatumToData,
  settingsScript,
  settingsScriptAddress,
  stakeScript,
  stakeScriptAddress,
  voteScript,
  voteScriptAddress,
  type DaoSettings,
  type ProposalDatum,
  type ProposalThresholds,
  type ProposalTimingConfig,
  type SettingsDatum,
  type StakePositionDatum,
  type VoteDatum,
} from "@contracts-library/meshjs";
import {
  mConStr0,
  resolveScriptHash,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
  chainNowMs,
  collateralOf,
  devnetReachable,
  devnetSlotConfig,
  fundedAccount,
  lovelaceOf,
  makeProvider,
  NETWORK_ID,
  newTxBuilder,
  scriptOutputOf,
  signAndSubmit,
  STORE_URL,
  waitForTx,
  waitUntilChainTimeMs,
  type Account,
} from "../src/devnet";
import { ALWAYS_TRUE } from "../src/fixtures";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping all e2e tests: no Yaci devnet at ${STORE_URL}. ` +
      `Run \`npm run test:devnet\` (or start one and set INDEXER_URL / YACI_STORE_URL).`,
  );
}

// hex("stake") — the DAO's staked token name (minted by the test harness).
const STAKE_TOKEN_NAME = "7374616b65";
const STAKE_TOKEN_QUANTITY = 1_000_000n;

const THRESHOLDS: ProposalThresholds = {
  create: 100_000n,
  cosign: 50_000n,
  accept: 100_000n,
  vote: 10_000n,
  execute: 200_000n,
};

const TIMINGS: ProposalTimingConfig = {
  draftLength: 10_000,
  votingLength: 10_000,
  tallyLength: 10_000,
};

/** Number of milliseconds of slack added past a phase boundary before waiting. */
const PHASE_SLACK = 2_000;

describe.skipIf(!reachable)("dao e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: SlotConfig;

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();
  });

  /** The stake token policy is an always-true test minting script. */
  const stakeTokenPolicy = () => resolveScriptHash(ALWAYS_TRUE.cbor, "V3");
  const stakeTokenUnit = () => stakeTokenPolicy() + STAKE_TOKEN_NAME;

  async function setup(): Promise<{
    owner: Account;
    cosigner: Account;
    admin: Account;
    settingsUtxo: UTxO;
    stake: { script: ReturnType<typeof stakeScript>; addr: string };
    proposal: { script: ReturnType<typeof proposalScript>; addr: string };
    vote: { script: ReturnType<typeof voteScript>; addr: string };
  }> {
    const owner = await fundedAccount(provider, [5_000, 5_000]);
    const cosigner = await fundedAccount(provider, [5_000, 5_000]);
    const admin = await fundedAccount(provider, [5_000, 5_000]);

    // 1. Mint the DAO's staked token (always-true policy) to the accounts that
    //    will hold positions.
    const policy = stakeTokenPolicy();
    const mintStakeTokens = async (account: Account): Promise<void> => {
      const col = (await account.wallet.getCollateral())[0];
      const mintTx = await newTxBuilder(provider)
        .mintPlutusScriptV3()
        .mint(STAKE_TOKEN_QUANTITY.toString(), policy, STAKE_TOKEN_NAME)
        .mintRedeemerValue(mConStr0([]))
        .mintingScript(ALWAYS_TRUE.cbor)
        .txInCollateral(
          col.input.txHash,
          col.input.outputIndex,
          col.output.amount,
          col.output.address,
        )
        .changeAddress(account.address)
        .selectUtxosFrom(await account.wallet.getUtxos())
        .complete();
      await waitForTx(provider, await signAndSubmit(account, mintTx));
    };
    await mintStakeTokens(owner);
    await mintStakeTokens(cosigner);

    // 2. Build the settings script and derive its hash (the settings NFT
    //    policy), which parameterizes the DAO validators independently of the
    //    settings UTxO location.
    const settingsSeed = (await admin.wallet.getUtxos())[0];
    const settingsParams = {
      seedUtxo: settingsSeed.input,
      proposeAuth: { kind: "key" as const, hash: admin.keyHash },
      applyAuth: { kind: "key" as const, hash: admin.keyHash },
      applyDelay: 4_000,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    };
    const settings = settingsScript(settingsParams);
    const settingsAddr = settingsScriptAddress(settings, NETWORK_ID);
    const settingsPolicy = resolveScriptHash(settings.code, "V3");

    // 3. Derive the DAO scripts from the settings policy + token name.
    const daoParams = {
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
      settingsPolicy,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    };
    const stake = stakeScript(daoParams);
    const proposal = proposalScript(daoParams);
    const vote = voteScript(daoParams);

    const daoSettings: DaoSettings = {
      thresholds: THRESHOLDS,
      timings: TIMINGS,
      stakeValidator: resolveScriptHash(stake.code, "V3"),
      proposalValidator: resolveScriptHash(proposal.code, "V3"),
      voteValidator: resolveScriptHash(vote.code, "V3"),
    };

    // 4. Launch the settings UTxO carrying the DaoSettings datum. Custom launch
    //    (rather than the library's `buildLaunchTx`) so the output carries
    //    enough ada for the large inline DaoSettings datum: the library's
    //    1.5 ADA default is below the min-UTxO once the datum is this big.
    const adminCol = (await admin.wallet.getCollateral())[0];
    const launchTx = await newTxBuilder(provider)
      .mintPlutusScriptV3()
      .mint("1", settingsPolicy, SETTINGS_TOKEN_NAME)
      .mintRedeemerValue(mintRedeemer(0))
      .mintingScript(settings.code)
      .txIn(
        settingsSeed.input.txHash,
        settingsSeed.input.outputIndex,
        settingsSeed.output.amount,
        settingsSeed.output.address,
      )
      .txOut(settingsAddr, [
        { unit: "lovelace", quantity: "2000000" },
        { unit: settingsPolicy + SETTINGS_TOKEN_NAME, quantity: "1" },
      ])
      .txOutInlineDatumValue(
        settingsDatumToData({
          current: daoSettingsToData(daoSettings),
          next: null,
          nextApply: null,
        } satisfies SettingsDatum),
      )
      .requiredSignerHash(admin.keyHash)
      .txInCollateral(
        adminCol.input.txHash,
        adminCol.input.outputIndex,
        adminCol.output.amount,
        adminCol.output.address,
      )
      .changeAddress(admin.address)
      .selectUtxosFrom(await admin.wallet.getUtxos())
      .complete();
    const launchHash = await signAndSubmit(admin, launchTx);
    await waitForTx(provider, launchHash);
    const settingsUtxo = await scriptOutputOf(
      provider,
      launchHash,
      settingsAddr,
    );

    return {
      owner,
      cosigner,
      admin,
      settingsUtxo,
      stake: {
        script: stake,
        addr: stakeScriptAddress(stake, NETWORK_ID),
      },
      proposal: {
        script: proposal,
        addr: proposalScriptAddress(proposal, NETWORK_ID),
      },
      vote: {
        script: vote,
        addr: voteScriptAddress(vote, NETWORK_ID),
      },
    };
  }

  function stakeDatum(owner: Account): StakePositionDatum {
    return {
      owner: { kind: "key", hash: owner.keyHash },
      delegatee: null,
      locks: [],
    };
  }

  /** The staked-token balance held by a stake position UTxO. */
  function stakeBalance(utxo: UTxO): bigint {
    const a = utxo.output.amount.find((x) => x.unit === stakeTokenUnit());
    return BigInt(a?.quantity ?? "0");
  }

  /** The single execution-effect script hash (one vote option). */
  function results(): string[] {
    return [stakeTokenPolicy()];
  }

  /** A proposal datum for the given lifecycle stage. */
  function proposalDatum(
    startTime: number,
    status: ProposalDatum["status"],
  ): ProposalDatum {
    return {
      thresholds: THRESHOLDS,
      timingConfig: TIMINGS,
      startTime,
      status,
      results: results(),
    };
  }

  // ------------------------------------------------------- lifecycle helpers

  async function createStakePosition(
    ctx: Awaited<ReturnType<typeof setup>>,
    owner: Account,
    stakeQuantity: bigint = THRESHOLDS.create,
  ): Promise<UTxO> {
    const utxos = await owner.wallet.getUtxos();
    const seed = utxos[0];
    const tx = await buildCreateStakePositionTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.stake.script,
      seedUtxo: seed,
      owner: { keyHash: owner.keyHash },
      datum: stakeDatum(owner),
      stakedTokens: [
        { unit: stakeTokenUnit(), quantity: stakeQuantity.toString() },
      ],
      utxos,
      changeAddress: owner.address,
      collateralUtxo: await collateralOf(owner),
    });
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    return scriptOutputOf(provider, hash, ctx.stake.addr);
  }

  interface ProposalState {
    utxo: UTxO;
    datum: ProposalDatum;
    tokenName: string;
    /** The continuing stake position after creation (holds the draft lock). */
    stakeUtxo: UTxO;
  }

  async function createProposal(
    ctx: Awaited<ReturnType<typeof setup>>,
    stakeUtxo: UTxO,
    owner: Account,
  ): Promise<ProposalState> {
    const now = await chainNowMs();
    const startTime = enclosingSlotBound(now, slotConfig).startMs;
    const tokenName = nftNameFromRef(stakeUtxo.input);
    const inStake = stakeBalance(stakeUtxo);

    const datum = proposalDatum(startTime, {
      kind: "Draft",
      cosigningStake: inStake,
    });

    const lockedStakeDatum: StakePositionDatum = {
      ...stakeDatum(owner),
      locks: [[tokenName, startTime + TIMINGS.draftLength, inStake]],
    };

    const tx = await buildCreateProposalTx({
      txBuilder: newTxBuilder(provider),
      proposalScript: ctx.proposal.script,
      stakeScript: ctx.stake.script,
      stakeUtxo,
      stakeDatum: lockedStakeDatum,
      settingsUtxo: ctx.settingsUtxo,
      proposalDatum: datum,
      now,
      utxos: await owner.wallet.getUtxos(),
      changeAddress: owner.address,
      collateralUtxo: await collateralOf(owner),
      customSlotConfig: slotConfig,
    });
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    return {
      utxo: await scriptOutputOf(provider, hash, ctx.proposal.addr),
      stakeUtxo: await scriptOutputOf(provider, hash, ctx.stake.addr),
      datum,
      tokenName,
    };
  }

  async function acceptDraft(
    ctx: Awaited<ReturnType<typeof setup>>,
    proposal: ProposalState,
    owner: Account,
  ): Promise<ProposalState> {
    const continuation = proposalDatum(proposal.datum.startTime, {
      kind: "Voting",
    });
    const tx = await buildAcceptDraftTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: proposal.utxo,
      settingsUtxo: ctx.settingsUtxo,
      datum: proposal.datum,
      now: await chainNowMs(),
      continuationDatum: continuation,
      utxos: await owner.wallet.getUtxos(),
      changeAddress: owner.address,
      collateralUtxo: await collateralOf(owner),
      customSlotConfig: slotConfig,
    });
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    return {
      ...proposal,
      utxo: await scriptOutputOf(provider, hash, ctx.proposal.addr),
      datum: continuation,
    };
  }

  async function voteOn(
    ctx: Awaited<ReturnType<typeof setup>>,
    proposal: ProposalState,
    voterStake: UTxO,
    voter: Account,
    option: number,
  ): Promise<UTxO> {
    const stake = stakeBalance(voterStake);
    const unlock =
      proposal.datum.startTime + TIMINGS.draftLength + TIMINGS.votingLength;

    const voteDatum: VoteDatum = {
      stakeOwner: { kind: "key", hash: voter.keyHash },
      proposal: proposal.tokenName,
      votedOption: option,
      stake,
    };

    const votedStakeDatum: StakePositionDatum = {
      ...stakeDatum(voter),
      locks: [[proposal.tokenName, unlock, stake]],
    };

    const tx = await buildVoteTx({
      txBuilder: newTxBuilder(provider),
      voteScript: ctx.vote.script,
      stakeScript: ctx.stake.script,
      stakeUtxo: voterStake,
      stakeDatum: votedStakeDatum,
      proposalUtxo: proposal.utxo,
      proposalDatum: proposal.datum,
      settingsUtxo: ctx.settingsUtxo,
      voteDatum,
      now: await chainNowMs(),
      utxos: await voter.wallet.getUtxos(),
      changeAddress: voter.address,
      collateralUtxo: await collateralOf(voter),
      customSlotConfig: slotConfig,
    });
    const hash = await signAndSubmit(voter, tx);
    await waitForTx(provider, hash);
    return scriptOutputOf(provider, hash, ctx.vote.addr);
  }

  // ----------------------------------------------------------- happy paths

  it("mints a stake position", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);
    expect(lovelaceOf(stakeUtxo)).toBeGreaterThan(0n);
  });

  it("deposits and delegates a stake position", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);
    const ownerUtxos = await ctx.owner.wallet.getUtxos();

    const depositTx = await buildDepositTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.stake.script,
      stakeUtxo,
      settingsUtxo: ctx.settingsUtxo,
      owner: { kind: "key", hash: ctx.owner.keyHash },
      datum: stakeDatum(ctx.owner),
      addedTokens: [{ unit: stakeTokenUnit(), quantity: "1000" }],
      now: await chainNowMs(),
      utxos: ownerUtxos,
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const depositHash = await signAndSubmit(ctx.owner, depositTx);
    await waitForTx(provider, depositHash);
    const deposited = await scriptOutputOf(
      provider,
      depositHash,
      ctx.stake.addr,
    );

    const delegateTx = await buildDelegateTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.stake.script,
      stakeUtxo: deposited,
      settingsUtxo: ctx.settingsUtxo,
      owner: { kind: "key", hash: ctx.owner.keyHash },
      datum: stakeDatum(ctx.owner),
      delegatee: { keyHash: ctx.cosigner.keyHash },
      now: await chainNowMs(),
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const delegateHash = await signAndSubmit(ctx.owner, delegateTx);
    await waitForTx(provider, delegateHash);
    const delegated = await scriptOutputOf(
      provider,
      delegateHash,
      ctx.stake.addr,
    );
    expect(lovelaceOf(delegated)).toBeGreaterThan(0n);
  });

  it("withdraws from a stake position", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);

    const withdrawTx = await buildWithdrawTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.stake.script,
      stakeUtxo,
      settingsUtxo: ctx.settingsUtxo,
      owner: { kind: "key", hash: ctx.owner.keyHash },
      datum: stakeDatum(ctx.owner),
      amount: 1_000n,
      stakeTokenUnit: stakeTokenUnit(),
      now: await chainNowMs(),
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const hash = await signAndSubmit(ctx.owner, withdrawTx);
    await waitForTx(provider, hash);
    const continued = await scriptOutputOf(provider, hash, ctx.stake.addr);
    expect(lovelaceOf(continued)).toBeGreaterThan(0n);
  });

  it("creates a proposal from a stake position", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);
    const proposal = await createProposal(ctx, stakeUtxo, ctx.owner);
    expect(lovelaceOf(proposal.utxo)).toBeGreaterThan(0n);
  });

  it("cosigns and accepts a draft proposal", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const cosignerStake = await createStakePosition(ctx, ctx.cosigner);
    const proposal = await createProposal(ctx, ownerStake, ctx.owner);

    // Cosign with the cosigner's full stake.
    const cosignerInStake = stakeBalance(cosignerStake);
    const cosignedDatum = proposalDatum(proposal.datum.startTime, {
      kind: "Draft",
      cosigningStake:
        proposal.datum.status.kind === "Draft"
          ? proposal.datum.status.cosigningStake + cosignerInStake
          : cosignerInStake,
    });
    const cosignerStakeDatum: StakePositionDatum = {
      ...stakeDatum(ctx.cosigner),
      locks: [
        [
          proposal.tokenName,
          proposal.datum.startTime + TIMINGS.draftLength,
          cosignerInStake,
        ],
      ],
    };
    const cosignTx = await buildCosignProposalTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: proposal.utxo,
      settingsUtxo: ctx.settingsUtxo,
      datum: proposal.datum,
      now: await chainNowMs(),
      proposalDatum: cosignedDatum,
      stakeScript: ctx.stake.script,
      stakeUtxo: cosignerStake,
      stakeDatum: cosignerStakeDatum,
      utxos: await ctx.cosigner.wallet.getUtxos(),
      changeAddress: ctx.cosigner.address,
      collateralUtxo: await collateralOf(ctx.cosigner),
      customSlotConfig: slotConfig,
    });
    const cosignHash = await signAndSubmit(ctx.cosigner, cosignTx);
    await waitForTx(provider, cosignHash);
    const cosigned = await scriptOutputOf(
      provider,
      cosignHash,
      ctx.proposal.addr,
    );

    const accepted = await acceptDraft(
      ctx,
      { ...proposal, utxo: cosigned, datum: cosignedDatum },
      ctx.owner,
    );
    expect(lovelaceOf(accepted.utxo)).toBeGreaterThan(0n);
  });

  it("votes, ends voting, and tallies", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const voterStake = await createStakePosition(ctx, ctx.cosigner);
    const proposal = await createProposal(ctx, ownerStake, ctx.owner);
    const voting = await acceptDraft(ctx, proposal, ctx.owner);

    const voteUtxo = await voteOn(ctx, voting, voterStake, ctx.cosigner, 0);

    // End voting after the voting phase has closed.
    const votingEnd =
      voting.datum.startTime + TIMINGS.draftLength + TIMINGS.votingLength;
    await waitUntilChainTimeMs(votingEnd + PHASE_SLACK);
    const tallyDatum = proposalDatum(voting.datum.startTime, {
      kind: "Tally",
      votes: [0n],
    });
    const endTx = await buildEndVotingStageTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: voting.utxo,
      settingsUtxo: ctx.settingsUtxo,
      datum: voting.datum,
      now: await chainNowMs(),
      continuationDatum: tallyDatum,
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const endHash = await signAndSubmit(ctx.owner, endTx);
    await waitForTx(provider, endHash);
    const tallyState = await scriptOutputOf(
      provider,
      endHash,
      ctx.proposal.addr,
    );

    const countedVotes = [stakeBalance(voterStake)];
    const tallyTx = await buildTallyTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: tallyState,
      settingsUtxo: ctx.settingsUtxo,
      datum: tallyDatum,
      now: await chainNowMs(),
      continuationDatum: proposalDatum(voting.datum.startTime, {
        kind: "Tally",
        votes: countedVotes,
      }),
      voteScript: ctx.vote.script,
      votes: [{ voteUtxo, ownerAddress: ctx.cosigner.address }],
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const tallyHash = await signAndSubmit(ctx.owner, tallyTx);
    await waitForTx(provider, tallyHash);
    const tallied = await scriptOutputOf(
      provider,
      tallyHash,
      ctx.proposal.addr,
    );
    expect(lovelaceOf(tallied)).toBeGreaterThan(0n);

    const outs = await provider.fetchUTxOs(tallyHash);
    expect(outs.some((u) => u.output.address === ctx.vote.addr)).toBe(false);
  });

  it("ends a proposal", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const proposal = await createProposal(ctx, ownerStake, ctx.owner);
    const voting = await acceptDraft(ctx, proposal, ctx.owner);

    // Drive Draft -> Voting -> Tally (no votes cast).
    const votingEnd =
      voting.datum.startTime + TIMINGS.draftLength + TIMINGS.votingLength;
    await waitUntilChainTimeMs(votingEnd + PHASE_SLACK);
    const tallyDatum = proposalDatum(voting.datum.startTime, {
      kind: "Tally",
      votes: [0n],
    });
    const endTx = await buildEndVotingStageTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: voting.utxo,
      settingsUtxo: ctx.settingsUtxo,
      datum: voting.datum,
      now: await chainNowMs(),
      continuationDatum: tallyDatum,
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const endHash = await signAndSubmit(ctx.owner, endTx);
    await waitForTx(provider, endHash);
    const tallyState = await scriptOutputOf(
      provider,
      endHash,
      ctx.proposal.addr,
    );

    // End the proposal after the tally phase has closed.
    const tallyEnd =
      voting.datum.startTime +
      TIMINGS.draftLength +
      TIMINGS.votingLength +
      TIMINGS.tallyLength;
    await waitUntilChainTimeMs(tallyEnd + PHASE_SLACK);
    const endProposalTx = await buildEndProposalTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: tallyState,
      settingsUtxo: ctx.settingsUtxo,
      datum: tallyDatum,
      now: await chainNowMs(),
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const hash = await signAndSubmit(ctx.owner, endProposalTx);
    await waitForTx(provider, hash);

    const outs = await provider.fetchUTxOs(hash);
    expect(outs.some((u) => u.output.address === ctx.proposal.addr)).toBe(
      false,
    );
  });

  it("closes a stake position", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);

    const closeTx = await buildClosePositionTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.stake.script,
      stakeUtxo,
      settingsUtxo: ctx.settingsUtxo,
      owner: { kind: "key", hash: ctx.owner.keyHash },
      now: await chainNowMs(),
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
      customSlotConfig: slotConfig,
    });
    const hash = await signAndSubmit(ctx.owner, closeTx);
    await waitForTx(provider, hash);

    const outs = await provider.fetchUTxOs(hash);
    expect(outs.some((u) => u.output.address === ctx.stake.addr)).toBe(false);
  });

  // -------------------------------------------------- rejects that work today

  it("rejects a stake spend with an unknown redeemer constructor", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);

    await expect(
      (async () => {
        const tb = newTxBuilder(provider);
        tb.spendingPlutusScriptV3()
          .txIn(
            stakeUtxo.input.txHash,
            stakeUtxo.input.outputIndex,
            stakeUtxo.output.amount,
            stakeUtxo.output.address,
          )
          .txInInlineDatumPresent()
          .txInRedeemerValue({ alternative: 9, fields: [] })
          .txInScript(ctx.stake.script.code);

        const col = await collateralOf(ctx.owner);
        const unsigned = await tb
          .txInCollateral(
            col.input.txHash,
            col.input.outputIndex,
            col.output.amount,
            col.output.address,
          )
          .changeAddress(ctx.owner.address)
          .selectUtxosFrom(await ctx.owner.wallet.getUtxos())
          .complete();

        return provider.submitTx(await ctx.owner.wallet.signTx(unsigned, true));
      })(),
    ).rejects.toThrow();
  });

  it("rejects a proposal mint with insufficient stake", async () => {
    const ctx = await setup();
    const owner = ctx.owner;
    const stakeUtxo = await createStakePosition(
      ctx,
      owner,
      THRESHOLDS.create - 1n,
    );

    await expect(createProposal(ctx, stakeUtxo, owner)).rejects.toThrow();
  });

  it("rejects a vote below the vote threshold", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const voterStake = await createStakePosition(
      ctx,
      ctx.cosigner,
      THRESHOLDS.vote - 1n,
    );
    const proposal = await createProposal(ctx, ownerStake, ctx.owner);
    const voting = await acceptDraft(ctx, proposal, ctx.owner);

    await expect(
      voteOn(ctx, voting, voterStake, ctx.cosigner, 0),
    ).rejects.toThrow();
  });

  it("rejects an accept-draft after the draft phase ends", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const proposal = await createProposal(ctx, ownerStake, ctx.owner);

    await waitUntilChainTimeMs(
      proposal.datum.startTime + TIMINGS.draftLength + PHASE_SLACK,
    );

    await expect(acceptDraft(ctx, proposal, ctx.owner)).rejects.toThrow();
  });

  it("rejects a close while locks are active", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const proposal = await createProposal(ctx, ownerStake, ctx.owner);
    const lockedStake = proposal.stakeUtxo;

    await expect(
      (async () => {
        const tx = await buildClosePositionTx({
          txBuilder: newTxBuilder(provider),
          script: ctx.stake.script,
          stakeUtxo: lockedStake,
          settingsUtxo: ctx.settingsUtxo,
          owner: { kind: "key", hash: ctx.owner.keyHash },
          now: await chainNowMs(),
          utxos: await ctx.owner.wallet.getUtxos(),
          changeAddress: ctx.owner.address,
          collateralUtxo: await collateralOf(ctx.owner),
          customSlotConfig: slotConfig,
        });
        return signAndSubmit(ctx.owner, tx);
      })(),
    ).rejects.toThrow();
  });
});
