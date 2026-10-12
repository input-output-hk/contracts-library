import CardanoLedgerApi
import Blaster
import PlutusCore.UPLC.CekMachine
import PlutusCore.UPLC.PlutusScript

namespace Formal.Universal.Evaluator

open CardanoLedgerApi.V2
open PlutusCore.UPLC.CekMachine
open PlutusCore.UPLC.PlutusScript
open PlutusCore.UPLC.Term
open PlutusCore.UPLC.Utils

set_option warn.sorry true

-- Blaster + Z3 work
theorem smoke : ∀ (a b : Nat), a + b = b + a := by blaster

theorem success_not_error :
  ∀ (vali : Program) (args : List Term) (fuel : Nat),
  isSuccessful (cekExecuteProgram vali args fuel) -> (cekExecuteProgram vali args fuel ≠ .Error) := by
  intro vali args fuel success exec
  rw [exec] at success
  exact success

theorem zero_fuel_always_fails (vali : Program) (args : List Term) :
  isUnsuccessful (cekExecuteProgram vali args 0) := by
  unfold cekExecuteProgram cekExecuteProgramWithSemanticVariant runSteps
  rcases vali with ⟨version, term⟩
  simp [initialState, isUnsuccessful, isErrorState]

end Formal.Universal.Evaluator
