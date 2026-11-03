-- Preserved propositions and concrete controls; standalone proof checks live in tests/UP016.
import Formal.Settings.Blueprint.Tx

namespace Formal.Settings.Blueprint

open PlutusCore.Data (Data)
open PlutusCore.UPLC.Term (Const)
open CardanoLedgerApi.V3 (ScriptContext validScriptContext)
open Formal.Universal.Properties (ledgerFuel)

/-- Rejection proposition; its standalone proof invocation does not alter this definition. -/
def quantityIncreaseRejects : Prop :=
  ∀ (p : MintLeaves) (delta : Int),
    delta > 0 →
    validScriptContext (original p) = true →
    accepts ledgerFuel (original p) →
    validScriptContext (changed p delta) = true →
    rejects ledgerFuel (changed p delta)

/-- Applicability proposition covering all premises of the rejection claim. -/
def quantityIncreaseApplies : Prop :=
  ∃ (p : MintLeaves) (delta : Int),
    delta > 0 ∧
    validScriptContext (original p) = true ∧
    accepts ledgerFuel (original p) ∧
    validScriptContext (changed p delta) = true

-- Concrete fixture retained from the original candidate.
def probe : MintLeaves :=
  { ada0 := 3000000, ada1 := 2000000, fee := 200000,
    validFrom := 0, current := 0 }

/-- Diagnostic classification uses the existing evaluator with explicit exhaustion.
It does not replace the generated accepts/rejects predicates used above.
-/
def executionOutcome (ctx : ScriptContext) (fuel : Nat) : String :=
  match program with
  | .Program _ body =>
      match Formal.Universal.Properties.runFor
        (PlutusCore.UPLC.CekMachine.initialState
          (PlutusCore.UPLC.CekMachine.applyParams body (args ctx))) fuel with
      | none => "fuel_exhausted"
      | some .Error => "error"
      | some (.Halt (.VCon Const.Unit)) => "accepted"
      | some (.Halt _) => "non_unit_halt"
      | some _ => "unexpected_nonterminal"

/-- Concrete controls for a supplied fixture and fuel. Keep these runtime arguments
explicit so closed CEK evaluations cannot be hoisted into module initialization. -/
def concreteAssertions (p : MintLeaves) (fuel : Nat) : List (String × Bool) :=
  let h := original p
  let m := changed p 1
  let originalOutcome := executionOutcome h fuel
  let changedOutcome := executionOutcome m fuel
  [ ("original_valid", validScriptContext h),
    ("original_accepts", originalOutcome == "accepted"),
    ("changed_valid", validScriptContext m),
    ("changed_explicitly_rejects", changedOutcome == "error" || changedOutcome == "non_unit_halt"),
    ("zero_fuel_is_exhaustion", executionOutcome h 0 == "fuel_exhausted"),
    ("mutation_is_nontrivial", decide (m ≠ h)),
    ("mint_quantity_is_two", decide (CardanoLedgerApi.V1.Value.valueOf ownPolicy tokenName
       m.scriptContextTxInfo.txInfoMint = 2)),
    ("canonical_mint", decide (m.scriptContextTxInfo.txInfoMint =
       [(.B ownPolicy, .Map [(.B tokenName, .I 2)])])),
    ("canonical_output1_credit", decide (m.scriptContextTxInfo.txInfoOutputs[1]? =
       some (Formal.Universal.TxBuilder.toKey applyKey
         (Formal.Universal.TxBuilder.adaAnd p.ada1 ownPolicy tokenName 1)))),
    ("protected_output_unchanged", decide (m.scriptContextTxInfo.txInfoOutputs[0]? =
       h.scriptContextTxInfo.txInfoOutputs[0]?)),
    ("other_fields_unchanged", decide
       ({ m with scriptContextTxInfo := { m.scriptContextTxInfo with
           txInfoMint := h.scriptContextTxInfo.txInfoMint
           txInfoOutputs := h.scriptContextTxInfo.txInfoOutputs } } = h)),
    ("output1_nonvalue_fields_unchanged", decide (m.scriptContextTxInfo.txInfoOutputs[1]? =
       some { changeOutput p with txOutValue :=
         Formal.Universal.TxBuilder.adaAnd p.ada1 ownPolicy tokenName 1 })),
    ("zero_delta_is_identity", decide (changed p 0 = h)),
    ("negative_delta_is_invalid", !(validScriptContext (changed p (-1)))),
    ("datum_encoding", decide (settingsDatum p.current =
       .Constr 0 [.I p.current, .Constr 1 [], .Constr 1 []])),
    ("redeemer_encoding", decide (mintRedeemer = .Constr 0 [.I 0])),
    ("context_only_argument", decide ((args h).length = 1)) ]

/-- Explicit runner only. There is no #eval command or automatic solver invocation. -/
def runConcreteControls (p : MintLeaves) (fuel : Nat) : IO Unit := do
  let checks := concreteAssertions p fuel
  for (name, result) in checks do
    if result then IO.println ("PASS " ++ name)
    else throw (IO.userError ("FAIL " ++ name))
  IO.println ("ALL_CONCRETE_CONTROLS_PASS " ++ toString checks.length)

end Formal.Settings.Blueprint
