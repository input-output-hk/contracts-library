/**
 * End-to-end tests against a local Yaci DevKit devnet.
 *
 * Since the on-chain validators are stubs (spend paths return True), tests
 * verify that transactions build, submit, and produce the expected outputs.
 * Mint-related paths (minting beacon / YES-NO tokens) are skipped until the
 * validators are implemented.
 */

import {
  ADA,
  buildResolveTx,
  buildRedeemWinnerTx,
  buildBurnCompleteSetTx,
  buildClaimTimeoutTx,
  buildClaimDrawTx,
  buildSweepResidualTx,
  outcomeDatumToData,
  outcomeScriptAddress,
  redemptionDatumToData,
  redemptionScriptAddress,
  type OutcomeDatum,
  type RedemptionDatum,
  type Winner,
} from "@contracts-library/meshjs";
import { ALWAYS_TRUE, REJECT_WITHDRAW } from "../src/fixtures";
import { type Data, type UTxO } from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
  chainNowMs,
  collateralOf,
  devnetReachable,
  fundedAccount,
  lovelaceOf,
  makeProvider,
  NETWORK_ID,
  newTxBuilder,
  registerStakeCredential,
  scriptOutputOf,
  signAndSubmit,
  STORE_URL,
  waitForTx,
  type Account,
} from "../src/devnet";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping all e2e tests: no Yaci devnet at ${STORE_URL}. ` +
      `Run \`npm run test:devnet\`.`,
  );
}

describe.skipIf(!reachable)(
  "prediction-market conditional-token e2e (Yaci devnet)",
  () => {
    let provider: ReturnType<typeof makeProvider>;
    let outcomeAddr: string;
    let redemptionAddr: string;

    beforeAll(async () => {
      provider = makeProvider();
      outcomeAddr = outcomeScriptAddress(NETWORK_ID);
      redemptionAddr = redemptionScriptAddress(NETWORK_ID);
    });

    const sampleMarketId =
      "aabbccdd00112233445566778899aabbccdd00112233445566778899aabbcc";
    const sampleBeaconPolicy =
      "00000000000000000000000000000000000000000000000000000000";

    function makeOutcomeDatum(
      overrides: Partial<OutcomeDatum> = {},
    ): OutcomeDatum {
      return {
        marketId: sampleMarketId,
        cutoff: Date.now() + 365 * 24 * 60 * 60 * 1000,
        winner: "None",
        outcomeCredential: { kind: "key", hash: "" },
        resolutionTimeout: Date.now() + 10_000,
        claimDeadline: Date.now() + 30_000,
        collateral: {
          asset: { policyId: "", assetName: "" },
          amount: 0n,
        },
        ...overrides,
      };
    }

    function makeRedemptionDatum(
      overrides: Partial<RedemptionDatum> = {},
    ): RedemptionDatum {
      return {
        marketId: sampleMarketId,
        beaconPolicy: sampleBeaconPolicy,
        ...overrides,
      };
    }

    /** Send ADA to a script address with an inline datum, return the UTxO. */
    async function sendToScript(
      signer: Account,
      address: string,
      lovelace: bigint,
      datumValue: Data,
      extraAssets: { unit: string; quantity: string }[] = [],
    ): Promise<UTxO> {
      const assets = [
        { unit: "lovelace", quantity: String(lovelace) },
        ...extraAssets,
      ];
      const tx = await newTxBuilder(provider)
        .txOut(address, assets)
        .txOutInlineDatumValue(datumValue)
        .changeAddress(signer.address)
        .selectUtxosFrom(await signer.wallet.getUtxos())
        .complete();
      const hash = await signAndSubmit(signer, tx);
      await waitForTx(provider, hash);
      return scriptOutputOf(provider, hash, address);
    }

    // ---------------------------------------------------------- Happy paths

    it("resolves an outcome (key credential)", async () => {
      const authority = await fundedAccount(provider);
      const now = await chainNowMs();
      const datum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: authority.keyHash },
      });

      const utxo = await sendToScript(
        authority,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(datum),
      );

      const winner: Winner = "Yes";
      const resolveTx = await buildResolveTx({
        txBuilder: newTxBuilder(provider),
        outcomeUtxo: utxo,
        datum,
        winner,
        changeAddress: authority.address,
        collateralUtxo: await collateralOf(authority),
        utxos: await authority.wallet.getUtxos(),
      });
      const hash = await signAndSubmit(authority, resolveTx);
      await waitForTx(provider, hash);

      const resolved = await scriptOutputOf(provider, hash, outcomeAddr);
      expect(lovelaceOf(resolved)).toBeGreaterThanOrEqual(3n * ADA);
    });

    it("resolves with a script credential (withdraw-0)", async () => {
      const authority = await fundedAccount(provider);
      await registerStakeCredential(provider, authority, ALWAYS_TRUE.hash);
      const now = await chainNowMs();

      const datum = makeOutcomeDatum({
        outcomeCredential: { kind: "script", hash: ALWAYS_TRUE.hash },
      });

      const utxo = await sendToScript(
        authority,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(datum),
      );

      const resolveTx = await buildResolveTx({
        txBuilder: newTxBuilder(provider),
        outcomeUtxo: utxo,
        datum,
        winner: "No",
        changeAddress: authority.address,
        collateralUtxo: await collateralOf(authority),
        utxos: await authority.wallet.getUtxos(),
        authorizer: { scriptCbor: ALWAYS_TRUE.cbor },
      });
      const hash = await signAndSubmit(authority, resolveTx);
      await waitForTx(provider, hash);

      const resolved = await scriptOutputOf(provider, hash, outcomeAddr);
      expect(lovelaceOf(resolved)).toBeGreaterThanOrEqual(3n * ADA);
    });

    it("rejects resolve with an unapproved script credential", async () => {
      const authority = await fundedAccount(provider);
      await registerStakeCredential(provider, authority, REJECT_WITHDRAW.hash);

      const datum = makeOutcomeDatum({
        outcomeCredential: { kind: "script", hash: REJECT_WITHDRAW.hash },
      });

      const utxo = await sendToScript(
        authority,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(datum),
      );

      await expect(
        (async () => {
          const resolveTx = await buildResolveTx({
            txBuilder: newTxBuilder(provider),
            outcomeUtxo: utxo,
            datum,
            winner: "Yes",
            changeAddress: authority.address,
            collateralUtxo: await collateralOf(authority),
            utxos: await authority.wallet.getUtxos(),
            authorizer: { scriptCbor: REJECT_WITHDRAW.cbor },
          });
          return signAndSubmit(authority, resolveTx);
        })(),
      ).rejects.toThrow();
    });

    it("redeems winner from redemption UTxO", async () => {
      const beneficiary = await fundedAccount(provider);
      const outcomeActor = await fundedAccount(provider);

      const collateralAda = 100n * ADA;
      const outcomeDatum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: outcomeActor.keyHash },
      });
      const redemptionDatum = makeRedemptionDatum();

      const outcomeUtxo = await sendToScript(
        outcomeActor,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(outcomeDatum),
      );
      const redemptionUtxo = await sendToScript(
        outcomeActor,
        redemptionAddr,
        collateralAda,
        redemptionDatumToData(redemptionDatum),
      );

      const resolveTx = await buildResolveTx({
        txBuilder: newTxBuilder(provider),
        outcomeUtxo,
        datum: outcomeDatum,
        winner: "Yes",
        changeAddress: outcomeActor.address,
        collateralUtxo: await collateralOf(outcomeActor),
        utxos: await outcomeActor.wallet.getUtxos(),
      });
      const resolveHash = await signAndSubmit(outcomeActor, resolveTx);
      await waitForTx(provider, resolveHash);
      const resolvedUtxo = await scriptOutputOf(
        provider,
        resolveHash,
        outcomeAddr,
      );

      const payoutAda = 30n * ADA;
      const redeemTx = await buildRedeemWinnerTx({
        txBuilder: newTxBuilder(provider),
        redemptionUtxo,
        datum: redemptionDatum,
        outcomeUtxo: resolvedUtxo,
        outcomeDatum,
        winner: "Yes",
        winTokens: payoutAda,
        tokenPolicy: sampleBeaconPolicy,
        outputIndex: 0,
        beneficiaryAddress: beneficiary.address,
        collateralUtxo: await collateralOf(beneficiary),
        utxos: await beneficiary.wallet.getUtxos(),
      });
      const redeemHash = await signAndSubmit(beneficiary, redeemTx);
      await waitForTx(provider, redeemHash);

      const outs = await provider.fetchUTxOs(redeemHash);
      const hasPayout = outs.some(
        (u) =>
          u.output.address === beneficiary.address &&
          u.output.amount.some(
            (a) => a.unit === "lovelace" && BigInt(a.quantity) >= payoutAda,
          ),
      );
      expect(hasPayout).toBe(true);
    });

    it("burns a complete set for collateral (pre-resolution)", async () => {
      const redeemer = await fundedAccount(provider);
      const collateralAda = 60n * ADA;

      const outcomeDatum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: redeemer.keyHash },
      });
      const redemptionDatum = makeRedemptionDatum();

      const outcomeUtxo = await sendToScript(
        redeemer,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(outcomeDatum),
      );
      const redemptionUtxo = await sendToScript(
        redeemer,
        redemptionAddr,
        collateralAda,
        redemptionDatumToData(redemptionDatum),
      );

      const burnAda = 20n * ADA;
      const burnTx = await buildBurnCompleteSetTx({
        txBuilder: newTxBuilder(provider),
        redemptionUtxo,
        datum: redemptionDatum,
        outcomeUtxo,
        outcomeDatum,
        outputIndex: 0,
        completeSets: burnAda,
        beneficiaryAddress: redeemer.address,
        collateralUtxo: await collateralOf(redeemer),
        utxos: await redeemer.wallet.getUtxos(),
      });
      const burnHash = await signAndSubmit(redeemer, burnTx);
      await waitForTx(provider, burnHash);

      const outs = await provider.fetchUTxOs(burnHash);
      const hasReturned = outs.some(
        (u) =>
          u.output.address === redeemer.address &&
          u.output.amount.some(
            (a) => a.unit === "lovelace" && BigInt(a.quantity) >= burnAda,
          ),
      );
      expect(hasReturned).toBe(true);
    });

    it("claims timeout after resolution_timeout", async () => {
      const claimant = await fundedAccount(provider);
      const now = await chainNowMs();
      const collateralAda = 60n * ADA;

      const outcomeDatum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: claimant.keyHash },
        resolutionTimeout: now - 2_000,
        claimDeadline: now + 600_000,
      });
      const redemptionDatum = makeRedemptionDatum();

      const outcomeUtxo = await sendToScript(
        claimant,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(outcomeDatum),
      );
      const redemptionUtxo = await sendToScript(
        claimant,
        redemptionAddr,
        collateralAda,
        redemptionDatumToData(redemptionDatum),
      );

      const claimTx = await buildClaimTimeoutTx({
        txBuilder: newTxBuilder(provider),
        redemptionUtxo,
        datum: redemptionDatum,
        outcomeUtxo,
        outcomeDatum,
        outputIndex: 0,
        tokenCount: 20n * ADA,
        beneficiaryAddress: claimant.address,
        collateralUtxo: await collateralOf(claimant),
        utxos: await claimant.wallet.getUtxos(),
      });
      const claimHash = await signAndSubmit(claimant, claimTx);
      await waitForTx(provider, claimHash);

      const outs = await provider.fetchUTxOs(claimHash);
      const payout = outs
        .filter((u) => u.output.address === claimant.address)
        .flatMap((u) => u.output.amount)
        .filter((a) => a.unit === "lovelace")
        .reduce((sum, a) => sum + BigInt(a.quantity), 0n);
      expect(payout).toBeGreaterThanOrEqual(10n * ADA);
    });

    it("claims draw from redemption UTxO", async () => {
      const claimant = await fundedAccount(provider);
      const outcomeActor = await fundedAccount(provider);
      const collateralAda = 60n * ADA;

      const outcomeDatum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: outcomeActor.keyHash },
      });
      const redemptionDatum = makeRedemptionDatum();

      const outcomeUtxo = await sendToScript(
        outcomeActor,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(outcomeDatum),
      );
      const redemptionUtxo = await sendToScript(
        outcomeActor,
        redemptionAddr,
        collateralAda,
        redemptionDatumToData(redemptionDatum),
      );

      const resolveTx = await buildResolveTx({
        txBuilder: newTxBuilder(provider),
        outcomeUtxo,
        datum: outcomeDatum,
        winner: "Draw",
        changeAddress: outcomeActor.address,
        collateralUtxo: await collateralOf(outcomeActor),
        utxos: await outcomeActor.wallet.getUtxos(),
      });
      const resolveHash = await signAndSubmit(outcomeActor, resolveTx);
      await waitForTx(provider, resolveHash);
      const resolvedUtxo = await scriptOutputOf(
        provider,
        resolveHash,
        outcomeAddr,
      );

      const claimTx = await buildClaimDrawTx({
        txBuilder: newTxBuilder(provider),
        redemptionUtxo,
        datum: redemptionDatum,
        outcomeUtxo: resolvedUtxo,
        outcomeDatum,
        outputIndex: 0,
        tokenCount: 20n * ADA,
        beneficiaryAddress: claimant.address,
        collateralUtxo: await collateralOf(claimant),
        utxos: await claimant.wallet.getUtxos(),
      });
      const claimHash = await signAndSubmit(claimant, claimTx);
      await waitForTx(provider, claimHash);

      const outs = await provider.fetchUTxOs(claimHash);
      const payout = outs
        .filter((u) => u.output.address === claimant.address)
        .flatMap((u) => u.output.amount)
        .filter((a) => a.unit === "lovelace")
        .reduce((sum, a) => sum + BigInt(a.quantity), 0n);
      expect(payout).toBeGreaterThanOrEqual(10n * ADA);
    });

    it("sweeps residual after claim_deadline", async () => {
      const sweeper = await fundedAccount(provider);
      const marketOwner = await fundedAccount(provider);
      const now = await chainNowMs();
      const collateralAda = 40n * ADA;

      const outcomeDatum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: sweeper.keyHash },
        claimDeadline: now - 2_000,
      });
      const redemptionDatum = makeRedemptionDatum();

      const outcomeUtxo = await sendToScript(
        sweeper,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(outcomeDatum),
      );
      const redemptionUtxo = await sendToScript(
        sweeper,
        redemptionAddr,
        collateralAda,
        redemptionDatumToData(redemptionDatum),
      );

      const sweepTx = await buildSweepResidualTx({
        txBuilder: newTxBuilder(provider),
        redemptionUtxo,
        datum: redemptionDatum,
        outcomeUtxo,
        outcomeDatum,
        outputIndex: 0,
        marketAddress: marketOwner.address,
        collateralUtxo: await collateralOf(sweeper),
        utxos: await sweeper.wallet.getUtxos(),
        changeAddress: sweeper.address,
      });
      const sweepHash = await signAndSubmit(sweeper, sweepTx);
      await waitForTx(provider, sweepHash);

      const outs = await provider.fetchUTxOs(sweepHash);
      const swept = outs
        .filter((u) => u.output.address === marketOwner.address)
        .flatMap((u) => u.output.amount)
        .filter((a) => a.unit === "lovelace")
        .reduce((sum, a) => sum + BigInt(a.quantity), 0n);
      expect(swept).toBeGreaterThanOrEqual(collateralAda);

      const stillAtScript = outs.some(
        (u) => u.output.address === redemptionAddr,
      );
      expect(stillAtScript).toBe(false);
    });

    // ---------------------------------------------------------- Attack paths

    it("rejects resolve by a non-authority signer", async () => {
      const authority = await fundedAccount(provider);
      const attacker = await fundedAccount(provider);

      const datum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: authority.keyHash },
      });

      const utxo = await sendToScript(
        authority,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(datum),
      );

      await expect(
        (async () => {
          const resolveTx = await buildResolveTx({
            txBuilder: newTxBuilder(provider),
            outcomeUtxo: utxo,
            datum,
            winner: "Yes",
            changeAddress: attacker.address,
            collateralUtxo: await collateralOf(attacker),
            utxos: await attacker.wallet.getUtxos(),
          });
          return signAndSubmit(attacker, resolveTx);
        })(),
      ).rejects.toThrow();
    });

    it("preserves outcome UTxO as continuation on resolve", async () => {
      const authority = await fundedAccount(provider);
      const datum = makeOutcomeDatum({
        outcomeCredential: { kind: "key", hash: authority.keyHash },
      });

      const utxo = await sendToScript(
        authority,
        outcomeAddr,
        5n * ADA,
        outcomeDatumToData(datum),
      );

      const resolveTx = await buildResolveTx({
        txBuilder: newTxBuilder(provider),
        outcomeUtxo: utxo,
        datum,
        winner: "No",
        changeAddress: authority.address,
        collateralUtxo: await collateralOf(authority),
        utxos: await authority.wallet.getUtxos(),
      });
      const hash = await signAndSubmit(authority, resolveTx);
      await waitForTx(provider, hash);

      const continuation = await scriptOutputOf(provider, hash, outcomeAddr);
      expect(continuation).toBeDefined();
    });
  },
);
