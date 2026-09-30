/**
 * Real-world happy path for the tokenized bond over the actual CIP-113 core
 * validators (vendored from cardano-foundation/cip113-programmable-tokens):
 * deploy the core, register + issue the bond through the registry, then
 * transfer → transform → graduate, all against a Yaci devnet.
 *
 * Single-signer discipline: the tx funder must be the wallet that authorizes,
 * because MeshJS's `signAndSubmit` signs with one wallet. `account` funds and
 * authorizes register/transfer/transform; `recipient` (the post-transfer
 * holder) funds and authorizes the graduation.
 *
 * Skips when no devnet is reachable (`npm run test:devnet`).
 */

import {
  mConStr0,
  resolveStakeKeyHash,
  unixTimeToEnclosingSlot,
  type SlotConfig,
  type UTxO,
} from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";

import {
  applyBond,
  buildGraduateOwner,
  buildRegisterAndIssue,
  buildTransfer,
  buildTransform,
  plbAddress,
  type Bond,
} from "../src/cip113/bond";
import {
  rewardAddressOf,
  scriptAddressOf,
  scriptHashOf,
} from "../src/cip113/core";
import { deployCore, type Deployment } from "../src/cip113/deploy";
import type { RegistryNode } from "../src/cip113/data";
import {
  chainNowMs,
  collateralOf,
  devnetReachable,
  devnetSlotConfig,
  fundedAccount,
  makeProvider,
  newTxBuilder,
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

const PRINCIPAL = "424f4e44"; // "BOND"
const REFERENCE = "524546323232"; // "REF222"
const SCALE = 1000;
const QUANTITY = 1000n;
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

    async function stakeHashOf(account: Account): Promise<string> {
      return resolveStakeKeyHash(
        (await account.wallet.getRewardAddresses())[0],
      );
    }

    /** Register a module script's stake credential with publish consent. */
    async function registerScriptStake(
      payer: Account,
      script: { code: string },
      hash: string,
    ): Promise<void> {
      const collateral = await collateralOf(payer);
      const tx = await newTxBuilder(provider)
        .registerStakeCertificate(rewardAddressOf(hash, 0))
        .certificateScript(script.code, "V3")
        .certificateRedeemerValue(mConStr0([]))
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

    async function holds(account: Account, unit: string): Promise<bigint> {
      const utxos = await account.wallet.getUtxos();
      return utxos.reduce((sum, u) => {
        const a = u.output.amount.find((x) => x.unit === unit);
        return sum + (a ? BigInt(a.quantity) : 0n);
      }, 0n);
    }

    it("deploys the core, registers + issues the bond, transfers, transforms and graduates", async () => {
      // `account` funds and signs register/transfer/transform; `recipient` becomes
      // the holder after the transfer and funds/signs the graduation.
      const account = await fundedAccount(
        provider,
        [20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000],
      );
      const recipient = await fundedAccount(provider);
      const accountStakeHash = await stakeHashOf(account);
      const recipientStakeHash = await stakeHashOf(recipient);

      // ---- deploy the core -------------------------------------------------
      const deployment: Deployment = await deployCore(provider, account);

      const start = await chainNowMs();
      const schedule = [
        { deadline: start, value: 1040 },
        { deadline: start + 10_000, value: 1081 },
        { deadline: start + 20_000, value: 1124 },
        { deadline: start + 30_000, value: 1169 },
      ];
      const finalDeadline = schedule[schedule.length - 1].deadline;
      const finalValue = BigInt(schedule[schedule.length - 1].value);

      // ---- apply the bond + register its module credentials (publish) ------
      const bond: Bond = applyBond(deployment, {
        principalName: PRINCIPAL,
        referenceName: REFERENCE,
        schedule,
        scale: SCALE,
        issuer: { kind: "key", hash: account.keyHash },
      });
      for (const script of bond.withdrawCredentials) {
        await registerScriptStake(account, script, scriptHashOf(script));
      }

      const nodeAddress = scriptAddressOf(deployment.core.registryNodeCs, 0);
      const beneficiaryAddress = plbAddress(
        deployment,
        accountStakeHash,
        false,
      );
      const referenceAddress = plbAddress(
        deployment,
        scriptHashOf(bond.transformation),
        true,
      );

      // ---- register + issue (T0/T1) ---------------------------------------
      const funding1 = await fundingOf(account);
      const registerTx = await buildRegisterAndIssue({
        txBuilder: newTxBuilder(provider),
        deployment,
        bond,
        covering: deployment.refs.originNode,
        coveringNode: ORIGIN_NODE,
        quantity: QUANTITY,
        beneficiaryAddress,
        referenceAddress,
        nodeAddress,
        funding: funding1.funding,
        collateral: funding1.collateral,
        changeAddress: account.address,
      });
      const registerHash = await signAndSubmit(account, registerTx);
      await waitForTx(provider, registerHash);

      const principalUtxo = await outputHolding(
        registerHash,
        bond.policyId + PRINCIPAL,
      );
      const referenceUtxo = await outputHolding(
        registerHash,
        bond.policyId + REFERENCE,
      );
      const bondNode = await outputHolding(
        registerHash,
        deployment.core.registryNodeCs + bond.policyId,
      );

      // ---- transfer (T2, owner path) --------------------------------------
      const funding2 = await fundingOf(account);
      const transferTx = await buildTransfer({
        txBuilder: newTxBuilder(provider),
        deployment,
        bond,
        node: bondNode,
        principalInputs: [principalUtxo],
        recipientAddress: plbAddress(deployment, recipientStakeHash, false),
        senderStakeHash: accountStakeHash,
        funding: funding2.funding,
        collateral: funding2.collateral,
        changeAddress: account.address,
      });
      const transferHash = await signAndSubmit(account, transferTx);
      await waitForTx(provider, transferHash);

      // The holder is now `recipient`.
      const recipientPrincipal = await outputHolding(
        transferHash,
        bond.policyId + PRINCIPAL,
      );
      expect(
        recipientPrincipal.output.amount.some(
          (a) => a.unit === bond.policyId + PRINCIPAL,
        ),
      ).toBe(true);

      // ---- transform (T3) --------------------------------------------------
      await waitUntilChainTimeMs(schedule[0].deadline);
      const now = await chainNowMs();
      const nextValue = schedule.reduce(
        (v, s) => (s.deadline <= now ? s.value : v),
        schedule[0].value,
      );
      const funding3 = await fundingOf(account);
      const transformTx = await buildTransform({
        txBuilder: newTxBuilder(provider),
        deployment,
        bond,
        node: bondNode,
        referenceUtxo,
        nextValue,
        validFromSlot: unixTimeToEnclosingSlot(now, slotConfig),
        funding: funding3.funding,
        collateral: funding3.collateral,
        changeAddress: account.address,
      });
      await waitForTx(provider, await signAndSubmit(account, transformTx));

      // ---- graduate (T4, owner path) --------------------------------------
      await waitUntilChainTimeMs(finalDeadline);
      const now4 = await chainNowMs();
      const nativeQuantity = (QUANTITY * finalValue) / BigInt(SCALE);
      const funding4 = await fundingOf(recipient);
      const graduateTx = await buildGraduateOwner({
        txBuilder: newTxBuilder(provider),
        deployment,
        bond,
        node: bondNode,
        referenceUtxo,
        principalInputs: [recipientPrincipal],
        principalQuantity: QUANTITY,
        nativeQuantity,
        nativeOutputAddress: recipient.address,
        ownerStakeHash: recipientStakeHash,
        validFromSlot: unixTimeToEnclosingSlot(now4, slotConfig),
        funding: funding4.funding,
        collateral: funding4.collateral,
        changeAddress: recipient.address,
      });
      await waitForTx(provider, await signAndSubmit(recipient, graduateTx));

      expect(await holds(recipient, bond.nativePolicyId + PRINCIPAL)).toBe(
        nativeQuantity,
      );
      expect(await holds(recipient, bond.policyId + PRINCIPAL)).toBe(0n);
    });
  },
);
