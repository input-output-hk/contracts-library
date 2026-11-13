/**
 * Real-world flows for the tokenized bond over the actual CIP-113 core
 * validators (vendored from cardano-foundation/cip113-programmable-tokens):
 * the core is deployed once, then each scenario applies its own bond
 * (deployment) and drives the real builders against a Yaci devnet:
 *
 *   - the owner path: deposit, transfer to a new owner, opt-in/opt-out,
 *     claim, redeem and graduation;
 *   - the issuer-triggered path: authorize, claim_issuer, redeem and
 *     graduation with its certificate-less shell;
 *   - several vaults with distinct coupon terms in one instrument; and
 *   - the invariant negatives (I3–I10), each asserted rejected.
 *
 * Single-signer discipline: the tx funder must be the wallet that authorizes,
 * because MeshJS's `signAndSubmit` signs with one wallet.
 *
 * Skips when no devnet is reachable (`npm run test:devnet`).
 */

import {
  applyBond,
  type Bond,
  type BondConfig,
  buildAuthorizeTx,
  buildBondDepositTx,
  buildClaimIssuerTx,
  buildClaimOwnerTx,
  buildCreateVaultTx,
  buildGraduateIssuerTx,
  buildGraduateOwnerTx,
  buildRedeemTx,
  buildRegisterTx,
  buildTransferTx,
  type CertificateDatum,
  couponName,
  couponPolicyScript,
  plbAddress,
  type RegistryNode,
  rewardAddressOf,
  scriptHashOf,
  stepName,
  vaultAddress,
} from "@contracts-library/meshjs";
import type { SlotConfig, UTxO } from "@meshsdk/core";
import { beforeAll, describe, expect, it } from "vitest";

import { type Deployment, deployCore } from "../src/cip113/deploy";
import {
  type Account,
  chainNowMs,
  collateralOf,
  devnetSlotConfig,
  fundedAccount,
  lovelaceOf,
  makeProvider,
  newTxBuilderManualExUnits,
  REACHABLE,
  scriptOutputOf,
  signAndSubmit,
  waitForTx,
  waitUntilChainTimeMs,
} from "../src/devnet";

const PRINCIPAL = 1000;
const INTERVAL = 10_000;
const AMOUNTS = [1040];
const VAULT_NFT_NAME = Buffer.from("V0").toString("hex");
const VAULT_NFT_NAME_B = Buffer.from("V1").toString("hex");
const VAULT_ADA = 5_000_000n;
const MIN_ADA = 2_000_000n;
const ORIGIN_NODE: RegistryNode = {
  key: "",
  next: "ff".repeat(30),
  mintingLogic: { kind: "key", hash: "" },
  transferLogic: { kind: "key", hash: "" },
  thirdPartyLogic: { kind: "key", hash: "" },
  unfrackingLogic: { kind: "key", hash: "" },
  globalStateCs: "",
};

describe.skipIf(!REACHABLE)(
  "event_triggered real-core e2e (Yaci devnet)",
  () => {
    let provider: ReturnType<typeof makeProvider>;
    let slotConfig: SlotConfig;
    let deployment: Deployment;

    /** Registry nodes created so far, for the covering-chain inserts. */
    const nodes: { key: string; datum: RegistryNode; utxo: UTxO }[] = [];
    /** Script stake credentials already registered on this devnet. */
    const registeredStakes = new Set<string>();

    beforeAll(async () => {
      provider = makeProvider();
      slotConfig = await devnetSlotConfig();
      // One well-funded payer deploys the core once for every scenario.
      const corePayer = await fundedAccount(
        provider,
        [20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000, 20_000],
      );
      deployment = await deployCore(provider, corePayer);
      nodes.push({
        key: "",
        datum: ORIGIN_NODE,
        utxo: deployment.refs.originNode,
      });
    }, 600_000);

    // --------------------------------------------------------------- helpers

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

    /**
     * Register a module script's stake credential so its withdraw-0 exists.
     * Idempotent: scripts that do not depend on the issuer (e.g. `transfer`)
     * are shared by every bond on the same core.
     */
    async function registerScriptStake(
      payer: Account,
      scriptHash: string,
    ): Promise<void> {
      if (registeredStakes.has(scriptHash)) return;
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
      registeredStakes.add(scriptHash);
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

    /** Unspent UTxOs at `address` carrying `unit`, fresh from the chain. */
    async function utxosHolding(
      address: string,
      unit: string,
    ): Promise<UTxO[]> {
      return (await provider.fetchAddressUTxOs(address)).filter((u) =>
        u.output.amount.some((a) => a.unit === unit),
      );
    }

    /**
     * The single unspent coupon of `amount` at `address`. MeshJS's coin
     * selection may move token UTxOs held in a payer's wallet as fee inputs,
     * so coupons are re-read by unit right before they are used.
     */
    async function couponOf(
      address: string,
      cntPolicy: string,
      amount: number,
    ): Promise<UTxO> {
      const unit = cntPolicy + couponName(amount);
      const [coupon] = await utxosHolding(address, unit);
      if (!coupon) throw new Error(`no coupon ${amount} at ${address}`);
      return coupon;
    }

    /** Apply one bond's scripts and insert its registry node. */
    async function applyRegistered(
      issuer: Account,
      overrides: Partial<BondConfig> = {},
    ): Promise<{ bond: Bond; node: UTxO }> {
      const bond = applyBond(deployment, {
        principal: PRINCIPAL,
        interval: INTERVAL,
        amounts: AMOUNTS,
        issuer: { kind: "key", hash: issuer.keyHash },
        vaultNftName: VAULT_NFT_NAME,
        ...overrides,
      });
      for (const script of bond.withdrawCredentials) {
        await registerScriptStake(issuer, scriptHashOf(script));
      }

      // Registry linked list: cover the greatest key below the new policy.
      const covering = nodes
        .filter((n) => n.key < bond.cipPolicy)
        .sort((a, b) => (a.key < b.key ? -1 : 1))
        .at(-1);
      if (!covering) throw new Error("no covering registry node available");
      const coveringDatum: RegistryNode = {
        ...covering.datum,
        next: bond.cipPolicy,
      };
      const nodeDatum: RegistryNode = {
        key: bond.cipPolicy,
        next: covering.datum.next,
        mintingLogic: { kind: "script", hash: scriptHashOf(bond.issuance) },
        transferLogic: { kind: "script", hash: scriptHashOf(bond.transfer) },
        thirdPartyLogic: {
          kind: "script",
          hash: scriptHashOf(bond.thirdParty),
        },
        unfrackingLogic: { kind: "key", hash: "" },
        globalStateCs: "",
      };

      const f = await fundingOf(issuer);
      const registerTx = await buildRegisterTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        covering: covering.utxo,
        coveringNode: covering.datum,
        funding: f.funding,
        collateral: f.collateral,
        changeAddress: issuer.address,
      });
      const registerHash = await signAndSubmit(issuer, registerTx);
      await waitForTx(provider, registerHash);

      // The covering node is spent and re-emitted; refresh its tracked UTxO.
      covering.utxo = await outputHolding(
        registerHash,
        deployment.core.registryNodeCs + covering.key,
      );
      covering.datum = coveringDatum;

      const node = await outputHolding(
        registerHash,
        deployment.core.registryNodeCs + bond.cipPolicy,
      );
      nodes.push({ key: bond.cipPolicy, datum: nodeDatum, utxo: node });
      return { bond, node };
    }

    /** Mint a vault NFT into a newly funded vault UTxO (§3.1). */
    async function createVault(
      owner: Account,
      bond: Bond,
      nftName: string,
      ada: bigint = VAULT_ADA,
    ): Promise<UTxO> {
      const view: Bond = {
        ...bond,
        config: { ...bond.config, vaultNftName: nftName },
      };
      const f = await fundingOf(owner);
      const tx = await buildCreateVaultTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond: view,
        vaultAda: ada,
        funding: f.funding,
        collateral: f.collateral,
        changeAddress: owner.address,
      });
      const hash = await signAndSubmit(owner, tx);
      await waitForTx(provider, hash);
      return scriptOutputOf(provider, hash, vaultAddress(bond));
    }

    /** A vault-specific view of the bond: its own coupon terms and policy. */
    function vaultView(
      base: Bond,
      terms: { interval: number; amounts: number[] },
    ): Bond {
      const couponPolicy = couponPolicyScript({
        cipPolicy: base.cipPolicy,
        principal: base.config.principal,
        interval: terms.interval,
        amounts: terms.amounts,
      });
      return {
        ...base,
        config: {
          ...base.config,
          interval: terms.interval,
          amounts: terms.amounts,
        },
        couponPolicy,
        cntPolicy: scriptHashOf(couponPolicy),
      };
    }

    /** Permissionless unit deposit (§4.2); returns the step-0 certificate. */
    async function deposit(
      depositor: Account,
      bond: Bond,
      node: UTxO,
      vault: UTxO,
    ): Promise<{ cert: UTxO; vault: UTxO; start: number }> {
      const upperSlot = firstSlotAt((await chainNowMs()) + 30_000);
      const start = slotStartMs(upperSlot);
      const f = await fundingOf(depositor);
      const tx = await buildBondDepositTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        vault,
        depositorStakeHash: depositor.keyHash,
        start,
        validHereafterSlot: upperSlot,
        funding: f.funding,
        collateral: f.collateral,
        changeAddress: depositor.address,
      });
      const hash = await signAndSubmit(depositor, tx);
      await waitForTx(provider, hash);
      const cert = await outputHolding(hash, bond.cipPolicy + stepName(0));
      const vaultAfter = await scriptOutputOf(
        provider,
        hash,
        vaultAddress(bond),
      );
      return { cert, vault: vaultAfter, start };
    }

    /** Burn-to-pay redemption (§4.6); returns the vault continuation. */
    async function redeem(
      payer: Account,
      bond: Bond,
      vault: UTxO,
      coupons: UTxO[],
      payouts: { address: string; amount: bigint }[],
    ): Promise<UTxO> {
      const f = await fundingOf(payer);
      const tx = await buildRedeemTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        vault,
        coupons,
        payouts,
        funding: f.funding,
        collateral: f.collateral,
        changeAddress: payer.address,
      });
      const hash = await signAndSubmit(payer, tx);
      await waitForTx(provider, hash);
      return scriptOutputOf(provider, hash, vaultAddress(bond));
    }

    // ------------------------------------------------------------- owner path

    it("transfers, authorizes, claims, redeems and graduates on the owner path", async () => {
      const issuer = await fundedAccount(provider);
      const holder = await fundedAccount(provider);
      const { bond, node } = await applyRegistered(issuer);
      const issuerPlb = plbAddress(deployment, issuer.keyHash);
      const holderPlb = plbAddress(deployment, holder.keyHash);

      const vault0 = await createVault(issuer, bond, VAULT_NFT_NAME);

      // ---- deposit (§4.2): the issuer deposits, then sells to the holder ---
      const d = await deposit(issuer, bond, node, vault0);
      expect(lovelaceOf(d.vault)).toBe(VAULT_ADA + BigInt(PRINCIPAL));

      const noCommit: CertificateDatum = {
        start: d.start,
        commit: null,
        cntPolicy: bond.cntPolicy,
      };
      const fTransfer = await fundingOf(issuer);
      const transferTx = await buildTransferTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: d.cert,
        recipientAddress: holderPlb,
        outputDatum: noCommit,
        holderStakeHash: issuer.keyHash,
        funding: fTransfer.funding,
        collateral: fTransfer.collateral,
        changeAddress: issuer.address,
      });
      const transferHash = await signAndSubmit(issuer, transferTx);
      await waitForTx(provider, transferHash);
      const heldCert = await outputHolding(
        transferHash,
        bond.cipPolicy + stepName(0),
      );
      const issuerUtxos = await provider.fetchAddressUTxOs(issuerPlb);
      expect(
        issuerUtxos.some((u) =>
          u.output.amount.some((a) => a.unit.startsWith(bond.cipPolicy)),
        ),
      ).toBe(false);

      // ---- authorize (§4.4): commit, then revoke ---------------------------
      const fCommit = await fundingOf(holder);
      const commitTx = await buildAuthorizeTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: heldCert,
        datum: noCommit,
        commit: { kind: "key", hash: holder.keyHash },
        holderStakeHash: holder.keyHash,
        funding: fCommit.funding,
        collateral: fCommit.collateral,
        changeAddress: holder.address,
      });
      const commitHash = await signAndSubmit(holder, commitTx);
      await waitForTx(provider, commitHash);
      const committedCert = await outputHolding(
        commitHash,
        bond.cipPolicy + stepName(0),
      );

      const fRevoke = await fundingOf(holder);
      const revokeTx = await buildAuthorizeTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: committedCert,
        datum: {
          start: d.start,
          commit: { kind: "key", hash: holder.keyHash },
          cntPolicy: bond.cntPolicy,
        },
        commit: null,
        holderStakeHash: holder.keyHash,
        funding: fRevoke.funding,
        collateral: fRevoke.collateral,
        changeAddress: holder.address,
      });
      const revokeHash = await signAndSubmit(holder, revokeTx);
      await waitForTx(provider, revokeHash);
      const cert0 = await outputHolding(
        revokeHash,
        bond.cipPolicy + stepName(0),
      );

      // ---- claim the coupon, step 1 (§4.5) ---------------------------------
      const deadline = d.start + INTERVAL;
      await waitUntilChainTimeMs(deadline);
      const fClaim = await fundingOf(holder);
      const claimTx = await buildClaimOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: cert0,
        step: 1,
        datum: noCommit,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(deadline),
        funding: fClaim.funding,
        collateral: fClaim.collateral,
        changeAddress: holder.address,
      });
      const claimHash = await signAndSubmit(holder, claimTx);
      await waitForTx(provider, claimHash);
      const cert1 = await outputHolding(
        claimHash,
        bond.cipPolicy + stepName(1),
      );
      await outputHolding(claimHash, bond.cntPolicy + couponName(AMOUNTS[0]));

      // ---- redeem the coupon (§4.6), graduate (§4.7), redeem the principal -
      const vaultAfterRedeem = await redeem(
        holder,
        bond,
        d.vault,
        [await couponOf(holder.address, bond.cntPolicy, AMOUNTS[0])],
        [{ address: holder.address, amount: BigInt(AMOUNTS[0]) }],
      );
      expect(lovelaceOf(vaultAfterRedeem)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]),
      );

      const fGrad = await fundingOf(holder);
      const graduateTx = await buildGraduateOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: cert1,
        step: 1,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(deadline),
        funding: fGrad.funding,
        collateral: fGrad.collateral,
        changeAddress: holder.address,
      });
      const graduateHash = await signAndSubmit(holder, graduateTx);
      await waitForTx(provider, graduateHash);
      await outputHolding(graduateHash, bond.cntPolicy + couponName(PRINCIPAL));

      const vaultFinal = await redeem(
        holder,
        bond,
        vaultAfterRedeem,
        [await couponOf(holder.address, bond.cntPolicy, PRINCIPAL)],
        [{ address: holder.address, amount: BigInt(PRINCIPAL) }],
      );
      expect(lovelaceOf(vaultFinal)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]) - BigInt(PRINCIPAL),
      );
      const finalUtxos = await provider.fetchAddressUTxOs(holderPlb);
      expect(finalUtxos.length).toBe(0);
    }, 300_000);

    // ------------------------------------------------------------ issuer path

    it("triggers claims and graduation on the issuer path", async () => {
      const issuer = await fundedAccount(provider);
      const holder = await fundedAccount(provider);
      const payout = await fundedAccount(provider);
      const { bond, node } = await applyRegistered(issuer);
      const holderPlb = plbAddress(deployment, holder.keyHash);

      const vault0 = await createVault(issuer, bond, VAULT_NFT_NAME);
      const d = await deposit(holder, bond, node, vault0);

      // ---- authorize (§4.4): commit the payout key -------------------------
      const committed: CertificateDatum = {
        start: d.start,
        commit: { kind: "key", hash: payout.keyHash },
        cntPolicy: bond.cntPolicy,
      };
      const fAuth = await fundingOf(holder);
      const authTx = await buildAuthorizeTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: d.cert,
        datum: { start: d.start, commit: null, cntPolicy: bond.cntPolicy },
        commit: committed.commit,
        holderStakeHash: holder.keyHash,
        funding: fAuth.funding,
        collateral: fAuth.collateral,
        changeAddress: holder.address,
      });
      const authHash = await signAndSubmit(holder, authTx);
      await waitForTx(provider, authHash);
      const committedCert = await outputHolding(
        authHash,
        bond.cipPolicy + stepName(0),
      );

      // ---- claim_issuer (§4.5): the issuer advances it ---------------------
      const deadline = d.start + INTERVAL;
      await waitUntilChainTimeMs(deadline);
      const fClaim = await fundingOf(issuer);
      const claimTx = await buildClaimIssuerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: committedCert,
        step: 1,
        datum: committed,
        payoutAddress: payout.address,
        validFromSlot: firstSlotAt(deadline),
        funding: fClaim.funding,
        collateral: fClaim.collateral,
        changeAddress: issuer.address,
      });
      const claimHash = await signAndSubmit(issuer, claimTx);
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
        coupon.output.address,
        "the triggered coupon goes to the committed payout",
      ).toBe(payout.address);

      // ---- redeem (the committed wallet holds the coupon) ------------------
      const vaultAfterRedeem = await redeem(
        payout,
        bond,
        d.vault,
        [await couponOf(payout.address, bond.cntPolicy, AMOUNTS[0])],
        [{ address: payout.address, amount: BigInt(AMOUNTS[0]) }],
      );
      expect(lovelaceOf(vaultAfterRedeem)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]),
      );

      // ---- graduate_issuer (§4.7): ghost shell + principal coupon ----------
      const fGrad = await fundingOf(issuer);
      const graduateTx = await buildGraduateIssuerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: cert1,
        step: 1,
        datum: committed,
        payoutAddress: payout.address,
        validFromSlot: firstSlotAt(deadline),
        funding: fGrad.funding,
        collateral: fGrad.collateral,
        changeAddress: issuer.address,
      });
      const graduateHash = await signAndSubmit(issuer, graduateTx);
      await waitForTx(provider, graduateHash);
      await outputHolding(graduateHash, bond.cntPolicy + couponName(PRINCIPAL));
      const shell = await scriptOutputOf(provider, graduateHash, holderPlb);
      const shellAda = lovelaceOf(shell);
      expect(shellAda, "the shell preserves the UTxO's lovelace").toBe(MIN_ADA);
      expect(
        shell.output.amount.some((a) => a.unit.startsWith(bond.cipPolicy)),
        "the shell holds no certificate",
      ).toBe(false);

      // ---- redeem the principal --------------------------------------------
      const vaultFinal = await redeem(
        payout,
        bond,
        vaultAfterRedeem,
        [await couponOf(payout.address, bond.cntPolicy, PRINCIPAL)],
        [{ address: payout.address, amount: BigInt(PRINCIPAL) }],
      );
      expect(lovelaceOf(vaultFinal)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - BigInt(AMOUNTS[0]) - BigInt(PRINCIPAL),
      );
    }, 300_000);

    // -------------------------------------------------------------- multi-vault

    it("supports several vaults with distinct coupon terms", async () => {
      const issuer = await fundedAccount(provider);
      const holder = await fundedAccount(provider);
      const { bond, node } = await applyRegistered(issuer);

      // A second vault with its own coupon terms (same instrument).
      const bondB = vaultView(bond, { interval: 20_000, amounts: [2222] });
      const vaultA = await createVault(issuer, bond, VAULT_NFT_NAME);
      const vaultB = await createVault(issuer, bondB, VAULT_NFT_NAME_B);

      // One deposit into each vault; each certificate binds to its vault.
      const depA = await deposit(holder, bond, node, vaultA);
      const depB = await deposit(holder, bondB, node, vaultB);
      expect(lovelaceOf(depA.vault)).toBe(VAULT_ADA + BigInt(PRINCIPAL));
      expect(lovelaceOf(depB.vault)).toBe(VAULT_ADA + BigInt(PRINCIPAL));

      // Claim both coupons once each vault's own deadline has passed.
      await waitUntilChainTimeMs(
        Math.max(depA.start + 10_000, depB.start + 20_000),
      );
      const datumA: CertificateDatum = {
        start: depA.start,
        commit: null,
        cntPolicy: bond.cntPolicy,
      };
      const datumB: CertificateDatum = {
        start: depB.start,
        commit: null,
        cntPolicy: bondB.cntPolicy,
      };

      const fClaimA = await fundingOf(holder);
      const claimA = await buildClaimOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: depA.cert,
        step: 1,
        datum: datumA,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(depA.start + 10_000),
        funding: fClaimA.funding,
        collateral: fClaimA.collateral,
        changeAddress: holder.address,
      });
      const claimAHash = await signAndSubmit(holder, claimA);
      await waitForTx(provider, claimAHash);
      await outputHolding(claimAHash, bond.cntPolicy + couponName(1040));

      const fClaimB = await fundingOf(holder);
      const claimB = await buildClaimOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond: bondB,
        node,
        certificate: depB.cert,
        step: 1,
        datum: datumB,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(depB.start + 20_000),
        funding: fClaimB.funding,
        collateral: fClaimB.collateral,
        changeAddress: holder.address,
      });
      const claimBHash = await signAndSubmit(holder, claimB);
      await waitForTx(provider, claimBHash);
      await outputHolding(claimBHash, bondB.cntPolicy + couponName(2222));

      // A coupon of vault A cannot be redeemed at vault B: the redemption
      // burns under A's policy (the bond that minted it), so B's coupon policy
      // sees no burned coupons and its vault fails closed (I4/I10). The
      // continuation datum is B's own, so the rejection cannot be a datum
      // mismatch — it proves the two coupon policies are kept separate.
      const fCross = await fundingOf(holder);
      const crossTx = await buildRedeemTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        vault: depB.vault,
        vaultDatum: { cntPolicy: bondB.cntPolicy },
        coupons: [await couponOf(holder.address, bond.cntPolicy, 1040)],
        payouts: [{ address: holder.address, amount: 1040n }],
        funding: fCross.funding,
        collateral: fCross.collateral,
        changeAddress: holder.address,
      });
      await expect(signAndSubmit(holder, crossTx)).rejects.toThrow();

      // Each coupon redeems at its own vault, at its own face value.
      const vaultAAfter = await redeem(
        holder,
        bond,
        depA.vault,
        [await couponOf(holder.address, bond.cntPolicy, 1040)],
        [{ address: holder.address, amount: 1040n }],
      );
      expect(lovelaceOf(vaultAAfter)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - 1040n,
      );
      const vaultBAfter = await redeem(
        holder,
        bondB,
        depB.vault,
        [await couponOf(holder.address, bondB.cntPolicy, 2222)],
        [{ address: holder.address, amount: 2222n }],
      );
      expect(lovelaceOf(vaultBAfter)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - 2222n,
      );
    }, 300_000);

    // --------------------------------------------------------------- negatives

    it("rejects the invariant violations", async () => {
      const issuer = await fundedAccount(provider);
      const holder = await fundedAccount(provider);
      const other = await fundedAccount(provider);
      // N = 2, so retiring at step 1 is "before maturity".
      const { bond, node } = await applyRegistered(issuer, {
        amounts: [1040, 1080],
      });
      const holderPlb = plbAddress(deployment, holder.keyHash);
      const otherPlb = plbAddress(deployment, other.keyHash);

      const vault0 = await createVault(issuer, bond, VAULT_NFT_NAME);
      const d = await deposit(holder, bond, node, vault0);
      const noCommit: CertificateDatum = {
        start: d.start,
        commit: null,
        cntPolicy: bond.cntPolicy,
      };

      // (I3) A claim before its step deadline fails the coupon policy gate.
      const fEarly = await fundingOf(holder);
      const earlyClaim = await buildClaimOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: d.cert,
        step: 1,
        datum: noCommit,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(await chainNowMs()),
        funding: fEarly.funding,
        collateral: fEarly.collateral,
        changeAddress: holder.address,
      });
      await expect(signAndSubmit(holder, earlyClaim)).rejects.toThrow();

      // (I7) An owner change must clear `commit`.
      const fDirty = await fundingOf(holder);
      const dirtyTransfer = await buildTransferTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: d.cert,
        recipientAddress: otherPlb,
        outputDatum: {
          start: d.start,
          commit: { kind: "key", hash: holder.keyHash },
          cntPolicy: bond.cntPolicy,
        },
        holderStakeHash: holder.keyHash,
        funding: fDirty.funding,
        collateral: fDirty.collateral,
        changeAddress: holder.address,
      });
      await expect(signAndSubmit(holder, dirtyTransfer)).rejects.toThrow();

      // ---- claim step 1 honestly, then the remaining negatives -------------
      const deadline1 = d.start + 10_000;
      await waitUntilChainTimeMs(deadline1);

      // (I9) The issuer cannot trigger a certificate without a commitment.
      // The deadline has passed, so only the missing commitment can fail it.
      const fNoCommit = await fundingOf(issuer);
      const triggerNoCommit = await buildClaimIssuerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: d.cert,
        step: 1,
        datum: noCommit,
        payoutAddress: issuer.address,
        validFromSlot: firstSlotAt(deadline1),
        funding: fNoCommit.funding,
        collateral: fNoCommit.collateral,
        changeAddress: issuer.address,
      });
      await expect(signAndSubmit(issuer, triggerNoCommit)).rejects.toThrow();

      const fClaim = await fundingOf(holder);
      const claimTx = await buildClaimOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: d.cert,
        step: 1,
        datum: noCommit,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(deadline1),
        funding: fClaim.funding,
        collateral: fClaim.collateral,
        changeAddress: holder.address,
      });
      const claimHash = await signAndSubmit(holder, claimTx);
      await waitForTx(provider, claimHash);
      const cert1 = await outputHolding(
        claimHash,
        bond.cipPolicy + stepName(1),
      );
      const coupon1 = await outputHolding(
        claimHash,
        bond.cntPolicy + couponName(1040),
      );

      // (I5) Retirement before the final step is refused.
      const fRetire = await fundingOf(holder);
      const earlyRetire = await buildGraduateOwnerTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        node,
        certificate: cert1,
        step: 1,
        couponAddress: holder.address,
        holderStakeHash: holder.keyHash,
        validFromSlot: firstSlotAt(deadline1),
        funding: fRetire.funding,
        collateral: fRetire.collateral,
        changeAddress: holder.address,
      });
      await expect(signAndSubmit(holder, earlyRetire)).rejects.toThrow();

      // (I4) The declared payout must equal the burned value exactly.
      const fOver = await fundingOf(holder);
      const overPayout = await buildRedeemTx({
        txBuilder: newTxBuilderManualExUnits(provider),
        deployment,
        bond,
        vault: d.vault,
        coupons: [coupon1],
        payouts: [{ address: holder.address, amount: 1041n }],
        funding: fOver.funding,
        collateral: fOver.collateral,
        changeAddress: holder.address,
      });
      await expect(signAndSubmit(holder, overPayout)).rejects.toThrow();

      // The rejections left the instrument intact: the honest redemption
      // still pays exactly the coupon's face value.
      const vaultAfter = await redeem(
        holder,
        bond,
        d.vault,
        [await couponOf(holder.address, bond.cntPolicy, 1040)],
        [{ address: holder.address, amount: 1040n }],
      );
      expect(lovelaceOf(vaultAfter)).toBe(
        VAULT_ADA + BigInt(PRINCIPAL) - 1040n,
      );
      expect(
        (await provider.fetchAddressUTxOs(holderPlb)).length,
        "the certificate survives the rejected attempts",
      ).toBe(1);
    }, 300_000);
  },
);
