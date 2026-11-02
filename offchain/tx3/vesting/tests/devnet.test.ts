import {
  vestedQuantity,
  vestingScript,
  vestingScriptAddress,
} from "@contracts-library/meshjs";
import { resolveScriptHash } from "@meshsdk/core";
import { Party, type SubmittedTx } from "tx3-sdk";
import { afterAll, beforeAll, expect, test } from "vitest";
import {
  DEVNET_POLL,
  type DevnetKitFactory,
  type DevnetUtxo,
  type DevnetWallet,
  TrixDevnet,
  unwrapCborBytes,
} from "../../devnet/utils";
import { Client } from "../codegen/ts-client/linear-vesting/protocol";

const ADA = 1_000_000n;

// Pinned linear_vesting blueprint (offchain/meshjs/lib/src/vesting/blueprint.ts).
// Asserted in beforeAll so a MeshJS/pin drift fails loudly instead of on-chain.
const PINNED_HASH = "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a";

// The locked bundle. Sized well above min-UTxO so the partial-claim
// continuation keeps the required remainder without hitting the floor.
const BUNDLE_ADA = 60n * ADA;

const SEED_ADA = 200n * ADA; // locker: funds the lock bundle + fees
const GAS_ADA = 10n * ADA; // gas + collateral split per wallet
const COLLATERAL = 5n * ADA;

let devnet: TrixDevnet;
/** The vesting script address, derived from the pinned blueprint. */
let vestingAddr: string;
/** The protocol env: the single-CBOR flat validator (tx3 witness form). */
let env: Record<string, unknown>;

const toBytes = (hex: string): Uint8Array => Buffer.from(hex, "hex");
const EMPTY_BYTES = new Uint8Array(0);

/** Dummy env for the test-kit txs (`devnet_pay` reads no env values). */
const KIT_ENV = { vesting_script: "00" };

const vestingKit: DevnetKitFactory = (trpUrl, faucet) => {
  const kitClient = () =>
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
    deploy: async () => {
      throw new Error("the vesting suite deploys no reference scripts");
    },
  };
};

beforeAll(async () => {
  devnet = await TrixDevnet.start({ protocolRoot: "vesting", kit: vestingKit });

  // The suite pins the vesting blueprint through the MeshJS library: fail
  // loudly here if the library and the pin drift apart.
  const scriptObj = vestingScript();
  expect(resolveScriptHash(scriptObj.code, "V3")).toBe(PINNED_HASH);

  // tx3 witnesses the single-CBOR payload form; MeshJS emits double-CBOR.
  vestingAddr = vestingScriptAddress(0);
  env = { vesting_script: unwrapCborBytes(scriptObj.code) };
}, 180_000);

afterAll(() => devnet.stop());

// --------------------------------------------------------------- datum shape

const keyCred = (keyHashHex: string) => ({
  Key: { hash: toBytes(keyHashHex) },
});

const vestingDatum = (
  beneficiaryKeyHash: string,
  lockerKeyHash: string,
  totalAda: bigint,
  startMs: number,
  endMs: number,
  recoveryMs: number,
) => ({
  beneficiary: keyCred(beneficiaryKeyHash),
  locker: keyCred(lockerKeyHash),
  vesting: [
    // The ada entry: empty policy/name per `cardano/assets.ada_policy_id`.
    { policy: EMPTY_BYTES, name: EMPTY_BYTES, total: Number(totalAda) },
  ],
  start_time: startMs,
  end_time: endMs,
  recovery_time: recoveryMs,
});

// ------------------------------------------------------------------ harness

/** resolve → sign → submit, without waiting for confirmation. */
function submit(builder: ReturnType<Client["lock"]>): Promise<SubmittedTx> {
  return builder
    .resolve()
    .then((r) => r.sign())
    .then((s) => s.submit());
}

/** Submit a transaction and wait until the devnet confirms it. */
async function confirm(builder: ReturnType<Client["lock"]>): Promise<void> {
  await (await submit(builder)).waitForConfirmed(DEVNET_POLL);
}

/** A still-unspent UTxO a rejected attack must have left untouched. */
interface UtxoGuard {
  address: string;
  ref: string;
}

/**
 * A rejected attack must fail for the RIGHT reason (ledger phase-2 script or
 * validity failure surfaced through TRP) and must leave the guarded UTxOs
 * untouched — a generic throw would also catch unrelated build-time failures
 * and prove nothing about the validator.
 */
async function expectAttackRejected(
  attack: Promise<unknown>,
  guards: UtxoGuard[],
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
  for (const guard of guards) {
    const stillThere = (await devnet.utxosOf(guard.address)).some(
      (u) => u.ref === guard.ref,
    );
    expect(stillThere, `guarded utxo ${guard.ref} was spent`).toBe(true);
  }
}

async function snapshot(address: string): Promise<Set<string>> {
  return new Set((await devnet.utxosOf(address)).map((u) => u.ref));
}

async function addedSince(
  address: string,
  before: Set<string>,
): Promise<DevnetUtxo[]> {
  return (await devnet.utxosOf(address)).filter((u) => !before.has(u.ref));
}

/** Bind the protocol parties: Locker/Beneficiary signers + the script address. */
const client = (locker: DevnetWallet, beneficiary: DevnetWallet) =>
  new Client({ endpoint: devnet.trpUrl }, "local")
    .withLocker(locker.party)
    .withBeneficiary(beneficiary.party)
    .withVesting(Party.address(vestingAddr));

// ------------------------------------------------------------------ builders

interface LockedInstance {
  utxo: DevnetUtxo;
  datum: ReturnType<typeof vestingDatum>;
  totalAda: bigint;
  startMs: number;
  endMs: number;
  recoveryMs: number;
}

/** Fund a locker (seed for the lock bundle + gas + collateral). */
async function fundLocker(name: string): Promise<DevnetWallet> {
  const wallet = devnet.wallet(name);
  await devnet.payTo(wallet.address, SEED_ADA);
  await devnet.payTo(wallet.address, GAS_ADA);
  await devnet.payTo(wallet.address, COLLATERAL);
  return wallet;
}

/** Fund an actor with gas + collateral only. */
async function fundActor(name: string): Promise<DevnetWallet> {
  const wallet = devnet.wallet(name);
  await devnet.payTo(wallet.address, GAS_ADA);
  await devnet.payTo(wallet.address, COLLATERAL);
  return wallet;
}

/** Lock a bundle with the given schedule and return the vesting UTxO. */
async function lock(p: {
  locker: DevnetWallet;
  beneficiary: DevnetWallet;
  startMs: number;
  endMs: number;
  recoveryMs: number;
  totalAda?: bigint;
}): Promise<LockedInstance> {
  const totalAda = p.totalAda ?? BUNDLE_ADA;
  const datum = vestingDatum(
    p.beneficiary.keyHash,
    p.locker.keyHash,
    totalAda,
    p.startMs,
    p.endMs,
    p.recoveryMs,
  );
  const before = await snapshot(vestingAddr);
  await confirm(
    client(p.locker, p.beneficiary)
      .lock({
        ada_total: Number(totalAda),
        vesting_datum: datum,
      } as unknown as Parameters<Client["lock"]>[0])
      .env(env),
  );
  const [utxo] = await addedSince(vestingAddr, before);
  return {
    utxo,
    datum,
    totalAda,
    startMs: p.startMs,
    endMs: p.endMs,
    recoveryMs: p.recoveryMs,
  };
}

/**
 * Build a partial-claim transaction against `inst`. The required remainder is
 * computed exactly as the validator will read it: `now` is the START of
 * `since_slot` (the validity lower bound the ledger reports), not wall-clock.
 */
async function buildClaim(p: {
  locker: DevnetWallet;
  /** The party bound as Beneficiary: signs and pays gas (attacks bind a
   * non-beneficiary wallet here). */
  beneficiary: DevnetWallet;
  inst: LockedInstance;
  /** Override the required remainder. */
  requiredAda?: bigint;
  /** Subtract from the computed required remainder (over-claim attack). */
  shortfall?: bigint;
  /** Override the continuation datum (tampering attack). */
  datum?: unknown;
}): Promise<{ submitted: SubmittedTx; required: bigint; sinceSlot: number }> {
  const sinceSlot = (await devnet.tip()).slot;
  const now = devnet.slotTimeMs(sinceSlot);
  const vested = vestedQuantity(
    p.inst.totalAda,
    p.inst.startMs,
    p.inst.endMs,
    now,
  );
  const required =
    p.requiredAda ?? p.inst.totalAda - vested - (p.shortfall ?? 0n);
  const submitted = await submit(
    client(p.locker, p.beneficiary)
      .claim({
        vesting_ref: p.inst.utxo.ref,
        vesting_datum: (p.datum ?? p.inst.datum) as never,
        required_ada: Number(required),
        since_slot: sinceSlot,
      } as unknown as Parameters<Client["claim"]>[0])
      .env(env),
  );
  return { submitted, required, sinceSlot };
}

/** Build a full-claim transaction (no continuation). */
async function buildClaimFull(p: {
  locker: DevnetWallet;
  beneficiary: DevnetWallet;
  inst: LockedInstance;
}): Promise<SubmittedTx> {
  return await submit(
    client(p.locker, p.beneficiary)
      .claimFull({
        vesting_ref: p.inst.utxo.ref,
        since_slot: (await devnet.tip()).slot,
      } as unknown as Parameters<Client["claimFull"]>[0])
      .env(env),
  );
}

/** Build a cancel transaction. `sinceSlot` defaults to the current tip. */
async function buildCancel(p: {
  /** The party bound as Locker: signs and pays gas (attacks bind a
   * non-locker wallet here). */
  lockerParty: DevnetWallet;
  inst: LockedInstance;
  sinceSlot?: number;
}): Promise<SubmittedTx> {
  const sinceSlot = p.sinceSlot ?? (await devnet.tip()).slot;
  return await submit(
    client(p.lockerParty, p.lockerParty)
      .cancel({
        vesting_ref: p.inst.utxo.ref,
        since_slot: sinceSlot,
      } as unknown as Parameters<Client["cancel"]>[0])
      .env(env),
  );
}

// ---------------------------------------------------------------- happy path

test("locks and partially claims mid-schedule", async () => {
  const locker = await fundLocker("locker-a");
  const beneficiary = await fundActor("beneficiary-a");
  const tip = await devnet.tip();
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 60_000,
    endMs: tip.timeMs + 120_000,
    recoveryMs: tip.timeMs + 420_000,
  });

  const before = await snapshot(vestingAddr);
  const beforeBeneficiary = await devnet.lovelaceBalanceOf(beneficiary.address);
  const { submitted, required } = await buildClaim({
    locker,
    beneficiary,
    inst,
  });
  await submitted.waitForConfirmed(DEVNET_POLL);

  const [continuation] = await addedSince(vestingAddr, before);
  // The spent UTxO is gone; exactly one continuation remains at the script.
  expect(continuation).toBeDefined();
  expect(continuation.lovelace).toBeGreaterThanOrEqual(required);
  expect(
    (await devnet.utxosOf(vestingAddr)).some((u) => u.ref === inst.utxo.ref),
  ).toBe(false);

  // The beneficiary received the vested portion (fees absorbed from its gas).
  const vested = inst.totalAda - required;
  const afterBeneficiary = await devnet.lovelaceBalanceOf(beneficiary.address);
  expect(
    afterBeneficiary.lovelace - beforeBeneficiary.lovelace,
  ).toBeGreaterThan(vested - 1n * ADA);
}, 300_000);

test("fully claims after end_time with no continuation", async () => {
  const locker = await fundLocker("locker-b");
  const beneficiary = await fundActor("beneficiary-b");
  const tip = await devnet.tip();
  const endMs = tip.timeMs + 8_000;
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 2_000,
    endMs,
    recoveryMs: endMs + 300_000,
  });

  await devnet.waitForChainTimeMs(endMs + 2_000);
  const before = await snapshot(vestingAddr);
  const fullClaim = await buildClaimFull({ locker, beneficiary, inst });
  await fullClaim.waitForConfirmed(DEVNET_POLL);

  // No continuation appeared at the script, and the spent instance is gone
  // (earlier tests' continuations legitimately share the script address).
  expect(await addedSince(vestingAddr, before)).toHaveLength(0);
  expect(
    (await devnet.utxosOf(vestingAddr)).some((u) => u.ref === inst.utxo.ref),
  ).toBe(false);
}, 300_000);

test("locker recovers the remainder after recovery_time", async () => {
  const locker = await fundLocker("locker-c");
  const beneficiary = await fundActor("beneficiary-c");
  const tip = await devnet.tip();
  const endMs = tip.timeMs + 6_000;
  const recoveryMs = endMs + 4_000;
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 2_000,
    endMs,
    recoveryMs,
  });

  await devnet.waitForChainTimeMs(recoveryMs + 2_000);
  const before = await snapshot(vestingAddr);
  const recovery = await buildCancel({ lockerParty: locker, inst });
  await recovery.waitForConfirmed(DEVNET_POLL);

  // No continuation appeared at the script, and the spent instance is gone:
  // the whole remainder flowed back to the locker.
  expect(await addedSince(vestingAddr, before)).toHaveLength(0);
  expect(
    (await devnet.utxosOf(vestingAddr)).some((u) => u.ref === inst.utxo.ref),
  ).toBe(false);
  const balance = await devnet.lovelaceBalanceOf(locker.address);
  expect(balance.lovelace).toBeGreaterThan(SEED_ADA - BUNDLE_ADA);
}, 300_000);

// ------------------------------------------------------------------- attacks

test("rejects a continuation short of the required remainder", async () => {
  const locker = await fundLocker("locker-d");
  const beneficiary = await fundActor("beneficiary-d");
  const tip = await devnet.tip();
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 60_000,
    endMs: tip.timeMs + 120_000,
    recoveryMs: tip.timeMs + 420_000,
  });

  // Keep 5 ada less than required → the no-over-release check must fail.
  await expectAttackRejected(
    buildClaim({ locker, beneficiary, inst, shortfall: 5n * ADA }),
    [{ address: vestingAddr, ref: inst.utxo.ref }],
  );

  // The failed attempt consumed nothing: an honest claim still succeeds.
  const before = await snapshot(vestingAddr);
  const { submitted, required } = await buildClaim({
    locker,
    beneficiary,
    inst,
  });
  await submitted.waitForConfirmed(DEVNET_POLL);
  const [continuation] = await addedSince(vestingAddr, before);
  expect(continuation.lovelace).toBeGreaterThanOrEqual(required);
}, 300_000);

test("rejects a tampered continuation datum", async () => {
  const locker = await fundLocker("locker-e");
  const beneficiary = await fundActor("beneficiary-e");
  const tip = await devnet.tip();
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 60_000,
    endMs: tip.timeMs + 120_000,
    recoveryMs: tip.timeMs + 420_000,
  });

  // Bring end_time forward so more appears "vested": the continuation datum
  // differs from the spent input's, so the schedule-tampering check fails.
  const tampered = { ...inst.datum, end_time: inst.datum.start_time + 1 };
  await expectAttackRejected(
    buildClaim({ locker, beneficiary, inst, datum: tampered }),
    [{ address: vestingAddr, ref: inst.utxo.ref }],
  );
}, 300_000);

test("rejects a claim missing the beneficiary signature", async () => {
  const locker = await fundLocker("locker-f");
  const beneficiary = await fundActor("beneficiary-f");
  const attacker = await fundActor("attacker-claim");
  const tip = await devnet.tip();
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 60_000,
    endMs: tip.timeMs + 120_000,
    recoveryMs: tip.timeMs + 420_000,
  });

  // The attacker binds itself as the Beneficiary party: it signs and pays gas,
  // but its key hash is not the datum's beneficiary credential. The honest,
  // fully-covering continuation is used, so only the missing auth can fail it.
  await expectAttackRejected(
    buildClaim({ locker, beneficiary: attacker, inst }),
    [{ address: vestingAddr, ref: inst.utxo.ref }],
  );
}, 300_000);

test("rejects a cancel with a lower bound exactly at recovery_time", async () => {
  const locker = await fundLocker("locker-g");
  const beneficiary = await fundActor("beneficiary-g");
  const tip = await devnet.tip();
  const endMs = tip.timeMs + 6_000;
  const recoveryMs = endMs + 4_000;
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 2_000,
    endMs,
    recoveryMs,
  });

  // Wait past recovery so the transaction is phase-1 valid at submission:
  // the rejection must come from the STRICT timing check (`now > recovery`),
  // not from a not-yet-valid validity range.
  await devnet.waitForChainTimeMs(recoveryMs + 2_000);
  await expectAttackRejected(
    buildCancel({
      lockerParty: locker,
      inst,
      sinceSlot: devnet.slotAtTimeMs(inst.recoveryMs),
    }),
    [{ address: vestingAddr, ref: inst.utxo.ref }],
  );
}, 300_000);

test("rejects a cancel by a non-locker after recovery_time", async () => {
  const locker = await fundLocker("locker-h");
  const beneficiary = await fundActor("beneficiary-h");
  const attacker = await fundActor("attacker-cancel");
  const tip = await devnet.tip();
  const endMs = tip.timeMs + 6_000;
  const recoveryMs = endMs + 4_000;
  const inst = await lock({
    locker,
    beneficiary,
    startMs: tip.timeMs - 2_000,
    endMs,
    recoveryMs,
  });

  await devnet.waitForChainTimeMs(recoveryMs + 2_000);
  await expectAttackRejected(buildCancel({ lockerParty: attacker, inst }), [
    { address: vestingAddr, ref: inst.utxo.ref },
  ]);

  // Positive control: the real locker's cancel is still accepted.
  const before = await snapshot(vestingAddr);
  const recovery = await buildCancel({ lockerParty: locker, inst });
  await recovery.waitForConfirmed(DEVNET_POLL);
  expect(await addedSince(vestingAddr, before)).toHaveLength(0);
  expect(
    (await devnet.utxosOf(vestingAddr)).some((u) => u.ref === inst.utxo.ref),
  ).toBe(false);
}, 300_000);
