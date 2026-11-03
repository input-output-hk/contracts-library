import PlutusCore.UPLC.Utils

namespace Formal.Universal.Evaluator

open PlutusCore.Default (BuiltinSemanticsVariant)
open PlutusCore.UPLC.CekMachine
open PlutusCore.UPLC.Term (Program Term)
open PlutusCore.UPLC.Utils

/-- A successful run never ends in the error state. -/
theorem ne_error_of_success
  (prog : Program) (args : List Term) (fuel : Nat) :
  isSuccessful (cekExecuteProgram prog args fuel) -> (cekExecuteProgram prog args fuel ≠ .Error) := by
    intro success exec
    rw [exec] at success
    exact success

/-- Every run with zero fuel is unsuccessful. -/
theorem unsuccessful_of_zero_fuel
  (prog : Program) (args : List Term) :
  isUnsuccessful (cekExecuteProgram prog args 0) := by
    unfold cekExecuteProgram cekExecuteProgramWithSemanticVariant runSteps
    rcases prog with ⟨version, term⟩
    simp [initialState, isUnsuccessful, isErrorState]

/-- Once the machine halts, more steps leave the state unchanged. -/
theorem runSteps_eq_of_halt
  (sv : BuiltinSemanticsVariant) (s : State) (n m : Nat)
  (hHalt : isHaltState (runSteps sv s n))
  (hNM : n ≤ m) :
  runSteps sv s m = runSteps sv s n := by
    induction n generalizing s m with
      | zero => cases s <;> simp_all [runSteps, isHaltState]
      | succ n ih =>
        obtain ⟨mm, rfl⟩ : ∃ mm, m = mm + 1 := ⟨m - 1, by omega⟩
        cases s with
          | Halt v => simp [runSteps]
          | Error => simp [runSteps]
          | Eval st env term =>
              simp [runSteps] at *
              exact ih _ _ hHalt (by omega)
          | Return st val =>
              simp [runSteps] at *
              exact ih _ _ hHalt (by omega)

/-- A run that succeeds with fuel n ends in the same state with any fuel m ≥ n. -/
theorem cekExecuteProgram_eq_of_success
  (prog : Program) (args : List Term) (n m : Nat)
  (hSuccess : isSuccessful (cekExecuteProgram prog args n))
  (hNM : n ≤ m) :
  cekExecuteProgram prog args m = cekExecuteProgram prog args n := by
    rcases prog with ⟨version, term⟩
    simp only [cekExecuteProgram, cekExecuteProgramWithSemanticVariant, isSuccessful] at hSuccess ⊢
    exact runSteps_eq_of_halt _ _ _ _ hSuccess hNM

/-- A run that succeeds with fuel n also succeeds with any fuel m ≥ n. -/
theorem cekExecuteProgram_mono_in_fuel
  (prog : Program) (args : List Term) (n m : Nat)
  (hSuccess : isSuccessful (cekExecuteProgram prog args n))
  (hNM : n ≤ m) :
  isSuccessful (cekExecuteProgram prog args m) := by
    rcases prog with ⟨version, term⟩
    simp only [cekExecuteProgram, cekExecuteProgramWithSemanticVariant, isSuccessful] at hSuccess ⊢
    rw [runSteps_eq_of_halt _ _ _ _ hSuccess hNM]
    exact hSuccess

end Formal.Universal.Evaluator
