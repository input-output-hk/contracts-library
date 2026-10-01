/**
 * End-to-end tests for the smart wallet Tx3 protocol against an ephemeral
 * trix/dolos devnet.
 *
 * Coverage is the wallet's *core lifecycle*: the on-chain multivalidator with
 * an empty delegated-withdrawals map, where the only spend authorization is the
 * base M-of-N floor read from a settings reference input:
 *
 *   - happy path: settings launch -> mint -> deposit -> spend -> update
 *     config -> close;
 *   - attack paths: each negative transaction must fail phase-2 validation for
 *     the right reason and leave the wallet UTxO untouched.
 *
 * Delegated withdrawal scripts are out of scope for Tx3 until upstream gains
 * registration/unregistration certificate blocks
 * (https://github.com/tx3-lang/tx3/issues/164): the wallet's `Mint` /
 * `UpdateConfig` / `Close` endpoints require `RegisterCredential` /
 * `UnregisterCredential` certificates in the same transaction, which the Tx3
 * v1beta0 language cannot express. See `../README.md`.
 */

import { afterAll, beforeAll, expect, test } from "vitest";
import {
  DEVNET_POLL,
  TrixDevnet,
  unwrapCborBytes,
  type DevnetKitFactory,
  type DevnetUtxo,
  type DevnetWallet,
} from "../../devnet/utils";
import {
  SETTINGS_TOKEN_NAME,
  settingsScript,
  settingsScriptAddress,
  smartWalletScript,
  smartWalletScriptAddress,
  type SettingsParams,
  type WalletParams,
} from "@contracts-library/meshjs";
import { Party, type SubmittedTx, type TxBuilder } from "tx3-sdk";
import { resolveScriptHash } from "@meshsdk/core";
import {
  Client,
  type WalletConfig as Tx3WalletConfig,
} from "../codegen/ts-client/smart-wallet/protocol";

const ADA = 1_000_000n;
const WALLET_TOKEN_NAME = "57414c4c4554"; // hex "WALLET"
const APPLY_DELAY = 4_000;

// Per-test funding: the settings seed, the wallet seed, and separate gas and
// collateral splits for every signer (a Plutus transaction needs pure-ADA
// collateral that is not also a spending input).
const SETTINGS_SEED = 5n * ADA;
const WALLET_SEED = 5n * ADA;
const GAS = 10n * ADA;
const COLLATERAL = 5n * ADA;

const toBytes = (hex: string): Uint8Array => Buffer.from(hex, "hex");

/** A key credential in the `Credential` variant's encoding (Constr 0 [hash]). */
const keyCred = (keyHash: string) => ({ Key: { hash: toBytes(keyHash) } });

/**
 * Dummy env satisfying the protocol's declared env for test-kit transactions.
 * The kit templates (`devnet_pay`, `devnet_deploy_authorizer`) reference none
 * of the wallet values, so structurally-valid dummies suffice.
 */
const KIT_ENV = {
  wallet_hash: "00",
  wallet_script: "00",
  wallet_token_name: WALLET_TOKEN_NAME,
  settings_hash: "00",
  settings_script: "00",
};

const smartWalletKit: DevnetKitFactory = (trpUrl, faucet) => {
  const kitClient = (): Client =>
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
          // Runtime args are snake_case; the generated param type says camelCase.
          script_code: Buffer.from(scriptCode, "hex"),
          lovelace: Number(lovelace),
        } as unknown as Parameters<Client["devnetDeployAuthorizer"]>[0])
        .env(KIT_ENV)
        .resolve()
        .then((r) => r.sign())
        .then((s) => s.submit());
      await submitted.waitForConfirmed(DEVNET_POLL);
    },
  };
};

let devnet: TrixDevnet;

beforeAll(async () => {
  devnet = await TrixDevnet.start({
    protocolRoot: "smart_wallet",
    kit: smartWalletKit,
  });
}, 180_000);

afterAll(() => devnet.stop());

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

/**
 * A rejected attack must fail for the RIGHT reason (ledger phase-2 script
 * failure surfaced through TRP) and must leave the guarded wallet UTxO
 * unspent — a generic throw would also catch unrelated build-time failures and
 * prove nothing about the validator.
 */
async function expectAttackRejected(
  attack: Promise<unknown>,
  guardAddress: string,
  guard: DevnetUtxo,
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
  const stillThere = (await devnet.utxosOf(guardAddress)).some(
    (u) => u.ref === guard.ref,
  );
  expect(stillThere, `guarded wallet ${guard.ref} was spent`).toBe(true);
}

// The tx3 template's runtime arg names are snake_case, but the generated params
// types mistakenly declare camelCase — cast past them at each call site.
type LaunchSettingsArgs = Parameters<Client["launchSettings"]>[0];
type MintWalletArgs = Parameters<Client["mintWallet"]>[0];
type DepositArgs = Parameters<Client["deposit"]>[0];
type SpendArgs = Parameters<Client["spend"]>[0];
type UpdateConfigArgs = Parameters<Client["updateConfig"]>[0];
type CloseArgs = Parameters<Client["close"]>[0];
type DepositRemovingValueAttackArgs = Parameters<
  Client["depositRemovingValueAttack"]
>[0];
type DepositChangedDatumAttackArgs = Parameters<
  Client["depositChangedDatumAttack"]
>[0];
type UpdateConfigNonAdminAttackArgs = Parameters<
  Client["updateConfigNonAdminAttack"]
>[0];
type SpendWithoutMemberSignatureAttackArgs = Parameters<
  Client["spendWithoutMemberSignatureAttack"]
>[0];

/** Runtime env overrides for the values baked into the `local` profile. */
type InstanceEnv = {
  wallet_hash: string;
  wallet_script: string;
  wallet_token_name: string;
  settings_hash: string;
  settings_script: string;
};

interface Instance {
  admin: DevnetWallet;
  depositor: DevnetWallet;
  member: DevnetWallet;
  client: Client;
  env: InstanceEnv;
  walletAddr: string;
  settingsAddr: string;
  /** `txHash#index` of the settings UTxO consumed as the M-of-N reference. */
  settingsRef: string;
  /** The minted wallet UTxO. */
  wallet: DevnetUtxo;
}

/**
 * Launch a settings instance holding a 1-of-1 wallet config and mint a wallet
 * whose depositor is the test's `depositor` key.
 */
async function setup(): Promise<Instance> {
  const admin = devnet.wallet("admin");
  const depositor = devnet.wallet("depositor");
  const member = devnet.wallet("member");

  await devnet.payTo(admin.address, SETTINGS_SEED);
  await devnet.payTo(admin.address, WALLET_SEED);
  await devnet.payTo(admin.address, GAS);
  await devnet.payTo(depositor.address, GAS);
  await devnet.payTo(depositor.address, COLLATERAL);
  await devnet.payTo(member.address, GAS);
  await devnet.payTo(member.address, COLLATERAL);

  const adminUtxos = await devnet.utxosOf(admin.address);
  const settingsSeed = adminUtxos[0];
  const walletSeed = adminUtxos[1];
  if (!settingsSeed || !walletSeed) {
    throw new Error("admin funding did not produce two seed UTxOs");
  }

  // The M-of-N config the wallet reads from its settings reference input.
  // Use the generated client's type: the Tx3 wire form carries the members as
  // bytes, unlike the MeshJS mirror (hex strings).
  const walletConfig: Tx3WalletConfig = {
    members: [toBytes(member.keyHash)],
    threshold: 1,
  };

  const settingsParams: SettingsParams = {
    seedUtxo: {
      txHash: settingsSeed.txHash,
      outputIndex: settingsSeed.outputIndex,
    },
    proposeAuth: { kind: "key", hash: admin.keyHash },
    applyAuth: { kind: "key", hash: admin.keyHash },
    applyDelay: APPLY_DELAY,
    settingsTokenName: SETTINGS_TOKEN_NAME,
  };
  const settings = settingsScript(settingsParams);
  const settingsHash = resolveScriptHash(settings.code, settings.version);
  const settingsAddr = settingsScriptAddress(settings);

  const walletParams: WalletParams = {
    seedUtxo: {
      txHash: walletSeed.txHash,
      outputIndex: walletSeed.outputIndex,
    },
    settingsPolicy: settingsHash,
    settingsTokenName: SETTINGS_TOKEN_NAME,
    walletTokenName: WALLET_TOKEN_NAME,
    admin: { kind: "key", hash: admin.keyHash },
  };
  const walletScript = smartWalletScript(walletParams);
  const walletHash = resolveScriptHash(walletScript.code, walletScript.version);
  const walletAddr = smartWalletScriptAddress(walletScript);

  const env: InstanceEnv = {
    wallet_hash: walletHash,
    // Must be the single-CBOR flat script (the mint/spend witness);
    // `applyParamsToScript` returns a double-CBOR wrapper, so strip one layer.
    wallet_script: unwrapCborBytes(walletScript.code),
    wallet_token_name: WALLET_TOKEN_NAME,
    settings_hash: settingsHash,
    settings_script: unwrapCborBytes(settings.code),
  };

  const client = new Client({ endpoint: devnet.trpUrl }, "local")
    .withAdmin(admin.party)
    .withDepositor(depositor.party)
    .withMember(member.party)
    .withWallet(Party.address(walletAddr))
    .withSettings(Party.address(settingsAddr));

  // 1. Launch the settings instance holding the M-of-N config.
  await confirm(
    client
      .launchSettings({
        seed: settingsSeed.ref,
        wallet_config: walletConfig,
        out_ix: 0,
      } as unknown as LaunchSettingsArgs)
      .env(env),
  );
  const settingsUtxo = (await devnet.utxosOf(settingsAddr))[0];
  if (!settingsUtxo) {
    throw new Error("settings UTxO not found after launch");
  }

  // 2. Create the wallet: spend the one-shot seed, mint the wallet NFT.
  await confirm(
    client
      .mintWallet({
        seed: walletSeed.ref,
        depositor: keyCred(depositor.keyHash),
        out_ix: 0,
      } as unknown as MintWalletArgs)
      .env(env),
  );
  const wallet = (await devnet.utxosOf(walletAddr))[0];
  if (!wallet) {
    throw new Error("wallet UTxO not found after mint");
  }

  return {
    admin,
    depositor,
    member,
    client,
    env,
    walletAddr,
    settingsAddr,
    settingsRef: settingsUtxo.ref,
    wallet,
  };
}

// ------------------------------------------------------------- happy path

test("mints, deposits, spends, updates config, and closes", async () => {
  const ctx = await setup();

  // 1. Deposit adds funds and preserves the wallet.
  const beforeDeposit = await devnet.lovelaceBalanceOf(ctx.walletAddr);
  await confirm(
    ctx.client
      .deposit({
        deposit_ada: Number(ADA),
        out_ix: 0,
      } as unknown as DepositArgs)
      .env(ctx.env),
  );
  const afterDeposit = await devnet.lovelaceBalanceOf(ctx.walletAddr);
  expect(afterDeposit.lovelace).toBe(beforeDeposit.lovelace + ADA);

  // 2. Spend: the single member signs and the wallet continues.
  await confirm(
    ctx.client
      .spend({
        settings_ref: ctx.settingsRef,
        payout_address: ctx.member.address,
        payout_ada: Number(ADA),
      } as unknown as SpendArgs)
      .env(ctx.env),
  );
  const afterSpend = await devnet.lovelaceBalanceOf(ctx.walletAddr);
  expect(afterSpend.lovelace).toBe(afterDeposit.lovelace - ADA);

  // 3. UpdateConfig: the admin rewrites the depositor.
  await confirm(
    ctx.client
      .updateConfig({
        new_depositor: keyCred(ctx.admin.keyHash),
        out_ix: 0,
      } as unknown as UpdateConfigArgs)
      .env(ctx.env),
  );
  expect(await devnet.utxosOf(ctx.walletAddr)).toHaveLength(1);

  // 4. Close: burn the NFT and tear the wallet down.
  await confirm(ctx.client.close({} as CloseArgs).env(ctx.env));
  expect(await devnet.utxosOf(ctx.walletAddr)).toHaveLength(0);
}, 240_000);

// ------------------------------------------------------------ attack paths

test("rejects unauthorized and malformed wallet transactions", async () => {
  const ctx = await setup();
  const guard = ctx.wallet;

  // A non-member (the admin) cannot satisfy the M-of-N floor.
  await expectAttackRejected(
    submit(
      ctx.client
        .spendWithoutMemberSignatureAttack({
          settings_ref: ctx.settingsRef,
          payout_address: ctx.member.address,
          payout_ada: Number(ADA),
        } as unknown as SpendWithoutMemberSignatureAttackArgs)
        .env(ctx.env),
    ),
    ctx.walletAddr,
    guard,
  );

  // A deposit cannot remove value...
  await expectAttackRejected(
    submit(
      ctx.client
        .depositRemovingValueAttack({
          out_ix: 0,
        } as unknown as DepositRemovingValueAttackArgs)
        .env(ctx.env),
    ),
    ctx.walletAddr,
    guard,
  );

  // ...nor rewrite the datum.
  await expectAttackRejected(
    submit(
      ctx.client
        .depositChangedDatumAttack({
          other_depositor: keyCred(ctx.admin.keyHash),
          out_ix: 0,
        } as unknown as DepositChangedDatumAttackArgs)
        .env(ctx.env),
    ),
    ctx.walletAddr,
    guard,
  );

  // A non-admin (a member) cannot rewrite the config.
  await expectAttackRejected(
    submit(
      ctx.client
        .updateConfigNonAdminAttack({
          new_depositor: keyCred(ctx.admin.keyHash),
          out_ix: 0,
        } as unknown as UpdateConfigNonAdminAttackArgs)
        .env(ctx.env),
    ),
    ctx.walletAddr,
    guard,
  );

  // Closing must burn the wallet NFT.
  await expectAttackRejected(
    submit(ctx.client.closeWithoutBurnAttack({}).env(ctx.env)),
    ctx.walletAddr,
    guard,
  );

  // The wallet survived every rejected attack.
  expect(await devnet.utxosOf(ctx.walletAddr)).toHaveLength(1);
}, 240_000);
