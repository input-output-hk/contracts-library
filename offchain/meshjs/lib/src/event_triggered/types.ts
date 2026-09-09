/**
 * Off-chain mirror of the on-chain types in
 * `onchain/lib/event_triggered/types.ak` (CIP-113 substandard scaffold,
 * docs/explorations/event-triggered-assets.md).
 */

import type { Credential } from "../common";

export type { Credential };

/** Lifecycle state of an instrument. P2 event rules drive transitions; P3
 * graduation consumes it. */
export type InstrumentState = "Active" | "Settled";

/** State of an event-triggered instrument. The two authorities are pluggable
 * `Credential`s per the repo auth pattern. */
export interface EventAssetDatum {
  /** Authority approving event-conditioned state changes (Q-RULE-1). */
  rule: Credential;
  /** Authority executing the graduation exit; per Q-GRAD-2 it must stay
   * event-gated, never a discretionary lever. */
  graduationAuth: Credential;
  state: InstrumentState;
}

/** P2 spend endpoint: keeper-submitted, event-conditioned actions. Nothing
 * self-executes — a keeper detects the event and submits. */
export type SpendRedeemer = "ApplyEvent";

/** P3 mint endpoint. */
export type MintRedeemer = "Graduate" | "Retire";
