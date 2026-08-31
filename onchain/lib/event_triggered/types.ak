//// On-chain state and actions for event-triggered assets — CIP-113
//// substandard scaffold. See `docs/explorations/event-triggered-assets.md`.
////
//// P1 (permissive transfer) needs no validator of its own — it is the
//// absence of gating. This scaffold covers P2 (event rules) and P3
//// (graduation); every predicate is a permissive stub pending triage (§7).

use cardano/address.{Credential}

/// Lifecycle state of an instrument. P2 event rules drive transitions; P3
/// graduation consumes it (§2 P2/P3).
pub type InstrumentState {
  Active
  Settled
}

/// State of an event-triggered instrument. Written at issuance, updated by
/// event-conditioned P2 actions, consumed by P3 graduation. The two
/// authorities are pluggable `Credential`s per the repo auth pattern (§4).
pub type EventAssetDatum {
  /// Authority approving event-conditioned state changes (Q-RULE-1).
  rule: Credential,
  /// Authority executing the graduation exit; per Q-GRAD-2 it must stay
  /// event-gated, never a discretionary lever.
  graduation_auth: Credential,
  state: InstrumentState,
}

/// P2 spend endpoint: keeper-submitted, event-conditioned actions. Nothing
/// self-executes — a keeper detects the event and submits, the predicate
/// approves (§5).
pub type SpendRedeemer {
  ApplyEvent
}

pub type MintRedeemer {
  /// Burn the programmable token and mint the graduated native token.
  /// Identity/fungibility across the swap is Q-GRAD-1.
  Graduate
  /// Burn-only retirement, for instruments with no graduated successor.
  Retire
}
