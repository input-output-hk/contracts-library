# Explore: DAO

## 1. Summary

Token-based governance of a protocol and its treasury: token holders propose actions, vote with weight proportional to holdings, and, if thresholds are met, a proposal becomes executable.

On Cardano, this design naturally splits into:

- Decide: proposal lifecycle, vote power model, double-vote prevention, tallying.
- Execute: authorization that a target contract or treasury recognizes.

For execution, two existing Cardano patterns are relevant:

- Governance Authority Token (GAT), as used by Agora/Liqwid.
- Pluggable forwarding authorization via `Credential`, as explored in this repository's authorization architecture.

This item is one of the largest in the catalog. Existing frameworks are strong (Agora, WingRiders), so a useful v1 needs clear scope boundaries and composability-first interfaces rather than novelty.

## 2. Context and Prior Art

- Agora (Liqwid): fully on-chain enforced governance, stake-lock voting, on-chain proposal state machine, GAT-authorized effects.
- WingRiders on-chain-dao-governance: metadata votes, snapshot slot, off-chain tally backend, verifiable but not on-chain enforced outcome.
- EVM references: Compound Governor and OpenZeppelin Governor + TimelockController, with checkpoint/snapshot voting patterns.
- CIP-1694: protocol-layer governance vocabulary on Cardano; related conceptually but separate from application/treasury governance.

## 3. Central Design Axis: Enforced vs Verified

The main architectural decision is how much governance logic is on-chain enforced.

### 3.1 Pole A: Fully On-Chain Enforced (Agora-style)

- Proposal lifecycle and tally enforced on-chain.
- Voting power commonly represented by stake/lock UTxOs.
- Double-voting prevented by lock semantics.
- Execution authorized trustlessly (for example via GAT).

Pros:

- Trustless execution path.
- Strong on-chain guarantees.

Cons:

- High implementation and audit surface.
- Shared-state contention risk (for example, serialized proposal tally updates).
- Higher operational complexity and cost.

### 3.2 Pole B: Verified, Not Enforced (WingRiders-style)

- Votes recorded as signed metadata.
- Snapshot slot defines voting power reference point.
- Off-chain service tallies and publishes results.
- Execution remains manual or otherwise externally trusted.

Pros:

- Low contention.
- Cheap and operationally simple.
- Flexible vote power definitions.

Cons:

- Outcome verification exists, but enforcement is external.
- Trust assumptions shift to backend/operator process.

## 4. Lightweight Design Sketch (Deliverable)

This sketch positions v1 between the two poles: enforce execution on-chain, while keeping tally complexity bounded.

### 4.1 Proposed v1 Position

- On-chain enforce execution authority.
- Keep vote lifecycle and tally model simple enough for tractable audit.
- Avoid committing v1 to a high-contention shared-state pattern unless benchmarked and justified.

### 4.2 Lifecycle

- Draft: proposal is created and validated against static schema.
- Voting: votes are accepted for a fixed window.
- Lock/Timelock: mandatory delay before execution for review/exit.
- Execution: authorized action can be consumed by treasury/target.
- Finalized: executed or failed/expired.

### 4.3 Voting and Double-Vote Approach

Two practical options for v1:

- Snapshot-based voting power at proposal start (ergonomic, lower friction).
- Stake-lock voting power for voting window (stronger on-chain enforcement, higher UX cost).

Given complexity constraints, snapshot-based power with explicit assumptions is a strong v1 candidate, provided the trust model is documented.

### 4.4 Tally and Contention Approach

Candidate implementations:

- Shared proposal state update (simple model, but serializes writes under load).
- Independent vote artifacts + fold/aggregation mechanism (less write contention, much higher complexity).
- Snapshot + off-chain tally (lowest on-chain complexity, not fully trustless if enforcement does not verify tally output).

A layered route is recommended:

- v1: choose one simple tally model and publish contention limits.
- v2+: introduce contention-reduction patterns after measurement.

### 4.5 Execution Binding

Execution should be bound to proposal payload hash and parameters so passed governance cannot be replayed or substituted with a different action.

Two compatible encodings:

- GAT-style effect authority token.
- Forwarding `Credential` authorization from a governance script.

Both can coexist; standardizing one as the primary interface for this repository should be explicit.

### 4.6 Treasury Gating

Treasury spends must require governance authorization and validate that authorization corresponds exactly to the approved proposal action.

## 5. Complexity and Risk Read (Deliverable)

### 5.1 Major Risks

- Vote contention: serialized shared proposal updates can degrade liveness/UX.
- Tally completeness: aggregation/fold designs are correctness-sensitive.
- Double-voting and flash-governance effects: especially around snapshot definitions and voting windows.
- Execution binding errors: approved action mismatch/replay/substitution.
- Treasury custody concentration: governance failures have direct asset impact.

### 5.2 Additional Risks

- Parameter misconfiguration (quorum, thresholds, windows, timelock).
- Operator dependence for verified/off-chain tally variants.
- Scope creep into "full governance platform" instead of composable authority module.

### 5.3 Suggested v1 Risk Boundary

- Keep lifecycle and authorization path minimal.
- Prefer transparent, inspectable proposal payload schema.
- Defer advanced vote-power sources (LP, custom distributions, delegation) until baseline security and operability are validated.
- Treat high-throughput contention handling as a later milestone.

## 6. Composability Check Against Architecture (Deliverable)

Alignment with this repository's architecture and constraints:

- No global transaction-shape assumptions:
  - DAO checks should be local to consumed governance/treasury state and required authorization evidence.
  - Avoid assertions like total input/output count or unrelated script participation.

- Authorization abstraction compatibility:
  - DAO can act as an authorizer through script `Credential` semantics described in architecture.
  - This allows treasury/target contracts to depend on "who authorizes" abstractly, not on DAO internals.

- On-chain/off-chain/spec separation:
  - On-chain: lifecycle invariants and authorization checks.
  - Off-chain: builders for propose/vote/finalize/execute actions.
  - Spec: state machine, invariants, threat model, and assumptions (especially if tally is verified rather than enforced).

- No hidden coupling:
  - DAO should publish the minimal execution-proof interface (for example payload hash + authorization witness) so consumer contracts remain independent.

## 7. Open Questions to Resolve Before Implementation

- Exact position on enforced-vs-verified tally for v1.
- Primary execution authority encoding (GAT vs forwarding `Credential`) and composition strategy.
- Definitive double-vote prevention model (snapshot vs stake-lock).
- v1 voting power source (flat token balance vs broader distribution model).
- Treasury state model (single UTxO vs distributed) and contention implications.
- Minimal parameter surface for safe defaults.

## 8. Recommendation (Deliverable)

Recommendation: Implement **now**, in layers.

Reason:

- Ecosystem demand is high, and this repository already has the right architectural hooks (pluggable authorization via `Credential`) to ship a useful governance authority source.
- Strong Cardano prior art at both poles reduces discovery risk and enables a scoped, opinionated v1 instead of greenfield design.
- A layered implementation can deliver immediate utility (execution-gated governance with timelock and clear lifecycle) while deferring high-contention and advanced vote-power features.

Suggested delivery order:

1. Define and lock the DAO-to-consumer authorization interface (execution proof shape, payload binding, timelock semantics).
2. Implement a minimal governance core with conservative lifecycle and parameter set.
3. Add advanced tally/throughput and flexible vote-power modules only after baseline audits and usage data.
