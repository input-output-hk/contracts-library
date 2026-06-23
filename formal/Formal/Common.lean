/-
Shared acceptance/rejection predicates over CEK execution of compiled UPLC.
Reusable across all contracts. Adopted from `francolq/aiken-good-practices`
(branch `francolq/formalization-talk`), `order-book/verify/Properties/Common.lean`.
-/
import PlutusCore.UPLC
import CardanoLedgerApi

namespace Formal.Common

open CardanoLedgerApi.IsData.Class (toTerm)
open CardanoLedgerApi.V3 (ScriptContext)
open PlutusCore.UPLC.Term (Const Program)
open PlutusCore.UPLC.CekMachine (cekExecuteProgram)

/-- The validator **accepts** `ctx`: running the compiled program on the script
context halts returning unit, within the execution budget. In Plutus V3 a
validator signals success by returning unit and failure by erroring, so this is
the concrete meaning of "the validator returns `True`" in the spec (§8). -/
def validatorAccepts (ctx : ScriptContext) (validator : Program) : Prop :=
  cekExecuteProgram validator [toTerm ctx] 5000000
    = .Halt (.VCon Const.Unit)

/-- The validator **rejects** `ctx`: it does not accept (it errors, or fails to
halt with unit within budget). The concrete meaning of "the validator returns
`False`" (§9). -/
def validatorRejects (ctx : ScriptContext) (validator : Program) : Prop :=
  ¬ validatorAccepts ctx validator

end Formal.Common
