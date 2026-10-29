/-
Shared acceptance/rejection predicates over CEK execution of compiled UPLC.
Reusable across all contracts.
-/
import PlutusCore.UPLC
import CardanoLedgerApi

namespace Formal.Common

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)
open PlutusCore.UPLC.Term (Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)

/-- The validator **accepts** `ctx`: running the compiled program on the script
context halts returning unit, within the execution budget. -/
def validatorAccepts (ctx : ScriptContext) (validator : Program) : Prop :=
  cekExecuteProgram validator [toTerm ctx] 1000
    = .Halt (.VCon Const.Unit)

/-- The validator **rejects** `ctx`: it does not accept (it errors, or fails to
halt with unit within budget). -/
def validatorRejects (ctx : ScriptContext) (validator : Program) : Prop :=
  ¬ validatorAccepts ctx validator

end Formal.Common
