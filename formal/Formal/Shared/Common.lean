/-
Shared acceptance/rejection predicates over CEK execution of compiled UPLC.
Reusable across all contracts.
-/
import PlutusCore.UPLC
import CardanoLedgerApi

namespace Formal.Shared.Common

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)
open PlutusCore.UPLC.Term (Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)

/-- The validator **accepts** `ctx`: running the compiled program on the script
context halts returning unit within 5,000,000 CEK steps. This step limit is not a
Cardano CPU/memory execution budget. -/
def validatorAccepts (ctx : ScriptContext) (validator : Program) : Prop :=
  cekExecuteProgram validator [toTerm ctx] 5000000
    = .Halt (.VCon Const.Unit)

/-- The validator **rejects** `ctx`: it errors, returns a non-unit value, or
exhausts the CEK step limit. -/
def validatorRejects (ctx : ScriptContext) (validator : Program) : Prop :=
  ¬ validatorAccepts ctx validator

end Formal.Shared.Common
