/**
 * Test harness for driving an ephemeral Cardano devnet from vitest through
 * the official tx3 toolchain.
 *
 * {@linkcode TrixDevnet.start} wipes the protocol's `.tx3` state directory,
 * boots `trix devnet` as a foreground child process (so teardown kills the
 * exact process tree we spawned — no port hunting), waits for a healthcheck
 * against the endpoints trix generates, and returns handles for funding
 * wallets and deploying fixture scripts through real transactions.
 *
 * Wallets are plain Ed25519 enterprise-address keys created fresh per call;
 * the SDK signs for them directly via {@link Party.signer}. Genesis funding
 * comes solely from the committed `settings/devnet.toml`, which funds the
 * fixed throwaway keypair in [`./faucet.ts`](./faucet.ts).
 *
 * Requires the tx3 toolchain (`trix`, and the dolos it spawns) on PATH, or
 * point `TRIX_BIN` at a specific binary.
 */

import { spawn, type ChildProcess } from "node:child_process";
import { connect } from "node:net";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { ed25519 } from "@noble/curves/ed25519";
import { blake2b } from "@noble/hashes/blake2b";
import { bech32 } from "bech32";
import { cst, MeshTxBuilder, serializeRewardAddress } from "@meshsdk/core";
import { Ed25519Signer, Party, PollConfig } from "tx3-sdk";

import { FAUCET } from "./faucet";
import { Client } from "../settings/codegen/ts-client/config-parameter-management/protocol"; // trix codegen ts-client

/** Poll config tuned for the devnet's block interval. */
export const DEVNET_POLL = new PollConfig(60, 1000);

const HERE = dirname(fileURLToPath(import.meta.url));
const BOOT_TIMEOUT_MS = 120_000;

const TRIX_BIN = process.env.TRIX_BIN ?? "trix";

/**
 * Ports trix's embedded dolos template binds (see the `dolos.toml` template
 * shipped in the tx3-lang/trix source, version-locked to the toolchain on
 * PATH). Hardcoded there, so any other dolos devnet running concurrently —
 * or a stale orphan from a crashed run — squats exactly these ports.
 */
const DOLOS_TRP_PORT = 8164;
const DOLOS_MINIBF_PORT = 3164;

/**
 * Env values for TEST KIT transactions.
 *
 * All templates of a protocol share one env block, and the kit templates
 * (`devnet_pay`, `devnet_deploy_authorizer`) reference none of the settings
 * values — these structurally-valid dummies simply satisfy resolvers that
 * require the declared env to be present.
 */
const KIT_ENV = {
  settings_hash: "00",
  settings_script: "00",
  apply_delay: 0,
  proposer_script_ref: "00#0",
  proposer_script_address: "00",
  applier_script_ref: "00#0",
  applier_script_address: "00",
};

/**
 * The test-kit operations a protocol must implement on top of its generated
 * client. Each closure submits a real transaction (funded by the faucet) and
 * resolves only once it is confirmed.
 */
export interface DevnetKit {
  /** Pay lovelace from the faucet to `address` (a `devnet_pay` tx). */
  pay(address: string, quantity: bigint): Promise<void>;
  /** Publish `scriptCode` as a reference script held by `publisherAddress`. */
  deploy(
    publisherAddress: string,
    scriptCode: string,
    lovelace: bigint,
  ): Promise<void>;
  /** Mint protocol tokens (with lovelace) to `address`. Optional. */
  mintTokens?(address: string, quantity: bigint): Promise<void>;
}

/** Builds a {@link DevnetKit} wired to the given TRP endpoint and faucet signer. */
export type DevnetKitFactory = (trpUrl: string, faucet: Party) => DevnetKit;

export interface DevnetStartOptions {
  /** Directory (relative to this file's dir) holding `trix.toml` + `devnet.toml`. */
  protocolRoot: string;
  /** Builds the protocol's test-kit transactions. */
  kit: DevnetKitFactory;
}

/** Default kit: the settings protocol's `devnet_pay` + `devnet_deploy_authorizer`. */
const settingsKit: DevnetKitFactory = (trpUrl, faucet) => ({
  pay: async (address, quantity) => {
    const submitted = await new Client({ endpoint: trpUrl }, "local")
      .withFaucet(faucet)
      .devnetPay({ destination: address, quantity: Number(quantity) })
      .env(KIT_ENV)
      .resolve()
      .then((r) => r.sign())
      .then((s) => s.submit());
    await (await submitted).waitForConfirmed(DEVNET_POLL);
  },
  deploy: async (publisherAddress, scriptCode, lovelace) => {
    const submitted = await new Client({ endpoint: trpUrl }, "local")
      .withFaucet(faucet)
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
    await (await submitted).waitForConfirmed(DEVNET_POLL);
  },
});

/**
 * Read the Shelley genesis trix generated for this boot to build the ledger's
 * linear slot->time mapping: `time(slot) = systemStart + slot * slotLength`.
 */
function shelleySlotConfig(stateDir: string): {
  zeroTimeMs: number;
  slotLengthMs: number;
} {
  const genesis = JSON.parse(
    readFileSync(join(stateDir, "dolos", "shelley.json"), "utf8"),
  ) as {
    systemStart?: string;
    slotLength?: number;
  };
  const zeroTimeMs = Date.parse(genesis.systemStart ?? "");
  if (Number.isNaN(zeroTimeMs))
    throw new Error("generated shelley genesis has no valid systemStart");
  return { zeroTimeMs, slotLengthMs: (genesis.slotLength ?? 1) * 1000 };
}

const toHex = (bytes: Uint8Array): string => Buffer.from(bytes).toString("hex");

/**
 * Strip a single CBOR byte-string wrapper from a hex-encoded script.
 * Some tooling emits a double-CBOR ("cbor") wrapper; the on-chain witness
 * often needs the inner single-CBOR flat script.
 */
export function unwrapCborBytes(hex: string): string {
  const tag = Number.parseInt(hex.slice(0, 2), 16);
  const headerHexLen =
    tag === 0x58 ? 4 : tag === 0x59 ? 6 : tag === 0x5a ? 10 : 0;
  return hex.slice(headerHexLen);
}

/** Enterprise-address network id: 0 = testnet (`addr_test`), 1 = mainnet. */
const NETWORK_ID: number = 0;
const STAKE_REGISTRATION_FEE = 500_000n;

export interface DevnetWallet {
  /** Free-form label; wallets are NOT cached or deduplicated by name. */
  readonly name: string;
  /** Bech32 enterprise address, ready to receive funds via {@link TrixDevnet.payTo}. */
  readonly address: string;
  /** Hex-encoded Blake2b-224 hash of the wallet's public key (payment credential). */
  readonly keyHash: string;
  /** Hex-encoded 32-byte Ed25519 private key backing the wallet. */
  readonly privateKeyHex: string;
  /** SDK party (signer) to bind to a protocol client. */
  readonly party: Party;
}

/** A UTxO living at a devnet address. */
export interface DevnetUtxo {
  /** Transaction id that produced the output. */
  readonly txHash: string;
  /** Index of the output within that transaction. */
  readonly outputIndex: number;
  /** `txHash#outputIndex`, the form tx3 expects for a `UtxoRef`. */
  readonly ref: string;
  /** Lovelace held by the output. */
  readonly lovelace: bigint;
}

/** The current chain tip, as reported by the node. */
export interface ChainTip {
  /** Absolute slot number of the tip. */
  readonly slot: number;
  /** POSIX time of the tip block, in milliseconds. */
  readonly timeMs: number;
  /** Block height of the tip. */
  readonly height: number;
}

/** Extract the listen port of one `[serve.<section>]` from a dolos.toml. */
function servePort(toml: string, section: string): number | undefined {
  const match = toml.match(
    new RegExp(
      `\\[serve\\.${section}\\][^[]*?listen_address\\s*=\\s*"\\[::\\]:(\\d+)"`,
    ),
  );
  return match ? Number(match[1]) : undefined;
}

const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms));

export class TrixDevnet {
  private constructor(
    readonly trpUrl: string,
    private readonly minibfUrl: string,
    private readonly proc: ChildProcess,
    private readonly slotConfig: { zeroTimeMs: number; slotLengthMs: number },
    /** The funded faucet wallet (see [`./faucet.ts`](./faucet.ts)). */
    readonly faucetWallet: DevnetWallet,
    private readonly kit: DevnetKit,
    private readonly stateDir: string,
  ) {}

  /**
   * Boot an ephemeral devnet.
   *
   * Wipes any previous `.tx3` state first, so every run gets a genuinely
   * fresh chain (fresh genesis, fresh stake registrations, no leftover NFTs).
   *
   * Defaults to the settings protocol when called with no arguments; pass
   * `{ protocolRoot, kit }` to boot a different protocol (e.g. `dao`).
   */
  static async start(options?: DevnetStartOptions): Promise<TrixDevnet> {
    const protocolRoot = join(HERE, "..", options?.protocolRoot ?? "settings");
    const stateDir = join(protocolRoot, ".tx3");
    const kit = options?.kit ?? settingsKit;
    rmSync(stateDir, { recursive: true, force: true });

    // Pre-flight: trix writes its dolos config with FIXED ports and spawns
    // the node immediately, so a port conflict can only be caught up front.
    for (const port of [DOLOS_TRP_PORT, DOLOS_MINIBF_PORT]) {
      if (await portInUse(port)) {
        throw new Error(
          `localhost:${port} is already in use: another trix devnet is ` +
            `running, or a stale dolos was left behind by a crashed run. ` +
            `Stop it before booting a new devnet.`,
        );
      }
    }

    // Foreground child: killing the process group below takes trix AND its
    // dolos down together.
    const proc = spawn(TRIX_BIN, ["devnet", "--config", "devnet.toml"], {
      cwd: protocolRoot,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let log = "";
    const capture = (chunk: Buffer): void => {
      log += chunk.toString();
      if (log.length > 16_384) log = log.slice(-16_384);
      if (process.env.DEBUG_TRIX) process.stderr.write(`[trix] ${chunk}`);
    };
    proc.stdout?.on("data", capture);
    proc.stderr?.on("data", capture);

    let exited:
      | { code: number | null; signal: NodeJS.Signals | null }
      | undefined;
    let spawnError: Error | undefined;
    proc.on("exit", (code, signal) => {
      exited = { code, signal };
    });
    // spawn emits `error` (not `exit`) when the binary is missing/unexecutable;
    // capture it so startup fails fast instead of polling until the timeout.
    proc.on("error", (err) => {
      spawnError = err;
    });

    const fail = (message: string): Error => {
      try {
        process.kill(-proc.pid!, "SIGKILL");
      } catch {
        // already gone
      }
      rmSync(stateDir, { recursive: true, force: true });
      return new Error(`${message}\n${log}`);
    };

    const deadline = Date.now() + BOOT_TIMEOUT_MS;
    let trpPort: number | undefined;
    let minibfPort: number | undefined;

    for (;;) {
      if (spawnError)
        throw fail(`failed to spawn ${TRIX_BIN}: ${spawnError.message}`);
      if (exited)
        throw fail(
          `trix devnet exited during boot (code=${exited.code}, signal=${exited.signal})`,
        );

      const tomlPath = join(stateDir, "dolos", "dolos.toml");
      if (!trpPort && existsSync(tomlPath)) {
        const toml = readFileSync(tomlPath, "utf8");
        trpPort = servePort(toml, "trp");
        minibfPort = servePort(toml, "minibf");
      }

      if (trpPort && minibfPort) {
        const healthy = await healthcheck(minibfPort, trpPort);
        if (healthy) break;
      }

      if (Date.now() > deadline)
        throw fail(
          `trix devnet did not become healthy within ${BOOT_TIMEOUT_MS}ms`,
        );
      await sleep(500);
    }

    const trpUrl = `http://localhost:${trpPort}`;
    const minibfUrl = `http://localhost:${minibfPort}`;

    // Rebuild the faucet wallet object from the committed fixture literals.
    const privateKey = Buffer.from(FAUCET.privateKeyHex, "hex");
    const publicKey = ed25519.getPublicKey(privateKey);
    const addr = enterpriseAddress(publicKey);
    const faucetSignerParty = Party.signer(
      Ed25519Signer.fromHex(FAUCET.address, FAUCET.privateKeyHex),
    );

    return new TrixDevnet(
      trpUrl,
      minibfUrl,
      proc,
      shelleySlotConfig(stateDir),
      {
        name: "faucet",
        address: FAUCET.address,
        keyHash: addr.keyHash,
        privateKeyHex: FAUCET.privateKeyHex,
        party: faucetSignerParty,
      },
      kit(trpUrl, faucetSignerParty),
      stateDir,
    );
  }

  /**
   * A fresh random wallet. Every call returns independent keys — hold onto
   * the returned object; looking up "the same" name again yields a different
   * (unfunded) wallet.
   */
  wallet(name: string): DevnetWallet {
    const privateKey = randomBytes(32);
    const publicKey = ed25519.getPublicKey(privateKey);
    const addr = enterpriseAddress(publicKey);
    const privateKeyHex = toHex(privateKey);
    return {
      name,
      address: addr.bech32,
      keyHash: addr.keyHash,
      privateKeyHex,
      party: Party.signer(Ed25519Signer.fromHex(addr.bech32, privateKeyHex)),
    };
  }

  /**
   * Pay lovelace from the faucet to `address` through a real `devnet_pay`
   * transaction. Calls are serialized because the live faucet holds exactly
   * one spendable UTxO at a time (each payment refunds change to itself).
   */
  payTo(address: string, lovelace: bigint): Promise<void> {
    return this.enqueue(() => this.kit.pay(address, lovelace));
  }

  /**
   * Mint protocol tokens (with lovelace) to `address` through the kit's
   * `mintTokens`. Also serialized against the faucet. No-op if the kit does
   * not implement it.
   */
  mintTokensTo(address: string, quantity: bigint): Promise<void> {
    return this.enqueue(
      async () => await this.kit.mintTokens?.(address, quantity),
    );
  }

  private queue: Promise<void> = Promise.resolve();

  /** Serialize faucet-funded operations (the faucet holds one spendable UTxO). */
  private enqueue<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.queue.then(fn, fn);
    this.queue = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }

  /**
   * Publish `scriptCode` (hex-encoded Plutus V3 flat script) as a reference
   * script held by `publisherAddress`, through a real `cardano::publish`
   * transaction funded by the faucet. Returns the reference-script UTxO,
   * discovered as the output that appeared at the publisher address.
   */
  async deployReferenceScript(p: {
    publisherAddress: string;
    scriptCode: string;
    /** Lovelace attached to the reference-script output. */
    lovelace: bigint;
  }): Promise<DevnetUtxo> {
    if (
      !/^(?:[0-9a-fA-F]{2})+$/.test(p.scriptCode) ||
      p.scriptCode.length < 2
    ) {
      throw new Error("scriptCode must be non-empty hexadecimal");
    }
    const before = new Set(
      (await this.utxosOf(p.publisherAddress)).map((u) => u.ref),
    );
    await this.enqueue(() =>
      this.kit.deploy(p.publisherAddress, p.scriptCode, p.lovelace),
    );
    const added = (await this.utxosOf(p.publisherAddress)).find(
      (u) => !before.has(u.ref),
    );
    if (!added)
      throw new Error(
        `reference-script deploy confirmed but no new UTxO appeared at ${p.publisherAddress}`,
      );
    return added;
  }

  /** Total lovelace held at an address (0 if the address has no UTxOs). */
  async lovelaceBalanceOf(address: string): Promise<{ lovelace: bigint }> {
    const res = await fetch(`${this.minibfUrl}/addresses/${address}`);
    if (res.status === 404) return { lovelace: 0n };
    if (!res.ok)
      throw new Error(
        `balance query failed for ${address}: HTTP ${res.status}`,
      );
    const body = (await res.json()) as {
      amount?: Array<{ unit: string; quantity: string }>;
    };
    const lovelace = (body.amount ?? [])
      .filter((a) => a.unit === "lovelace")
      .reduce((sum, a) => sum + BigInt(a.quantity), 0n);
    return { lovelace };
  }

  /** UTxOs currently held at an address (empty if it has none). */
  async utxosOf(address: string): Promise<DevnetUtxo[]> {
    const res = await fetch(`${this.minibfUrl}/addresses/${address}/utxos`);
    if (res.status === 404) return [];
    if (!res.ok)
      throw new Error(`utxo query failed for ${address}: HTTP ${res.status}`);
    const body = (await res.json()) as Array<{
      tx_hash: string;
      output_index: number;
      amount?: Array<{ unit: string; quantity: string }>;
    }>;
    return body.map((u) => ({
      txHash: u.tx_hash,
      outputIndex: u.output_index,
      ref: `${u.tx_hash}#${u.output_index}`,
      lovelace: (u.amount ?? [])
        .filter((a) => a.unit === "lovelace")
        .reduce((sum, a) => sum + BigInt(a.quantity), 0n),
    }));
  }

  /** The first UTxO of `wallet`, suitable as a tx seed. Throws if unfunded. */
  async seedUtxo(wallet: DevnetWallet): Promise<DevnetUtxo> {
    const utxos = await this.utxosOf(wallet.address);
    const seed = utxos[0];
    if (!seed)
      throw new Error(`wallet ${wallet.name} has no UTxOs to use as a seed`);
    return seed;
  }

  /**
   * Register a script stake credential so its withdraw-0 reward account
   * exists. `payer` must already be funded ({@link TrixDevnet.payTo}).
   */
  async registerScriptStakeCredential(
    payer: DevnetWallet,
    scriptHash: string,
  ): Promise<void> {
    const utxos = await this.utxosOf(payer.address);
    const input = utxos[0];
    if (!input)
      throw new Error(`wallet ${payer.name} has no UTxO to fund registration`);
    const change = input.lovelace - STAKE_REGISTRATION_FEE;
    if (change < 1_000_000n) {
      throw new Error(
        `wallet ${payer.name} has insufficient funds for registration`,
      );
    }

    const tx = new MeshTxBuilder()
      .registerStakeCertificate(
        serializeRewardAddress(scriptHash, true, NETWORK_ID as 0),
      )
      .txIn(
        input.txHash,
        input.outputIndex,
        [{ unit: "lovelace", quantity: input.lovelace.toString() }],
        payer.address,
      )
      .txOut(payer.address, [{ unit: "lovelace", quantity: change.toString() }])
      .setFee(STAKE_REGISTRATION_FEE.toString())
      .changeAddress(payer.address)
      .selectUtxosFrom([
        {
          input: { txHash: input.txHash, outputIndex: input.outputIndex },
          output: {
            address: payer.address,
            amount: [{ unit: "lovelace", quantity: input.lovelace.toString() }],
          },
        },
      ])
      .completeSync();
    const parsed = cst.deserializeTx(tx);
    const body = parsed.body().toCbor();
    const signer = Ed25519Signer.fromHex(payer.address, payer.privateKeyHex);
    const witness = await signer.sign({
      txHashHex: parsed.getId(),
      txCborHex: body,
    });
    const submitted = await this.trpSubmit(tx, witness);
    await this.waitForConfirmed(submitted.hash);
  }

  /** Raw TRP submission for hand-built transactions (Mesh paths). */
  private async trpSubmit(tx: string, witness: unknown) {
    const res = await fetch(this.trpUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "trp.submit",
        params: {
          tx: { content: tx, contentType: "hex" },
          witnesses: [witness],
        },
      }),
    });
    if (!res.ok) throw new Error(`TRP submit failed: HTTP ${res.status}`);
    const body = (await res.json()) as {
      error?: { message?: string };
      result?: unknown;
    };
    if (body.error) throw new Error(`TRP submit failed: ${body.error.message}`);
    return body.result as { hash: string };
  }

  /** Poll TRP until the transaction reaches a confirmed stage (or drop out). */
  private async waitForConfirmed(txHash: string): Promise<void> {
    for (let attempt = 0; attempt < DEVNET_POLL.attempts; attempt++) {
      const status = await this.trpCall<{
        statuses: Record<string, { stage?: string }>;
      }>("trp.checkStatus", { hashes: [txHash] });
      const stage = status.statuses[txHash]?.stage;
      if (stage === "confirmed" || stage === "finalized") return;
      if (stage === "dropped")
        throw new Error(`transaction ${txHash} was dropped`);
      await sleep(DEVNET_POLL.delayMs);
    }
    throw new Error(`transaction ${txHash} was not confirmed`);
  }

  private async trpCall<T>(method: string, params: unknown): Promise<T> {
    const res = await fetch(this.trpUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    if (!res.ok) throw new Error(`TRP ${method} failed: HTTP ${res.status}`);
    const body = (await res.json()) as {
      error?: { message?: string };
      result?: T;
    };
    if (body.error)
      throw new Error(`TRP ${method} failed: ${body.error.message}`);
    if (body.result === undefined)
      throw new Error(`TRP ${method} returned no result`);
    return body.result;
  }

  /**
   * The current chain tip. `timeMs` is the *ledger* time of the tip slot
   * (`systemStart + slot * slotLength`) — the exact value a validator sees
   * as the validity lower bound — not dolos's reported `block.time`.
   */
  async tip(): Promise<ChainTip> {
    const res = await fetch(`${this.minibfUrl}/blocks/latest`);
    if (!res.ok) throw new Error(`tip query failed: HTTP ${res.status}`);
    const b = (await res.json()) as { slot?: number; height?: number };
    const slot = b.slot ?? 0;
    const timeMs =
      this.slotConfig.zeroTimeMs + slot * this.slotConfig.slotLengthMs;
    return { slot, timeMs, height: b.height ?? 0 };
  }

  /**
   * The enclosing slot whose interval contains `targetMs` (POSIX ms) — the
   * slot a validity bound must use for a validator reading that instant.
   */
  slotAtTimeMs(targetMs: number): number {
    return Math.floor(
      (targetMs - this.slotConfig.zeroTimeMs) / this.slotConfig.slotLengthMs,
    );
  }

  /** Poll until the chain's tip time reaches `targetMs` (or throw on timeout). */
  async waitForChainTimeMs(
    targetMs: number,
    timeoutSeconds = 90,
  ): Promise<void> {
    const deadline = Date.now() + timeoutSeconds * 1000;
    for (;;) {
      if ((await this.tip()).timeMs >= targetMs) return;
      if (Date.now() > deadline) {
        throw new Error(
          `chain time did not reach ${targetMs}ms within ${timeoutSeconds}s`,
        );
      }
      await sleep(1000);
    }
  }

  /** Stop the node (and its whole process tree) and remove trix's state. */
  stop(): void {
    try {
      process.kill(-this.proc.pid!, "SIGTERM");
    } catch {
      // already gone
    }
    rmSync(this.stateDir, { recursive: true, force: true });
  }
}

/** Whether any process is listening on the given localhost TCP port. */
function portInUse(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = connect(port, "127.0.0.1");
    socket.once("connect", () => {
      socket.destroy();
      resolve(true);
    });
    socket.once("error", () => resolve(false));
  });
}

/**
 * Confirm the discovered endpoints actually belong to OUR freshly booted
 * services: minibf must report a producing chain (height >= 1), and the TRP
 * port must answer with a JSON-RPC envelope. NOTE: this CANNOT distinguish
 * our node from a foreign dolos — any dolos answers identically — so the
 * pre-flight port check in {@linkcode TrixDevnet.start} is what guards
 * against squatters; this only confirms the endpoints are live.
 */
async function healthcheck(
  minibfPort: number,
  trpPort: number,
): Promise<boolean> {
  try {
    const blocks = await fetch(`http://localhost:${minibfPort}/blocks/latest`, {
      signal: AbortSignal.timeout(2000),
    });
    if (!blocks.ok) return false;
    const tip = (await blocks.json()) as { height?: number };
    if ((tip.height ?? 0) < 1) return false;

    const trp = await fetch(`http://localhost:${trpPort}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 0,
        method: "trp.checkStatus",
        params: { hashes: [] },
      }),
      signal: AbortSignal.timeout(2000),
    });
    if (!trp.ok) return false;
    const envelope = (await trp.json()) as { jsonrpc?: string };
    return envelope.jsonrpc === "2.0";
  } catch {
    return false;
  }
}

/** Enterprise address (bytes + bech32 + key hash) for an Ed25519 public key. */
function enterpriseAddress(publicKey: Uint8Array): {
  bytes: Uint8Array;
  bech32: string;
  keyHash: string;
} {
  const keyHash = blake2b(publicKey, { dkLen: 28 });
  const bytes = new Uint8Array(29);
  bytes[0] = 0x60 | (NETWORK_ID & 0x0f); // type 6 (enterprise, key credential)
  bytes.set(keyHash, 1);
  const hrp = NETWORK_ID === 1 ? "addr" : "addr_test";
  return {
    bytes,
    bech32: bech32.encode(hrp, bech32.toWords(bytes), 1023),
    keyHash: toHex(keyHash),
  };
}
