import Blaster
import CardanoLedgerApi.V3
import Formal.LinearVesting.SpecNew
import Formal.LinearVesting.Cancel

namespace Formal.LinearVesting.Claim

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V1.Value (CurrencySymbol TokenName)
open CardanoLedgerApi.V3
  (Credential POSIXTimeRange PubKeyHash ScriptContext ScriptHash TxInfo TxOut TxOutRef)
open Formal.LinearVesting.SpecNew (VestedAsset VestingDatum datumData redeemerData)
open Formal.LinearVesting.Cancel (Agrees)

/-- An output at a script address, with any datum, holding ada and one other asset. -/
structure ClaimOut where
  scriptHash : ScriptHash
  datum      : Data
  ada        : Integer
  policy     : CurrencySymbol
  name       : TokenName
  qty        : Integer

def ClaimOut.toTxOut (o : ClaimOut) : TxOut :=
  ⟨⟨.ScriptCredential o.scriptHash, none⟩,
   [(Data.B "", Data.Map [(Data.B "", Data.I o.ada)]),
    (Data.B o.policy, Data.Map [(Data.B o.name, Data.I o.qty)])],
   .OutputDatum o.datum, none⟩

/-- A claim transaction: the vesting UTxO being spent is the only input, and every
field the claim does not read comes from `rest`. -/
structure ClaimTx where
  datum       : VestingDatum
  ownRef      : TxOutRef
  scriptHash  : ScriptHash
  ownValue    : List (Data × Data)
  range       : POSIXTimeRange
  signatories : List PubKeyHash
  withdrawals : List (Credential × Integer)
  outputs     : List ClaimOut
  rest        : TxInfo

def ClaimTx.ctx (tx : ClaimTx) : ScriptContext :=
  { scriptContextTxInfo :=
      { tx.rest with
        txInfoInputs :=
          [⟨tx.ownRef,
            ⟨⟨.ScriptCredential tx.scriptHash, none⟩, tx.ownValue,
             .OutputDatum (datumData tx.datum), none⟩⟩]
        txInfoOutputs := tx.outputs.map ClaimOut.toTxOut
        txInfoWdrl := tx.withdrawals
        txInfoValidRange := IsData.toData tx.range
        txInfoSignatories := tx.signatories }
    scriptContextRedeemer := redeemerData .claim
    scriptContextScriptInfo := .SpendingScript tx.ownRef (some (datumData tx.datum)) }

def claimAgreesOn (tx : ClaimTx) : Prop := Agrees tx.datum .claim tx.ctx

theorem claim_agrees
    (tx : ClaimTx) (bh : PubKeyHash) (asset : VestedAsset)
    (hB : tx.datum.beneficiary = .PubKeyCredential bh)
    (hV : tx.datum.vesting = [asset])
    (hU : tx.range.ivTo = .InfiniteUpperBound .PosInf)
    (hSig : tx.signatories.length < 2)
    (hOut : tx.outputs.length < 3) :
    claimAgreesOn tx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, ownValue, ⟨low, up⟩,
      sigs, wdrl, outs, rest⟩
  simp only at hB hV hU
  subst hB hV hU
  unfold claimAgreesOn Agrees
  rcases locker with _ | _ <;>
  rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
  repeat' (first
    | (simp only [List.length_cons, List.length_nil] at hSig hOut; exfalso; omega)
    | (rcases sigs with _ | ⟨_, sigs⟩)
    | (rcases outs with _ | ⟨_, outs⟩))
  all_goals (clear hSig hOut; blaster)

end Formal.LinearVesting.Claim
