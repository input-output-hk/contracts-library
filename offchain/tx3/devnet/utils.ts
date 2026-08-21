/**
 * Test harness for driving an ephemeral Cardano devnet from vitest, mirroring
 * what `trix test <file>.toml` does but letting the test body drive the protocol
 * through the generated tx3 TypeScript client instead of a declarative TOML.
 *
 * `TestDevnet.start(...)` boots a throwaway {@link https://github.com/txpipe/dolos | Dolos}
 * node (the same engine `trix devnet` uses) in a temp directory:
 *   - genesis comes from the committed static template in `devnet/genesis`,
 *   - each requested wallet is funded with one or more UTxOs (`custom_utxos`),
 *   - the node serves TRP (for the SDK), minibf (for balance queries) and gRPC.
 *
 * The wallets are plain Ed25519 enterprise-address keys owned by the harness, so
 * the SDK can sign for them directly via {@link Party.signer}. Each devnet gets
 * its own fresh in-memory chain and its own free ports, so test files never
 * pollute each other.
 *
 * Requires the `dolos` binary on `PATH`, at `DOLOS_BIN`, or under the tx3
 * toolchain (`~/.tx3/<channel>/bin/dolos`, installed by `tx3up`).
 */

import { spawn, type ChildProcess } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import net from "node:net";
import os from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { ed25519 } from "@noble/curves/ed25519";
import { blake2b } from "@noble/hashes/blake2b";
import { bech32 } from "bech32";
import {
  cst,
  MeshTxBuilder,
  serializeRewardAddress,
} from "@meshsdk/core";
import { Ed25519Signer, Party, PollConfig } from "tx3-sdk";

/** Poll config tuned for the devnet's 1s block interval. */
export const DEVNET_POLL = new PollConfig(60, 1000);

const HERE = dirname(fileURLToPath(import.meta.url));
const GENESIS_DIR = join(HERE, "genesis");
const GENESIS_FILES = [
  "byron.json",
  "shelley.json",
  "alonzo.json",
  "conway.json",
] as const;

/**
 * Read the Shelley genesis to build the ledger's linear slot->time mapping:
 * `time(slot) = systemStart + slot * slotLength`. Devnets start at slot 0, so
 * `zeroTime` is simply the system start.
 */
function shelleySlotConfig(): { zeroTimeMs: number; slotLengthMs: number } {
  const genesis = JSON.parse(
    readFileSync(join(GENESIS_DIR, "shelley.json"), "utf8"),
  ) as {
    systemStart?: string;
    slotLength?: number;
  };
  const zeroTimeMs = Date.parse(genesis.systemStart ?? "");
  if (Number.isNaN(zeroTimeMs))
    throw new Error("shelley genesis has no valid systemStart");
  return { zeroTimeMs, slotLengthMs: (genesis.slotLength ?? 1) * 1000 };
}

/** Enterprise-address network id: 0 = testnet (`addr_test`), 1 = mainnet. */
const NETWORK_ID: number = 0;
const STAKE_REGISTRATION_FEE = 500_000n;

export interface DevnetOptions {
  /**
   * Wallet name -> starting balance in lovelace. Pass an array to fund the
   * wallet with several UTxOs (e.g. a seed plus a separate collateral UTxO,
   * which Plutus transactions require).
   */
  wallets: Record<string, bigint | number | Array<bigint | number>>;
  /** Named Plutus V3 scripts seeded as reference-script UTxOs. */
  referenceScripts?: Record<
    string,
    {
      /** Wallet whose address receives the reference script UTxO. */
      owner: string;
      /** Raw single-CBOR Plutus V3 flat script bytes. */
      scriptCode: string;
      /** Lovelace locked with the reference script (default: 2 ADA). */
      lovelace?: bigint | number;
    }
  >;
  /** Seconds between produced blocks (default 1). */
  blockIntervalSeconds?: number;
  /** Max seconds to wait for the node to start serving (default 60). */
  startupTimeoutSeconds?: number;
  /** Stream the dolos node logs to stderr (default false, or when `DEBUG_DOLOS` is set). */
  logs?: boolean;
}

export interface DevnetWallet {
  /** Wallet name, as passed to {@link TestDevnet.start}. */
  readonly name: string;
  /** Bech32 enterprise address funded on the devnet. */
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

/** Deterministic 32-byte Ed25519 key from a wallet name (stable across runs). */
function deriveKey(name: string): Uint8Array {
  return blake2b(new TextEncoder().encode(`tx3-test-devnet:${name}`), {
    dkLen: 32,
  });
}

/** Deterministic 32-byte funding-UTxO txid for a wallet (stable across runs). */
function deriveTxid(name: string): Uint8Array {
  return blake2b(new TextEncoder().encode(`tx3-test-devnet:utxo:${name}`), {
    dkLen: 32,
  });
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

/** Big-endian byte expansion of `n` into `len` bytes. */
function beBytes(n: bigint, len: number): number[] {
  const out: number[] = [];
  for (let i = len - 1; i >= 0; i--)
    out.push(Number((n >> BigInt(i * 8)) & 0xffn));
  return out;
}

/** Minimal CBOR unsigned-integer encoding. */
function cborUint(n: bigint): number[] {
  if (n < 0n) throw new Error(`negative coin: ${n}`);
  if (n < 24n) return [Number(n)];
  if (n < 256n) return [0x18, Number(n)];
  if (n < 65536n) return [0x19, ...beBytes(n, 2)];
  if (n < 4294967296n) return [0x1a, ...beBytes(n, 4)];
  return [0x1b, ...beBytes(n, 8)];
}

/** CBOR for a simple `{0: address, 1: coin}` transaction output. */
function outputCbor(address: Uint8Array, coin: bigint): number[] {
  const out: number[] = [0xa2, 0x00];
  if (address.length < 24) out.push(0x40 + address.length);
  else out.push(0x58, address.length);
  out.push(...address, 0x01, ...cborUint(coin));
  return out;
}

function cborByteString(bytes: number[]): number[] {
  if (bytes.length < 24) return [0x40 + bytes.length, ...bytes];
  if (bytes.length < 256) return [0x58, bytes.length, ...bytes];
  if (bytes.length < 65536)
    return [0x59, ...beBytes(BigInt(bytes.length), 2), ...bytes];
  throw new Error(`CBOR byte string is too large: ${bytes.length} bytes`);
}

/**
 * CBOR for a Conway output holding a Plutus V3 reference script.
 *
 * The reference script is ledger-encoded as tag 24 around the serialized
 * `Script = [3, bytes(flat-script)]` value.
 */
function referenceScriptOutputCbor(
  address: Uint8Array,
  coin: bigint,
  scriptCode: string,
): number[] {
  if (!/^(?:[0-9a-fA-F]{2})+$/.test(scriptCode)) {
    throw new Error("reference script code must be non-empty hexadecimal");
  }
  const scriptBytes = [...Buffer.from(scriptCode, "hex")];
  const serializedScript = [0x82, 0x03, ...cborByteString(scriptBytes)];
  return [
    0xa3,
    0x00,
    ...cborByteString([...address]),
    0x01,
    ...cborUint(coin),
    0x03,
    0xd8,
    0x18,
    ...cborByteString(serializedScript),
  ];
}

/** Ask the OS for a free TCP port. */
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on("error", reject);
    srv.listen(0, "127.0.0.1", () => {
      const port = (srv.address() as net.AddressInfo).port;
      srv.close(() => resolve(port));
    });
  });
}

/** Locate the `dolos` binary. */
function resolveDolosBin(): string {
  if (process.env.DOLOS_BIN) return process.env.DOLOS_BIN;
  const home = os.homedir();
  for (const channel of ["default", "stable", "beta", "nightly"]) {
    const candidate = join(home, ".tx3", channel, "bin", "dolos");
    if (existsSync(candidate)) return candidate;
  }
  return "dolos"; // fall back to PATH
}

const sleep = (ms: number): Promise<void> =>
  new Promise((r) => setTimeout(r, ms));

export class TestDevnet {
  private constructor(
    readonly trpUrl: string,
    private readonly minibfUrl: string,
    private readonly proc: ChildProcess,
    private readonly workdir: string,
    private readonly walletsByName: Map<string, DevnetWallet>,
    private readonly referenceScriptsByName: Map<string, DevnetUtxo>,
    private readonly slotConfig: { zeroTimeMs: number; slotLengthMs: number },
  ) {}

  /** Boot an ephemeral devnet funding the requested wallets. */
  static async start(options: DevnetOptions): Promise<TestDevnet> {
    if (!GENESIS_FILES.every((f) => existsSync(join(GENESIS_DIR, f)))) {
      throw new Error(`devnet genesis template not found in ${GENESIS_DIR}`);
    }

    // Ledger slot->time config, straight from the Shelley genesis. The
    // validators convert a transaction's validity lower-bound slot to POSIX
    // time with this, so chain time must be derived from the slot the same
    // way (dolos may report wall-clock `block.time`, which would not match).
    const slotConfig = shelleySlotConfig();

    // Derive wallets and their funding UTxOs.
    const walletsByName = new Map<string, DevnetWallet>();
    const referenceScriptsByName = new Map<string, DevnetUtxo>();
    const utxoBlocks: string[] = [];
    for (const [name, balanceSpec] of Object.entries(options.wallets)) {
      const privateKey = deriveKey(name);
      const publicKey = ed25519.getPublicKey(privateKey);
      const addr = enterpriseAddress(publicKey);
      const privateKeyHex = toHex(privateKey);
      walletsByName.set(name, {
        name,
        address: addr.bech32,
        keyHash: addr.keyHash,
        privateKeyHex,
        party: Party.signer(Ed25519Signer.fromHex(addr.bech32, privateKeyHex)),
      });
      const txid = toHex(deriveTxid(name));
      const balances = Array.isArray(balanceSpec) ? balanceSpec : [balanceSpec];
      balances.forEach((balance, index) => {
        const cbor = outputCbor(addr.bytes, BigInt(balance));
        utxoBlocks.push(
          `[[chain.custom_utxos]]\nref = ["${txid}", ${index}]\nera = 7\ncbor = [${cbor.join(",")}]\n`,
        );
      });
    }

    for (const [name, spec] of Object.entries(options.referenceScripts ?? {})) {
      const owner = walletsByName.get(spec.owner);
      if (!owner) {
        throw new Error(
          `reference script ${name} has unknown owner wallet ${spec.owner}`,
        );
      }
      const txHash = toHex(deriveTxid(`reference-script:${name}`));
      const outputIndex = 0;
      const lovelace = BigInt(spec.lovelace ?? 2_000_000);
      const address = new Uint8Array(
        bech32.fromWords(bech32.decode(owner.address, 1023).words),
      );
      const cbor = referenceScriptOutputCbor(address, lovelace, spec.scriptCode);
      utxoBlocks.push(
        `[[chain.custom_utxos]]\nref = ["${txHash}", ${outputIndex}]\nera = 7\ncbor = [${cbor.join(",")}]\n`,
      );
      referenceScriptsByName.set(name, {
        txHash,
        outputIndex,
        ref: `${txHash}#${outputIndex}`,
        lovelace,
      });
    }

    const [trpPort, minibfPort, grpcPort] = await Promise.all([
      freePort(),
      freePort(),
      freePort(),
    ]);

    // Lay out an isolated dolos workspace.
    const workdir = mkdtempSync(join(os.tmpdir(), "tx3-devnet-"));
    mkdirSync(join(workdir, "data"), { recursive: true });
    for (const f of GENESIS_FILES)
      copyFileSync(join(GENESIS_DIR, f), join(workdir, f));
    writeFileSync(
      join(workdir, "dolos.toml"),
      dolosConfig({
        trpPort,
        minibfPort,
        grpcPort,
        blockInterval: options.blockIntervalSeconds ?? 1,
        utxoBlocks,
      }),
    );

    // Boot the node.
    const proc = spawn(resolveDolosBin(), ["-c", "dolos.toml", "daemon"], {
      cwd: workdir,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const streamLogs = options.logs ?? Boolean(process.env.DEBUG_DOLOS);
    let log = "";
    const capture = (chunk: Buffer): void => {
      log += chunk.toString();
      if (log.length > 16_384) log = log.slice(-16_384);
      if (streamLogs) process.stderr.write(`[dolos] ${chunk}`);
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

    const trpUrl = `http://localhost:${trpPort}`;
    const minibfUrl = `http://localhost:${minibfPort}`;
    const devnet = new TestDevnet(
      trpUrl,
      minibfUrl,
      proc,
      workdir,
      walletsByName,
      referenceScriptsByName,
      slotConfig,
    );

    // Wait until it is serving blocks.
    const deadline = Date.now() + (options.startupTimeoutSeconds ?? 60) * 1000;
    for (;;) {
      if (spawnError) {
        cleanupDir(workdir);
        throw new Error(
          `failed to spawn dolos (${resolveDolosBin()}): ${spawnError.message}`,
        );
      }
      if (exited) {
        cleanupDir(workdir);
        throw new Error(
          `dolos exited during startup (code=${exited.code}, signal=${exited.signal}):\n${log}`,
        );
      }
      try {
        const res = await fetch(`${minibfUrl}/blocks/latest`, {
          signal: AbortSignal.timeout(2000),
        });
        if (res.ok) {
          const tip = (await res.json()) as { height?: number };
          if ((tip.height ?? 0) >= 1) return devnet;
        }
      } catch {
        // not up yet
      }
      if (Date.now() > deadline) {
        devnet.stop();
        throw new Error(
          `dolos did not start serving within the timeout:\n${log}`,
        );
      }
      await sleep(500);
    }
  }

  /** Look up a funded wallet by name. */
  wallet(name: string): DevnetWallet {
    const w = this.walletsByName.get(name);
    if (!w) throw new Error(`unknown wallet: ${name}`);
    return w;
  }

  /** Look up a reference-script UTxO seeded when the devnet started. */
  referenceScript(name: string): DevnetUtxo {
    const script = this.referenceScriptsByName.get(name);
    if (!script) throw new Error(`unknown reference script: ${name}`);
    return script;
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

  /**
   * Returns the first UTxO of the wallet, suitable as a seed for transactions.
   * Throws if the wallet has no UTxOs.
   */
  async seedUtxo(name: string): Promise<DevnetUtxo> {
    const utxos = await this.utxosOf(this.wallet(name).address);
    const seed = utxos[0];
    if (!seed) throw new Error(`wallet ${name} has no UTxOs to use as a seed`);
    return seed;
  }

  /** Register a script stake credential so its withdraw-0 reward account exists. */
  async registerScriptStakeCredential(
    payerName: string,
    scriptHash: string,
  ): Promise<void> {
    const payer = this.wallet(payerName);
    const utxos = await this.utxosOf(payer.address);
    const input = utxos[0];
    if (!input) throw new Error(`wallet ${payerName} has no UTxO to fund registration`);
    const change = input.lovelace - STAKE_REGISTRATION_FEE;
    if (change < 1_000_000n) {
      throw new Error(`wallet ${payerName} has insufficient funds for registration`);
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
      .txOut(payer.address, [
        { unit: "lovelace", quantity: change.toString() },
      ])
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
    const witness = await signer.sign({ txHashHex: parsed.getId(), txCborHex: body });
    const submitted = await this.trpCall<{ hash: string }>("trp.submit", {
      tx: { content: tx, contentType: "hex" },
      witnesses: [witness],
    });
    await this.waitForConfirmed(submitted.hash);
  }

  private async waitForConfirmed(txHash: string): Promise<void> {
    for (let attempt = 0; attempt < DEVNET_POLL.attempts; attempt++) {
      const status = await this.trpCall<{
        statuses: Record<string, { stage?: string }>;
      }>("trp.checkStatus", { hashes: [txHash] });
      const stage = status.statuses[txHash]?.stage;
      if (stage === "confirmed" || stage === "finalized") return;
      if (stage === "dropped") throw new Error(`transaction ${txHash} was dropped`);
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
    const body = (await res.json()) as { error?: { message?: string }; result?: T };
    if (body.error) throw new Error(`TRP ${method} failed: ${body.error.message}`);
    if (body.result === undefined) throw new Error(`TRP ${method} returned no result`);
    return body.result;
  }

  /**
   * The current chain tip. `timeMs` is the *ledger* time of the tip slot
   * (`systemStart + slot * slotLength`) — the exact value a validator sees as
   * the validity lower bound — not dolos's reported `block.time`.
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

  /** Poll until the chain's tip time reaches `targetMs` (or throw on timeout). */
  async waitForChainTimeMs(
    targetMs: number,
    timeoutSeconds = 60,
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

  /** Stop the node and remove its workspace. */
  stop(): void {
    if (!this.proc.killed) this.proc.kill("SIGTERM");
    cleanupDir(this.workdir);
  }
}

function cleanupDir(dir: string): void {
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {
    // best effort
  }
}

function dolosConfig(opts: {
  trpPort: number;
  minibfPort: number;
  grpcPort: number;
  blockInterval: number;
  utxoBlocks: string[];
}): string {
  return `[upstream]
block_production_interval = ${opts.blockInterval}

[storage]
version = "v3"
path = "data"
[storage.wal]
backend = "in_memory"
[storage.state]
backend = "in_memory"
[storage.archive]
backend = "in_memory"
[storage.index]
backend = "in_memory"

[genesis]
byron_path = "./byron.json"
shelley_path = "./shelley.json"
alonzo_path = "./alonzo.json"
conway_path = "./conway.json"
force_protocol = 9

[sync]
pull_batch_size = 100

[serve.grpc]
listen_address = "[::]:${opts.grpcPort}"
permissive_cors = true
[serve.minibf]
listen_address = "[::]:${opts.minibfPort}"
permissive_cors = true
[serve.trp]
listen_address = "[::]:${opts.trpPort}"
max_optimize_rounds = 10
permissive_cors = true

[chain]
type = "cardano"
magic = 0
is_testnet = false

${opts.utxoBlocks.join("\n")}`;
}
