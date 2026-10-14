/**
 * Real-world happy path for the tokenized bond over the actual CIP-113 core
 * validators (vendored from cardano-foundation/cip113-programmable-tokens):
 * deploy the core, create the vault, register the bond, deposit, claim the
 * coupon, redeem it at the vault, and graduate (owner path) — all against a
 * Yaci devnet.
 *
 * Single-signer discipline: the tx funder must be the wallet that authorizes,
 * because MeshJS's `signAndSubmit` signs with one wallet.
 *
 * Skips when no devnet is reachable (`npm run test:devnet`).
 */

import {
  unixTimeToEnclosingSlot,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";

import {
  applyBond,
  buildBondDepositTx,
  buildClaimOwnerTx,
  buildCreateVaultTx,
  buildGraduateOwnerTx,
  buildRedeemTx,
  buildRegisterTx,
  couponName,
  rewardAddressOf,
  scriptHashOf,
  stepName,
  vaultAddress,
  type Bond,
  type CertificateDatum,
  type RegistryNode,
} from "@contracts-library/meshjs";

import { deployCore, type Deployment } from "../src/cip113/deploy";
import {
  chainNowMs,
  collateralOf,
  devnetReachable,
  devnetSlotConfig,
  fundedAccount,
  makeProvider,
  newTxBuilderManualExUnits,
  signAndSubmit,
  STORE_URL,
  waitForTx,
  waitUntilChainTimeMs,
  type Account,
} from "../src/devnet";

const reachable = await devnetReachable();
if (!reachable) {
  console.warn(
    `[e2e] Skipping event_triggered real-core e2e: no Yaci devnet at ${STORE_URL}.`,
  );
}

const PRINCIPAL = 1000;
const INTERVAL = 10_000;
const AMOUNTS = [1040];
const VAULT_NFT_NAME = Buffer.from("V0").toString("hex");
const VAULT_ADA = 5_000_000n;
const ORIGIN_NODE: RegistryNode = {
  key: "",
  next: "ff".repeat(30),
  mintingLogic: { kind: "key", hash: "" },
  transferLogic: { kind: "key", hash: "" },
  thirdPartyLogic: { kind: "key", hash: "" },
  unfrackingLogic: { kind: "key", hash: "" },
  globalStateCs: "",
};

describe.skipIf(!reachable)(
  "event_triggered real-core e2e (Yaci devnet)",
  () => {
    let provider: ReturnType<typeof makeProvider>;
    let slotConfig: SlotConfig;

    beforeAll(async () => {
      provider = makeProvider();
      slotConfig = await devnetSlotConfig();
    });

    /** The first slot whose start time is at least `ms`. */
    function firstSlotAt(ms: number): number {
      return Math.ceil((ms - slotConfig.zeroTime) / slotConfig.slotLength);
    }

    /** The start time (POSIX ms) of a slot. */
    function slotStartMs(slot: number): number {
      return (
        slotConfig.zeroTime +
        (slot - slotConfig.zeroSlot) * slotConfig.slotLength
      );
    }

    /** Register a module script's stake credential so its withdraw-0 exists. */
    async function registerScriptStake(
      payer: Account,
      scriptHash: string,
    ): Promise<void> {
      const collateral = await collateralOf(payer);
      const tx = await newTxBuilderManualExUnits(provider)
        .registerStakeCertificate(rewardAddressOf(scriptHash, 0))
        .txInCollateral(
          collateral.input.txHash,
          collateral.input.outputIndex,
          collateral.output.amount,
          collateral.output.address,
        )
        .changeAddress(payer.address)
        .selectUtxosFrom(await payer.wallet.getUtxos())
        .complete();
      await waitForTx(provider, await signAndSubmit(payer, tx));
    }

    async function fundingOf(payer: Account) {
      const collateral = await collateralOf(payer);
      return {
        collateral,
        funding: (await payer.wallet.getUtxos()).filter(
          (u) =>
            !(
              u.input.txHash === collateral.input.txHash &&
              u.input.outputIndex === collateral.input.outputIndex
            ),
        ),
      };
    }

    async function outputHolding(txHash: string, unit: string): Promise<UTxO> {
      const outs = await provider.fetchUTxOs(txHash);
      const found = outs.find((u) =>
        u.output.amount.some((a) => a.unit === unit),
      );
      if (!found) throw new Error(`no output holding ${unit} in ${txHash}`);
      return found;
    }

    function lovelaceOf(utxo: UTxO): bigint {
      const a = utxo.output.amount.find((x) => x.unit === "lovelace");
      return a ? BigInt(a.quantity) : 0n;
    }

    it("creates the vault, registers, deposits, claims, redeems and graduates", async () => {
      // `account` funds and signs the core, the vault and the registration;
      // `holder` deposits and owns the certificate afterwards.
      const account = await fundedAccount(
        provider,
        [20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000],
      );
      const holder = await fundedAccount(provider);

      // ---- deploy the core -------------------------------------------------
      const deployment: Deployment = await deployCore(provider, account);

      // ---- apply the bond + register its module credentials (publish) ------
      const bond: Bond = applyBond(deployment, {
        principal: PRINCIPAL,
        interval: INTERVAL,
        amounts: AMOUNTS,
        issuer: { kind: "key", hash: account.keyHash },
        vaultNftName: VAULT_NFT_NAME,
      });
      for (const script of bond.withdrawCredentials) {
        await registerScriptStake(account, scriptHashOf(script));
      }

      // ---- create the vault (§3.1, I10) ------------------------------------
      const funding0 = await fundingOf(account);
      const createTx = await buildCreateVaultTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        vaultAda: VAULT_ADA,
        funding: funding0.funding,
        collateral: funding0.collateral,
        changeAddress: account.address,
      });
      const createHash = await signAndSubmit(account, createTx);
      await waitForTx(provider, createHash);
      const vaultUtxo = await outputHolding(
        createHash,
        bond.vaultNftCs + VAULT_NFT_NAME,
      );
      expect(lovelaceOf(vaultUtxo)).toBe(VAULT_ADA);

      // ---- register (§4.1) -------------------------------------------------
      const funding1 = await fundingOf(account);
      const registerTx = await buildRegisterTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        covering: deployment.refs.originNode,
        coveringNode: ORIGIN_NODE,
        funding: funding1.funding,
        collateral: funding1.collateral,
        changeAddress: account.address,
      });
      const registerHash = await signAndSubmit(account, registerTx);
      await waitForTx(provider, registerHash);
      const bondNode = await outputHolding(
        registerHash,
        deployment.core.registryNodeCs + bond.cipPolicy,
      );

      // ---- deposit (§4.2) --------------------------------------------------
      const upperSlot = firstSlotAt((await chainNowMs()) + 30_000);
      const start = slotStartMs(upperSlot);
      const funding2 = await fundingOf(holder);
      const depositTx = await buildBondDepositTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node: bondNode,
        vault: vaultUtxo,
        depositorStakeHash: holder.keyHash,
        start,
        validHereafterSlot: upperSlot,
        funding: funding2.funding,
        collateral: funding2.collateral,
        changeAddress: holder.address,
      });
      const depositHash = await signAndSubmit(holder, depositTx);
      await waitForTx(provider, depositHash);
      const cert0 = await outputHolding(
        depositHash,
        bond.cipPolicy + stepName(0),
      );
      const vaultAfterDeposit = await outputHolding(
        depositHash,
        bond.vaultNftCs + VAULT_NFT_NAME,
      );
      expect(lovelaceOf(vaultAfterDeposit)).toBe(VAULT_ADA + BigInt(PRINCIPAL));

      // ---- claim the coupon, step 1 (§4.5) ---------------------------------
      const deadline = start + INTERVAL;
      await waitUntilChainTimeMs(deadline);
      const funding3 = await fundingOf(holder);
      const datum: CertificateDatum = {
        start,
        commit: null,
        cntPolicy: bond.cntPolicy,
      };
      const claimTx = await buildClaimOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node: bondNode,
        certificate: cert0,
        step: 1,
        datum,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(deadline),
        funding: funding3.funding,
        collateral: funding3.collateral,
        changeAddress: holder.address,
      });
      const claimHash = await signAndSubmit(holder, claimTx);
      await waitForTx(provider, claimHash);
      const cert1 = await outputHolding(
        claimHash,
        bond.cipPolicy + stepName(1),
      );
      const coupon = await outputHolding(
        claimHash,
        bond.cntPolicy + couponName(AMOUNTS[0]),
      );
      expect(
        coupon.output.amount.some(
          (a) =>
            a.unit === bond.cntPolicy + couponName(AMOUNTS[0]) &&
            a.quantity === "1",
        ),
      ).toBe(true);

      // ---- redeem the coupon (§4.6) ----------------------------------------
      const funding4 = await fundingOf(holder);
      const redeemTx = await buildRedeemTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        vault: vaultAfterDeposit,
        coupons: [coupon],
        payouts: [{ address: holder.address, amount: BigInt(AMOUNTS[0]) }],
        funding: funding4.funding,
        collateral: funding4.collateral,
        changeAddress: holder.address,
      });
      const redeemHash = await signAndSubmit(holder, redeemTx);
      await waitForTx(provider, redeemHash);
      const vaultAfterRedeem = await outputHolding(
        redeemHash,
        bond.vaultNftCs + VAULT_NFT_NAME,
      );
      expect(lovelaceOf(vaultAfterRedeem)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]),
      );

      // ---- graduate (owner path, §4.7) -------------------------------------
      const funding5 = await fundingOf(holder);
      const graduateTx = await buildGraduateOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node: bondNode,
        certificate: cert1,
        step: 1,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(deadline),
        funding: funding5.funding,
        collateral: funding5.collateral,
        changeAddress: holder.address,
      });
      const graduateHash = await signAndSubmit(holder, graduateTx);
      await waitForTx(provider, graduateHash);
      const principalCoupon = await outputHolding(
        graduateHash,
        bond.cntPolicy + couponName(PRINCIPAL),
      );

      // ---- redeem the principal (§4.6) -------------------------------------
      const funding6 = await fundingOf(holder);
      const redeemPrincipalTx = await buildRedeemTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        vault: vaultAfterRedeem,
        coupons: [principalCoupon],
        payouts: [{ address: holder.address, amount: BigInt(PRINCIPAL) }],
        funding: funding6.funding,
        collateral: funding6.collateral,
        changeAddress: holder.address,
      });
      const redeemPrincipalHash = await signAndSubmit(
        holder,
        redeemPrincipalTx,
      );
      await waitForTx(provider, redeemPrincipalHash);

      // The certificate is retired and the vault is back to the reserve (the
      // coupon and principal were paid out of it).
      const vaultFinal = await outputHolding(
        redeemPrincipalHash,
        bond.vaultNftCs + VAULT_NFT_NAME,
      );
      expect(lovelaceOf(vaultFinal)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]) - BigInt(PRINCIPAL),
      );
      const vaultUtxos = await provider.fetchAddressUTxOs(vaultAddress(bond));
      const certsHeld = vaultUtxos.reduce(
        (n, u) =>
          n +
          u.output.amount.filter((a) => a.unit.startsWith(bond.cipPolicy))
            .length,
        0,
      );
      expect(certsHeld).toBe(0);
    });
  },
);
