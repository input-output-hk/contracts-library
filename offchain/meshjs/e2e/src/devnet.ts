/**
 * Helpers for driving a local Yaci DevKit devnet from the e2e tests.
 *
 * The test harness that stands in for "a developer with a wallet and a provider". 
 * Configuration comes from env so the same tests run locally and in CI:
 *   - YACI_STORE_URL  (default http://localhost:8080/api/v1/)
 *   - YACI_ADMIN_URL  (default http://localhost:10000)
 */

import {
    DEFAULT_V1_COST_MODEL_LIST,
    DEFAULT_V2_COST_MODEL_LIST,
    DEFAULT_V3_COST_MODEL_LIST,
    deserializeAddress,
    MeshTxBuilder,
    MeshWallet,
    serializeRewardAddress,
    YaciProvider,
    type SlotConfig,
    type UTxO,
} from "@meshsdk/core";

// `INDEXER_URL` is the convention used by the shared devnet lifecycle script.
export const STORE_URL =
    process.env.YACI_STORE_URL ??
    process.env.INDEXER_URL ??
    "http://localhost:8080/api/v1/";
export const ADMIN_URL = process.env.YACI_ADMIN_URL ?? "http://localhost:10000";

export const NETWORK_ID = 0;

/** Pull the most informative message out of an error (axios bodies, etc.). */
function describeError(err: unknown): string {
    const e = err as {
        response?: { data?: unknown };
        message?: unknown;
    } | string;
    if (typeof e === "string") return e;
    if (e?.response?.data !== undefined) {
        const data = e.response.data;
        return typeof data === "string" ? data : JSON.stringify(data);
    }
    if (e?.message !== undefined) return String(e.message);
    try {
        return JSON.stringify(e);
    } catch {
        return String(e);
    }
}

export function makeProvider(): YaciProvider {
    const provider = new YaciProvider(STORE_URL, ADMIN_URL);
    // YaciProvider surfaces ledger rejections as terse axios errors; rethrow with
    // the response body so the actual reason (script failure, validity interval,
    // value mismatch, ...) appears in the test output instead of "status code 400".
    const patch = provider as unknown as Record<string, (...args: unknown[]) => Promise<unknown>>;
    for (const method of ["evaluateTx", "submitTx"] as const) {
        const original = patch[method].bind(provider);
        patch[method] = async (...args: unknown[]) => {
            try {
                return await original(...args);
            } catch (err) {
                throw new Error(`${method} rejected: ${describeError(err)}`);
            }
        };
    }
    return provider;
}

export function newTxBuilder(provider: YaciProvider): MeshTxBuilder {
    const builder = new MeshTxBuilder({
        fetcher: provider,
        submitter: provider,
        evaluator: provider,
    });
    // Pin the Plutus cost models the script-data hash is computed from. These are
    // the current protocol-era constants (what every Cardano network uses), so tx
    // building is deterministic and does not depend on the provider implementing
    // `fetchCostModels` — YaciProvider does not, and its default-model fallback
    // produces a script-data hash the devnet rejects.
    builder.setNetwork([
        DEFAULT_V1_COST_MODEL_LIST,
        DEFAULT_V2_COST_MODEL_LIST,
        DEFAULT_V3_COST_MODEL_LIST,
    ]);
    return builder;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Is the devnet reachable? Used to skip the suite when no devnet is running.
 * Logs the reason on failure so a skip is never silent.
 */
export async function devnetReachable(): Promise<boolean> {
    const url = `${STORE_URL}blocks/latest`;
    try {
        const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
        if (res.ok) return true;
        console.warn(`[e2e] devnet probe ${url} returned HTTP ${res.status}`);
        return false;
    } catch (err) {
        console.warn(
            `[e2e] devnet not reachable at ${url}: ${(err as Error).message}`,
        );
        return false;
    }
}

interface Tip {
    slot: number;
    /** POSIX seconds (Blockfrost-compatible). */
    time: number;
}

async function chainTip(): Promise<Tip> {
    const res = await fetch(`${STORE_URL}blocks/latest`);
    if (!res.ok) throw new Error(`blocks/latest failed: ${res.status}`);
    const b = (await res.json()) as Tip;
    return { slot: b.slot, time: b.time };
}

/** Current devnet wall-clock, in POSIX milliseconds. */
export async function chainNowMs(): Promise<number> {
    return (await chainTip()).time * 1000;
}

/**
 * Slot config for the devnet, so the library's time→slot conversion matches
 * this chain. Yaci's default devnet uses 1s slots starting at its genesis.
 */
export async function devnetSlotConfig(): Promise<SlotConfig> {
    const tip = await chainTip();
    const slotLength = 1000;
    return {
        zeroTime: tip.time * 1000 - tip.slot * slotLength,
        zeroSlot: 0,
        slotLength,
        startEpoch: 0,
        epochLength: 432000,
    };
}

/** Poll until the devnet's wall-clock reaches `targetMs`. */
export async function waitUntilChainTimeMs(
    targetMs: number,
    timeoutMs = 90_000,
): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        if ((await chainNowMs()) >= targetMs) return;
        await sleep(1000);
    }
    throw new Error(`devnet did not reach time ${targetMs} within ${timeoutMs}ms`);
}

/**
 * Wait for a submitted transaction to land on-chain by polling for its outputs.
 *
 * We deliberately avoid `provider.onTxConfirmed`: it only fires once the tx's
 * block has `confirmations > 0`, but on a quiet devnet that block is usually the
 * tip, so the count stays 0 and it never fires. A tx whose outputs are queryable
 * is in a block, which is all we need before spending them.
 */
export async function waitForTx(
    provider: YaciProvider,
    txHash: string,
    timeoutMs = 90_000,
): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        try {
            const outs = await provider.fetchUTxOs(txHash);
            if (outs.length > 0) return;
        } catch {
            // not indexed yet
        }
        await sleep(2000);
    }
    throw new Error(`tx ${txHash} not on-chain within ${timeoutMs}ms`);
}

export interface Account {
    wallet: MeshWallet;
    address: string;
    /** Payment key hash, for use as a `key` credential in a datum. */
    keyHash: string;
}

/** Create a fresh wallet, fund it with the given ada topups, and wait for funds. */
export async function fundedAccount(
    provider: YaciProvider,
    adaTopups: number[] = [10_000, 10_000],
): Promise<Account> {
    const wallet = new MeshWallet({
        networkId: 0,
        fetcher: provider,
        submitter: provider,
        key: { type: "mnemonic", words: MeshWallet.brew() as string[] },
    });
    await wallet.init();
    const address = await wallet.getChangeAddress();
    for (const amount of adaTopups) {
        await provider.addressTopup(address, String(amount));
    }
    await waitForUtxoCount(provider, address, adaTopups.length);
    const { pubKeyHash } = deserializeAddress(address);
    return { wallet, address, keyHash: pubKeyHash };
}

async function waitForUtxoCount(
    provider: YaciProvider,
    address: string,
    atLeast: number,
    timeoutMs = 60_000,
): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const utxos = await provider.fetchAddressUTxOs(address);
        if (utxos.length >= atLeast) return;
        await sleep(1000);
    }
    throw new Error(`address ${address} never reached ${atLeast} UTxOs`);
}

/** The single output of `txHash` that sits at `scriptAddress` (our vesting UTxO). */
export async function scriptOutputOf(
    provider: YaciProvider,
    txHash: string,
    scriptAddress: string,
): Promise<UTxO> {
    const outs = await provider.fetchUTxOs(txHash);
    const found = outs.find((u) => u.output.address === scriptAddress);
    if (!found) throw new Error(`no script output at ${scriptAddress} in ${txHash}`);
    return found;
}

/**
 * Register a (script) stake credential so its reward account exists and a
 * withdraw-0 against it is permitted by the ledger. Registration does not run
 * the credential's script, so it works even for the reject-withdraw fixture.
 */
export async function registerStakeCredential(
    provider: YaciProvider,
    payer: Account,
    scriptHash: string,
): Promise<void> {
    const rewardAddress = serializeRewardAddress(scriptHash, true, NETWORK_ID);
    const tx = await newTxBuilder(provider)
        .registerStakeCertificate(rewardAddress)
        .changeAddress(payer.address)
        .selectUtxosFrom(await payer.wallet.getUtxos())
        .complete();
    const hash = await payer.wallet.submitTx(await payer.wallet.signTx(tx, true));
    await waitForTx(provider, hash);
}
