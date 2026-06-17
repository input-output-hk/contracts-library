/**
 * End-to-end tests against a local Yaci DevKit devnet.
 *
 * Happy paths drive the library exactly as a consumer would (buildLockTx /
 * buildClaimTx / buildCancelTx). Attack paths build raw malicious transactions
 * with MeshTxBuilder (an attacker would not use our honest builder) but reuse
 * the library's public encoders, and assert the on-chain validator rejects them.
 *
 * The suite skips itself when no devnet is reachable, so `npm test` is safe to
 * run without Yaci; CI starts Yaci first (see .github/workflows/ci.yml).
 */

import {
  buildCancelTx,
  buildClaimTx,
  buildLockTx,
  cancelRedeemer,
  claimRedeemer,
  requiredRemainder,
  vestingDatumToData,
  vestingScript,
  vestingScriptAddress,
  type Credential,
  type VestingDatum,
} from "@contracts-library/vesting-meshjs";
import { ALWAYS_TRUE, REJECT_WITHDRAW } from "../src/fixtures";
import {
  unixTimeToEnclosingSlot,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";
import {
  chainNowMs,
  devnetReachable,
  devnetSlotConfig,
  fundedAccount,
  makeProvider,
  NETWORK_ID,
  newTxBuilder,
  registerStakeCredential,
  scriptOutputOf,
  STORE_URL,
  waitForTx,
  waitUntilChainTimeMs,
  type Account,
} from "../src/devnet";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping all e2e tests: no Yaci devnet at ${STORE_URL}. ` +
      `Run \`npm run test:devnet\` (or start one and set INDEXER_URL / YACI_STORE_URL).`,
  );
}
const ADA = 1_000_000n;

function lovelaceOf(utxo: UTxO): bigint {
  const a = utxo.output.amount.find((x) => x.unit === "lovelace");
  return BigInt(a?.quantity ?? "0");
}

describe.skipIf(!reachable)("linear vesting e2e (Yaci devnet)", () => {
  let provider: ReturnType<typeof makeProvider>;
  let slotConfig: SlotConfig;
  let scriptAddr: string;

  beforeAll(async () => {
    provider = makeProvider();
    slotConfig = await devnetSlotConfig();
    scriptAddr = vestingScriptAddress(NETWORK_ID);
  });

  /**
   * A grantor locks `totalAda` on the given schedule. The returned `beneficiary`
   * account always pays fees/collateral and signs the claim; the datum's
   * beneficiary credential defaults to that account's key, or is overridden by
   * `beneficiaryCredential` (e.g. a script credential for the withdraw-0 path).
   */
  async function lock(opts: {
    totalAda: bigint;
    startMs: number;
    endMs: number;
    recoveryMs: number;
    beneficiaryCredential?: Credential;
  }) {
    const grantor = await fundedAccount(provider);
    const beneficiary = await fundedAccount(provider);
    const datum: VestingDatum = {
      beneficiary:
        opts.beneficiaryCredential ?? { kind: "key", hash: beneficiary.keyHash },
      locker: { kind: "key", hash: grantor.keyHash },
      vesting: [{ policyId: "", assetName: "", total: opts.totalAda }],
      startTime: opts.startMs,
      endTime: opts.endMs,
      recoveryTime: opts.recoveryMs,
    };
    const lockTx = await buildLockTx({
      txBuilder: newTxBuilder(provider),
      datum,
      utxos: await grantor.wallet.getUtxos(),
      changeAddress: grantor.address,
      networkId: NETWORK_ID,
    });
    const lockHash = await grantor.wallet.submitTx(
      await grantor.wallet.signTx(lockTx, true),
    );
    await waitForTx(provider, lockHash);
    const vestingUtxo = await scriptOutputOf(provider, lockHash, scriptAddr);
    return { grantor, beneficiary, datum, vestingUtxo };
  }

  /** A raw, possibly-malicious spend of a vesting UTxO. */
  async function rawSpend(p: {
    action: "claim" | "cancel";
    signer: Account;
    vestingUtxo: UTxO;
    validityNow: number;
    continuation?: { datum: VestingDatum; lovelace: bigint };
    requiredSigner?: string;
  }): Promise<string> {
    const tb = newTxBuilder(provider);
    tb.spendingPlutusScriptV3()
      .txIn(
        p.vestingUtxo.input.txHash,
        p.vestingUtxo.input.outputIndex,
        p.vestingUtxo.output.amount,
        p.vestingUtxo.output.address,
      )
      .txInInlineDatumPresent()
      .txInRedeemerValue(p.action === "claim" ? claimRedeemer() : cancelRedeemer())
      .txInScript(vestingScript().code);

    if (p.continuation) {
      tb.txOut(scriptAddr, [
        { unit: "lovelace", quantity: String(p.continuation.lovelace) },
      ]).txOutInlineDatumValue(vestingDatumToData(p.continuation.datum));
    }

    tb.invalidBefore(unixTimeToEnclosingSlot(p.validityNow, slotConfig));
    if (p.requiredSigner) tb.requiredSignerHash(p.requiredSigner);

    const col = (await p.signer.wallet.getCollateral())[0];
    const unsigned = await tb
      .txInCollateral(
        col.input.txHash,
        col.input.outputIndex,
        col.output.amount,
        col.output.address,
      )
      .changeAddress(p.signer.address)
      .selectUtxosFrom(await p.signer.wallet.getUtxos())
      .complete();

    return provider.submitTx(await p.signer.wallet.signTx(unsigned, true));
  }

  // ----------------------------------------------------------- happy paths

  it("locks then partially claims mid-schedule", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 60n * ADA,
      startMs: now - 60_000,
      endMs: now + 60_000,
      recoveryMs: now + 600_000,
    });

    const claimNow = await chainNowMs();
    const claimTx = await buildClaimTx({
      txBuilder: newTxBuilder(provider),
      vestingUtxo: ctx.vestingUtxo,
      datum: ctx.datum,
      now: claimNow,
      beneficiaryAddress: ctx.beneficiary.address,
      collateralUtxo: (await ctx.beneficiary.wallet.getCollateral())[0],
      utxos: await ctx.beneficiary.wallet.getUtxos(),
      customSlotConfig: slotConfig,
    });
    const hash = await ctx.beneficiary.wallet.submitTx(
      await ctx.beneficiary.wallet.signTx(claimTx, true),
    );
    await waitForTx(provider, hash);

    const continuation = await scriptOutputOf(provider, hash, scriptAddr);
    const required = requiredRemainder(ctx.datum, claimNow)[0];
    expect(lovelaceOf(continuation)).toBeGreaterThanOrEqual(required.total);
  });

  it("fully claims after end_time with no continuation", async () => {
    const now = await chainNowMs();
    const endMs = now + 8_000;
    const ctx = await lock({
      totalAda: 40n * ADA,
      startMs: now - 2_000,
      endMs,
      recoveryMs: endMs + 600_000,
    });

    await waitUntilChainTimeMs(endMs + 2_000);
    const claimNow = await chainNowMs();
    const claimTx = await buildClaimTx({
      txBuilder: newTxBuilder(provider),
      vestingUtxo: ctx.vestingUtxo,
      datum: ctx.datum,
      now: claimNow,
      beneficiaryAddress: ctx.beneficiary.address,
      collateralUtxo: (await ctx.beneficiary.wallet.getCollateral())[0],
      utxos: await ctx.beneficiary.wallet.getUtxos(),
      customSlotConfig: slotConfig,
    });
    const hash = await ctx.beneficiary.wallet.submitTx(
      await ctx.beneficiary.wallet.signTx(claimTx, true),
    );
    await waitForTx(provider, hash);

    const outs = await provider.fetchUTxOs(hash);
    expect(outs.some((u) => u.output.address === scriptAddr)).toBe(false);
  });

  it("locker recovers the remainder after recovery_time", async () => {
    const now = await chainNowMs();
    const endMs = now + 6_000;
    const recoveryMs = now + 10_000;
    const ctx = await lock({
      totalAda: 30n * ADA,
      startMs: now - 2_000,
      endMs,
      recoveryMs,
    });

    await waitUntilChainTimeMs(recoveryMs + 2_000);
    const cancelNow = await chainNowMs();
    const cancelTx = await buildCancelTx({
      txBuilder: newTxBuilder(provider),
      vestingUtxo: ctx.vestingUtxo,
      datum: ctx.datum,
      now: cancelNow,
      lockerAddress: ctx.grantor.address,
      collateralUtxo: (await ctx.grantor.wallet.getCollateral())[0],
      utxos: await ctx.grantor.wallet.getUtxos(),
      customSlotConfig: slotConfig,
    });
    const hash = await ctx.grantor.wallet.submitTx(
      await ctx.grantor.wallet.signTx(cancelTx, true),
    );
    await waitForTx(provider, hash);

    const outs = await provider.fetchUTxOs(hash);
    expect(outs.some((u) => u.output.address === scriptAddr)).toBe(false);
  });

  // ----------------------------------------- script-credential authorization

  it("claims with an always-approving script beneficiary (withdraw-0)", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 60n * ADA,
      startMs: now - 60_000,
      endMs: now + 60_000,
      recoveryMs: now + 600_000,
      beneficiaryCredential: { kind: "script", hash: ALWAYS_TRUE.hash },
    });
    // the authorizer's stake credential must exist for a withdraw-0 to be legal
    await registerStakeCredential(provider, ctx.beneficiary, ALWAYS_TRUE.hash);

    const claimNow = await chainNowMs();
    const claimTx = await buildClaimTx({
      txBuilder: newTxBuilder(provider),
      vestingUtxo: ctx.vestingUtxo,
      datum: ctx.datum,
      now: claimNow,
      beneficiaryAddress: ctx.beneficiary.address,
      collateralUtxo: (await ctx.beneficiary.wallet.getCollateral())[0],
      utxos: await ctx.beneficiary.wallet.getUtxos(),
      customSlotConfig: slotConfig,
      authorizer: { scriptCbor: ALWAYS_TRUE.cbor },
    });
    const hash = await ctx.beneficiary.wallet.submitTx(
      await ctx.beneficiary.wallet.signTx(claimTx, true),
    );
    await waitForTx(provider, hash);

    const continuation = await scriptOutputOf(provider, hash, scriptAddr);
    const required = requiredRemainder(ctx.datum, claimNow)[0];
    expect(lovelaceOf(continuation)).toBeGreaterThanOrEqual(required.total);
  });

  it("rejects a claim whose script authorizer refuses (reject-withdraw)", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 60n * ADA,
      startMs: now - 60_000,
      endMs: now + 60_000,
      recoveryMs: now + 600_000,
      beneficiaryCredential: { kind: "script", hash: REJECT_WITHDRAW.hash },
    });
    await registerStakeCredential(provider, ctx.beneficiary, REJECT_WITHDRAW.hash);

    const claimNow = await chainNowMs();
    await expect(
      (async () => {
        const claimTx = await buildClaimTx({
          txBuilder: newTxBuilder(provider),
          vestingUtxo: ctx.vestingUtxo,
          datum: ctx.datum,
          now: claimNow,
          beneficiaryAddress: ctx.beneficiary.address,
          collateralUtxo: (await ctx.beneficiary.wallet.getCollateral())[0],
          utxos: await ctx.beneficiary.wallet.getUtxos(),
          customSlotConfig: slotConfig,
          authorizer: { scriptCbor: REJECT_WITHDRAW.cbor },
        });
        return ctx.beneficiary.wallet.submitTx(
          await ctx.beneficiary.wallet.signTx(claimTx, true),
        );
      })(),
    ).rejects.toThrow();
  });

  // ----------------------------------------------------------- attacks

  it("rejects over-claim (continuation short of the required remainder)", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 60n * ADA,
      startMs: now - 60_000,
      endMs: now + 60_000,
      recoveryMs: now + 600_000,
    });
    const validityNow = await chainNowMs();
    const required = requiredRemainder(ctx.datum, validityNow)[0].total;

    await expect(
      rawSpend({
        action: "claim",
        signer: ctx.beneficiary,
        vestingUtxo: ctx.vestingUtxo,
        validityNow,
        requiredSigner: ctx.beneficiary.keyHash,
        // keep 5 ada less than required → value-preservation must fail
        continuation: { datum: ctx.datum, lovelace: required - 5n * ADA },
      }),
    ).rejects.toThrow();
  });

  it("rejects a claim missing the beneficiary signature", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 60n * ADA,
      startMs: now - 60_000,
      endMs: now + 60_000,
      recoveryMs: now + 600_000,
    });
    const attacker = await fundedAccount(provider);
    const validityNow = await chainNowMs();

    await expect(
      rawSpend({
        action: "claim",
        signer: attacker, // pays + signs its own inputs, but is not the beneficiary
        vestingUtxo: ctx.vestingUtxo,
        validityNow,
        // honest, fully-covering continuation: only the missing auth should fail it
        continuation: { datum: ctx.datum, lovelace: 60n * ADA },
      }),
    ).rejects.toThrow();
  });

  it("rejects a tampered continuation datum", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 60n * ADA,
      startMs: now - 60_000,
      endMs: now + 60_000,
      recoveryMs: now + 600_000,
    });
    const validityNow = await chainNowMs();
    // bring end_time forward so more appears "vested": continuation datum differs
    const tampered: VestingDatum = { ...ctx.datum, endTime: ctx.datum.startTime + 1 };

    await expect(
      rawSpend({
        action: "claim",
        signer: ctx.beneficiary,
        vestingUtxo: ctx.vestingUtxo,
        validityNow,
        requiredSigner: ctx.beneficiary.keyHash,
        continuation: { datum: tampered, lovelace: 60n * ADA },
      }),
    ).rejects.toThrow();
  });

  it("rejects a cancel before recovery_time", async () => {
    const now = await chainNowMs();
    const ctx = await lock({
      totalAda: 30n * ADA,
      startMs: now - 2_000,
      endMs: now + 4_000,
      recoveryMs: now + 600_000, // far away
    });
    const validityNow = await chainNowMs(); // well before recovery

    await expect(
      rawSpend({
        action: "cancel",
        signer: ctx.grantor,
        vestingUtxo: ctx.vestingUtxo,
        validityNow,
        requiredSigner: ctx.grantor.keyHash,
      }),
    ).rejects.toThrow();
  });

  it("rejects a cancel by a non-locker after recovery_time", async () => {
    const now = await chainNowMs();
    const recoveryMs = now + 8_000;
    const ctx = await lock({
      totalAda: 30n * ADA,
      startMs: now - 2_000,
      endMs: now + 4_000,
      recoveryMs,
    });
    const attacker = await fundedAccount(provider);
    await waitUntilChainTimeMs(recoveryMs + 2_000);
    const validityNow = await chainNowMs();

    await expect(
      rawSpend({
        action: "cancel",
        signer: attacker, // not the locker
        vestingUtxo: ctx.vestingUtxo,
        validityNow,
      }),
    ).rejects.toThrow();
  });
});
