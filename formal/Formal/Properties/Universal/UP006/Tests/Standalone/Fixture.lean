/- Standalone UP-006 fixture for the tracked linear vesting blueprint.
Types and encodings retain the public blueprint generator's definitions. The generator
originates in sayyadirfanali's PR #44 at 99a5734f0e036b6abfb4c3f121a298e35fa2eff6.
The frozen program is the 1404-byte compiledCode in onchain/plutus.json,
compiled with Aiken v1.1.22+39d6b04. This file requires no generation step.
-/
import PlutusCore.UPLC
import CardanoLedgerApi
import Formal.Support.Compatibility
import Formal.Support.ReturnDatum

namespace UP006

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Term (Term Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)
open CardanoLedgerApi.IsData.Class (IsData toTerm)
open CardanoLedgerApi.V3 (Address Credential StakingCredential ScriptContext TxOutRef)

/-! ## Types -/

/-- `vesting/types/VestedAsset` -/
structure Vesting.Types.VestedAsset where
  policy : ByteString
  name : ByteString
  total : Int

instance : IsData Vesting.Types.VestedAsset where
  toData x := Data.Constr 0 [Data.B x.policy, Data.B x.name, Data.I x.total]
  fromData
    | Data.Constr 0 [d0, d1, d2] => do
        let a0 ← (match d0 with | Data.B b1 => some b1 | _ => none)
        let a1 ← (match d1 with | Data.B b2 => some b2 | _ => none)
        let a2 ← (match d2 with | Data.I i3 => some i3 | _ => none)
        pure (Vesting.Types.VestedAsset.mk a0 a1 a2)
    | _ => none

/-- `vesting/types/VestingDatum` -/
structure Vesting.Types.VestingDatum where
  beneficiary : Credential
  locker : Credential
  vesting : List (Vesting.Types.VestedAsset)
  start_time : Int
  end_time : Int
  recovery_time : Int

instance : IsData Vesting.Types.VestingDatum where
  toData x := Data.Constr 0 [IsData.toData x.beneficiary, IsData.toData x.locker, Data.List ((x.vesting).map (fun v1 => IsData.toData v1)), Data.I x.start_time, Data.I x.end_time, Data.I x.recovery_time]
  fromData
    | Data.Constr 0 [d0, d1, d2, d3, d4, d5] => do
        let a0 ← (IsData.fromData d0 : Option Credential)
        let a1 ← (IsData.fromData d1 : Option Credential)
        let a2 ← (match d2 with | Data.List xs3 => xs3.mapM (fun v2 => (IsData.fromData v2 : Option Vesting.Types.VestedAsset)) | _ => none)
        let a3 ← (match d3 with | Data.I i4 => some i4 | _ => none)
        let a4 ← (match d4 with | Data.I i5 => some i5 | _ => none)
        let a5 ← (match d5 with | Data.I i6 => some i6 | _ => none)
        pure (Vesting.Types.VestingDatum.mk a0 a1 a2 a3 a4 a5)
    | _ => none

/-- `vesting/types/VestingRedeemer` -/
inductive Vesting.Types.VestingRedeemer where
  | Claim
  | Cancel

instance : IsData Vesting.Types.VestingRedeemer where
  toData
    | Vesting.Types.VestingRedeemer.Claim => Data.Constr 0 []
    | Vesting.Types.VestingRedeemer.Cancel => Data.Constr 1 []
  fromData
    | Data.Constr 0 [] => some Vesting.Types.VestingRedeemer.Claim
    | Data.Constr 1 [] => some Vesting.Types.VestingRedeemer.Cancel
    | _ => none

/-! ## Handlers -/

/-- Purposes with a handler in the blueprint (the `else` fallback is not listed). -/
def handlers : List String := ["spend"]

abbrev SpendDatum := Vesting.Types.VestingDatum
abbrev SpendRedeemer := Vesting.Types.VestingRedeemer

/-! ## Parameters and script -/

/-- The script's arguments: the script context only (no parameters). -/
def args (ctx : ScriptContext) : List Term := [toTerm ctx]

def compiledCode : String := "59057901010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264653001300800198041804800cdc3a400530080024888966002600460106ea800e2653001300d00198069807000cdc3a400091119912cc004c00c0062b3001300f37540150028b20208acc004c0200062b3001300f37540150028b20208b201a40342b30013001300c375400519800980818069baa0029112cc004c010c03cdd5001c4c8c8cc004004010896600200314a115980099b8f375c602c00200714a31330020023017001404480a0dd7180998081baa00389919800800801112cc00400629422b30013375e00a6022602a00314a313300200230160014040809900e48c044c048c048c04800646022602460246024602400323011301200148888966002600c60226ea8036264b300130073012375400319800912cc0040062900044cdc02400466004004603200280b244646600200200644b30010018a518acc004c00cc068006266004004603600314a080a901848c05cc060c060006600460266ea8c058c04cdd5000cc04cdd5005a4444464646644b30019800980f980e1baa00f9bac301f30200029bab301f003403915980099b88375a601a60386ea803cdd69806180e1baa00f8992cc004c058c070dd5000c56600266e1d2004301c37546010603a6ea801e330013758604000d3758604000b3020301d37546040603a6ea801e6eb4c080c074dd5000a444464b3001337126eb4c048c088dd500a8014528c56600266e24c8c8cc00400401c896600200314800226644b30015980099baf302a302737546054604e6ea8c058c09cdd500100444cdd7980918139baa30163027375400400b14a0812a266e0120020018800a04a30280013300200230290014098601a60446ea8030c01c00626601c00246601e6eb0c038c08cdd500b119b89337026eb4c03cc090dd5000cc004dd6980798121baa0019bad30153024375402f375a602860486ea805d2225980099b890070028a400115980099b890010078801c4cdc199b820033370200e00466e04004009025204a4c004dd5980998121baa0029bae302730243754003375c602660486ea8006290002444466446600200200464646600200200c44b3001001801c4c8c96600266e440200062b30013371e01000313756605a00500540ad133004004303100340ac6eb8c0ac004c0b800502c0a5eb7bdb1808966002003003899192cc004cdc8803000c56600266e3c01800626eb4c0b000a00a815226600800860600068150dd718150009816800a056452820404080646600200200844b30010018a5eb8226644b30015980099baf3028302537546050604a6ea800801a266ebcc040c094dd5001180818129baa00f8a50408d13302700233004004001899802002000a0463026001302700140908b20368b2036301f301c3754603e60386ea8c07c00a2c80d22c80d0c078004c01c01cc074c074c074c074004c070c07000516404464660020026eb0c058c04cdd5005912cc0040062980103d87a80008992cc004cdd7980c180a9baa00100b899ba548000cc05c0052f5c11330030033019002404c602e00280aa2646644b300198009802180a9baa0089bac301830190029bab3018003401d15980099b88375a600c602a6ea8020dd69802980a9baa0088acc004cdc41bad3005301537540106eb4c004c054dd500444c8c8cc89660026024005132598009809980c9baa3009301a3754603a60346ea8016266e20008006266e240080050181bad301c30193754007159800980680145284528a02e405c602c6ea8004dd69801980b9baa00a3019301637546032602c6ea8004c06000a2c809a2c809a2c8098c05c0048c05cc060c060c060c060c060004c058c058c058c058c058c058c048dd5005202045900b18061baa00818049baa0038b200e180400098019baa0088a4d13656400401"

abbrev linearVestingScript : PlutusCore.UPLC.PlutusScript.PlutusScript :=
  ⟨.PlutusV3, singleCborEncodedScriptFromHexM "59057901010029800aba2aba1aba0aab9faab9eaab9dab9a488888896600264653001300800198041804800cdc3a400530080024888966002600460106ea800e2653001300d00198069807000cdc3a400091119912cc004c00c0062b3001300f37540150028b20208acc004c0200062b3001300f37540150028b20208b201a40342b30013001300c375400519800980818069baa0029112cc004c010c03cdd5001c4c8c8cc004004010896600200314a115980099b8f375c602c00200714a31330020023017001404480a0dd7180998081baa00389919800800801112cc00400629422b30013375e00a6022602a00314a313300200230160014040809900e48c044c048c048c04800646022602460246024602400323011301200148888966002600c60226ea8036264b300130073012375400319800912cc0040062900044cdc02400466004004603200280b244646600200200644b30010018a518acc004c00cc068006266004004603600314a080a901848c05cc060c060006600460266ea8c058c04cdd5000cc04cdd5005a4444464646644b30019800980f980e1baa00f9bac301f30200029bab301f003403915980099b88375a601a60386ea803cdd69806180e1baa00f8992cc004c058c070dd5000c56600266e1d2004301c37546010603a6ea801e330013758604000d3758604000b3020301d37546040603a6ea801e6eb4c080c074dd5000a444464b3001337126eb4c048c088dd500a8014528c56600266e24c8c8cc00400401c896600200314800226644b30015980099baf302a302737546054604e6ea8c058c09cdd500100444cdd7980918139baa30163027375400400b14a0812a266e0120020018800a04a30280013300200230290014098601a60446ea8030c01c00626601c00246601e6eb0c038c08cdd500b119b89337026eb4c03cc090dd5000cc004dd6980798121baa0019bad30153024375402f375a602860486ea805d2225980099b890070028a400115980099b890010078801c4cdc199b820033370200e00466e04004009025204a4c004dd5980998121baa0029bae302730243754003375c602660486ea8006290002444466446600200200464646600200200c44b3001001801c4c8c96600266e440200062b30013371e01000313756605a00500540ad133004004303100340ac6eb8c0ac004c0b800502c0a5eb7bdb1808966002003003899192cc004cdc8803000c56600266e3c01800626eb4c0b000a00a815226600800860600068150dd718150009816800a056452820404080646600200200844b30010018a5eb8226644b30015980099baf3028302537546050604a6ea800801a266ebcc040c094dd5001180818129baa00f8a50408d13302700233004004001899802002000a0463026001302700140908b20368b2036301f301c3754603e60386ea8c07c00a2c80d22c80d0c078004c01c01cc074c074c074c074004c070c07000516404464660020026eb0c058c04cdd5005912cc0040062980103d87a80008992cc004cdd7980c180a9baa00100b899ba548000cc05c0052f5c11330030033019002404c602e00280aa2646644b300198009802180a9baa0089bac301830190029bab3018003401d15980099b88375a600c602a6ea8020dd69802980a9baa0088acc004cdc41bad3005301537540106eb4c004c054dd500444c8c8cc89660026024005132598009809980c9baa3009301a3754603a60346ea8016266e20008006266e240080050181bad301c30193754007159800980680145284528a02e405c602c6ea8004dd69801980b9baa00a3019301637546032602c6ea8004c06000a2c809a2c809a2c8098c05c0048c05cc060c060c060c060c060004c058c058c058c058c058c058c048dd5005202045900b18061baa00818049baa0038b200e180400098019baa0088a4d13656400401"⟩

def program : Program := linearVestingScript.script

/-- The script hash recorded in the blueprint (hex). -/
def scriptHashHex : String := "95da21788eb1f59f51aad9669eb8c8b7081ab618c1f29b871925894a"

/-- The script accepts within `fuel` steps. -/
def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)

/-- The script genuinely fails within `fuel` steps (running out of steps is not a failure). -/
def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  Formal.Support.rejectedWithin program (args ctx) fuel

open CardanoLedgerApi.V3 (validScriptContext TxOut Value TxInInfo)
open Formal.Support (ledgerFuel)
open Formal.Support.ReturnDatum (allReturnDatumsValid)

/-- The 28 hash bytes recorded for the frozen Plutus V3 script. -/
def returnDatumScriptHash : ByteString :=
  ⟨String.mk (([149, 218, 33, 120, 142, 177, 245, 159, 81, 170, 217, 102, 158, 184,
    200, 183, 8, 26, 182, 24, 193, 242, 155, 135, 25, 37, 137, 74] : List Nat).map Char.ofNat)⟩

/-- Exact schema decoder used by the public UP-006 generator. -/
def returnDatumConforms (datum : Data) : Bool :=
  (IsData.fromData datum : Option SpendDatum).isSome

/-- The unrestricted UP-006 goal, with the existing 1,000,000-step CEK bound. -/
def returnDatumGoal : Prop :=
  ∀ (ctx : ScriptContext), validScriptContext ctx = true →
    accepts ledgerFuel ctx →
    allReturnDatumsValid returnDatumScriptHash returnDatumConforms
      ctx.scriptContextTxInfo.txInfoOutputs = true

/-- One vested asset, halfway through its vesting period. -/
def datum : Data := IsData.toData
  ({ beneficiary := .PubKeyCredential "beneficiary"
     locker := .PubKeyCredential "locker"
     vesting := [{ policy := "policyA", name := "token", total := 10 }]
     start_time := 0
     end_time := 10
     recovery_time := 20 } : SpendDatum)

def ada (amount : Int) : Value :=
  [(.B "", .Map [(.B "", .I amount)])]

def adaAndTokens (amount tokens : Int) : Value :=
  [(.B "", .Map [(.B "", .I amount)]),
   (.B "policyA", .Map [(.B "token", .I tokens)])]

def continuation : TxOut :=
  ⟨⟨.ScriptCredential returnDatumScriptHash, none⟩, adaAndTokens 2000000 5,
   .OutputDatum datum, none⟩

def payout (amount : Int) : TxOut :=
  ⟨⟨.PubKeyCredential "beneficiary", none⟩, adaAndTokens amount 5,
   .NoOutputDatum, none⟩

def extraDatumless : TxOut :=
  ⟨⟨.ScriptCredential returnDatumScriptHash, none⟩, ada 2000000,
   .NoOutputDatum, none⟩

/-- Concrete Claim bookkeeping from the public vesting transaction fixture.
The literals describe a ledger-model example, without a ledger-reachability claim. -/
def claimWithOutputs (outputs : List TxOut) : ScriptContext :=
  let ownRef : TxOutRef := ⟨"previous", 0⟩
  let own : TxInInfo :=
    ⟨ownRef, ⟨⟨.ScriptCredential returnDatumScriptHash, none⟩,
      adaAndTokens 5000000 10, .OutputDatum datum, none⟩⟩
  let feeInput : TxInInfo :=
    ⟨⟨"previous", 1⟩, ⟨⟨.PubKeyCredential "beneficiary", none⟩,
      ada 5000000, .NoOutputDatum, none⟩⟩
  let redeemer := IsData.toData Vesting.Types.VestingRedeemer.Claim
  { scriptContextTxInfo :=
      { txInfoInputs := [own, feeInput]
        txInfoReferenceInputs := []
        txInfoOutputs := outputs
        txInfoFee := 1000000
        txInfoMint := []
        txInfoTxCerts := []
        txInfoWdrl := []
        txInfoValidRange := IsData.toData (CardanoLedgerApi.V1.Time.after 5)
        txInfoSignatories := ["beneficiary"]
        txInfoRedeemers := [(.Spending ownRef, redeemer)]
        txInfoData := []
        txInfoId := "transaction"
        txInfoVotes := []
        txInfoProposalProcedures := []
        txInfoCurrentTreasuryAmount := IsData.toData (none : Option Int)
        txInfoTreasuryDonation := IsData.toData (none : Option Int) }
    scriptContextRedeemer := redeemer
    scriptContextScriptInfo := .SpendingScript ownRef (some datum) }

/-- Accepted-control candidate: 10M input ada = 2M continuation + 7M payout + 1M fee. -/
def original : ScriptContext := claimWithOutputs [continuation, payout 7000000]

/-- Counterexample candidate: move 2M payout ada into a third, datumless script output. -/
def extraOutput : ScriptContext :=
  claimWithOutputs [continuation, payout 5000000, extraDatumless]

end UP006
