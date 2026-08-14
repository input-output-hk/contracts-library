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
  mintRedeemer,
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
  type OutputRef,
  type ProposalDatum,
  type ProposalThresholds,
  type ProposalTimingConfig,
  type SettingsDatum,
  type StakePositionDatum,
  type VoteDatum,
} from "@contracts-library/meshjs";
import {
  mConStr0,
  deserializeAddress,
  resolveScriptHash,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
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

// hex("stake") — the stake NFT's token name. Not a validator parameter, so the
// tests are free to pick it; keep it constant so proposal's `stake_nft_name`
// parameter agrees.
const STAKE_NFT_NAME = "7374616b65";
// hex("stake") — the DAO's staked token name (minted by the test harness).
const STAKE_TOKEN_NAME = "7374616b65";
const STAKE_TOKEN_QUANTITY = 1_000_000n;
const PROPOSAL_TOKEN_NAME = "00".repeat(32);
const VOTE_TOKEN_NAME = "01".repeat(32);

const THRESHOLDS: ProposalThresholds = {
  create: 100_000n,
  cosign: 50_000n,
  accept: 150_000n,
  vote: 10_000n,
  execute: 10_000n,
};

const TIMINGS: ProposalTimingConfig = {
  draftLength: 20_000,
  votingLength: 20_000,
  tallyLength: 20_000,
};

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

  /** A fixed, deterministic placeholder output reference used only to compute
   * the sibling script hashes published in DaoSettings before the settings
   * UTxO exists. See the bootstrap note in `setup`. */
  const PLACEHOLDER_REF: OutputRef = {
    transactionId: "00".repeat(32),
    outputIndex: 0,
  };

  function addressDataOf(address: string): VoteDatum["stakeOwner"] {
    const { pubKeyHash } = deserializeAddress(address);
    return {
      paymentCredential: { kind: "key", hash: pubKeyHash },
      stakeCredential: null,
    };
  }

  async function setup(): Promise<{
    owner: Account;
    cosigner: Account;
    admin: Account;
    settingsUtxo: UTxO;
    settingsRef: OutputRef;
    stake: { script: ReturnType<typeof stakeScript>; addr: string };
    proposal: { script: ReturnType<typeof proposalScript>; addr: string };
    vote: { script: ReturnType<typeof voteScript>; addr: string };
  }> {
    const owner = await fundedAccount(provider);
    const cosigner = await fundedAccount(provider);
    const admin = await fundedAccount(provider);

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

    // 2. Derive the sibling script hashes from placeholder-parameterized
    //    scripts (they only feed the DaoSettings datum; the live scripts below
    //    are re-derived from the real settings UTxO reference). This is the
    //    DAO's bootstrap: hashes <-> settings UTxO ref are mutually dependent,
    //    so the settings datum is finalized once and the live scripts use the
    //    post-launch reference. TODO: resolve cleanly with the real logic.
    const placeholderStake = stakeScript({
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
      settingsUtxo: PLACEHOLDER_REF,
    });
    const placeholderProposal = proposalScript({
      settingsUtxo: PLACEHOLDER_REF,
      stakeNftPolicy: resolveScriptHash(placeholderStake.code, "V3"),
      stakeNftName: STAKE_NFT_NAME,
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
    });
    const placeholderVote = voteScript({
      stakeNftPolicy: resolveScriptHash(placeholderStake.code, "V3"),
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
      proposalPolicy: resolveScriptHash(placeholderProposal.code, "V3"),
    });

    const daoSettings: DaoSettings = {
      thresholds: THRESHOLDS,
      timings: TIMINGS,
      stakeValidator: resolveScriptHash(placeholderStake.code, "V3"),
      proposalValidator: resolveScriptHash(placeholderProposal.code, "V3"),
      voteValidator: resolveScriptHash(placeholderVote.code, "V3"),
    };

    // 3. Launch the settings UTxO carrying the DaoSettings datum.
    const settingsSeed = (await admin.wallet.getUtxos())[0];
    const settingsParams = {
      seedUtxo: {
        transactionId: settingsSeed.input.txHash,
        outputIndex: settingsSeed.input.outputIndex,
      },
      proposeAuth: { kind: "key" as const, hash: admin.keyHash },
      applyAuth: { kind: "key" as const, hash: admin.keyHash },
      applyDelay: 4_000,
      settingsTokenName: SETTINGS_TOKEN_NAME,
    };
    const settings = settingsScript(settingsParams);
    const settingsAddr = settingsScriptAddress(settings, NETWORK_ID);
    const settingsPolicy = resolveScriptHash(settings.code, "V3");
    const adminCol = (await admin.wallet.getCollateral())[0];
    // Custom launch (rather than the library's `buildLaunchTx`) so the output
    // carries enough ada for the large inline DaoSettings datum: the library's
    // 1.5 ADA default is below the min-UTxO once the datum is this big.
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
    const settingsRef = {
      transactionId: settingsUtxo.input.txHash,
      outputIndex: settingsUtxo.input.outputIndex,
    };

    // 4. Live scripts parameterized with the real settings UTxO reference.
    const liveStake = stakeScript({
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
      settingsUtxo: settingsRef,
    });
    const liveProposal = proposalScript({
      settingsUtxo: settingsRef,
      stakeNftPolicy: resolveScriptHash(liveStake.code, "V3"),
      stakeNftName: STAKE_NFT_NAME,
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
    });
    const liveVote = voteScript({
      stakeNftPolicy: resolveScriptHash(liveStake.code, "V3"),
      stakeTokenPolicy: policy,
      stakeTokenName: STAKE_TOKEN_NAME,
      proposalPolicy: resolveScriptHash(liveProposal.code, "V3"),
    });

    return {
      owner,
      cosigner,
      admin,
      settingsUtxo,
      settingsRef,
      stake: {
        script: liveStake,
        addr: stakeScriptAddress(liveStake, NETWORK_ID),
      },
      proposal: {
        script: liveProposal,
        addr: proposalScriptAddress(liveProposal, NETWORK_ID),
      },
      vote: {
        script: liveVote,
        addr: voteScriptAddress(liveVote, NETWORK_ID),
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

  function initialProposalDatum(
    ctx: Awaited<ReturnType<typeof setup>>,
  ): ProposalDatum {
    return {
      thresholds: THRESHOLDS,
      timingConfig: TIMINGS,
      startTime: 0,
      status: { kind: "Draft", cosigningStake: THRESHOLDS.create },
      results: new Map(),
    };
  }

  // ------------------------------------------------------- lifecycle helpers

  async function createStakePosition(
    ctx: Awaited<ReturnType<typeof setup>>,
    owner: Account,
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
        { unit: stakeTokenUnit(), quantity: THRESHOLDS.create.toString() },
      ],
      stakeNftName: STAKE_NFT_NAME,
      utxos,
      changeAddress: owner.address,
      collateralUtxo: await collateralOf(owner),
    });
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    return scriptOutputOf(provider, hash, ctx.stake.addr);
  }

  async function createProposal(
    ctx: Awaited<ReturnType<typeof setup>>,
    stakeUtxo: UTxO,
    owner: Account,
    datum: ProposalDatum,
  ): Promise<UTxO> {
    const tx = await buildCreateProposalTx({
      txBuilder: newTxBuilder(provider),
      proposalScript: ctx.proposal.script,
      stakeScript: ctx.stake.script,
      stakeUtxo,
      stakeDatum: stakeDatum(owner),
      settingsUtxo: ctx.settingsUtxo,
      proposalDatum: datum,
      proposalTokenName: PROPOSAL_TOKEN_NAME,
      utxos: await owner.wallet.getUtxos(),
      changeAddress: owner.address,
      collateralUtxo: await collateralOf(owner),
    });
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    return scriptOutputOf(provider, hash, ctx.proposal.addr);
  }

  async function voteOn(
    ctx: Awaited<ReturnType<typeof setup>>,
    stakeUtxo: UTxO,
    proposalUtxo: UTxO,
    voter: Account,
    stake: bigint,
    option: number,
  ): Promise<UTxO> {
    const voteDatum: VoteDatum = {
      stakeOwner: addressDataOf(voter.address),
      proposal: PROPOSAL_TOKEN_NAME,
      votedOption: option,
      stake,
    };
    const tx = await buildVoteTx({
      txBuilder: newTxBuilder(provider),
      voteScript: ctx.vote.script,
      stakeScript: ctx.stake.script,
      stakeUtxo,
      stakeDatum: stakeDatum(voter),
      proposalUtxo,
      voteDatum,
      voteTokenName: VOTE_TOKEN_NAME,
      utxos: await voter.wallet.getUtxos(),
      changeAddress: voter.address,
      collateralUtxo: await collateralOf(voter),
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
      datum: stakeDatum(ctx.owner),
      addedTokens: [{ unit: stakeTokenUnit(), quantity: "1000" }],
      utxos: ownerUtxos,
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
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
      datum: stakeDatum(ctx.owner),
      delegatee: { keyHash: ctx.cosigner.keyHash },
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
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
      datum: stakeDatum(ctx.owner),
      amount: 1_000n,
      stakeTokenUnit: stakeTokenUnit(),
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
    });
    const hash = await signAndSubmit(ctx.owner, withdrawTx);
    await waitForTx(provider, hash);
    const continued = await scriptOutputOf(provider, hash, ctx.stake.addr);
    expect(lovelaceOf(continued)).toBeGreaterThan(0n);
  });

  it("creates a proposal from a stake position", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);
    const proposalUtxo = await createProposal(
      ctx,
      stakeUtxo,
      ctx.owner,
      initialProposalDatum(ctx),
    );
    expect(lovelaceOf(proposalUtxo)).toBeGreaterThan(0n);
  });

  it("cosigns and accepts a draft proposal", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const cosignerStake = await createStakePosition(ctx, ctx.cosigner);
    const proposalUtxo = await createProposal(
      ctx,
      ownerStake,
      ctx.owner,
      initialProposalDatum(ctx),
    );

    const cosignTx = await buildCosignProposalTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo,
      proposalDatum: {
        ...initialProposalDatum(ctx),
        status: {
          kind: "Draft",
          cosigningStake: THRESHOLDS.create + THRESHOLDS.cosign,
        },
      },
      stakeScript: ctx.stake.script,
      stakeUtxo: cosignerStake,
      stakeDatum: stakeDatum(ctx.cosigner),
      utxos: await ctx.cosigner.wallet.getUtxos(),
      changeAddress: ctx.cosigner.address,
      collateralUtxo: await collateralOf(ctx.cosigner),
    });
    const cosignHash = await signAndSubmit(ctx.cosigner, cosignTx);
    await waitForTx(provider, cosignHash);
    const cosigned = await scriptOutputOf(
      provider,
      cosignHash,
      ctx.proposal.addr,
    );

    const acceptTx = await buildAcceptDraftTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: cosigned,

      continuationDatum: {
        ...initialProposalDatum(ctx),
        status: { kind: "Voting" },
      },
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
    });
    const acceptHash = await signAndSubmit(ctx.owner, acceptTx);
    await waitForTx(provider, acceptHash);
    const accepted = await scriptOutputOf(
      provider,
      acceptHash,
      ctx.proposal.addr,
    );
    expect(lovelaceOf(accepted)).toBeGreaterThan(0n);
  });

  it("votes, ends voting, and tallies", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const voterStake = await createStakePosition(ctx, ctx.cosigner);
    const proposalUtxo = await createProposal(
      ctx,
      ownerStake,
      ctx.owner,
      initialProposalDatum(ctx),
    );
    const voteUtxo = await voteOn(
      ctx,
      voterStake,
      proposalUtxo,
      ctx.cosigner,
      THRESHOLDS.vote,
      0,
    );

    const endTx = await buildEndVotingStageTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo,

      continuationDatum: {
        ...initialProposalDatum(ctx),
        status: { kind: "Tally", votes: new Map() },
      },
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
    });
    const endHash = await signAndSubmit(ctx.owner, endTx);
    await waitForTx(provider, endHash);
    const tallyState = await scriptOutputOf(
      provider,
      endHash,
      ctx.proposal.addr,
    );

    const tallyTx = await buildTallyTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo: tallyState,

      continuationDatum: {
        ...initialProposalDatum(ctx),
        status: { kind: "Tally", votes: new Map([[0, THRESHOLDS.vote]]) },
      },
      voteScript: ctx.vote.script,
      votes: [{ voteUtxo, ownerAddress: ctx.cosigner.address }],
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
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
    const proposalUtxo = await createProposal(
      ctx,
      ownerStake,
      ctx.owner,
      initialProposalDatum(ctx),
    );

    const endTx = await buildEndProposalTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.proposal.script,
      proposalUtxo,

      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
    });
    const hash = await signAndSubmit(ctx.owner, endTx);
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

      stakeNftName: STAKE_NFT_NAME,
      utxos: await ctx.owner.wallet.getUtxos(),
      changeAddress: ctx.owner.address,
      collateralUtxo: await collateralOf(ctx.owner),
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
    // stake a position below thresholds.create, then mint a proposal NFT from it
    const owner = ctx.owner;
    const utxos = await owner.wallet.getUtxos();
    const tx = await buildCreateStakePositionTx({
      txBuilder: newTxBuilder(provider),
      script: ctx.stake.script,
      seedUtxo: utxos[0],
      owner: { keyHash: owner.keyHash },
      datum: stakeDatum(owner),
      stakedTokens: [
        {
          unit: stakeTokenUnit(),
          quantity: (THRESHOLDS.create - 1n).toString(),
        },
      ],
      stakeNftName: STAKE_NFT_NAME,
      utxos,
      changeAddress: owner.address,
      collateralUtxo: await collateralOf(owner),
    });
    const hash = await signAndSubmit(owner, tx);
    await waitForTx(provider, hash);
    const stakeUtxo = await scriptOutputOf(provider, hash, ctx.stake.addr);

    await expect(
      (async () => {
        const ptx = await buildCreateProposalTx({
          txBuilder: newTxBuilder(provider),
          proposalScript: ctx.proposal.script,
          stakeScript: ctx.stake.script,
          stakeUtxo,
          stakeDatum: stakeDatum(owner),
          settingsUtxo: ctx.settingsUtxo,
          proposalDatum: initialProposalDatum(ctx),
          proposalTokenName: PROPOSAL_TOKEN_NAME,
          utxos: await owner.wallet.getUtxos(),
          changeAddress: owner.address,
          collateralUtxo: await collateralOf(owner),
        });
        return signAndSubmit(owner, ptx);
      })(),
    ).rejects.toThrow();
  });

  it("rejects a vote below the vote threshold", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const voterStake = await createStakePosition(ctx, ctx.cosigner);
    const proposalUtxo = await createProposal(
      ctx,
      ownerStake,
      ctx.owner,
      initialProposalDatum(ctx),
    );

    await expect(
      voteOn(
        ctx,
        voterStake,
        proposalUtxo,
        ctx.cosigner,
        THRESHOLDS.vote - 1n,
        0,
      ),
    ).rejects.toThrow();
  });

  it("rejects an accept-draft before the draft phase ends", async () => {
    const ctx = await setup();
    const ownerStake = await createStakePosition(ctx, ctx.owner);
    const proposalUtxo = await createProposal(
      ctx,
      ownerStake,
      ctx.owner,
      initialProposalDatum(ctx),
    );

    await expect(
      (async () => {
        const tx = await buildAcceptDraftTx({
          txBuilder: newTxBuilder(provider),
          script: ctx.proposal.script,
          proposalUtxo,

          continuationDatum: {
            ...initialProposalDatum(ctx),
            status: { kind: "Voting" },
          },
          utxos: await ctx.owner.wallet.getUtxos(),
          changeAddress: ctx.owner.address,
          collateralUtxo: await collateralOf(ctx.owner),
        });
        return signAndSubmit(ctx.owner, tx);
      })(),
    ).rejects.toThrow();
  });

  it("rejects a close while locks are active", async () => {
    const ctx = await setup();
    const stakeUtxo = await createStakePosition(ctx, ctx.owner);
    await expect(
      (async () => {
        const tx = await buildClosePositionTx({
          txBuilder: newTxBuilder(provider),
          script: ctx.stake.script,
          stakeUtxo,

          stakeNftName: STAKE_NFT_NAME,
          utxos: await ctx.owner.wallet.getUtxos(),
          changeAddress: ctx.owner.address,
          collateralUtxo: await collateralOf(ctx.owner),
        });
        return signAndSubmit(ctx.owner, tx);
      })(),
    ).rejects.toThrow();
  });
});
