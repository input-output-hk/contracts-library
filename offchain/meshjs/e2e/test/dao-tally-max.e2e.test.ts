/**
 * Stress e2e (worst case): find the maximum number of votes a single
 * `TallyVotes` transaction can consume on the Yaci devnet when every vote
 * belongs to a *distinct* owner — one vote per wallet.
 *
 * This is the true worst case for the tally: the on-chain refund check
 * (`list.any` over tx outputs, onchain/lib/dao/proposal/spend.ak) short-circuits
 * at the first output addressed to the vote's stake_owner. With N distinct
 * owners each vote only matches its own refund output, so the scan walks
 * j+1 outputs for the j-th vote: N(N+1)/2 output checks in total. With
 * repeated owners the scan collapses to a near-constant; this mode cannot be
 * improved by merging refund outputs, so it measures the honest floor of the
 * current design. It is also order-independent: the parallel creation
 * interleaving does not affect the verdict.
 *
 * Strategy: pre-create an upper bound of votes (env TALLY_MAX_VOTES, default
 * 50), then binary-search the largest k whose tally tx survives `complete()`
 * plus the *total* per-tx ExUnits budget (which Mesh does not check; the node
 * does — see ExUnitsTooBigUTxO). Failed probes are read-only and don't consume
 * chain state. The winning k is submitted on-chain to prove the verdict.
 *
 * Harness notes:
 *   - Votes can only be created *inside* the voting window (the vote builder
 *     bounds the tx by the voting deadline), so votingLength is stretched.
 *   - Funding 50 wallets through the Yaci faucet would take minutes of
 *     sequential topups; instead a distributor wallet mint-then-fan-outs in a
 *     single transaction (2 outputs per voter: a 5-ADA pure-ada collateral
 *     and a 10-ADA + tokens spendable).
 *   - Voter transactions run in bounded waves to avoid hammering the store.
 *
 * This file runs against its own fresh devnet (see scripts/devnet-test.sh).
 */

import {
  buildAcceptDraftTx,
  buildCreateProposalTx,
  buildCreateStakePositionTx,
  buildEndVotingStageTx,
  buildTallyTx,
  buildVoteTx,
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
  deserializeAddress,
  mConStr0,
  MeshWallet,
  resolveScriptHash,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
  chainNowMs,
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

/** Upper bound of votes (= distinct owners) to pre-create. 0 disables. */
const TALLY_MAX_VOTES = Number(process.env.TALLY_MAX_VOTES ?? "50");

/** Concurrent voter wallets per wave. */
const WAVE_SIZE = 8;

// hex("stake") — the DAO's staked token name (minted by the test harness).
const STAKE_TOKEN_NAME = "7374616b65";

/** Stake locked per vote (must clear the `vote` threshold). */
const STAKE_PER_VOTE = 100_000n;

const COLLATERAL_ADA = 5_000_000n;
const SPENDABLE_ADA = 10_000_000n;

const THRESHOLDS: ProposalThresholds = {
  create: 100_000n,
  cosign: 50_000n,
  accept: 100_000n,
  vote: 10_000n,
  execute: 200_000n,
};

/**
 * The voting window must be long enough to host all vote-creation traffic
 * (votes are only mintable while Voting, and their txs are bounded by the
 * voting deadline). The tally window must outlast the probe (~1 min) yet stay
 * well inside the ledger's evaluation horizon: the evaluator can only compute
 * slot arithmetic ~300 slots past the current epoch boundary (epoch = 600
 * slots), so an hour-long window makes `invalidHereafter` uncomputable.
 */
const TIMINGS: ProposalTimingConfig = {
  draftLength: 5_000,
  votingLength: 120_000,
  tallyLength: 180_000,
};

describe.skipIf(!reachable || TALLY_MAX_VOTES <= 0)(
  "dao tally max votes e2e, worst case: one vote per distinct owner (Yaci devnet)",
  () => {
    let provider: ReturnType<typeof makeProvider>;
    let slotConfig: SlotConfig;

    beforeAll(async () => {
      provider = makeProvider();
      slotConfig = await devnetSlotConfig();
    });

    const stakeTokenPolicy = () => resolveScriptHash(ALWAYS_TRUE.cbor, "V3");
    const stakeTokenUnit = () => stakeTokenPolicy() + STAKE_TOKEN_NAME;

    /** Poll faster than devnet.waitForTx: this file submits ~100 txs. */
    async function waitForTx(txHash: string): Promise<void> {
      const deadline = Date.now() + 60_000;
      while (Date.now() < deadline) {
        try {
          const outs = await provider.fetchUTxOs(txHash);
          if (outs.length > 0) return;
        } catch {
          // not indexed yet
        }
        await new Promise((r) => setTimeout(r, 400));
      }
      throw new Error(`tx ${txHash} not on-chain within 60s`);
    }

    /** A funded wallet plus its dedicated pure-ada collateral utxo. */
    interface Actor {
      account: Account;
      collateral: UTxO;
    }

    /**
     * Carve a dedicated pure-ada collateral utxo (10 ADA) for wallets that
     * submit several script transactions: MeshWallet.getCollateral()'s
     * "smallest pure-ada utxo >= 5 ADA" heuristic runs dry once change
     * outputs fragment or carry tokens. The collateral is kept out of every
     * utxo selection afterwards.
     */
    async function makeActor(adaTopups: number[]): Promise<Actor> {
      const account = await fundedAccount(provider, adaTopups);
      const source = (await account.wallet.getUtxos()).find(
        (u) => u.output.amount.length === 1 && lovelaceOf(u) >= 15_000_000n,
      );
      if (!source) throw new Error("no pure-ada utxo left to split");
      const splitTx = await newTxBuilder(provider)
        .txIn(
          source.input.txHash,
          source.input.outputIndex,
          source.output.amount,
          source.output.address,
        )
        .txOut(account.address, [{ unit: "lovelace", quantity: "10000000" }])
        .changeAddress(account.address)
        .selectUtxosFrom(await account.wallet.getUtxos())
        .complete();
      await waitForTx(await signAndSubmit(account, splitTx));
      const collateral = (await account.wallet.getUtxos()).find(
        (u) => u.output.amount.length === 1 && lovelaceOf(u) === 10_000_000n,
      );
      if (!collateral) throw new Error("dedicated collateral utxo not found");
      return { account, collateral };
    }

    /** All wallet utxos except the actor's reserved collateral one. */
    function selectable(actor: Actor): Promise<UTxO[]> {
      return actor.account.wallet.getUtxos().then((utxos) =>
        utxos.filter(
          (u) =>
            !(
              u.input.txHash === actor.collateral.input.txHash &&
              u.input.outputIndex === actor.collateral.input.outputIndex
            ),
        ),
      );
    }

    /** An unfunded one-vote wallet, ready to receive the fan-out. */
    async function bareWallet(): Promise<Account> {
      const wallet = new MeshWallet({
        networkId: 0,
        fetcher: provider,
        submitter: provider,
        key: { type: "mnemonic", words: MeshWallet.brew() as string[] },
      });
      await wallet.init();
      const address = await wallet.getChangeAddress();
      const { pubKeyHash } = deserializeAddress(address);
      return { wallet, address, keyHash: pubKeyHash };
    }

    /** The voter actor whose utxos landed in the fan-out transaction. */
    async function actorOf(account: Account): Promise<Actor> {
      const utxos = await provider.fetchAddressUTxOs(account.address);
      const collateral = utxos.find(
        (u) => u.output.amount.length === 1 && lovelaceOf(u) === COLLATERAL_ADA,
      );
      if (!collateral) {
        throw new Error(`collateral utxo missing for ${account.address}`);
      }
      return { account, collateral };
    }

    async function setup(): Promise<{
      owner: Actor;
      voters: Actor[];
      settingsUtxo: UTxO;
      stake: { script: ReturnType<typeof stakeScript>; addr: string };
      proposal: { script: ReturnType<typeof proposalScript>; addr: string };
      vote: { script: ReturnType<typeof voteScript>; addr: string };
    }> {
      const owner = await makeActor([5_000, 5_000]);
      const distributor = await makeActor([5_000, 5_000]);

      // 1. The proposal creator needs one position's worth of tokens.
      const policy = stakeTokenPolicy();
      const ownerMint = await newTxBuilder(provider)
        .mintPlutusScriptV3()
        .mint((STAKE_PER_VOTE * 2n).toString(), policy, STAKE_TOKEN_NAME)
        .mintRedeemerValue(mConStr0([]))
        .mintingScript(ALWAYS_TRUE.cbor)
        .txInCollateral(
          owner.collateral.input.txHash,
          owner.collateral.input.outputIndex,
          owner.collateral.output.amount,
          owner.collateral.output.address,
        )
        .changeAddress(owner.account.address)
        .selectUtxosFrom(await selectable(owner))
        .complete();
      await waitForTx(await signAndSubmit(owner.account, ownerMint));

      // 2. One vote per distinct owner: brew N voter wallets.
      const voters: Account[] = [];
      for (let i = 0; i < TALLY_MAX_VOTES; i++) {
        voters.push(await bareWallet());
      }

      // 3. Mint all stake tokens to the distributor...
      const distributorMint = await newTxBuilder(provider)
        .mintPlutusScriptV3()
        .mint(
          (STAKE_PER_VOTE * BigInt(TALLY_MAX_VOTES + 2)).toString(),
          policy,
          STAKE_TOKEN_NAME,
        )
        .mintRedeemerValue(mConStr0([]))
        .mintingScript(ALWAYS_TRUE.cbor)
        .txInCollateral(
          distributor.collateral.input.txHash,
          distributor.collateral.input.outputIndex,
          distributor.collateral.output.amount,
          distributor.collateral.output.address,
        )
        .changeAddress(distributor.account.address)
        .selectUtxosFrom(await selectable(distributor))
        .complete();
      await waitForTx(await signAndSubmit(distributor.account, distributorMint));

      // 4. ...and fan-out ada + tokens in a single transaction: 2 outputs per
      //    voter (5-ADA pure-ada collateral + 10-ADA-with-tokens spendable).
      const fanOut = newTxBuilder(provider);
      for (const v of voters) {
        fanOut
          .txOut(v.address, [{ unit: "lovelace", quantity: COLLATERAL_ADA.toString() }])
          .txOut(v.address, [
            { unit: "lovelace", quantity: SPENDABLE_ADA.toString() },
            { unit: stakeTokenUnit(), quantity: STAKE_PER_VOTE.toString() },
          ]);
      }
      const fanOutTx = await fanOut
        .changeAddress(distributor.account.address)
        .selectUtxosFrom(await selectable(distributor))
        .complete();
      await waitForTx(await signAndSubmit(distributor.account, fanOutTx));

      // 5. Turn the bare wallets into actors (locate their collateral utxo).
      const voterActors: Actor[] = [];
      for (const v of voters) {
        voterActors.push(await actorOf(v));
      }

      const settingsSeed = (await distributor.account.wallet.getUtxos())[0];
      const settingsParams = {
        seedUtxo: settingsSeed.input,
        proposeAuth: { kind: "key" as const, hash: distributor.account.keyHash },
        applyAuth: { kind: "key" as const, hash: distributor.account.keyHash },
        applyDelay: 4_000,
        settingsTokenName: SETTINGS_TOKEN_NAME,
      };
      const settings = settingsScript(settingsParams);
      const settingsAddr = settingsScriptAddress(settings, NETWORK_ID);
      const settingsPolicy = resolveScriptHash(settings.code, "V3");

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
        .requiredSignerHash(distributor.account.keyHash)
        .txInCollateral(
          distributor.collateral.input.txHash,
          distributor.collateral.input.outputIndex,
          distributor.collateral.output.amount,
          distributor.collateral.output.address,
        )
        .changeAddress(distributor.account.address)
        .selectUtxosFrom(await selectable(distributor))
        .complete();
      const launchHash = await signAndSubmit(distributor.account, launchTx);
      await waitForTx(launchHash);
      const settingsUtxo = await scriptOutputOf(
        provider,
        launchHash,
        settingsAddr,
      );

      return {
        owner,
        voters: voterActors,
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

    function stakeDatum(actor: Actor): StakePositionDatum {
      return {
        owner: { kind: "key", hash: actor.account.keyHash },
        delegatee: null,
        locks: [],
      };
    }

    function stakeBalance(utxo: UTxO): bigint {
      const a = utxo.output.amount.find((x) => x.unit === stakeTokenUnit());
      return BigInt(a?.quantity ?? "0");
    }

    function proposalDatum(
      startTime: number,
      status: ProposalDatum["status"],
    ): ProposalDatum {
      return {
        thresholds: THRESHOLDS,
        timingConfig: TIMINGS,
        startTime,
        status,
        // one execution-effect option; its identity is irrelevant here
        results: [stakeTokenPolicy()],
      };
    }

    /** Retry a whole build+submit step: the store occasionally 500s its
     * evaluation endpoint under wave bursts. Rebuilds the tx from scratch. */
    async function withRetry<T>(label: string, fn: () => Promise<T>): Promise<T> {
      let lastError: unknown;
      for (let attempt = 1; attempt <= 3; attempt++) {
        try {
          return await fn();
        } catch (err) {
          lastError = err;
          const msg = (err as Error).message ?? "";
          const transient =
            msg.includes("Internal Server Error") ||
            msg.includes("Evaluate redeemers failed") ||
            msg.includes("502") ||
            msg.includes("503");
          if (!transient || attempt === 3) throw err;
          console.warn(`[tally-max] retrying ${label} (${attempt}): ${msg.slice(0, 120)}`);
          await new Promise((r) => setTimeout(r, 1_500 * attempt));
        }
      }
      throw lastError;
    }

    async function createStakePosition(
      ctx: Awaited<ReturnType<typeof setup>>,
      actor: Actor,
      quantity: bigint = THRESHOLDS.create,
    ): Promise<UTxO> {
      return withRetry("createStakePosition", async () => {
        const utxos = await selectable(actor);
        const seed = utxos[0];
        const tx = await buildCreateStakePositionTx({
          txBuilder: newTxBuilder(provider),
          script: ctx.stake.script,
          seedUtxo: seed,
          owner: { keyHash: actor.account.keyHash },
          datum: stakeDatum(actor),
          stakedTokens: [
            { unit: stakeTokenUnit(), quantity: quantity.toString() },
          ],
          utxos,
          changeAddress: actor.account.address,
          collateralUtxo: actor.collateral,
        });
        const hash = await signAndSubmit(actor.account, tx);
        await waitForTx(hash);
        return scriptOutputOf(provider, hash, ctx.stake.addr);
      });
    }

    async function createProposal(
      ctx: Awaited<ReturnType<typeof setup>>,
      stakeUtxo: UTxO,
      owner: Actor,
    ): Promise<{ utxo: UTxO; datum: ProposalDatum; tokenName: string }> {
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
        utxos: await selectable(owner),
        changeAddress: owner.account.address,
        collateralUtxo: owner.collateral,
        customSlotConfig: slotConfig,
      });
      const hash = await signAndSubmit(owner.account, tx);
      await waitForTx(hash);
      return {
        utxo: await scriptOutputOf(provider, hash, ctx.proposal.addr),
        datum,
        tokenName,
      };
    }

    async function acceptDraft(
      ctx: Awaited<ReturnType<typeof setup>>,
      proposal: Awaited<ReturnType<typeof createProposal>>,
      owner: Actor,
    ): Promise<{ utxo: UTxO; datum: ProposalDatum; tokenName: string }> {
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
        utxos: await selectable(owner),
        changeAddress: owner.account.address,
        collateralUtxo: owner.collateral,
        customSlotConfig: slotConfig,
      });
      const hash = await signAndSubmit(owner.account, tx);
      await waitForTx(hash);
      return {
        utxo: await scriptOutputOf(provider, hash, ctx.proposal.addr),
        datum: continuation,
        tokenName: proposal.tokenName,
      };
    }

    async function voteOn(
      ctx: Awaited<ReturnType<typeof setup>>,
      proposal: { utxo: UTxO; datum: ProposalDatum; tokenName: string },
      voterStake: UTxO,
      voter: Actor,
    ): Promise<UTxO> {
      const stake = stakeBalance(voterStake);
      const unlock =
        proposal.datum.startTime + TIMINGS.draftLength + TIMINGS.votingLength;

      const voteDatum: VoteDatum = {
        stakeOwner: { kind: "key", hash: voter.account.keyHash },
        proposal: proposal.tokenName,
        votedOption: 0,
        stake,
      };
      const votedStakeDatum: StakePositionDatum = {
        ...stakeDatum(voter),
        locks: [[proposal.tokenName, unlock, stake]],
      };

      return withRetry("voteOn", async () => {
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
          utxos: await selectable(voter),
          changeAddress: voter.account.address,
          collateralUtxo: voter.collateral,
          customSlotConfig: slotConfig,
        });
        const hash = await signAndSubmit(voter.account, tx);
        await waitForTx(hash);
        return scriptOutputOf(provider, hash, ctx.vote.addr);
      });
    }

    it(
      "finds the max number of votes tally-able in one tx (worst case)",
      async () => {
        const ctx = await setup();
        const owner = ctx.owner;

        // 1. Proposal lifecycle up to Tally.
        const stakeUtxo = await createStakePosition(ctx, owner);
        const proposal = await createProposal(ctx, stakeUtxo, owner);
        const voting = await acceptDraft(ctx, proposal, owner);
        const votingEnd =
          voting.datum.startTime + TIMINGS.draftLength + TIMINGS.votingLength;

        // 2. One vote per distinct owner, in bounded waves so the store is
        //    not hammered by N concurrent submissions.
        const votes: Array<{ utxo: UTxO; refundTo: string }> = [];
        const t0 = Date.now();
        for (let i = 0; i < ctx.voters.length; i += WAVE_SIZE) {
          const wave = ctx.voters.slice(i, i + WAVE_SIZE);
          await Promise.all(
            wave.map(async (voter) => {
              const position = await createStakePosition(
                ctx,
                voter,
                STAKE_PER_VOTE,
              );
              const vote = await voteOn(ctx, voting, position, voter);
              votes.push({ utxo: vote, refundTo: voter.account.address });
            }),
          );
          console.log(
            `[tally-max] ${votes.length}/${TALLY_MAX_VOTES} votes created ` +
              `(${Math.round((Date.now() - t0) / 1000)}s)`,
          );
        }
        expect(votes.length).toBe(TALLY_MAX_VOTES);

        // 3. The voting window must close before EndVotingStage is legal.
        await waitUntilChainTimeMs(votingEnd, TIMINGS.votingLength + 60_000);

        // 4. Voting -> Tally.
        const endTx = await buildEndVotingStageTx({
          txBuilder: newTxBuilder(provider),
          script: ctx.proposal.script,
          proposalUtxo: voting.utxo,
          settingsUtxo: ctx.settingsUtxo,
          datum: voting.datum,
          now: await chainNowMs(),
          continuationDatum: proposalDatum(voting.datum.startTime, {
            kind: "Tally",
            votes: [0n],
          }),
          utxos: await selectable(owner),
          changeAddress: owner.account.address,
          collateralUtxo: owner.collateral,
          customSlotConfig: slotConfig,
        });
        const endHash = await signAndSubmit(owner.account, endTx);
        await waitForTx(endHash);
        const tallyState = await scriptOutputOf(
          provider,
          endHash,
          ctx.proposal.addr,
        );
        const tallyDatum: ProposalDatum = {
          ...voting.datum,
          status: { kind: "Tally", votes: [0n] },
        };

        // 5. Binary-search the largest k whose tally tx is acceptable to the
        //    node. Two node limits are invisible to Mesh's complete():
        //    coin selection (tx size) fails inside the build, and the
        //    *total* per-tx ExUnits budget is only checked by the ledger,
        //    so the probe sums the evaluator's per-redeemer budgets itself.
        const MAX_TX_EX_UNITS = { mem: 14_000_000, steps: 10_000_000_000 };
        const attempt = async (k: number): Promise<string> => {
          const tx = await buildTallyTx({
            txBuilder: newTxBuilder(provider),
            script: ctx.proposal.script,
            proposalUtxo: tallyState,
            settingsUtxo: ctx.settingsUtxo,
            datum: tallyDatum,
            now: await chainNowMs(),
            continuationDatum: {
              ...tallyDatum,
              status: { kind: "Tally", votes: [STAKE_PER_VOTE * BigInt(k)] },
            },
            voteScript: ctx.vote.script,
            votes: votes
              .slice(0, k)
              .map((v) => ({ voteUtxo: v.utxo, ownerAddress: v.refundTo })),
            utxos: await selectable(owner),
            changeAddress: owner.account.address,
            collateralUtxo: owner.collateral,
            customSlotConfig: slotConfig,
          });
          const budgets = (await provider.evaluateTx(tx)) as Array<{
            budget: { mem: number; steps: number };
          }>;
          const totalMem = budgets.reduce((a, b) => a + b.budget.mem, 0);
          const totalSteps = budgets.reduce((a, b) => a + b.budget.steps, 0);
          if (
            totalMem > MAX_TX_EX_UNITS.mem ||
            totalSteps > MAX_TX_EX_UNITS.steps
          ) {
            throw new Error(
              `total tx ExUnits (mem ${totalMem}, cpu ${totalSteps}) exceed ` +
                `maxTxExUnits (mem ${MAX_TX_EX_UNITS.mem}, cpu ${MAX_TX_EX_UNITS.steps})`,
            );
          }
          return tx;
        };

        let maxOk = 0;
        let failureReason = "";
        let bestTx: string | null = null;
        let lo = 1;
        let hi = votes.length;
        while (lo <= hi) {
          const k = Math.floor((lo + hi) / 2);
          try {
            const tx = await attempt(k);
            maxOk = k;
            bestTx = tx;
            console.log(`[tally-max] probe k=${k}: OK`);
            lo = k + 1;
          } catch (err) {
            failureReason = (err as Error).message;
            console.log(
              `[tally-max] probe k=${k}: FAIL — ${failureReason.split("\n")[0]}`,
            );
            hi = k - 1;
          }
        }

        expect(maxOk, failureReason).toBeGreaterThanOrEqual(2);
        expect(bestTx).not.toBeNull();
        console.log(
          `[tally-max] max votes per tally tx (one vote per distinct owner): ${maxOk}` +
            (failureReason ? ` (last blocking reason: ${failureReason})` : ""),
        );

        // 6. Prove the maximum end-to-end on-chain: the k tallied votes are
        //    consumed, the rest remain untouched at the vote address.
        const tallyHash = await signAndSubmit(owner.account, bestTx!);
        await waitForTx(tallyHash);
        const remaining = await provider.fetchAddressUTxOs(ctx.vote.addr);
        expect(remaining.length).toBe(votes.length - maxOk);
        const continued = await scriptOutputOf(
          provider,
          tallyHash,
          ctx.proposal.addr,
        );
        expect(lovelaceOf(continued)).toBeGreaterThan(0n);
      },
      1_500_000,
    );
  },
);
