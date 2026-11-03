import Blaster
import Formal.Universal.Properties

set_option Elab.async false

namespace Tests.UP005.AcceptingControl

open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open PlutusCore.UPLC.Term (Program Term Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.Universal.Properties

/-!
Synthetic negative control: a UPLC lambda that ignores its context and returns
unit. This is not an Aiken or deployed validator. Each unchanged UP005 statement
below must be Falsified, so this file intentionally fails Lean compilation.
-/

def program : Program := .Program (.Version 1 1 0) (.Lam "ctx" (.Const .Unit))

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program [toTerm ctx] fuel = .Halt (.VCon Const.Unit)

theorem malformedRedeemer_spend_wrongForm_int :
    ∀ (n : Int) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.I n)) := by blaster

theorem malformedRedeemer_spend_wrongForm_bytes :
    ∀ (b : ByteString) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.B b)) := by blaster

theorem malformedRedeemer_spend_wrongForm_list :
    ∀ (l : List Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.List l)) := by blaster

theorem malformedRedeemer_spend_wrongForm_map :
    ∀ (m : List (Data × Data)) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Map m)) := by blaster

theorem malformedRedeemer_spend_unknownIndex2 :
    ∀ (fs : List Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 2 fs)) := by blaster

theorem malformedRedeemer_spend_unknownIndex3 :
    ∀ (fs : List Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 3 fs)) := by blaster

theorem malformedRedeemer_spend_Claim_extraField :
    ∀ (x1 : Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 0 [x1])) := by blaster

theorem malformedRedeemer_spend_Cancel_extraField :
    ∀ (x1 : Data) (t : EverySpend),
      ¬ accepts ledgerFuel (EverySpend.ctx t (Data.Constr 1 [x1])) := by blaster

end Tests.UP005.AcceptingControl
