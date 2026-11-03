import Blaster
import Formal.Settings.Blueprint.MintQuantity

set_option Elab.async false

namespace Tests.UP016.AcceptingControl

open PlutusCore.UPLC.Term (Program Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Universal.Properties (ledgerFuel rejectedWithin)
open Formal.Settings.Blueprint (MintLeaves original changed args)

/-- Synthetic UPLC control that ignores its context and returns unit. -/
def program : Program := .Program (.Version 1 1 0) (.Lam "ctx" (.Const .Unit))

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program (args ctx) fuel = .Halt (.VCon Const.Unit)

def rejects (fuel : Nat) (ctx : ScriptContext) : Prop :=
  rejectedWithin program (args ctx) fuel

-- Exact original statements with only the executed program substituted.
def quantityIncreaseRejects : Prop :=
  ∀ (p : MintLeaves) (delta : Int),
    delta > 0 →
    validScriptContext (original p) = true →
    accepts ledgerFuel (original p) →
    validScriptContext (changed p delta) = true →
    rejects ledgerFuel (changed p delta)

def quantityIncreaseApplies : Prop :=
  ∃ (p : MintLeaves) (delta : Int),
    delta > 0 ∧
    validScriptContext (original p) = true ∧
    accepts ledgerFuel (original p) ∧
    validScriptContext (changed p delta) = true

-- Expected Falsified and Valid; expected falsification is an observation, not a theorem.
#blaster (solve-result: 1) [quantityIncreaseRejects]
#blaster [quantityIncreaseApplies]

end Tests.UP016.AcceptingControl
