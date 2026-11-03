import Blaster
import Formal.Universal.Properties

set_option Elab.async false

namespace Tests.UP001.AcceptingControl

open PlutusCore.Data (Data)
open PlutusCore.UPLC.Term (Program Term Const)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram State)
open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)
open Formal.Universal.Properties

/-!
Synthetic negative control: a UPLC lambda that ignores its context and returns
unit. This is not an Aiken or deployed validator. Each unchanged UP001 statement
below must be Falsified, so this file intentionally fails Lean compilation.
-/

def program : Program := .Program (.Version 1 1 0) (.Lam "ctx" (.Const .Unit))

def accepts (fuel : Nat) (ctx : ScriptContext) : Prop :=
  cekExecuteProgram program [toTerm ctx] fuel = .Halt (.VCon Const.Unit)

theorem otherPurpose_mint :
    ∀ (r : Data) (t : EveryMint),
      ¬ accepts ledgerFuel (EveryMint.ctx t r) := by blaster

theorem otherPurpose_withdraw :
    ∀ (r : Data) (t : EveryWithdraw),
      ¬ accepts ledgerFuel (EveryWithdraw.ctx t r) := by blaster

theorem otherPurpose_publish :
    ∀ (r : Data) (t : EveryPublish),
      ¬ accepts ledgerFuel (EveryPublish.ctx t r) := by blaster

theorem otherPurpose_vote :
    ∀ (r : Data) (t : EveryVote),
      ¬ accepts ledgerFuel (EveryVote.ctx t r) := by blaster

theorem otherPurpose_propose :
    ∀ (r : Data) (t : EveryPropose),
      ¬ accepts ledgerFuel (EveryPropose.ctx t r) := by blaster

end Tests.UP001.AcceptingControl
