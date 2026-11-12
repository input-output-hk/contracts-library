import Blaster
import Formal.Support.Compatibility
import Formal.Vesting.Linear.Blueprint.Types
import Formal.Vesting.Linear.Blueprint.Tx

set_option Elab.async false

namespace Tests.UP000.RejectingControl

open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Support
open Formal.Vesting.Linear.Blueprint

/-!
Synthetic negative control: the program takes a script context and immediately
errors. Preserve the original Claim and Cancel models, validity condition,
argument encoding, and CEK bound. Both existence claims must be Falsified, so
this file intentionally fails Lean compilation.
-/

def rejectingProgram : Program := .Program (.Version 1 1 0) (.Lam "ctx" .Error)

def controlAccepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram rejectingProgram (args ctx) fuel = .Halt (.VCon Const.Unit)

theorem someAccepted_claim_control :
    ∃ p,
      validScriptContext (claim p) = true ∧
      controlAccepts ledgerFuel (claim p) := by blaster

theorem someAccepted_cancel_control :
    ∃ p,
      validScriptContext (cancel p) = true ∧
      controlAccepts ledgerFuel (cancel p) := by blaster

end Tests.UP000.RejectingControl
