import Formal.TxModels.Common

/-! Types and datum construction for the experimental linear-vesting models. -/

namespace Formal.TxModels.Vesting

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.IsData.Class.IsData (toData)
open CardanoLedgerApi.V3 (Credential)

/-- `vesting/types/VestedAsset` -/
structure Types.VestedAsset where
  policy : ByteString
  name : ByteString
  total : Int

instance : IsData Types.VestedAsset where
  toData x := Data.Constr 0 [Data.B x.policy, Data.B x.name, Data.I x.total]
  fromData
    | Data.Constr 0 [d0, d1, d2] => do
        let a0 ← (match d0 with | Data.B b1 => some b1 | _ => none)
        let a1 ← (match d1 with | Data.B b2 => some b2 | _ => none)
        let a2 ← (match d2 with | Data.I i3 => some i3 | _ => none)
        pure (Types.VestedAsset.mk a0 a1 a2)
    | _ => none

/-- `vesting/types/VestingDatum` -/
structure Types.VestingDatum where
  beneficiary : Credential
  locker : Credential
  vesting : List (Types.VestedAsset)
  start_time : Int
  end_time : Int
  recovery_time : Int

instance : IsData Types.VestingDatum where
  toData x := Data.Constr 0 [IsData.toData x.beneficiary, IsData.toData x.locker, Data.List ((x.vesting).map (fun v1 => IsData.toData v1)), Data.I x.start_time, Data.I x.end_time, Data.I x.recovery_time]
  fromData
    | Data.Constr 0 [d0, d1, d2, d3, d4, d5] => do
        let a0 ← (IsData.fromData d0 : Option Credential)
        let a1 ← (IsData.fromData d1 : Option Credential)
        let a2 ← (match d2 with | Data.List xs3 => xs3.mapM (fun v2 => (IsData.fromData v2 : Option Types.VestedAsset)) | _ => none)
        let a3 ← (match d3 with | Data.I i4 => some i4 | _ => none)
        let a4 ← (match d4 with | Data.I i5 => some i5 | _ => none)
        let a5 ← (match d5 with | Data.I i6 => some i6 | _ => none)
        pure (Types.VestingDatum.mk a0 a1 a2 a3 a4 a5)
    | _ => none

/-- `vesting/types/VestingRedeemer` -/
inductive Types.VestingRedeemer where
  | Claim
  | Cancel

instance : IsData Types.VestingRedeemer where
  toData
    | Types.VestingRedeemer.Claim => Data.Constr 0 []
    | Types.VestingRedeemer.Cancel => Data.Constr 1 []
  fromData
    | Data.Constr 0 [] => some Types.VestingRedeemer.Claim
    | Data.Constr 1 [] => some Types.VestingRedeemer.Cancel
    | _ => none

/-- The policy of the vested asset. A literal: a symbolic policy stops Blaster inside
    `validScriptContext` (docs/Universal/DEAD_ENDS.md §17). -/
def vestedPolicy : ByteString := "policyA"

/-- The datum: one vested asset, key credentials for the beneficiary and the locker. -/
def vestingDatum (beneficiary locker name : ByteString) (total start finish recovery : Int) : Data :=
  toData
    ({ beneficiary := .PubKeyCredential beneficiary
       locker := .PubKeyCredential locker
       vesting := [{ policy := vestedPolicy, name := name, total := total }]
       start_time := start
       end_time := finish
       recovery_time := recovery } : Types.VestingDatum)

end Formal.TxModels.Vesting
