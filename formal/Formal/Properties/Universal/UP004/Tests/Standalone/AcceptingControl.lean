import Blaster
import Formal.Support.Compatibility
import Formal.Vesting.Linear.Blueprint.Tx

set_option Elab.async false

namespace Tests.UP004.AcceptingControl

open PlutusCore.UPLC.Term (Program)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Support
open Formal.Vesting.Linear.Blueprint (args claim cancel)

/-!
Synthetic negative control: a UPLC lambda that ignores its context and returns
unit. This is not an Aiken or deployed validator. Both rejection-existence claims
below must be Falsified, so this file intentionally fails Lean compilation.
The formulas retain the original Claim/Cancel models, validity predicate, genuine
rejection predicate, and CEK bound; only the checked program changes.
-/

def program : Program := .Program (.Version 1 1 0) (.Lam "ctx" (.Const .Unit))

def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin program (args ctx) fuel

theorem someRejected_claim_control :
    ∃ p,
      validScriptContext (claim p) = true ∧
      rejects ledgerFuel (claim p) := by blaster

theorem someRejected_cancel_control :
    ∃ p,
      validScriptContext (cancel p) = true ∧
      rejects ledgerFuel (cancel p) := by blaster

end Tests.UP004.AcceptingControl
