import type { SlotConfig } from "@meshsdk/core";
import { describe, expect, it } from "vitest";
import {
  DEFAULT_PROPOSE_TTL_MS,
  proposalTiming,
} from "../../src/settings/settings";

// 1-second slots starting at t = 1_000_000 ms.
const SLOT_CONFIG: SlotConfig = {
  zeroTime: 1_000_000,
  zeroSlot: 0,
  slotLength: 1_000,
  startEpoch: 0,
  epochLength: 432_000,
};

describe("proposalTiming", () => {
  it("anchors next_apply on the upper bound's slot start", () => {
    const timing = proposalTiming({
      now: 1_010_500,
      applyDelay: 60_000,
      ttlMs: 120_000,
      slotConfig: SLOT_CONFIG,
    });
    // now + ttl = 1_130_500 lies in slot 130, which starts at 1_130_000.
    expect(timing.untilSlot).toBe(130);
    expect(timing.untilMs).toBe(1_130_000);
    expect(timing.nextApply).toBe(1_130_000 + 60_000);
  });

  it("defaults the validity window to DEFAULT_PROPOSE_TTL_MS", () => {
    const now = 2_000_000;
    const timing = proposalTiming({
      now,
      applyDelay: 0,
      slotConfig: SLOT_CONFIG,
    });
    expect(timing.untilMs).toBe(now + DEFAULT_PROPOSE_TTL_MS);
  });

  it("keeps next_apply at least apply_delay after any landing time", () => {
    const now = 1_234_567;
    const applyDelay = 30_000;
    const timing = proposalTiming({ now, applyDelay, slotConfig: SLOT_CONFIG });
    // The tx is valid only before untilMs, so it lands before it.
    expect(timing.untilMs).toBeGreaterThan(now);
    expect(timing.nextApply - timing.untilMs).toBe(applyDelay);
  });
});
