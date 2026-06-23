/-
Linear vesting — pure-Lean specification model. No UPLC here.

Two layers:
  1. The schedule arithmetic (`vested`/`required`) and its properties — spec
     §3.3 and the §9 boundary lemmas B1-B3. These are self-contained and
     proved by `blaster`.
  2. The datum/redeemer encoding and the "valid instance / valid transition"
     relations the Completeness/Soundness/Robustness proofs are stated against.
     The encodings mirror `onchain/lib/vesting/types.ak` exactly.

See `specs/vesting/linear-vesting.md`.
-/
import Blaster
import PlutusCore.UPLC
import CardanoLedgerApi.V3

namespace Formal.Vesting.Linear.Spec

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)

/-! ## 1. Schedule arithmetic (spec §3.3) -/

/-- Quantity of a single asset vested by `now`, given original total `T` and
schedule `[start, finish]`. Mirrors spec §3.3. Floored (Int division is floor
on the non-negative domain this is used in). -/
def vested (T start finish now : Int) : Int :=
  if now ≤ start then 0
  else if finish ≤ now then T
  else T * (now - start) / (finish - start)

/-- Remainder of one asset that must stay locked after a claim at `now`. -/
def required (T start finish now : Int) : Int :=
  T - vested T start finish now

/-- **B3 (pre-start floor).** Spec §9 B3, §5.2. -/
theorem vested_preStart (T start finish now : Int) (h : now ≤ start) :
    vested T start finish now = 0 := by
  unfold vested
  blaster

/-- **Full vesting ⇒ free.** Spec §8.2, I4. -/
theorem vested_full (T start finish now : Int)
    (hs : start < finish) (h : finish ≤ now) :
    vested T start finish now = T := by
  unfold vested
  blaster

/-- **B1 (floor / no over-release).** Spec §9 B1. -/
theorem vested_le_total (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    vested T start finish now ≤ T := by
  unfold vested
  blaster

/-- Required remainder is non-negative — the dual of B1. -/
theorem required_nonneg (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    0 ≤ required T start finish now := by
  unfold required vested
  blaster

/-- A claim never releases a negative amount. -/
theorem vested_nonneg (T start finish now : Int)
    (hT : 0 ≤ T) (hs : start < finish) :
    0 ≤ vested T start finish now := by
  unfold vested
  blaster

/-- **B2 (monotonicity).** Spec §9 B2, §5.2. -/
theorem vested_mono (T start finish n₁ n₂ : Int)
    (hT : 0 ≤ T) (hs : start < finish) (h : n₁ ≤ n₂) :
    vested T start finish n₁ ≤ vested T start finish n₂ := by
  unfold vested
  blaster

/-! ## 2. Datum / redeemer encoding (spec §3.1-§3.2)

Encodings mirror `onchain/lib/vesting/types.ak`:
- `Credential`     : `VerificationKey h → Constr 0 [B h]`, `Script h → Constr 1 [B h]`
- `VestedAsset`    : `Constr 0 [B policy, B name, I total]`
- `VestingDatum`   : `Constr 0 [beneficiary, locker, vesting, start, end, recovery]`
- `VestingRedeemer`: `Claim = Constr 0 []`, `Cancel = Constr 1 []`
-/

/-- A pluggable authorization credential (spec §2, `authorization.ak`). -/
inductive Cred where
  | key (hash : ByteString)
  | script (hash : ByteString)

def credData : Cred → Data
  | .key h    => Data.Constr 0 [Data.B h]
  | .script h => Data.Constr 1 [Data.B h]

structure VestedAsset where
  policy : ByteString
  name   : ByteString
  total  : Int

def assetData (a : VestedAsset) : Data :=
  Data.Constr 0 [Data.B a.policy, Data.B a.name, Data.I a.total]

structure VestingDatum where
  beneficiary  : Cred
  locker       : Cred
  vesting      : List VestedAsset
  startTime    : Int
  endTime      : Int
  recoveryTime : Int

def datumData (d : VestingDatum) : Data :=
  Data.Constr 0
    [ credData d.beneficiary,
      credData d.locker,
      Data.List (d.vesting.map assetData),
      Data.I d.startTime,
      Data.I d.endTime,
      Data.I d.recoveryTime ]

def claimRedeemer : Data := Data.Constr 0 []
def cancelRedeemer : Data := Data.Constr 1 []

/-! ## 3. Spec relations the property proofs are stated against -/

/-- Well-formed schedule (spec I7 / C0): `start < end < recovery`. -/
def validSchedule (d : VestingDatum) : Prop :=
  d.startTime < d.endTime ∧ d.endTime < d.recoveryTime

/-- The credential `c` is satisfied: a **key** credential by a signature in
`sigs`; a **script** credential by a withdrawal keyed by it (withdraw-0), i.e.
its hash is among `wdrlScripts`. Mirrors `authorization.is_authorized`. -/
def authorized (c : Cred) (sigs wdrlScripts : List ByteString) : Prop :=
  match c with
  | .key h    => h ∈ sigs
  | .script h => h ∈ wdrlScripts

end Formal.Vesting.Linear.Spec
