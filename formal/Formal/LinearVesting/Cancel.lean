import Blaster
import CardanoLedgerApi.V3
import Formal.Shared.Common
import Formal.LinearVesting.SpecNew
import Formal.LinearVesting.Script

namespace Formal.LinearVesting.Cancel

open PlutusCore.Data (Data)
open PlutusCore.Integer (Integer)
open CardanoLedgerApi.IsData.Class (IsData)
open CardanoLedgerApi.V3
  (Credential POSIXTimeRange PubKeyHash ScriptContext ScriptHash TxInfo TxOutRef)
open Formal.Shared.Common (validatorAccepts)
open Formal.LinearVesting.SpecNew
  (VestingDatum VestingRedeemer datumData redeemerData specAccepts)
open Formal.LinearVesting.Script (spendValidator)

/-- The compiled validator accepts `ctx` exactly when the spec does. -/
def Agrees (d : VestingDatum) (r : VestingRedeemer) (ctx : ScriptContext) : Prop :=
  validatorAccepts ctx spendValidator ↔ specAccepts d r ctx = true

/-- A cancel transaction: the vesting input being spent, put first among the inputs,
and everything else left arbitrary. -/
structure CancelTx where
  datum       : VestingDatum
  ownRef      : TxOutRef
  scriptHash  : ScriptHash
  ownValue    : List (Data × Data)
  range       : POSIXTimeRange
  signatories : List PubKeyHash
  withdrawals : List (Credential × Integer)
  rest        : TxInfo

def CancelTx.ctx (tx : CancelTx) : ScriptContext :=
  { scriptContextTxInfo :=
      { tx.rest with
        txInfoInputs :=
          ⟨tx.ownRef,
            ⟨⟨.ScriptCredential tx.scriptHash, none⟩, tx.ownValue,
             .OutputDatum (datumData tx.datum), none⟩⟩ :: tx.rest.txInfoInputs
        txInfoWdrl := tx.withdrawals
        txInfoValidRange := IsData.toData tx.range
        txInfoSignatories := tx.signatories }
    scriptContextRedeemer := redeemerData .cancel
    scriptContextScriptInfo := .SpendingScript tx.ownRef (some (datumData tx.datum)) }

def agreesOn (tx : CancelTx) : Prop := Agrees tx.datum .cancel tx.ctx

set_option profiler true in
theorem cancel_agrees
    (tx : CancelTx)
    (hSig : ∀ lk, tx.datum.locker = .PubKeyCredential lk → tx.signatories.length < 3)
    (hWdrl : ∀ ls, tx.datum.locker = .ScriptCredential ls → tx.withdrawals.length < 3) :
    agreesOn tx := by
  rcases tx with
    ⟨⟨bene, locker, vesting, start, finish, recovery⟩, ownRef, sh, a, ⟨low, up⟩, sigs, wdrl,
      rest⟩
  unfold agreesOn Agrees
  rcases locker with lk | ls
  · have h : sigs.length < 3 := hSig lk rfl
    clear hSig hWdrl
    rcases bene with _ | _ <;>
    rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
    repeat' (first
      | (simp only [List.length_cons, List.length_nil] at h; exfalso; omega)
      | (rcases sigs with _ | ⟨_, sigs⟩))
    all_goals (clear h; blaster)
  · have h : wdrl.length < 3 := hWdrl ls rfl
    clear hSig hWdrl
    rcases bene with _ | _ <;>
    rcases low with ⟨_, _ | _⟩ | (_ | _) <;>
    repeat' (first
      | (simp only [List.length_cons, List.length_nil] at h; exfalso; omega)
      | (rcases wdrl with _ | ⟨⟨_ | _, _⟩, wdrl⟩))
    all_goals (clear h; blaster)

end Formal.LinearVesting.Cancel
