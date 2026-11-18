import { describe, expect, it, vi } from "vitest";
import type { Client } from "../codegen/ts-client/linear-vesting/protocol";
import {
  assertValidTx3Lock,
  buildLockTx,
  type Tx3LockParams,
  type Tx3VestingDatum,
} from "../lock";

const EMPTY = new Uint8Array(0);
const tokenName = new Uint8Array([0x54, 0x4f, 0x4b, 0x45, 0x4e]);

function datum(overrides: Partial<Tx3VestingDatum> = {}): Tx3VestingDatum {
  return {
    beneficiary: { Key: { hash: new Uint8Array(28).fill(0xab) } },
    locker: { Key: { hash: new Uint8Array(28).fill(0xef) } },
    vesting: [{ policy: EMPTY, name: EMPTY, total: 100_000_000 }],
    start_time: 1_000,
    end_time: 2_000,
    recovery_time: 3_000,
    ...overrides,
  };
}

function params(overrides: Partial<Tx3LockParams> = {}): Tx3LockParams {
  return { ada_total: 100_000_000, vesting_datum: datum(), ...overrides };
}

describe("assertValidTx3Lock", () => {
  it("accepts an ada bundle whose total matches ada_total", () => {
    expect(() => assertValidTx3Lock(params())).not.toThrow();
  });

  it("rejects degenerate schedules", () => {
    expect(() =>
      assertValidTx3Lock(params({ vesting_datum: datum({ end_time: 1_000 }) })),
    ).toThrow(/start_time < end_time < recovery_time/);
    expect(() =>
      assertValidTx3Lock(
        params({ vesting_datum: datum({ recovery_time: 2_000 }) }),
      ),
    ).toThrow(/start_time < end_time < recovery_time/);
    expect(() =>
      assertValidTx3Lock(
        params({
          vesting_datum: datum({ start_time: Number.MAX_SAFE_INTEGER + 1 }),
        }),
      ),
    ).toThrow(/safe integer/);
  });

  it("rejects a non-ada, empty, or multi-asset bundle", () => {
    expect(() =>
      assertValidTx3Lock(
        params({
          vesting_datum: datum({
            vesting: [
              { policy: new Uint8Array(28).fill(1), name: tokenName, total: 1 },
            ],
          }),
        }),
      ),
    ).toThrow(/exactly one ada entry/);
    expect(() =>
      assertValidTx3Lock(params({ vesting_datum: datum({ vesting: [] }) })),
    ).toThrow(/exactly one ada entry/);
    expect(() =>
      assertValidTx3Lock(
        params({
          vesting_datum: datum({
            vesting: [
              { policy: EMPTY, name: EMPTY, total: 100_000_000 },
              { policy: new Uint8Array(28).fill(1), name: tokenName, total: 1 },
            ],
          }),
        }),
      ),
    ).toThrow(/exactly one ada entry/);
  });

  it("rejects an underfunded lock", () => {
    expect(() => assertValidTx3Lock(params({ ada_total: 99_999_999 }))).toThrow(
      /ada_total is 99999999 but the datum requires 100000000/,
    );
  });

  it("rejects overfunding by default", () => {
    expect(() =>
      assertValidTx3Lock(params({ ada_total: 100_000_001 })),
    ).toThrow(/1 lovelace exceeds the datum total/);
  });

  it("warns instead of rejecting when surplus is explicitly allowed", () => {
    const warn = vi.fn();
    expect(() =>
      assertValidTx3Lock(params({ ada_total: 100_000_001 }), {
        allowUnprotectedValue: true,
        logger: { warn },
      }),
    ).not.toThrow();
    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0][0]).toMatch(/not schedule-protected/);
  });

  it("rejects invalid totals and output amounts", () => {
    expect(() =>
      assertValidTx3Lock(
        params({
          vesting_datum: datum({
            vesting: [{ policy: EMPTY, name: EMPTY, total: -1 }],
          }),
        }),
      ),
    ).toThrow(/must be non-negative/);
    expect(() => assertValidTx3Lock(params({ ada_total: -1 }))).toThrow(
      /ada_total must be non-negative/,
    );
  });
});

describe("buildLockTx", () => {
  it("typechecks against the generated client", () => {
    // Compile-time check: the wrapper accepts the generated `Client` type.
    const lockWithClient = (client: Client) =>
      buildLockTx(client, {
        ada_total: 100_000_000,
        vesting_datum: datum(),
      });
    expect(lockWithClient).toBeTypeOf("function");
  });

  it("validates and forwards the wire-form parameters", () => {
    const lock = vi.fn((_params: unknown) => "tx");
    const p = params();
    expect(buildLockTx({ lock }, p)).toBe("tx");
    expect(lock).toHaveBeenCalledWith(p);
  });

  it("normalizes camel-case generated-client fields", () => {
    const lock = vi.fn((_params: unknown) => "tx");
    const p = params();
    expect(
      buildLockTx(
        { lock },
        { adaTotal: p.ada_total, vestingDatum: p.vesting_datum },
      ),
    ).toBe("tx");
    expect(lock).toHaveBeenCalledWith(p);
  });

  it("does not call the client for an invalid lock", () => {
    const lock = vi.fn((_params: unknown) => "tx");
    expect(() => buildLockTx({ lock }, params({ ada_total: 1 }))).toThrow(
      /shortfall blocks/,
    );
    expect(lock).not.toHaveBeenCalled();
  });

  it("rejects ambiguous wire/camel input", () => {
    const p = params();
    expect(() =>
      buildLockTx(
        { lock: vi.fn() },
        {
          ada_total: p.ada_total,
          adaTotal: p.ada_total + 1,
          vesting_datum: p.vesting_datum,
        },
      ),
    ).toThrow(/disagree/);
  });
});
